import math
import optparse
import os
import threading
import time

import yt_dlp
from yt_dlp.utils import DownloadCancelled

from . import inproc_popen, strict
from .log import Silent as _Silent, log

# yt-dlp picks FFmpegFD for these even with FFmpegFD.available patched off, and ffmpeg cannot stream in-process.
_FFMPEG_PROTOCOLS = ("rtmp", "rtsp", "mms")
_EMIT_EVERY = 0.25
_clock = time.monotonic


class FetchrBridgeError(Exception):
    """A failure whose error code is known here; the envelope sends `hint` as it is."""

    def __init__(self, hint, message):
        super().__init__(message)
        self.hint = hint


def _options(argv):
    # A config file next to the package or under HOME must not change what Fetchr asks for.
    # yt-dlp reports a bad option as OptParseError; older optparse paths exit instead.
    try:
        opts = yt_dlp.parse_options(["--ignore-config", *argv]).ydl_opts
    except (optparse.OptParseError, SystemExit):
        raise ValueError("bad yt-dlp arguments") from None
    # fetchr_bridge.jsc registers the runtime; the EJS solver scripts come from the yt_dlp_ejs package, GitHub
    # only if that copy is rejected.
    opts.update(js_runtimes={"javascriptcore": {}}, remote_components=["ejs:github"], hls_prefer_native=True)
    opts.update(
        quiet=True,
        # The CLI default ('only_download') makes extract_info return None on a failed extraction.
        ignoreerrors=False,
        no_warnings=False,
        noprogress=True,
        logger=_Silent(),
        # Colour codes would land in the DownloadError text that ErrorClassifier matches on.
        color={"stdout": "never", "stderr": "never"},
    )
    return opts


# YouTube can flag a network's IPv6 address ("confirm you're not a bot") while its IPv4 one still passes. The media
# URLs it signs belong to the address that asked, so a retry runs the whole call over IPv4. On an IPv6-only network
# the retry fails the same way, and the first error is what the user sees then.
_IPV4 = {"source_address": "0.0.0.0"}


def _bot_check(error):
    text = str(error)
    return "confirm you\u2019re not a bot" in text or "confirm you're not a bot" in text


def _over_ipv4_on_bot_check(opts, call):
    try:
        return call(opts)
    except yt_dlp.utils.DownloadError as first:
        if opts.get("source_address") or not _bot_check(first):
            raise
        try:
            return call({**opts, **_IPV4})
        except yt_dlp.utils.DownloadError:
            raise first from None


def info(argv, url):
    def call(opts):
        with yt_dlp.YoutubeDL(opts) as ydl:
            return ydl.sanitize_info(ydl.extract_info(url, download=False))

    return _over_ipv4_on_bot_check(_options(argv), call)


def cancel(task_id):
    inproc_popen.cancel_task(task_id)


def _check_cancel(task_id):
    if inproc_popen.is_cancelled(task_id):
        raise DownloadCancelled()


def _int(value):
    return int(value) if isinstance(value, (int, float)) and math.isfinite(value) else None


class _Events:
    """Turns yt-dlp's hooks into bridge events; fragment threads call the progress hook concurrently."""

    def __init__(self, task_id):
        self._task = task_id
        self._lock = threading.Lock()
        self._stage = None
        self._last = None

    def _send(self, event):
        # Progress is a view; a failed emit must never fail the download it reports on.
        try:
            import _fetchr

            _fetchr.emit(self._task, strict.dumps(event))
        except Exception as exc:
            log(f"emit failed for {self._task}: {exc!r}")

    def progress(self, d):
        _check_cancel(self._task)
        status = d.get("status")
        if status not in ("downloading", "finished"):
            return
        now = _clock()
        with self._lock:
            due = status == "finished" or self._stage != "downloading" or now - self._last >= _EMIT_EVERY
            if not due:
                return
            self._stage, self._last = "downloading", now
        self._send({
            "type": "progress",
            "stage": "downloading",
            "downloaded": _int(d.get("downloaded_bytes")),
            "total": _int(d.get("total_bytes") or d.get("total_bytes_estimate")),
            "speed": d.get("speed"),
            "eta": _int(d.get("eta")),
        })

    def postprocessor(self, d):
        _check_cancel(self._task)
        name = d.get("postprocessor")
        if d.get("status") != "started" or name == "MoveFiles":
            return
        with self._lock:
            self._stage = "postProcessing"
        self._send({"type": "stage", "stage": "postProcessing", "pp": name})


def _refuse_unsupported(info):
    # A post with several videos is a playlist even under --no-playlist; like Android, every entry is downloaded,
    # so every entry is checked.
    if info.get("_type") in ("playlist", "multi_video"):
        for entry in info.get("entries") or []:
            if entry:
                _refuse_unsupported(entry)
        return
    if info.get("is_live"):
        raise FetchrBridgeError("unsupported_site", "Live streams can't be downloaded on iPhone yet.")
    protocols = [info.get("protocol")] + [fmt.get("protocol") for fmt in info.get("requested_formats") or []]
    for protocol in protocols:
        if any(part.startswith(_FFMPEG_PROTOCOLS) for part in (protocol or "").split("+")):
            raise FetchrBridgeError("unsupported_site", "This stream can't be downloaded on iPhone yet.")


def download(argv, url, task_id, out_dir):
    token = inproc_popen.current_task.set(task_id)
    try:
        _check_cancel(task_id)
        events = _Events(task_id)
        opts = _options(argv)
        opts.update(progress_hooks=[events.progress], postprocessor_hooks=[events.postprocessor])

        def call(opts):
            with yt_dlp.YoutubeDL(opts) as ydl:
                # Extracting first shows the live flag and the chosen formats before anything is written.
                info = ydl.extract_info(url, download=False)
                # A cover never streams through ffmpeg, so a live stream's thumbnail is fine.
                if not ydl.params.get("skip_download"):
                    _refuse_unsupported(info)
                _check_cancel(task_id)
                ydl.process_ie_result(info, download=True)

        _over_ipv4_on_bot_check(opts, call)
        files = sorted(name for name in os.listdir(out_dir) if os.path.isfile(os.path.join(out_dir, name)))
        return {"files": files}
    finally:
        inproc_popen.forget_task(task_id)
        inproc_popen.current_task.reset(token)
