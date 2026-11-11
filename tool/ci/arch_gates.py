"""Architecture gates, ratcheted against tool/ci/arch_baseline.json.

    python tool/ci/arch_gates.py                    # all lib files vs the baseline
    python tool/ci/arch_gates.py --files A B ...    # only these files (pre-commit)
    python tool/ci/arch_gates.py --update-baseline  # shrink-only: record fixed violations
    python tool/ci/arch_gates.py --init-baseline    # write the current state, no checks
    python tool/ci/arch_gates.py --self-test        # synthetic checks, reads no files
    python tool/ci/arch_gates.py --list             # gate status only, exit 0

The package name comes from pubspec.yaml `name:`; the state management (getx, bloc or
riverpod) from its dependencies (get, flutter_bloc, flutter_riverpod). The state
management decides which DI-entry folders may import lib/app/di, whether G9 exists, what
G10 treats as a service locator and whether a module's di/ folder is its own wiring layer
(riverpod: providers that build the module's data and domain objects, so it may import data).

Existing violations are baselined per (gate, file). A run fails when a count grows
(or a new file appears) and also when one shrinks, so a fix has to be locked in with
--update-baseline. --update-baseline refuses to write while a gate's total has grown;
a moved or split file keeps the total, so moving a baselined file is ratcheted the
same way as a fix. --init-baseline is for creating the baseline once; it overwrites
without checking.
G-size is a ceiling per file: growth fails, shrinking is only reported.

A gate whose scope matches no file reports VACUOUS (a module gate in an app that has no
layered module yet); --self-test guards against mistyped scopes.

Python 3 stdlib only; runs the same on Windows and ubuntu.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import posixpath
import re
import sys
from collections.abc import Callable
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / 'tool' / 'ci' / 'arch_baseline.json'
PUBSPEC = ROOT / 'pubspec.yaml'
SIZE_LIMIT = 800
SHOWN = 20
RATCHET_HINT = 'run python tool/ci/arch_gates.py --update-baseline to ratchet down'

GENERATED = re.compile(r'\.(g|gen|config|freezed)\.dart$')
SKIPPED = ('lib/main.dart',)
IMPORT = re.compile(r"""^[ \t]*(?:import|export)\s+(['"])([^'"\r\n]+)\1[^;]*;""", re.M)

Hit = tuple[int, str]

# Set once by configure(); every path and import resolves against them.
PACKAGE = ''
SM_NAME = ''
MODULE_DI = False
GATES: list[Gate] = []


def excluded(path: str) -> bool:
    return bool(GENERATED.search(path)) or path in SKIPPED


def layer_of(path: str) -> str | None:
    if path.startswith('lib/core/'):
        return 'core'
    if path.startswith('lib/app/shared/data/'):
        return 'data'
    if path.startswith('lib/app/shared/domain/'):
        return 'domain'
    if path.startswith('lib/app/'):
        return 'app'
    if path.startswith('lib/modules/'):
        parts = path.split('/')
        if len(parts) > 4 and parts[3] in ('data', 'domain'):
            return parts[3]
        if len(parts) > 4 and parts[3] == 'di' and MODULE_DI:
            return 'di'
        return 'presentation'
    return None


def resolve(importer: str, uri: str) -> str | None:
    if uri.startswith('dart:'):
        return None
    if uri.startswith('package:'):
        pkg, _, rest = uri[len('package:'):].partition('/')
        return f'lib/{rest}' if pkg == PACKAGE else uri
    return posixpath.normpath(posixpath.join(posixpath.dirname(importer), uri))


class SrcFile:
    def __init__(self, path: str, text: str | None = None) -> None:
        self.path = path
        self._text = text

    @cached_property
    def text(self) -> str:
        if self._text is not None:
            return self._text
        try:
            return (ROOT / self.path).read_text(encoding='utf-8-sig', errors='replace')
        except OSError as e:
            sys.exit(f'cannot read {self.path}: {e}')

    @cached_property
    def lines(self) -> list[str]:
        return self.text.split('\n')

    @cached_property
    def layer(self) -> str | None:
        return layer_of(self.path)

    @cached_property
    def dirs(self) -> list[str]:
        return self.path.split('/')[:-1]

    @cached_property
    def imports(self) -> list[tuple[int, str]]:
        found = []
        for m in IMPORT.finditer(self.text):
            target = resolve(self.path, m.group(2))
            if target is not None:
                found.append((self.text.count('\n', 0, m.start()) + 1, target))
        return found


@dataclass(frozen=True)
class Gate:
    gid: str
    title: str
    message: str
    scope: Callable[[SrcFile], bool]
    find: Callable[[SrcFile], list[Hit]]
    size: bool = False


def import_gate(pred: Callable[[SrcFile, str], bool]) -> Callable[[SrcFile], list[Hit]]:
    def find(f: SrcFile) -> list[Hit]:
        return [(ln, f.lines[ln - 1].strip()[:100]) for ln, t in f.imports if pred(f, t)]
    return find


def regex_gate(pattern: re.Pattern[str]) -> Callable[[SrcFile], list[Hit]]:
    def find(f: SrcFile) -> list[Hit]:
        out = []
        for m in pattern.finditer(f.text):
            ln = f.text.count('\n', 0, m.start()) + 1
            line = f.lines[ln - 1].strip()
            if not line.startswith('//'):
                out.append((ln, line[:100]))
        return out
    return find


def line_count(f: SrcFile) -> int:
    return len(f.lines) - (f.lines[-1] == '')


def find_size(f: SrcFile) -> list[Hit]:
    n = line_count(f)
    return [(n, f'{n} lines')] if n > SIZE_LIMIT else []


DATA_LAYER = lambda _f, t: layer_of(t) == 'data'  # noqa: E731
# 'package:get' also covers get_it; 'package:flutter' also covers flutter_bloc and
# flutter_riverpod; the explicit names keep the intent readable.
DOMAIN_BANNED = ('package:flutter', 'package:get', 'package:dio', 'package:flutter_bloc',
                 'package:bloc', 'package:flutter_riverpod', 'package:riverpod')
# Trailing slash: package:bloc/ must not match package:bloc_test/.
CORE_BANNED = ('package:get/', 'package:get_it/', 'package:injectable/', 'package:flutter_bloc/',
               'package:bloc/', 'package:flutter_riverpod/', 'package:riverpod/')
APP_ALLOWED = ('lib/app/routes/', 'lib/app/shared/', 'lib/app/theme/')
REPO_NAME = r'(?:Repository|DataSource|Datasource)'
REGISTERS_REPO = re.compile(
    r'\bGet\s*\.\s*(?:put|lazyPut|putAsync)\s*(?:'
    rf'<[^>(]*?{REPO_NAME}'
    r'|(?:<[^>(]*>\s*)?\(\s*(?:\(\s*\)\s*(?:async\s*)?(?:=>|\{\s*return)\s*)?(?:await\s+)?(?:const\s+)?(?:sl\s*<\s*)?'
    rf'\w*{REPO_NAME}\w*\s*[(<.>])'
)
SERVICE_LOCATOR = re.compile(
    r'\b(?:sl|getIt|locator)\s*(?:<|\(|\.)|\bGetIt\s*\.\s*(?:I|instance)\b|\bGet\s*\.\s*find\b'
)
REF_LOOKUP = re.compile(SERVICE_LOCATOR.pattern + r'|(?<![\w$])ref\s*\.\s*(?:read|watch|listen)\b')
# dart:developer is matched on its import: a bare log( would also hit dart:math.
RAW_LOG = re.compile(r'''(?<![\w.$])(?:debugPrint|print)\s*\(|^[ \t]*import\s+['"]dart:developer['"]''', re.M)


@dataclass(frozen=True)
class StateManagement:
    di_dirs: tuple[str, ...]  # module folders that may import lib/app/di
    g9: bool
    locator: re.Pattern[str]
    di_note: str


STATE_MANAGEMENT = {
    'getx': StateManagement(('bindings',), True, SERVICE_LOCATOR, 'Bindings may also import app/di.'),
    'bloc': StateManagement((), False, SERVICE_LOCATOR,
                            'No module folder may import app/di; cubits are built in lib/app/routes/.'),
    'riverpod': StateManagement(('providers', 'di'), False, REF_LOOKUP,
                                'providers/ and a module di/ may also import app/di.'),
}
DEPENDENCY_TO_SM = {'get': 'getx', 'flutter_bloc': 'bloc', 'flutter_riverpod': 'riverpod'}


def build_gates(sm_name: str) -> list[Gate]:
    sm = STATE_MANAGEMENT[sm_name]
    or_di = ' or di/' if 'di' in sm.di_dirs else ''
    wiring = lambda _f, t: layer_of(t) in ('data', 'di')  # noqa: E731

    def app_leak(f: SrcFile, t: str) -> bool:
        if not t.startswith('lib/app/') or t.startswith(APP_ALLOWED):
            return False
        return not (any(d in sm.di_dirs for d in f.dirs) and t.startswith('lib/app/di/'))

    gates = [
        Gate('G-core', 'core imports nothing from app/ or modules/',
             'lib/core is leaf code; the app layer injects behaviour into it.',
             lambda f: f.layer == 'core',
             import_gate(lambda _f, t: t.startswith(('lib/app/', 'lib/modules/')))),
        Gate('G-core-neutral', 'core imports no GetX, GetIt, injectable, Bloc or Riverpod',
             'lib/core is state-management-neutral: plain classes with constructor injection; lib/app/di registers them.',
             lambda f: f.layer == 'core',
             import_gate(lambda _f, t: t.startswith(CORE_BANNED))),
        Gate('G1', f'domain imports nothing from data/{or_di}',
             'The domain layer must not know the data layer exists.',
             lambda f: f.layer == 'domain', import_gate(wiring)),
        Gate('G2', 'domain imports no Flutter, GetX, GetIt, Dio, Bloc or Riverpod',
             'Domain is pure Dart (equatable and injectable annotations are fine).',
             lambda f: f.layer == 'domain',
             import_gate(lambda _f, t: t.startswith(DOMAIN_BANNED))),
        Gate('G3', 'module presentation imports nothing from data/',
             'Presentation talks to use cases, never to a repository impl or a datasource.',
             lambda f: f.layer == 'presentation', import_gate(DATA_LAYER)),
        Gate('G4', f'data imports nothing from presentation/{or_di}',
             'Data knows domain and core only; a datasource must not reach a controller or view.',
             lambda f: f.layer == 'data',
             import_gate(lambda _f, t: layer_of(t) in ('presentation', 'di'))),
    ]
    if sm.g9:
        gates.append(Gate(
            'G9', 'bindings do not register repositories or datasources',
            'A Binding registers its controllers; repositories and datasources belong to DI.',
            lambda f: 'bindings' in f.dirs, regex_gate(REGISTERS_REPO)))
    gates += [
        Gate('G10', 'data and domain do not resolve from a service locator',
             'Receive dependencies through constructors, never sl/GetIt/Get.find'
             + (' or ref.read/ref.watch.' if sm_name == 'riverpod' else '.'),
             lambda f: f.layer in ('data', 'domain'), regex_gate(sm.locator)),
        Gate('G-app', 'modules import only app/routes, app/shared, app/theme',
             f'{sm.di_note} Everything else under app/ is wiring a module must not reach.',
             lambda f: f.path.startswith('lib/modules/'), import_gate(app_leak)),
        Gate('G-log', 'no print/debugPrint/dart:developer outside lib/core/logging',
             'AppLogger in lib/core/logging is the only sink.',
             lambda f: not f.path.startswith('lib/core/logging/'), regex_gate(RAW_LOG)),
        Gate('G-size', f'no lib file over {SIZE_LIMIT} lines',
             'Split the file; a baselined file may not grow.',
             lambda f: True, find_size, size=True),
    ]
    return gates


def configure(package: str, sm_name: str) -> None:
    global PACKAGE, SM_NAME, MODULE_DI, GATES
    PACKAGE, SM_NAME, GATES = package, sm_name, build_gates(sm_name)
    MODULE_DI = 'di' in STATE_MANAGEMENT[sm_name].di_dirs


def read_package(pubspec: str) -> str:
    m = re.search(r'^name:\s*([A-Za-z0-9_]+)', pubspec, re.M)
    if not m:
        sys.exit('pubspec.yaml has no top-level name:')
    return m.group(1)


def detect_sm(pubspec: str) -> str:
    found = sorted({sm for dep, sm in DEPENDENCY_TO_SM.items() if re.search(rf'^  {dep}:', pubspec, re.M)})
    if len(found) != 1:
        want = ', '.join(DEPENDENCY_TO_SM)
        sys.exit(f'expected exactly one of {want} in pubspec.yaml dependencies, found: {found or "none"}')
    return found[0]


@dataclass
class Result:
    gate: Gate
    scanned: int
    vacuous: bool
    hits: dict[str, list[Hit]]
    counts: dict[str, int]
    grew: list[tuple[str, int, int]]
    fixed: list[tuple[str, int, int]]
    info: list[str]
    tolerated: int
    base_total: int

    @property
    def failed(self) -> bool:
        return bool(self.grew or self.fixed)


def total_grew(results: list[Result]) -> list[Result]:
    return [r for r in results if sum(r.counts.values()) > r.base_total]


def run(files: list[SrcFile], checked: set[str] | None, baseline: dict[str, dict[str, int]]) -> list[Result]:
    """`files` is every lib file (scope canary); `checked` limits which are scanned."""
    targets = files if checked is None else [f for f in files if f.path in checked]
    results = []
    for g in GATES:
        scoped = [f for f in targets if g.scope(f)]
        hits = {f.path: h for f in scoped if (h := g.find(f))}
        counts = {p: (h[0][0] if g.size else len(h)) for p, h in hits.items()}
        base = baseline.get(g.gid, {})
        if checked is not None:
            base = {p: c for p, c in base.items() if p in checked}
        grew, fixed, info, tolerated = [], [], [], 0
        for p in sorted(set(counts) | set(base)):
            c, b = counts.get(p, 0), base.get(p, 0)
            if c > b:
                grew.append((p, c, b))
                tolerated += 0 if g.size else b
            elif g.size:
                tolerated += 1 if c else 0
                if c < b:
                    info.append(f'{p}: {b} -> {c or "under limit"}')
            else:
                tolerated += c
                if c < b:
                    fixed.append((p, c, b))
        vacuous = not any(g.scope(f) for f in files)
        results.append(Result(g, len(scoped), vacuous, hits, counts, grew, fixed, info, tolerated,
                              sum(base.values())))
    return results


def status(r: Result) -> str:
    if r.failed:
        return 'FAIL'
    if r.vacuous:
        return 'VACUOUS'
    return 'PASS' if r.scanned else 'SKIP'


def offender_lines(r: Result) -> list[str]:
    g = r.gate
    lines = []
    for p, c, b in r.grew:
        if g.size:
            lines.append(f'{p}: {c} lines, ceiling {b or SIZE_LIMIT}')
            continue
        lines.append(f'{p}: {c} found, baseline {b}')
        lines.extend(f'  {p}:{ln}: {text}' for ln, text in r.hits[p])
    if r.fixed:
        lines.append(f'fixed {sum(b - c for _, c, b in r.fixed)}: {RATCHET_HINT}')
        lines.extend(f'  {p}: {c} found, baseline {b}' for p, c, b in r.fixed)
    return lines


def report(results: list[Result], detail: bool) -> int:
    for r in results:
        g, st = r.gate, status(r)
        head = f'{st:<8}{g.gid:<16}{g.title}'
        if st == 'FAIL':
            print(f'{head}  ({len(r.grew)} grown, {len(r.fixed)} fixed files)')
            if detail:
                print(f'        {g.message}')
                lines = offender_lines(r)
                for line in lines[:SHOWN]:
                    print(f'          {line}')
                if len(lines) > SHOWN:
                    print(f'          ... and {len(lines) - SHOWN} more lines')
        elif st == 'VACUOUS':
            print(f'{head}  -- no file in scope, enforcing nothing')
        elif st == 'SKIP':
            print(f'{head}  -- none of the checked files is in scope')
        else:
            print(f'{head}  ({r.scanned} files, {r.tolerated} baselined in {len(r.counts)} files)')
        if detail and st != 'FAIL':
            for line in r.info[:5]:
                print(f'          info: {line}')
    tally = {s: sum(status(r) == s for r in results) for s in ('PASS', 'SKIP', 'VACUOUS', 'FAIL')}
    skipped = f' | {tally["SKIP"]} skipped' if tally['SKIP'] else ''
    print()
    print(f'{tally["PASS"]} pass{skipped} | {tally["VACUOUS"]} vacuous | {tally["FAIL"]} failed'
          f' | {sum(r.tolerated for r in results)} baselined violations')
    moved = [r.gate.gid for r in results if r.grew and not total_grew([r])]
    if moved:
        print(f'{", ".join(moved)}: the total did not grow, so this may be a moved file: {RATCHET_HINT}')
    return tally['FAIL']


def discover() -> list[SrcFile]:
    paths = (p.relative_to(ROOT).as_posix() for p in (ROOT / 'lib').rglob('*.dart'))
    return [SrcFile(p) for p in sorted(paths) if not excluded(p)]


def normalize(args: list[str]) -> set[str]:
    out = set()
    for a in args:
        p = Path(a)
        try:
            rel = (p if p.is_absolute() else Path.cwd() / p).resolve().relative_to(ROOT).as_posix()
        except ValueError:
            continue
        # A deleted path stays in: its baseline entries then show up as fixed.
        if rel.startswith('lib/') and rel.endswith('.dart') and not excluded(rel):
            out.add(rel)
    return out


def load_baseline() -> dict[str, dict[str, int]]:
    if not BASELINE.is_file():
        sys.exit(f'{BASELINE.relative_to(ROOT).as_posix()} is missing: '
                 'run python tool/ci/arch_gates.py --init-baseline once')
    return json.loads(BASELINE.read_text(encoding='utf-8'))


def write_baseline(results: list[Result]) -> int:
    data = {r.gate.gid: dict(sorted(r.counts.items())) for r in results if r.counts}
    BASELINE.write_bytes((json.dumps(data, indent=2, sort_keys=True) + '\n').encode('utf-8'))
    return sum(len(v) if gid == 'G-size' else sum(v.values()) for gid, v in data.items())


def probe(gid: str, path: str, text: str) -> list[Hit] | None:
    """Hits of one gate on a synthetic file; None when the file is out of its scope."""
    g = next(g for g in GATES if g.gid == gid)
    f = SrcFile(path, text)
    return g.find(f) if g.scope(f) else None


def self_test() -> None:
    self_test_common()
    self_test_state_management()


def self_test_state_management() -> None:
    def gate_ids(sm: str) -> list[str]:
        configure('grabby', sm)
        return [g.gid for g in GATES]

    getx_ids = gate_ids('getx')
    assert 'G9' in getx_ids and 'G-core-neutral' in getx_ids
    assert getx_ids.index('G4') == getx_ids.index('G3') + 1
    for sm in ('bloc', 'riverpod'):
        ids = gate_ids(sm)
        assert 'G9' not in ids and ids == [g for g in getx_ids if g != 'G9'], (sm, ids)
    assert getx_ids[-1] == 'G-size' and getx_ids.count('G-core-neutral') == 1

    # detection reads dependencies only: get_it must not count as get
    deps = 'name: demo_app\ndependencies:\n  flutter:\n    sdk: flutter\n'
    assert read_package(deps) == 'demo_app'
    assert detect_sm(deps + '  get: 4.7.3\n  get_it: ^9.3.0\n') == 'getx'
    assert detect_sm(deps + '  flutter_bloc: ^9.1.1\n  get_it: ^9.3.0\n') == 'bloc'
    assert detect_sm(deps + '  flutter_riverpod: ^3.3.0\n') == 'riverpod'
    for bad in (deps + '  get_it: ^9.3.0\n', deps + '  get: 4.7.3\n  flutter_bloc: ^9.1.1\n',
                deps + '  # get: 4.7.3\n'):
        try:
            detect_sm(bad)
        except SystemExit:
            continue
        raise AssertionError(f'detect_sm accepted:\n{bad}')

    di = "import 'package:grabby/app/di/injection_service.dart';"
    data = 'lib/modules/a/data/r.dart'
    domain = 'lib/modules/a/domain/u.dart'
    ref_lines = ['ref.read(fooProvider)', 'ref.watch(fooProvider)', 'x.ref.read(p)', 'ref . listen(p, f)']
    not_ref = ['// ref.read(p)', 'pref.read(p)', 'ref.invalidate(p)', 'final refresh = 1;', 'xref.watch(p)']
    wiring = 'lib/modules/a/di/p.dart'
    for sm, entries in (('getx', ('bindings',)), ('riverpod', ('providers', 'di')), ('bloc', ())):
        configure('grabby', sm)
        # G-app: only the SM's DI-entry folders may reach app/di
        for d in ('bindings', 'providers', 'di'):
            for base in ('presentation/', ''):
                hits = probe('G-app', f'lib/modules/a/{base}{d}/x.dart', di)
                assert len(hits) == (0 if d in entries else 1), (sm, base, d, hits)
        assert len(probe('G-app', 'lib/modules/a/presentation/controllers/c.dart', di)) == 1
        # a module di/ folder is a wiring layer under riverpod only: it may import data, nothing
        # below it may import it
        is_rp = sm == 'riverpod'
        assert layer_of(wiring) == ('di' if is_rp else 'presentation'), sm
        assert layer_of('lib/modules/a/di/sub/q.dart') == ('di' if is_rp else 'presentation'), sm
        assert layer_of('lib/modules/a/presentation/di/q.dart') == 'presentation', sm
        assert layer_of('lib/modules/di/views/v.dart') == 'presentation', sm
        wired = probe('G3', wiring, "import '../data/y.dart';")
        assert (wired is None) if is_rp else (len(wired) == 1), (sm, wired)
        assert len(probe('G3', 'lib/modules/a/presentation/providers/n.dart', "import '../../data/y.dart';")) == 1
        assert probe('G3', 'lib/modules/a/presentation/providers/n.dart', "import '../../di/p.dart';") == []
        assert len(probe('G1', domain, "import '../di/p.dart';")) == (1 if is_rp else 0), sm
        assert len(probe('G4', data, "import '../di/p.dart';")) == 1, sm
        assert len(probe('G-app', wiring, "import '../../../app/di/core_providers.dart';")) == (0 if is_rp else 1), sm
        # G10: the base locator everywhere, ref.* only under riverpod
        for line in ['sl<Foo>()', 'GetIt.instance', 'GetIt.I<Foo>()', 'Get.find<Foo>()']:
            assert len(probe('G10', data, line)) == 1, (sm, line)
        for line in ref_lines:
            assert len(probe('G10', domain, line)) == (1 if sm == 'riverpod' else 0), (sm, line)
        for line in not_ref:
            assert probe('G10', domain, line) == [], (sm, line)


def self_test_common() -> None:
    configure('grabby', 'getx')

    # resolution
    assert resolve('lib/modules/a/data/x.dart', '../domain/y.dart') == 'lib/modules/a/domain/y.dart'
    assert resolve('lib/core/a.dart', 'b/c.dart') == 'lib/core/b/c.dart'
    assert resolve('lib/core/a.dart', 'package:grabby/app/app.dart') == 'lib/app/app.dart'
    assert resolve('lib/core/a.dart', 'package:other_app/app/app.dart') == 'package:other_app/app/app.dart'
    assert resolve('lib/core/a.dart', 'package:dio/dio.dart') == 'package:dio/dio.dart'
    assert resolve('lib/core/a.dart', 'dart:async') is None

    # multi-line directive, both quote styles, comments, dart:
    src = SrcFile('lib/modules/a/domain/x.dart',
                  "import 'package:flutter/material.dart'\n    show Foo,\n        Bar;\n"
                  'import "../data/x.dart";\n'
                  "// import '../data/c.dart';\n  // import '../data/d.dart';\n"
                  "export '../data/e.dart' hide Z;\nimport 'dart:io';\n")
    assert src.imports == [(1, 'package:flutter/material.dart'),
                           (4, 'lib/modules/a/data/x.dart'),
                           (7, 'lib/modules/a/data/e.dart')], src.imports
    assert [h[0] for h in probe('G1', src.path, src.text)] == [4, 7]
    assert [h[0] for h in probe('G2', src.path, src.text)] == [1]

    # layers
    for path, want in [
        ('lib/core/utils/x.dart', 'core'),
        ('lib/app/theme/theme_controller.dart', 'app'),
        ('lib/app/shared/domain/entities/user.dart', 'domain'),
        ('lib/app/shared/data/x.dart', 'data'),
        ('lib/modules/settings/views/settings_view.dart', 'presentation'),
        ('lib/modules/settings/bindings/settings_binding.dart', 'presentation'),
        ('lib/modules/home/data/models/x.dart', 'data'),
        ('lib/modules/home/domain/entities/x.dart', 'domain'),
        ('lib/modules/home/presentation/views/x.dart', 'presentation'),
        ('lib/modules/data/views/x.dart', 'presentation'),
        ('lib/modules/a/presentation/widgets/data/x.dart', 'presentation'),
        ('lib/modules/a/views/domain/x.dart', 'presentation'),
        ('lib/modules/a/x.dart', 'presentation'),
        ('lib/main.dart', None),
    ]:
        assert layer_of(path) == want, (path, layer_of(path), want)
    assert excluded('lib/a/b.g.dart') and excluded('lib/core/gen/assets.gen.dart')
    assert excluded('lib/app/di/injection_service.config.dart') and excluded('lib/main.dart')
    assert not excluded('lib/core/config/environment.dart')

    # G-core, G3
    assert len(probe('G-core', 'lib/core/x.dart', "import '../app/app.dart';")) == 1
    assert len(probe('G-core', 'lib/core/x.dart', "import 'package:grabby/modules/a/b.dart';")) == 1
    assert probe('G-core', 'lib/core/x.dart', "import '../utils/y.dart';") == []
    assert probe('G-core', 'lib/app/x.dart', "import '../app/app.dart';") is None
    assert len(probe('G3', 'lib/modules/a/views/x.dart', "import '../data/y.dart';")) == 1
    assert probe('G3', 'lib/modules/a/views/x.dart', "import '../domain/y.dart';") == []
    assert probe('G3', 'lib/modules/a/data/x.dart', "import '../data/y.dart';") is None

    # G4
    assert len(probe('G4', 'lib/modules/a/data/x.dart', "import '../presentation/controllers/c.dart';")) == 1
    assert probe('G4', 'lib/modules/a/data/x.dart', "import '../domain/y.dart';") == []
    assert probe('G4', 'lib/modules/a/views/v.dart', "import '../data/y.dart';") is None

    # G-core-neutral
    for pkg in ('get/get.dart', 'get_it/get_it.dart', 'injectable/injectable.dart',
                'flutter_bloc/flutter_bloc.dart', 'bloc/bloc.dart', 'flutter_riverpod/flutter_riverpod.dart',
                'riverpod/riverpod.dart'):
        assert len(probe('G-core-neutral', 'lib/core/x.dart', f"import 'package:{pkg}';")) == 1, pkg
    assert len(probe('G-core-neutral', 'lib/core/x.dart',
                     "import 'package:get/get.dart' show Get;\nimport 'package:get_it/get_it.dart';")) == 2
    for pkg in ('flutter/material.dart', 'dio/dio.dart', 'equatable/equatable.dart', 'bloc_test/bloc_test.dart',
                'get_storage/get_storage.dart', 'riverpod_annotation/riverpod_annotation.dart',
                'grabby/core/utils/scale.dart'):
        assert probe('G-core-neutral', 'lib/core/x.dart', f"import 'package:{pkg}';") == [], pkg
    assert probe('G-core-neutral', 'lib/core/x.dart', "// import 'package:get/get.dart';") == []
    assert probe('G-core-neutral', 'lib/app/x.dart', "import 'package:get/get.dart';") is None
    assert probe('G-core-neutral', 'lib/modules/a/views/x.dart', "import 'package:get/get.dart';") is None

    # G-log
    for line in ['debugPrint(x)', 'print(x)', '  print (x);', 'a; print(x)']:
        assert len(probe('G-log', 'lib/core/x.dart', line)) == 1, line
    for line in ['  // print(x)', '/// print(x)', 'Fingerprint(', 'foo.print(', 'reprint(', 'x.debugPrint(', 'print;',
                 "import 'dart:math';", "// import 'dart:developer';"]:
        assert probe('G-log', 'lib/core/x.dart', line) == [], line
    for line in ["import 'dart:developer';", 'import "dart:developer" as dev;']:
        assert len(probe('G-log', 'lib/core/x.dart', line)) == 1, line
    assert probe('G-log', 'lib/core/logging/app_logger.dart', 'print(x)') is None

    # G2
    d = 'lib/modules/a/domain/x.dart'
    for pkg in ('flutter_svg/svg.dart', 'flutter/material.dart', 'get/get.dart', 'get_it/get_it.dart',
                'dio/dio.dart', 'flutter_bloc/flutter_bloc.dart', 'bloc/bloc.dart',
                'flutter_riverpod/flutter_riverpod.dart', 'riverpod/riverpod.dart'):
        assert len(probe('G2', d, f"import 'package:{pkg}';")) == 1, pkg
    for pkg in ('equatable/equatable.dart', 'injectable/injectable.dart', 'meta/meta.dart', 'dartz/dartz.dart'):
        assert probe('G2', d, f"import 'package:{pkg}';") == [], pkg
    assert probe('G2', 'lib/modules/a/data/x.dart', "import 'package:dio/dio.dart';") is None

    # G-app
    di = "import 'package:grabby/app/di/injection_service.dart';"
    assert probe('G-app', 'lib/modules/a/presentation/bindings/b.dart', di) == []
    assert probe('G-app', 'lib/modules/a/bindings/b.dart', di) == []
    assert len(probe('G-app', 'lib/modules/a/presentation/controllers/c.dart', di)) == 1
    assert len(probe('G-app', 'lib/modules/a/data/c.dart', di)) == 1
    for ok in ['routes/app_pages.dart', 'shared/domain/entities/user.dart', 'theme/theme_mode_button.dart']:
        assert probe('G-app', 'lib/modules/a/views/v.dart', f"import 'package:grabby/app/{ok}';") == [], ok
    for bad in ['session/auth_controller.dart', 'bootstrap/x.dart', 'shell/app_shell.dart', 'app.dart', 'di/injection_service.dart']:
        assert len(probe('G-app', 'lib/modules/a/views/v.dart', f"import '../../../app/{bad}';")) == 1, bad
    assert probe('G-app', 'lib/core/x.dart', di) is None

    # G9
    bind = 'lib/modules/a/presentation/bindings/b.dart'
    for line in ['Get.lazyPut<IFooRepository>(() => FooRepositoryImpl(sl()));',
                 'Get.put(FooDataSource());',
                 'Get.lazyPut(\n  () => FooRepositoryImpl(sl()));',
                 'Get.putAsync<FooDatasource>(() async => FooDatasource());',
                 'Get.putAsync(() async { return FooRepository(); });',
                 'Get.put(sl<IFooRepository>());',
                 'Get.lazyPut(() => sl<IFooRepository>());',
                 'Get.put(const FooRepositoryImpl());',
                 'Get.lazyPut(FooRepositoryImpl.new);',
                 'Get.put<Object>(FooRepositoryImpl());',
                 'Get.put(sl<IFooDataSource>());']:
        assert len(probe('G9', bind, line)) == 1, line
    for line in ['Get.lazyPut(() => FooController(sl<IFooRepository>()));',
                 'Get.put(FooController());',
                 'Get.lazyPut<FooController>(() => FooController(repo: FooRepository()));',
                 'Get.lazyPut(() => FooController(Get.find<FooRepository>()));']:
        assert probe('G9', bind, line) == [], line
    assert probe('G9', 'lib/modules/a/views/v.dart', 'Get.put(FooDataSource());') is None

    # G10
    data = 'lib/modules/a/data/r.dart'
    for line in ['sl<Foo>()', 'sl.get<Foo>()', 'sl()', 'getIt<Foo>()', 'GetIt.instance', 'Get.find<Foo>()',
                 'GetIt.I<Foo>()', 'GetIt.I.get<Foo>()', 'getIt.get<Foo>()', 'sl.getAsync<Foo>()',
                 'sl.getAll<Foo>()', 'sl.call<Foo>()', 'locator<Foo>()']:
        assert len(probe('G10', data, line)) == 1, line
    for line in ['// sl<Foo>()', 'final isl = 1;', 'rsl(x)', 'Get.isRegistered<X>()', 'ref.read(p)']:
        assert probe('G10', data, line) == [], line
    assert probe('G10', 'lib/modules/a/views/v.dart', 'sl<Foo>()') is None

    # G-size
    assert probe('G-size', 'lib/core/x.dart', 'a\n' * 801) == [(801, '801 lines')]
    assert probe('G-size', 'lib/core/x.dart', 'a\n' * 800) == []
    assert probe('G-size', 'lib/core/x.dart', '\n'.join(['a'] * 801)) == [(801, '801 lines')]

    # ratchet and canary
    files = [SrcFile('lib/core/a.dart', 'print(1);\nprint(2);\n'), SrcFile('lib/core/b.dart', 'x\n')]

    def by_id(checked, baseline):
        return {r.gate.gid: r for r in run(files, checked, baseline)}

    r = by_id(None, {})['G-log']
    assert r.grew == [('lib/core/a.dart', 2, 0)] and not r.fixed
    r = by_id(None, {'G-log': {'lib/core/a.dart': 2}})['G-log']
    assert not r.failed and r.tolerated == 2 and status(r) == 'PASS'
    r = by_id(None, {'G-log': {'lib/core/a.dart': 1}})['G-log']
    assert r.grew == [('lib/core/a.dart', 2, 1)] and r.tolerated == 1
    r = by_id(None, {'G-log': {'lib/core/a.dart': 3, 'lib/core/gone.dart': 1}})['G-log']
    assert [p for p, _, _ in r.fixed] == ['lib/core/a.dart', 'lib/core/gone.dart'] and not r.grew
    r = by_id({'lib/core/b.dart'}, {'G-log': {'lib/core/a.dart': 5}})['G-log']
    assert not r.failed and status(r) == 'PASS'
    skip = {r.gate.gid: r for r in run(files + [SrcFile('lib/modules/a/domain/d.dart', 'x')],
                                        {'lib/core/b.dart'}, {})}
    assert status(skip['G1']) == 'SKIP' and status(skip['G-core']) == 'PASS'
    r = by_id({'lib/core/a.dart'}, {'G-log': {'lib/core/a.dart': 5}})['G-log']
    assert r.fixed == [('lib/core/a.dart', 2, 5)]
    res = by_id(None, {'G-size': {'lib/core/a.dart': 900}})
    assert not res['G-size'].failed and res['G-size'].info == ['lib/core/a.dart: 900 -> under limit']
    assert status(res['G1']) == 'VACUOUS' and status(res['G-core']) == 'PASS'
    assert status(res['G-core-neutral']) == 'PASS'
    big = [SrcFile('lib/core/big.dart', 'a\n' * 850)]
    assert run(big, None, {'G-size': {'lib/core/big.dart': 850}})[-1].tolerated == 1
    assert run(big, None, {'G-size': {'lib/core/big.dart': 849}})[-1].grew == [('lib/core/big.dart', 850, 849)]
    assert run(big, None, {})[-1].grew == [('lib/core/big.dart', 850, 0)]
    leak = [SrcFile('lib/core/x.dart', "import 'package:get/get.dart';\n")]
    assert {r.gate.gid: r for r in run(leak, None, {})}['G-core-neutral'].grew == [('lib/core/x.dart', 1, 0)]

    # a moved file grows one path and fixes another but keeps the total
    moved = by_id(None, {'G-log': {'lib/core/old.dart': 2}})['G-log']
    assert moved.grew and moved.fixed and not total_grew([moved])
    assert total_grew([by_id(None, {'G-log': {'lib/core/old.dart': 1}})['G-log']])
    r = by_id({'lib/core/gone.dart'}, {'G-log': {'lib/core/gone.dart': 1}})['G-log']
    assert r.fixed == [('lib/core/gone.dart', 0, 1)]
    with contextlib.redirect_stdout(io.StringIO()):
        assert report([Result(GATES[0], 0, True, {}, {}, [], [], [], 0, 0)], detail=False) == 0
        assert report(run([SrcFile('lib/core/a.dart', 'x\n')], None, {}), detail=False) == 0


def main() -> int:
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--files', nargs='*', metavar='PATH', help='only scan and compare these files')
    ap.add_argument('--update-baseline', action='store_true', help='shrink-only baseline rewrite')
    ap.add_argument('--init-baseline', action='store_true',
                    help='write the current state unconditionally (use once to create the file)')
    ap.add_argument('--self-test', action='store_true', help='run the built-in checks and exit')
    ap.add_argument('--list', action='store_true', help='show gate status only, always exit 0')
    args = ap.parse_args()

    if args.self_test:
        self_test()
        print('self-test: ok')
        return 0
    if args.files is not None and (args.update_baseline or args.init_baseline):
        ap.error('--files cannot be combined with --update-baseline or --init-baseline')

    try:
        pubspec = PUBSPEC.read_text(encoding='utf-8')
    except OSError as e:
        sys.exit(f'cannot read pubspec.yaml: {e}')
    configure(read_package(pubspec), detect_sm(pubspec))

    files = discover()
    checked = None if args.files is None else normalize(args.files)
    results = run(files, checked, {} if args.init_baseline else load_baseline())

    if args.init_baseline:
        print(f'baseline written: {write_baseline(results)} violations '
              f'in {sum(len(r.counts) for r in results)} files')
        return 0
    if args.update_baseline:
        if grown := total_grew(results):
            report(grown, detail=True)
            print("\nbaseline not updated: a gate's total grew, fix the growth above first")
            return 1
        print(f'baseline updated: {write_baseline(results)} violations left')
        return 0

    print(f'package {PACKAGE}, state management {SM_NAME}\n')
    failed = report(results, detail=not args.list)
    return 0 if args.list else int(failed > 0)


if __name__ == '__main__':
    sys.exit(main())
