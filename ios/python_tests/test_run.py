import json

import pytest
import yt_dlp

from fetchr_bridge import api, run

URL = "https://example.com/watch?v=x"


def info_reply(monkeypatch, tmp_path, value):
    """The info envelope's text when extract_info returns `value`."""
    monkeypatch.setattr(yt_dlp.YoutubeDL, "extract_info", lambda self, url, download=True, **kwargs: value)
    return api.call("info", json.dumps({"argv": ["--cache-dir", str(tmp_path)], "url": URL}))


def test_info_returns_sanitized_info(monkeypatch, tmp_path):
    seen = {}

    def extract_info(self, url, download=True, **kwargs):
        seen.update(url=url, download=download, params=self.params)
        return {"id": "x", "title": "T", "formats": []}

    monkeypatch.setattr(yt_dlp.YoutubeDL, "extract_info", extract_info)
    out = run.info(["--flat-playlist", "--cache-dir", str(tmp_path)], URL)
    assert out["title"] == "T"
    assert isinstance(out, dict)
    assert seen["url"] == URL
    assert seen["download"] is False
    params = seen["params"]
    assert params["extract_flat"] == "in_playlist"
    assert params["ignoreerrors"] is False
    assert params["color"] == {"stdout": "never", "stderr": "never"}


def test_non_finite_floats_become_null(monkeypatch, tmp_path):
    text = info_reply(
        monkeypatch, tmp_path, {"id": "x", "fps": float("nan"), "tbr": float("inf"), "formats": [{"vbr": float("-inf")}]}
    )
    assert '"fps": null' in text
    assert '"tbr": null' in text
    assert json.loads(text)["value"]["formats"][0]["vbr"] is None


def test_bad_arguments_raise_value_error():
    with pytest.raises(ValueError):
        run.info(["--bogus"], URL)


def test_lone_surrogates_are_replaced(monkeypatch, tmp_path):
    text = info_reply(
        monkeypatch, tmp_path, {"id": "x", "title": "broken \ud83d end", "tags": ["\udc00"], "chapters": {"k\ud83d": 1}}
    )
    out = json.loads(text)["value"]
    assert out["title"] == "broken � end"
    assert out["tags"] == ["�"]
    assert out["chapters"] == {"k�": 1}
    assert "\\ud8" not in text and "\\udc" not in text


def test_paired_surrogates_survive_as_one_code_point(monkeypatch, tmp_path):
    text = info_reply(monkeypatch, tmp_path, {"id": "x", "title": json.loads('"\\ud83d\\ude00"')})
    assert json.loads(text)["value"]["title"] == "\U0001f600"
