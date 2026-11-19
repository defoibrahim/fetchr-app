import json
import sys
import types

import pytest
import yt_dlp
from yt_dlp.utils import DownloadCancelled, DownloadError

from fetchr_bridge import api, inproc_popen, run

URL = "https://example.com/watch?v=x"
INFO = {"id": "x", "title": "T", "protocol": "https", "ext": "mp4"}


@pytest.fixture
def fake(monkeypatch):
    fake = types.ModuleType("_fetchr")
    fake.events = []
    fake.cancelled = []
    fake.forgotten = []
    fake.emit = lambda task, text: fake.events.append((task, json.loads(text)))
    fake.cancel_session = fake.cancelled.append
    fake.forget_session = fake.forgotten.append
    monkeypatch.setitem(sys.modules, "_fetchr", fake)
    return fake


@pytest.fixture
def ydl(monkeypatch):
    """Stands in for yt-dlp's extraction and download; `body(ydl, info)` plays the download."""
    state = types.SimpleNamespace(info=dict(INFO), body=lambda ydl, info: None, extracted=[], processed=[])

    def extract_info(self, url, download=True, **kwargs):
        state.extracted.append((url, download, self.params))
        return state.info

    def process_ie_result(self, ie_result, download=True, extra_info=None):
        state.processed.append((ie_result, download))
        state.body(self, ie_result)
        return ie_result

    monkeypatch.setattr(yt_dlp.YoutubeDL, "extract_info", extract_info)
    monkeypatch.setattr(yt_dlp.YoutubeDL, "process_ie_result", process_ie_result)
    return state


def progress(ydl, **d):
    for hook in ydl.params["progress_hooks"]:
        hook({"status": "downloading", **d})


def finished(ydl, **d):
    for hook in ydl.params["progress_hooks"]:
        hook({"status": "finished", **d})


def postprocessor(ydl, name, status="started"):
    for hook in ydl.params["postprocessor_hooks"]:
        hook({"status": status, "postprocessor": name, "info_dict": {}})


def download(tmp_path, task="t1", argv=None):
    payload = {"argv": argv or ["--cache-dir", str(tmp_path / "cache")], "url": URL, "task": task,
               "outDir": str(tmp_path)}
    return json.loads(api.call("download", json.dumps(payload)))


def events(fake, kind=None):
    return [event for _, event in fake.events if kind is None or event["type"] == kind]


def test_progress_events_throttled(fake, ydl, tmp_path):
    def body(ydl_, info):
        for i in range(20):
            progress(ydl_, downloaded_bytes=i, total_bytes=100)
        finished(ydl_, downloaded_bytes=100, total_bytes=100)

    ydl.body = body
    assert download(tmp_path)["ok"] is True
    sent = events(fake)
    assert [event["downloaded"] for event in sent] == [0, 100]
    assert all(task == "t1" for task, _ in fake.events)


def test_progress_emitted_again_after_250_ms(fake, ydl, tmp_path, monkeypatch):
    now = [100.0]
    monkeypatch.setattr(run, "_clock", lambda: now[0])

    def body(ydl_, info):
        for step in (0.0, 0.1, 0.24, 0.26, 0.3, 0.52):
            now[0] = 100.0 + step
            progress(ydl_, downloaded_bytes=int(step * 100))

    ydl.body = body
    download(tmp_path)
    assert [event["downloaded"] for event in events(fake)] == [0, 26, 52]


def test_progress_event_fields(fake, ydl, tmp_path):
    def body(ydl_, info):
        progress(ydl_, downloaded_bytes=10, total_bytes_estimate=1234.7, speed=512.5, eta=3.0)

    ydl.body = body
    download(tmp_path)
    assert events(fake) == [
        {"type": "progress", "stage": "downloading", "downloaded": 10, "total": 1234, "speed": 512.5, "eta": 3}
    ]


def test_progress_event_unknowns_are_null(fake, ydl, tmp_path):
    ydl.body = lambda ydl_, info: progress(ydl_, speed=float("nan"))
    download(tmp_path)
    assert events(fake) == [
        {"type": "progress", "stage": "downloading", "downloaded": None, "total": None, "speed": None, "eta": None}
    ]


def test_postprocessor_stage_event(fake, ydl, tmp_path):
    def body(ydl_, info):
        progress(ydl_, downloaded_bytes=1)
        postprocessor(ydl_, "Merger")
        postprocessor(ydl_, "Merger", "finished")
        postprocessor(ydl_, "MoveFiles")

    ydl.body = body
    download(tmp_path)
    assert events(fake, "stage") == [{"type": "stage", "stage": "postProcessing", "pp": "Merger"}]


def test_stage_change_back_to_downloading_is_sent_at_once(fake, ydl, tmp_path):
    def body(ydl_, info):
        progress(ydl_, downloaded_bytes=1)
        postprocessor(ydl_, "FixupM3u8")
        progress(ydl_, downloaded_bytes=2)

    ydl.body = body
    download(tmp_path)
    assert [(event["type"], event.get("downloaded")) for event in events(fake)] == [
        ("progress", 1), ("stage", None), ("progress", 2)
    ]


def test_live_refused(fake, ydl, tmp_path):
    ydl.info = {**INFO, "is_live": True}
    reply = download(tmp_path)
    assert reply["ok"] is False
    assert reply["hint"] == "unsupported_site"
    assert reply["message"] == "Live streams can't be downloaded on iPhone yet."
    assert ydl.processed == []


@pytest.mark.parametrize("info", [
    {**INFO, "protocol": "rtmp"},
    {**INFO, "protocol": "https+rtmpe"},
    {**INFO, "protocol": "https+https", "requested_formats": [{"protocol": "https"}, {"protocol": "rtsp"}]},
    {**INFO, "protocol": "mms"},
])
def test_rtmp_refused(fake, ydl, tmp_path, info):
    ydl.info = info
    reply = download(tmp_path)
    assert reply["ok"] is False
    assert reply["hint"] == "unsupported_site"
    assert reply["message"] == "This stream can't be downloaded on iPhone yet."
    assert ydl.processed == []


# A post with several videos comes back as a playlist even with --no-playlist; Android downloads its entries and
# keeps the largest file, so iOS does too, after checking every entry.
def test_multi_video_result_downloads_its_entries(fake, ydl, tmp_path):
    ydl.info = {"_type": "multi_video", "id": "p", "entries": [dict(INFO), {**INFO, "id": "y"}]}
    reply = download(tmp_path)
    assert reply["ok"] is True
    assert len(ydl.processed) == 1


def test_playlist_entry_that_is_live_is_refused(fake, ydl, tmp_path):
    ydl.info = {"_type": "playlist", "id": "p", "entries": [dict(INFO), None, {**INFO, "is_live": True}]}
    reply = download(tmp_path)
    assert reply["ok"] is False
    assert reply["message"] == "Live streams can't be downloaded on iPhone yet."
    assert ydl.processed == []


def test_cover_of_a_live_stream_is_not_refused(fake, ydl, tmp_path):
    ydl.info = {**INFO, "is_live": True, "protocol": "m3u8+rtmp"}
    reply = download(tmp_path, argv=["--cache-dir", str(tmp_path / "cache"), "--skip-download", "--write-thumbnail"])
    assert reply["ok"] is True


def test_failing_emit_does_not_fail_the_download(fake, ydl, tmp_path):
    def broken(task, text):
        raise RuntimeError("emit broke")

    fake.emit = broken

    def body(ydl_, info):
        progress(ydl_, downloaded_bytes=1, total_bytes=2)
        postprocessor(ydl_, "Merger")
        finished(ydl_, downloaded_bytes=2, total_bytes=2)

    ydl.body = body
    assert download(tmp_path)["ok"] is True


def test_download_failure_envelope(fake, ydl, tmp_path):
    def body(ydl_, info):
        raise DownloadError("ERROR: [youtube] x: Video unavailable")

    ydl.body = body
    reply = download(tmp_path)
    assert reply["ok"] is False
    assert reply["message"].startswith("ERROR:")
    assert reply["hint"] is None


def test_cancel_raises_download_cancelled(fake, ydl, tmp_path):
    raised = []

    def body(ydl_, info):
        progress(ydl_, downloaded_bytes=1)
        assert json.loads(api.call("cancel", json.dumps({"task": "t1"})))["ok"] is True
        try:
            progress(ydl_, downloaded_bytes=2)
        except DownloadCancelled as exc:
            raised.append(exc)
            raise

    ydl.body = body
    reply = download(tmp_path)
    assert len(raised) == 1
    assert reply["ok"] is False
    assert [event["downloaded"] for event in events(fake)] == [1]


def test_cancel_stops_postprocessing_too(fake, ydl, tmp_path):
    def body(ydl_, info):
        run.cancel("t1")
        postprocessor(ydl_, "Merger")

    ydl.body = body
    assert download(tmp_path)["ok"] is False
    assert events(fake) == []


def test_cancel_handler_calls_cancel_task(fake, monkeypatch):
    seen = []
    monkeypatch.setattr(inproc_popen, "cancel_task", seen.append)
    reply = json.loads(api.call("cancel", json.dumps({"task": "t9"})))
    assert reply == {"ok": True, "value": None}
    assert seen == ["t9"]
    inproc_popen.forget_task("t9")


def test_cancel_marks_the_bridge_session(fake):
    api.call("cancel", json.dumps({"task": "t9"}))
    assert fake.cancelled == ["t9"]
    inproc_popen.forget_task("t9")


@pytest.mark.parametrize("outcome", ["success", "failure", "cancel"])
def test_forget_task_runs_when_the_run_ends(fake, ydl, tmp_path, monkeypatch, outcome):
    forgotten = []
    real_forget = inproc_popen.forget_task
    monkeypatch.setattr(inproc_popen, "forget_task", lambda task: (forgotten.append(task), real_forget(task)))

    def body(ydl_, info):
        if outcome == "failure":
            raise DownloadError("ERROR: boom")
        if outcome == "cancel":
            run.cancel("t1")
            progress(ydl_, downloaded_bytes=1)

    ydl.body = body
    reply = download(tmp_path)
    assert reply["ok"] is (outcome == "success")
    assert forgotten == ["t1"]
    assert fake.forgotten == ["t1"]
    assert not inproc_popen.is_cancelled("t1")


def test_cancel_before_the_run_starts_stops_it(fake, ydl, tmp_path):
    run.cancel("t1")
    reply = download(tmp_path)
    assert reply["ok"] is False
    assert ydl.extracted == []
    assert not inproc_popen.is_cancelled("t1")


def test_current_task_is_set_for_the_run(fake, ydl, tmp_path):
    seen = []
    ydl.body = lambda ydl_, info: seen.append(inproc_popen.current_task.get())
    download(tmp_path, task="t42")
    assert seen == ["t42"]
    assert inproc_popen.current_task.get() == "none"


def test_returns_files_in_out_dir(fake, ydl, tmp_path):
    out = tmp_path / "out"
    out.mkdir()

    def body(ydl_, info):
        (out / "b [x].mp4").write_bytes(b"v")
        (out / "a.jpg").write_bytes(b"c")
        (out / "sub").mkdir()

    ydl.body = body
    reply = json.loads(api.call("download", json.dumps(
        {"argv": ["--cache-dir", str(tmp_path / "cache")], "url": URL, "task": "t1", "outDir": str(out)}
    )))
    assert reply == {"ok": True, "value": {"files": ["a.jpg", "b [x].mp4"]}}


def test_extracts_first_then_downloads_the_same_info(fake, ydl, tmp_path):
    download(tmp_path)
    assert [(url, dl) for url, dl, _ in ydl.extracted] == [(URL, False)]
    assert ydl.processed == [(ydl.info, True)]


def test_options_come_from_argv_plus_the_shared_ones(fake, ydl, tmp_path):
    argv = ["--no-playlist", "--cache-dir", str(tmp_path / "c"), "-o", str(tmp_path / "%(title)s.%(ext)s"),
            "-N", "4", "-f", "ba/b", "-x", "--audio-format", "mp3"]
    download(tmp_path, argv=argv)
    params = ydl.extracted[0][2]
    assert params["noplaylist"] is True
    assert params["outtmpl"]["default"] == str(tmp_path / "%(title)s.%(ext)s")
    assert params["concurrent_fragment_downloads"] == 4
    assert params["postprocessors"][0]["key"] == "FFmpegExtractAudio"
    assert params["js_runtimes"] == {"javascriptcore": {}}
    assert params["hls_prefer_native"] is True
    assert params["ignoreerrors"] is False
    assert params["color"] == {"stdout": "never", "stderr": "never"}
    assert isinstance(params["logger"], run._Silent)


BOT_CHECK = "ERROR: [youtube] x: Sign in to confirm you’re not a bot. This helps protect our community."


# YouTube can flag a network's IPv6 address while its IPv4 one still passes; the media URLs it then signs belong to
# that IPv4 address, so the whole run, not only the extraction, goes over IPv4.
def test_bot_check_retries_the_whole_run_over_ipv4(fake, ydl, tmp_path, monkeypatch):
    real = yt_dlp.YoutubeDL.extract_info
    seen = []

    def extract_info(self, url, download=True, **kwargs):
        seen.append(self.params.get("source_address"))
        if self.params.get("source_address") != "0.0.0.0":
            raise DownloadError(BOT_CHECK)
        return real(self, url, download=download, **kwargs)

    monkeypatch.setattr(yt_dlp.YoutubeDL, "extract_info", extract_info)
    reply = download(tmp_path)
    assert reply["ok"] is True
    assert seen == [None, "0.0.0.0"]
    assert len(ydl.processed) == 1


def test_bot_check_over_ipv4_is_not_retried_again(fake, ydl, tmp_path, monkeypatch):
    seen = []

    def extract_info(self, url, download=True, **kwargs):
        seen.append(self.params.get("source_address"))
        raise DownloadError(BOT_CHECK)

    monkeypatch.setattr(yt_dlp.YoutubeDL, "extract_info", extract_info)
    reply = download(tmp_path)
    assert reply["ok"] is False
    assert seen == [None, "0.0.0.0"]


def test_other_errors_are_not_retried(fake, ydl, tmp_path, monkeypatch):
    seen = []

    def extract_info(self, url, download=True, **kwargs):
        seen.append(self.params.get("source_address"))
        raise DownloadError("ERROR: [youtube] x: Video unavailable")

    monkeypatch.setattr(yt_dlp.YoutubeDL, "extract_info", extract_info)
    assert download(tmp_path)["ok"] is False
    assert seen == [None]


def test_info_bot_check_retries_over_ipv4(monkeypatch):
    seen = []

    def extract_info(self, url, download=True, **kwargs):
        seen.append(self.params.get("source_address"))
        if self.params.get("source_address") != "0.0.0.0":
            raise DownloadError(BOT_CHECK)
        return {"id": "x", "title": "T"}

    monkeypatch.setattr(yt_dlp.YoutubeDL, "extract_info", extract_info)
    reply = json.loads(api.call("info", json.dumps({"argv": [], "url": URL})))
    assert reply["ok"] is True, reply
    assert seen == [None, "0.0.0.0"]
