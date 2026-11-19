import importlib
import json
import sys
import types

import pytest
from yt_dlp.extractor.youtube.jsc._registry import _jsc_preferences, _jsc_providers
from yt_dlp.extractor.youtube.jsc.provider import (
    JsChallengeRequest,
    JsChallengeType,
    NChallengeInput,
    NChallengeOutput,
)
import yt_dlp
from yt_dlp.globals import supported_js_runtimes

import fetchr_bridge
from fetchr_bridge import api, jsc, run

EJS_MODULE = "yt_dlp.extractor.youtube.jsc._builtin.ejs"


@pytest.fixture
def fake_fetchr(monkeypatch):
    fake = types.ModuleType("_fetchr")
    fake.sources = []
    fake.reply = "a\nb"

    def js_eval(source):
        fake.sources.append(source)
        return fake.reply

    fake.js_eval = js_eval
    monkeypatch.setitem(sys.modules, "_fetchr", fake)
    return fake


@pytest.fixture
def fresh_jsc(monkeypatch):
    """Imports a new copy of jsc; the registries and the original module come back afterwards."""
    providers = dict(_jsc_providers.value)
    preferences = set(_jsc_preferences.value)
    for key in [k for k, cls in _jsc_providers.value.items() if cls.__module__ == jsc.__name__]:
        del _jsc_providers.value[key]
    _jsc_preferences.value.difference_update({p for p in preferences if p.__module__ == jsc.__name__})
    monkeypatch.delitem(sys.modules, jsc.__name__)
    monkeypatch.setattr(fetchr_bridge, "jsc", jsc)

    def load():
        return importlib.import_module(jsc.__name__)

    yield load
    _jsc_providers.value.clear()
    _jsc_providers.value.update(providers)
    _jsc_preferences.value.clear()
    _jsc_preferences.value.update(preferences)


def test_boot_survives_a_broken_jsc(monkeypatch, fake_fetchr, tmp_path):
    logged = []
    fake_fetchr.log = logged.append
    # As if a yt-dlp update removed the private module jsc builds on.
    monkeypatch.setitem(sys.modules, "yt_dlp.utils._jsruntime", None)
    monkeypatch.delitem(sys.modules, jsc.__name__)
    monkeypatch.delattr(fetchr_bridge, "jsc")
    monkeypatch.delitem(supported_js_runtimes.value, "javascriptcore")
    monkeypatch.setattr(api, "_jsc", api._jsc)
    api.boot()
    assert any("JS challenge provider unavailable" in line for line in logged)
    assert json.loads(api.call("ping", "{}"))["ok"] is True
    monkeypatch.setenv("FETCHR_TESTING", "1")
    assert json.loads(api.call("debug_jsc", "{}"))["value"] == {"plan": None, "solveMs": []}

    seen = {}

    def extract_info(self, url, download=True, **kwargs):
        seen["js_runtimes"] = self.params["js_runtimes"]
        return {"id": "x", "formats": []}

    # YoutubeDL drops the unregistered runtime with a warning instead of failing.
    monkeypatch.setattr(yt_dlp.YoutubeDL, "extract_info", extract_info)
    assert run.info(["--cache-dir", str(tmp_path)], "https://example.com/v")["id"] == "x"
    assert seen["js_runtimes"] == {}


def preference_of(cls):
    provider = object.__new__(cls)
    return sum(pref(provider, []) for pref in _jsc_preferences.value)


def test_runtime_registered():
    runtime = supported_js_runtimes.value["javascriptcore"]
    info = runtime().info
    assert info.supported
    assert info.name == "javascriptcore"


def test_plan_a_by_default():
    assert jsc.ACTIVE_PLAN == "A"
    assert _jsc_providers.value[jsc.FetchrJscJCP.PROVIDER_KEY] is jsc.FetchrJscJCP
    assert jsc.FetchrJscJCP.PROVIDER_NAME == "fetchr-jsc"
    assert jsc.FetchrJscJCP.JS_RUNTIME_NAME == "javascriptcore"
    assert preference_of(jsc.FetchrJscJCP) == 1000


def test_plan_b_used_when_plan_a_import_fails(monkeypatch, fresh_jsc):
    # A None entry makes the import raise ImportError, as a renamed or removed module would.
    monkeypatch.setitem(sys.modules, EJS_MODULE, None)
    module = fresh_jsc()
    assert module.ACTIVE_PLAN == "B"
    public = _jsc_providers.value[module.FetchrJscPublicJCP.PROVIDER_KEY]
    assert public is module.FetchrJscPublicJCP
    assert preference_of(public) == 1000
    assert "javascriptcore" in supported_js_runtimes.value


def test_plan_b_used_when_plan_a_contract_changes(monkeypatch, fresh_jsc):
    ejs = importlib.import_module(EJS_MODULE)
    monkeypatch.delattr(ejs.EJSBaseJCP, "_run_js_runtime")
    assert fresh_jsc().ACTIVE_PLAN == "B"


def test_run_js_collects_console_log(fake_fetchr):
    assert jsc.run_js("console.log('a')") == "a\nb"
    source = fake_fetchr.sources[-1]
    assert source.startswith(jsc.PRELUDE)
    assert source.endswith(jsc.EPILOGUE)
    assert "console.log('a')" in source


def test_run_js_records_solve_time(fake_fetchr):
    before = len(jsc.solve_ms)
    jsc.run_js("0")
    assert len(jsc.solve_ms) == before + 1
    assert jsc.solve_ms[-1] >= 0


def test_public_provider_solves_through_run_js(fake_fetchr, monkeypatch):
    request = JsChallengeRequest(
        type=JsChallengeType.N, input=NChallengeInput(player_url="https://p/base.js", challenges=["abc"]), video_id="v"
    )
    fake_fetchr.reply = json.dumps(
        {"type": "result", "responses": [{"type": "result", "data": {"abc": "xyz"}}]}
    )
    provider = object.__new__(jsc.FetchrJscPublicJCP)
    provider.logger = types.SimpleNamespace(info=lambda *a, **k: None)
    monkeypatch.setattr(jsc.FetchrJscPublicJCP, "_get_player", lambda self, video_id, url: "var player = 1;")
    [response] = list(provider._real_bulk_solve([request]))
    assert response.error is None
    assert response.response.output == NChallengeOutput({"abc": "xyz"})
    source = fake_fetchr.sources[-1]
    assert "Object.assign(globalThis, lib);" in source
    assert '"player": "var player = 1;"' in source
    assert '"challenges": ["abc"]' in source


def test_options_enable_javascriptcore():
    opts = run._options(["--flat-playlist"])
    assert opts["js_runtimes"] == {"javascriptcore": {}}
    assert "ejs:github" in opts["remote_components"]
