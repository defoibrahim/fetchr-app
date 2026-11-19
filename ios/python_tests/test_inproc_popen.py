import errno
import subprocess
import sys
import threading
import types

import pytest

from fetchr_bridge import api, inproc_popen, run
from fetchr_bridge.inproc_popen import InProcPopen, current_task

BSFS_BANNER = (
    "{prog} version 9.0.2 Copyright (c) 2000-2026 the FFmpeg developers\n"
    "  built with Apple clang version 17.0.0\n"
    "  configuration: --enable-libmp3lame --enable-gpl\n"
    "  libavutil      60.  8.100 / 60.  8.100\n"
    "  libavformat    62.  3.100 / 62.  3.100\n"
    "Bitstream filters:\n"
    "aac_adtstoasc\n"
    "h264_mp4toannexb\n"
    "setts\n"
)


@pytest.fixture
def fake(monkeypatch):
    fake = types.ModuleType("_fetchr")
    fake.calls = []
    fake.cancelled = []
    fake.reply = (0, "")

    def ffmpeg(argv, task):
        fake.calls.append(("ffmpeg", list(argv), task))
        return fake.reply

    def ffprobe(argv, task):
        fake.calls.append(("ffprobe", list(argv), task))
        return fake.reply

    fake.ffmpeg = ffmpeg
    fake.ffprobe = ffprobe
    fake.cancel_session = fake.cancelled.append
    fake.forgotten = []
    fake.forget_session = fake.forgotten.append
    monkeypatch.setitem(sys.modules, "_fetchr", fake)
    return fake


@pytest.fixture
def task():
    def enter(task_id):
        token = current_task.set(task_id)
        tokens.append((token, task_id))

    tokens = []
    yield enter
    for token, task_id in reversed(tokens):
        inproc_popen.forget_task(task_id)
        current_task.reset(token)


def test_package_import_installs_popen():
    assert subprocess.Popen is InProcPopen


def test_ffmpeg_dispatch_injects_nostdin(fake, task):
    task("t1")
    fake.reply = (0, "log")
    proc = InProcPopen(["/bin/ffmpeg", "-i", "a.mp4", "b.mp3"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert fake.calls == [("ffmpeg", ["-nostdin", "-i", "a.mp4", "b.mp3"], "t1")]
    assert proc.communicate() == (b"", b"log")
    assert proc.returncode == 0


def test_ffprobe_stdout_is_bridge_out(fake, task):
    task("t1")
    fake.reply = (0, '{"streams": []}')
    proc = InProcPopen(["ffprobe", "-show_streams", "a.mp4"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert fake.calls == [("ffprobe", ["-show_streams", "a.mp4"], "t1")]
    assert "-o" not in fake.calls[0][1]
    assert proc.communicate() == ('{"streams": []}', "")


def test_ffprobe_caller_o_passes_through(fake):
    InProcPopen(["ffprobe", "-o", "report.json", "a.mp4"], stdout=subprocess.PIPE)
    assert fake.calls[0][1] == ["-o", "report.json", "a.mp4"]


def test_default_task_is_none(fake):
    InProcPopen(["ffmpeg", "-i", "x"])
    assert fake.calls[0][2] == "none"


def test_unknown_program_raises_enoent(fake):
    with pytest.raises(FileNotFoundError) as caught:
        InProcPopen(["aria2c", "--version"], stdout=subprocess.PIPE)
    assert caught.value.errno == errno.ENOENT
    assert fake.calls == []


def test_shell_true_raises_enoent(fake):
    with pytest.raises(FileNotFoundError) as caught:
        InProcPopen("ffmpeg -version", shell=True)
    assert caught.value.errno == errno.ENOENT
    assert fake.calls == []


def test_missing_bridge_reads_as_no_ffmpeg(monkeypatch):
    monkeypatch.setitem(sys.modules, "_fetchr", None)
    with pytest.raises(FileNotFoundError):
        InProcPopen(["ffmpeg", "-bsfs"], stdout=subprocess.PIPE)


def test_stderr_stdout_merge(fake):
    fake.reply = (0, "banner")
    proc = InProcPopen(["ffmpeg", "-bsfs"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert proc.communicate() == ("banner", None)


def test_unpiped_streams_are_none(fake):
    fake.reply = (0, "log")
    proc = InProcPopen(["ffmpeg", "-version"])
    assert proc.communicate() == (None, None)
    assert proc.stdin is None and proc.stdout is None and proc.stderr is None


def test_text_mode_decodes_utf8(fake):
    fake.reply = (0, "Ünïcode\r\nline\rnext")
    text = InProcPopen(["ffmpeg", "-i", "x"], stderr=subprocess.PIPE, text=True).communicate()[1]
    assert text == "Ünïcode\nline\nnext"
    raw = InProcPopen(["ffmpeg", "-i", "x"], stderr=subprocess.PIPE).communicate()[1]
    assert raw == "Ünïcode\r\nline\rnext".encode()
    assert InProcPopen(["ffmpeg", "-i", "x"], stderr=subprocess.PIPE, encoding="utf-8").communicate()[1] == text


def test_kill_after_the_run_cancels_nothing(fake, task):
    # The session already ended inside the constructor; a cancel now would hit the task's next session.
    task("t7")
    proc = InProcPopen(["ffmpeg", "-i", "x"], stdin=subprocess.PIPE)
    proc.kill()
    proc.terminate()
    proc.communicate(b"q")
    assert fake.cancelled == []


def test_return_code_255_is_kept(fake):
    fake.reply = (255, "Exiting normally, received signal 2.")
    with InProcPopen(["ffmpeg", "-i", "x"], stderr=subprocess.PIPE) as proc:
        assert proc.wait() == 255
        assert proc.poll() == 255
        assert proc.wait(timeout=1) == 255
    assert proc.returncode == 255


def test_failure_without_log_still_has_a_line(fake):
    fake.reply = (1, "")
    _, err = InProcPopen(["ffmpeg", "-i", "x"], stderr=subprocess.PIPE, text=True).communicate()
    assert err.strip().splitlines()[-1]


def test_cancel_task_marks_and_cancels(fake, task):
    task("t9")
    inproc_popen.cancel_task("t9")
    assert fake.cancelled == ["t9"]
    proc = InProcPopen(["ffmpeg", "-i", "x"], stderr=subprocess.PIPE, text=True)
    assert proc.returncode == 255
    assert fake.calls == []
    assert proc.communicate()[1].strip().splitlines()[-1]


def test_cancel_only_marks_its_own_task(fake, task):
    task("other")
    inproc_popen.cancel_task("t9")
    try:
        assert InProcPopen(["ffmpeg", "-i", "x"]).returncode == 0
        assert len(fake.calls) == 1
    finally:
        inproc_popen.forget_task("t9")


def test_forget_task_clears_the_mark(fake, task):
    task("t9")
    inproc_popen.cancel_task("t9")
    inproc_popen.forget_task("t9")
    assert fake.forgotten == ["t9"]
    assert InProcPopen(["ffmpeg", "-i", "x"]).returncode == 0
    assert len(fake.calls) == 1


def test_cancel_from_another_thread(fake, task):
    task("t9")
    worker = threading.Thread(target=inproc_popen.cancel_task, args=("t9",))
    worker.start()
    worker.join()
    assert InProcPopen(["ffprobe", "-show_streams", "x"]).returncode == 255
    assert fake.calls == []


# yt-dlp caches the version per program for the whole process, so a cancelled probe would hide ffmpeg for good.
def test_version_probe_ignores_cancel(fake, task):
    task("t9")
    inproc_popen.cancel_task("t9")
    fake.reply = (0, BSFS_BANNER.format(prog="ffmpeg"))
    assert InProcPopen(["ffmpeg", "-bsfs"], stdout=subprocess.PIPE).returncode == 0
    assert fake.calls[0][2] != "t9"


@pytest.fixture
def ffmpeg_pp(monkeypatch, fake):
    from yt_dlp.postprocessor.ffmpeg import FFmpegPostProcessor

    monkeypatch.setattr(FFmpegPostProcessor, "_version_cache", {None: None})
    monkeypatch.setattr(FFmpegPostProcessor, "_features_cache", {})

    def reply(prog):
        return lambda argv, task: (fake.calls.append((prog, list(argv), task)), (0, BSFS_BANNER.format(prog=prog)))[1]

    fake.ffmpeg = reply("ffmpeg")
    fake.ffprobe = reply("ffprobe")
    api.boot()
    return FFmpegPostProcessor


def test_yt_dlp_sees_ffmpeg(ffmpeg_pp):
    import yt_dlp.utils

    pp = ffmpeg_pp(None)
    assert pp.available
    assert pp.basename == "ffmpeg"
    assert pp._version == "9.0.2"
    assert pp._features["setts"] is True
    assert issubclass(yt_dlp.utils.Popen, InProcPopen)


def test_yt_dlp_sees_ffprobe(ffmpeg_pp, fake):
    pp = ffmpeg_pp(None)
    assert pp.probe_available
    assert pp.probe_basename == "ffprobe"
    assert ("ffprobe", ["-bsfs"]) in [call[:2] for call in fake.calls]


def test_ffmpeg_fd_disabled(ffmpeg_pp):
    from yt_dlp.downloader.external import FFmpegFD

    assert ffmpeg_pp(None).available
    assert not FFmpegFD.available()


def test_hls_prefer_native():
    assert run._options([])["hls_prefer_native"] is True
