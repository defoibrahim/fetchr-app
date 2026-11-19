import json
import os
import sys
import types

import pytest
import yt_dlp
import yt_dlp.utils
import yt_dlp.version
from yt_dlp.extractor.youtube.jsc._registry import _jsc_providers

import fetchr_bridge
from fetchr_bridge import api, jsc, run, selftest
from fetchr_bridge.inproc_popen import InProcPopen

BUNDLED = os.path.realpath(os.path.dirname(os.path.dirname(yt_dlp.__file__)))


@pytest.fixture
def fake_fetchr(monkeypatch):
    fake = types.ModuleType("_fetchr")
    fake.logged = []
    fake.log = fake.logged.append
    fake.ffmpeg = lambda argv, task: (0, "ffmpeg version 7.1-fetchr Copyright (c) the FFmpeg developers")
    fake.ffprobe = lambda argv, task: (0, "")
    monkeypatch.setitem(sys.modules, "_fetchr", fake)
    monkeypatch.delitem(sys._xoptions, selftest.DIR_OPTION, raising=False)
    monkeypatch.setattr(selftest, "dropped", None)
    return fake


def check():
    return selftest.run(jsc, run._options([]))


def test_selftest_checks_import_shim_and_provider(fake_fetchr, monkeypatch):
    version = yt_dlp.version.__version__
    assert check() == {"ok": True, "version": version, "reason": ""}

    with monkeypatch.context() as m:
        m.setattr(yt_dlp.utils, "Popen", type("RealPopen", (), {}))
        result = check()
        assert result["ok"] is False and result["version"] == version
        assert "ffmpeg" in result["reason"]

    with monkeypatch.context() as m:
        # The shim is installed but has no in-process ffmpeg behind it.
        m.setitem(sys.modules, "_fetchr", None)
        assert "ffmpeg" in check()["reason"]

    assert "JS challenge provider" in selftest.run(None, run._options([]))["reason"]

    with monkeypatch.context() as m:
        m.delitem(_jsc_providers.value, jsc._provider.PROVIDER_KEY)
        assert "not registered" in check()["reason"]

    with monkeypatch.context() as m:
        m.setattr(jsc._provider, "is_available", lambda self: False)
        assert "not available" in check()["reason"]

    assert any("selftest failed" in line for line in fake_fetchr.logged)
    assert check()["ok"] is True


def test_selftest_fails_when_the_installed_copy_did_not_load(fake_fetchr, monkeypatch, tmp_path):
    monkeypatch.setitem(sys._xoptions, selftest.DIR_OPTION, str(tmp_path / "2026.11.12"))
    result = check()
    assert result["ok"] is False
    assert "2026.11.12" in result["reason"]


def test_selftest_fails_when_yt_dlp_and_ejs_come_from_different_folders(fake_fetchr, monkeypatch, tmp_path):
    import yt_dlp_ejs

    monkeypatch.setattr(yt_dlp_ejs, "__file__", str(tmp_path / "yt_dlp_ejs" / "__init__.py"))
    assert "different folders" in check()["reason"]


def test_selftest_reports_why_the_installed_copy_was_dropped(fake_fetchr, monkeypatch):
    monkeypatch.setattr(selftest, "dropped", "yt-dlp 2026.11.12 failed to import: SyntaxError()")
    result = check()
    assert result == {"ok": False, "version": yt_dlp.version.__version__,
                      "reason": "yt-dlp 2026.11.12 failed to import: SyntaxError()"}


def test_selftest_after_a_fallback_still_checks_what_runs(fake_fetchr, monkeypatch):
    monkeypatch.setattr(selftest, "dropped", "yt-dlp 2026.11.12 failed to import: SyntaxError: x")
    monkeypatch.setattr(yt_dlp.utils, "Popen", type("RealPopen", (), {}))
    reason = check()["reason"]
    assert reason.startswith("yt-dlp 2026.11.12 failed to import: SyntaxError: x; ")
    assert "ffmpeg shim is not active" in reason


def test_selftest_is_a_bridge_call(fake_fetchr, monkeypatch):
    monkeypatch.setattr(api, "_jsc", jsc)
    envelope = json.loads(api.call("selftest", "{}"))
    assert envelope == {"ok": True, "value": {"ok": True, "version": yt_dlp.version.__version__, "reason": ""}}


def _packages():
    return {name: module for name, module in sys.modules.items() if selftest.is_package_module(name)}


@pytest.fixture
def isolated_yt_dlp():
    """Lets a test import yt_dlp and the bridge's jsc afresh; the session's modules come back afterwards."""
    saved = _packages()
    saved_jsc = sys.modules.pop(jsc.__name__)
    for name in saved:
        del sys.modules[name]
    yield
    for name in _packages():
        del sys.modules[name]
    sys.modules.update(saved)
    sys.modules[jsc.__name__] = saved_jsc
    fetchr_bridge.jsc = saved_jsc
    sys.modules.pop("fetchr_update_helper", None)


def _broken_update(root, version="2026.11.12"):
    folder = root / version
    (folder / "yt_dlp").mkdir(parents=True)
    # A top-level module of the update's own, imported before the failure, must go too.
    (folder / "fetchr_update_helper.py").write_text("")
    (folder / "yt_dlp" / "__init__.py").write_text("import fetchr_update_helper\nraise ImportError('corrupt update')\n")
    (folder / "yt_dlp_ejs").mkdir()
    (folder / "yt_dlp_ejs" / "__init__.py").write_text("")
    return folder


def test_broken_installed_copy_falls_back_to_the_bundled_one(fake_fetchr, monkeypatch, tmp_path, isolated_yt_dlp):
    import importlib

    folder = _broken_update(tmp_path)
    monkeypatch.setitem(sys._xoptions, selftest.DIR_OPTION, str(folder))
    monkeypatch.syspath_prepend(str(folder))

    selftest.load()

    assert str(folder) not in sys.path
    assert "fetchr_update_helper" not in sys.modules
    assert os.path.realpath(sys.modules["yt_dlp"].__file__).startswith(BUNDLED + os.sep)
    assert os.path.realpath(sys.modules["yt_dlp_ejs"].__file__).startswith(BUNDLED + os.sep)
    assert selftest.dropped == "yt-dlp 2026.11.12 failed to import: ImportError: corrupt update"
    assert any("failed to import" in line for line in fake_fetchr.logged)
    assert issubclass(sys.modules["yt_dlp.utils"].Popen, InProcPopen), "the shim took for the bundled copy"

    # As at boot: jsc is imported after load, so it registers with the bundled copy.
    fresh_jsc = importlib.import_module(jsc.__name__)
    assert fresh_jsc._provider.__module__ == jsc.__name__
    result = selftest.run(fresh_jsc, run._options([]))
    assert result["ok"] is False
    assert result["reason"] == selftest.dropped, "nothing else is wrong with the copy that runs"


def test_bundled_copy_that_fails_to_import_still_raises(fake_fetchr, monkeypatch, tmp_path, isolated_yt_dlp):
    # Without an installed update there is nothing to fall back to, so boot fails as before.
    folder = _broken_update(tmp_path)
    monkeypatch.syspath_prepend(str(folder))
    monkeypatch.delitem(sys._xoptions, selftest.DIR_OPTION, raising=False)
    with pytest.raises(ImportError, match="corrupt update"):
        selftest.load()
    assert selftest.dropped is None


def test_compile_writes_timestamped_bytecode_next_to_the_sources(tmp_path):
    import importlib.util

    package = tmp_path / "2026.11.12" / "yt_dlp"
    package.mkdir(parents=True)
    (package / "__init__.py").write_text("VALUE = 1\n")
    (package / "broken.py").write_text("def (:\n")
    envelope = json.loads(api.call("compile", json.dumps({"dir": str(tmp_path / "2026.11.12")})))
    assert envelope == {"ok": True, "value": {"compiled": False}}, "one file did not compile"
    pyc = package / "__pycache__" / f"__init__.{sys.implementation.cache_tag}.pyc"
    data = pyc.read_bytes()
    assert data[:4] == importlib.util.MAGIC_NUMBER
    # Flags 0: checked against the source's mtime, so an edited source is read again, not the stale bytecode.
    assert int.from_bytes(data[4:8], "little") == 0
