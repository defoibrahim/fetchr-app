#!/usr/bin/env bash
# One entry point for the checks: `tool/check.sh fast|full`.
#   fast  staged .dart files only, seconds
#   full  everything, before a push or in CI
set -euo pipefail

# The app can live in a subfolder of the git repo, so
# anchor on this script, not on the git top level. Git pathspecs below are then
# relative to the app folder; --relative makes git print paths the same way.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# A global flutter on PATH can differ from the pinned one (.fvmrc), and the
# formatter style and analyzer rules follow the SDK.
if [ -d .fvm/flutter_sdk/bin ]; then
  PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"
else
  echo ".fvm/flutter_sdk missing: run 'fvm use'" >&2
  exit 1
fi

step() { printf '\n==> %s\n' "$1"; }

# Without a package config dart format falls back to the newest language
# version and its style, which flags every file.
ensure_deps() {
  [ -f .dart_tool/package_config.json ] || flutter pub get
}

# A doubled slash loads the file as a second library (separate GetIt,
# "X is not a subtype of X"); the analyzer normalizes it, the compiler
# does not. A relative ../lib/ import is caught by avoid_relative_lib_imports.
# --untracked: a first commit has nothing tracked yet.
check_import_uris() {
  if git grep --untracked -nE "^(import|export|part) '[^']*[^:]//" -- lib test tool; then
    echo "import URI contains '//'" >&2
    return 1
  fi
}

# On Windows python3 can be the Microsoft Store stub, which exits non-zero,
# so each candidate has to actually run.
PY=""
find_py() {
  local cand
  [ -z "$PY" ] || return 0
  for cand in python3 python; do
    if "$cand" -c 'import sys; sys.exit(sys.version_info < (3, 9))' >/dev/null 2>&1; then
      PY="$cand"
      return 0
    fi
  done
  echo "no python >= 3.9 on PATH (tried python3, python)" >&2
  return 1
}

py() {
  find_py
  "$PY" "$@"
}

# Nothing to compare against before the first commit.
check_generated_committed() {
  local gen=('*.gen.dart' '*.config.dart' '*.g.dart')
  local untracked
  if ! git rev-parse --verify --quiet HEAD >/dev/null; then
    echo "no commit yet, skipping"
    return 0
  fi
  git diff --exit-code -- "${gen[@]}"
  untracked="$(git ls-files --others --exclude-standard -- "${gen[@]}")"
  if [ -n "$untracked" ]; then
    printf 'generated but not committed:\n%s\n' "$untracked" >&2
    return 1
  fi
}

# An app without code generation (no injectable, no flutter_gen) has no build_runner.
has_build_runner() {
  grep -Eq '^[[:space:]]+build_runner:' pubspec.yaml
}

static_checks() {
  ensure_deps

  step "import URIs load each library once"
  check_import_uris
}

fast() {
  static_checks

  step "dart format (staged files)"
  # Batched because Windows caps the command line.
  git diff --cached --relative --name-only --diff-filter=ACMR -z -- '*.dart' |
    xargs -0 -r -s 7000 dart format --output=none --set-exit-if-changed

  # Captured, not piped to grep -q: pipefail would turn its early exit into a failure.
  # Deletions are included so their baseline entries surface as fixed.
  local staged_lib
  staged_lib="$(git diff --cached --relative --name-only --diff-filter=ACMRD -- 'lib/*.dart')"
  if [ -n "$staged_lib" ]; then
    step "architecture gates (staged lib files)"
    find_py
    git diff --cached --relative --name-only --diff-filter=ACMRD -z -- 'lib/*.dart' |
      xargs -0 -r -s 7000 "$PY" tool/ci/arch_gates.py --files
  fi
}

full() {
  static_checks

  step "architecture gates (self-test)"
  py tool/ci/arch_gates.py --self-test

  step "architecture gates (all lib files)"
  py tool/ci/arch_gates.py

  step "dart format (lib, test)"
  dart format --output=none --set-exit-if-changed lib test

  if has_build_runner; then
    step "build_runner"
    dart run build_runner build

    step "generated files match what is committed"
    check_generated_committed
  fi

  step "flutter analyze"
  flutter analyze

  step "flutter test"
  flutter test
}

case "${1:-}" in
  fast) fast ;;
  full) full ;;
  *)
    echo "usage: tool/check.sh fast|full" >&2
    exit 2
    ;;
esac

printf '\ncheck %s: ok\n' "$1"
