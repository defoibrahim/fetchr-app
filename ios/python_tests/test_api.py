import json

import yt_dlp

from fetchr_bridge import api, run


def call(name, payload=None):
    return json.loads(api.call(name, json.dumps(payload or {})))


def test_ping_returns_yt_dlp_version():
    api.boot()
    reply = call("ping")
    assert reply["ok"] is True
    assert reply["value"]["ytDlpVersion"] == "2026.10.26"


def test_unknown_handler_is_an_error_envelope():
    reply = call("nope")
    assert reply["ok"] is False
    assert reply["message"]


def test_download_error_is_an_error_envelope(monkeypatch):
    def fail(argv, url):
        raise yt_dlp.utils.DownloadError(
            "ERROR: [generic] x: <urlopen error [Errno 8] nodename nor servname provided, or not known>"
        )

    monkeypatch.setattr(run, "info", fail)
    reply = call("info", {"argv": [], "url": "https://example.com/x"})
    assert reply["ok"] is False
    assert "nodename nor servname provided" in reply["message"]


def test_download_error_from_extract_info_keeps_its_error_line(monkeypatch, tmp_path):
    def extract_info(self, url, download=True, **kwargs):
        self.report_error("[generic] x: Unsupported URL: https://example.com/x")

    monkeypatch.setattr(yt_dlp.YoutubeDL, "extract_info", extract_info)
    reply = call("info", {"argv": ["--cache-dir", str(tmp_path)], "url": "https://example.com/x"})
    assert reply["ok"] is False
    assert reply["message"] == "ERROR: [generic] x: Unsupported URL: https://example.com/x"


def test_debug_emit_exists_only_when_testing(monkeypatch):
    monkeypatch.delenv("FETCHR_TESTING", raising=False)
    assert call("debug_emit", {"task": "t", "json": "{}"})["ok"] is False
    assert "no bridge call" in call("debug_emit", {"task": "t", "json": "{}"})["message"]

    monkeypatch.setenv("FETCHR_TESTING", "1")
    # The handler exists now; it fails only because _fetchr lives in the app, not on the host.
    assert "_fetchr" in call("debug_emit", {"task": "t", "json": "{}"})["message"]


def test_bad_payload_is_an_error_envelope():
    reply = json.loads(api.call("ping", "not json"))
    assert reply["ok"] is False
    assert reply["message"]


def test_replies_are_strict_json(monkeypatch):
    monkeypatch.setitem(api._HANDLERS, "ping", lambda payload: {"fps": float("nan")})
    text = api.call("ping", "{}")
    assert "NaN" not in text
    assert json.loads(text)["value"] == {"fps": None}


def test_value_with_lone_surrogate_is_replaced(monkeypatch):
    monkeypatch.setattr(run, "info", lambda argv, url: {"title": "broken \ud83d end"})
    text = api.call("info", json.dumps({"argv": [], "url": "https://example.com/x"}))
    assert "\\ud83d" not in text
    assert json.loads(text)["value"] == {"title": "broken � end"}


def test_error_message_with_lone_surrogate_is_replaced(monkeypatch):
    def fail(argv, url):
        raise yt_dlp.utils.DownloadError("ERROR: [generic] broken \ud83d end: Unsupported URL")

    monkeypatch.setattr(run, "info", fail)
    text = api.call("info", json.dumps({"argv": [], "url": "https://example.com/x"}))
    assert "\\ud83d" not in text
    reply = json.loads(text)
    assert reply["ok"] is False
    assert reply["message"] == "ERROR: [generic] broken � end: Unsupported URL"


def test_debug_echo_exists_only_when_testing(monkeypatch):
    payload = {"json": '"broken \\ud83d end"'}
    monkeypatch.delenv("FETCHR_TESTING", raising=False)
    assert "no bridge call" in call("debug_echo", payload)["message"]

    monkeypatch.setenv("FETCHR_TESTING", "1")
    assert call("debug_echo", payload)["value"] == "broken � end"
    assert call("debug_echo", {**payload, "raise": True})["message"] == "broken � end"
