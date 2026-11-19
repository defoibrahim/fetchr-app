import json
import os

from . import classify, run, selftest, strict
from .log import log

_version = None
_jsc = None


def boot():
    global _version, _jsc
    import yt_dlp.version

    _version = yt_dlp.version.__version__
    # FFmpegFD would pipe media through ffmpeg's stdin and stdout, which an in-process session does not have;
    # HLS and DASH then go through yt-dlp's native downloaders and ffmpeg only post-processes files.
    from yt_dlp.downloader.external import FFmpegFD

    FFmpegFD.available = classmethod(lambda cls, path=None: False)
    # Registers the JavaScriptCore runtime and challenge provider, which every YoutubeDL reads when it is built.
    # It leans on yt-dlp internals; if an update breaks them, YouTube loses its JS clients but the bridge and
    # every other site (and the next update) still work.
    try:
        from . import jsc
    except Exception as exc:
        _jsc = None
        log(f"JS challenge provider unavailable: {exc!r}")
    else:
        _jsc = jsc


def _ping(payload):
    return {"ytDlpVersion": _version}


def _selftest(payload):
    return selftest.run(_jsc, run._options([]))


def _compile(payload):
    # Once per installed update: the bundle ships its bytecode and Python never writes any at import.
    # Timestamp pycs, so a source that changes later is read again rather than its stale bytecode.
    import compileall

    return {"compiled": bool(compileall.compile_dir(payload["dir"], quiet=1))}


def _info(payload):
    return run.info(payload["argv"], payload["url"])


def _download(payload):
    return run.download(payload["argv"], payload["url"], payload["task"], payload["outDir"])


def _cancel(payload):
    run.cancel(payload["task"])


def _debug_emit(payload):
    import _fetchr

    _fetchr.emit(payload["task"], payload["json"])


def _debug_echo(payload):
    value = json.loads(payload["json"])
    if payload.get("raise"):
        raise ValueError(value)
    return value


def _debug_js(payload):
    import _fetchr

    return _fetchr.js_eval(payload["src"])


def _debug_jsc(payload):
    if _jsc is None:
        return {"plan": None, "solveMs": []}
    return {"plan": _jsc.ACTIVE_PLAN, "solveMs": list(_jsc.solve_ms)}


def _debug_ffmpeg(payload):
    import _fetchr

    rc, out = (_fetchr.ffprobe if payload.get("probe") else _fetchr.ffmpeg)(payload["argv"], payload["task"])
    return {"rc": rc, "out": out}


def _debug_ffmpeg_cancel(payload):
    import _fetchr

    _fetchr.cancel_session(payload["task"])


def _debug_ffmpeg_forget(payload):
    import _fetchr

    _fetchr.forget_session(payload["task"])


def _debug_pp(payload):
    """Runs one of yt-dlp's own ffmpeg postprocessors on local files and returns the output path."""
    import yt_dlp
    import yt_dlp.utils
    from yt_dlp.downloader.external import FFmpegFD
    from yt_dlp.postprocessor import ffmpeg as pp

    from .inproc_popen import InProcPopen

    kind, path = payload["kind"], payload.get("path")
    with yt_dlp.YoutubeDL({"quiet": True, "noprogress": True, "logger": run._Silent()}) as ydl:
        if kind == "versions":
            probe = pp.FFmpegPostProcessor(ydl)
            return {
                "versions": probe._versions,
                "popen": issubclass(yt_dlp.utils.Popen, InProcPopen),
                "ffmpegFd": FFmpegFD.available(),
            }
        if kind == "merge":
            video, audio = payload["video"], payload["audio"]
            info = {
                "filepath": path,
                "__files_to_merge": [video, audio],
                "requested_formats": [
                    {"filepath": video, "vcodec": "mpeg4", "acodec": "none", "protocol": "https"},
                    {"filepath": audio, "vcodec": "none", "acodec": "aac", "protocol": "https"},
                ],
            }
            _, info = pp.FFmpegMergerPP(ydl).run(info)
        elif kind == "mp3":
            info = {"filepath": path, "ext": os.path.splitext(path)[1][1:]}
            _, info = pp.FFmpegExtractAudioPP(ydl, preferredcodec="mp3", preferredquality="0").run(info)
        elif kind == "thumbnail":
            info = {"thumbnails": [{"filepath": path}], "__files_to_move": {path: path}}
            _, info = pp.FFmpegThumbnailsConvertorPP(ydl, format="jpg").run(info)
            return info["thumbnails"][0]["filepath"]
        elif kind == "fixup_m3u8":
            info = {"filepath": path, "ext": "mp4", "protocol": "m3u8_native"}
            _, info = pp.FFmpegFixupM3u8PP(ydl).run(info)
        else:
            raise LookupError(f"no postprocessor named {kind!r}")
        return info["filepath"]


def _debug_main_alive(payload):
    import threading

    return threading.main_thread().is_alive()


_HANDLERS = {"ping": _ping, "selftest": _selftest, "compile": _compile,
             "info": _info, "download": _download, "cancel": _cancel}
_DEBUG = {
    "debug_emit": _debug_emit, "debug_echo": _debug_echo, "debug_main_alive": _debug_main_alive,
    "debug_js": _debug_js, "debug_jsc": _debug_jsc,
    "debug_ffmpeg": _debug_ffmpeg, "debug_ffmpeg_cancel": _debug_ffmpeg_cancel,
    "debug_ffmpeg_forget": _debug_ffmpeg_forget, "debug_pp": _debug_pp,
}


def call(name, payload):
    try:
        handler = _HANDLERS.get(name) or (_DEBUG.get(name) if os.environ.get("FETCHR_TESTING") == "1" else None)
        if handler is None:
            raise LookupError(f"no bridge call named {name!r}")
        return strict.dumps({"ok": True, "value": handler(json.loads(payload))})
    except Exception as exc:
        # yt-dlp's DownloadError reads as its "ERROR: ..." line.
        hint = exc.hint if isinstance(exc, run.FetchrBridgeError) else classify.hint(exc)
        return strict.dumps({"ok": False, "hint": hint, "message": str(exc)})
