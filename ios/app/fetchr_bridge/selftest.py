"""Which yt-dlp this launch runs and whether it works. Swift picks an installed update before boot (CPython cannot
be re-initialised in-process) and reads the verdict after it, so the next launch can skip a broken one."""

import importlib
import os
import sys
import time

from .log import Silent, log

_PACKAGES = ("yt_dlp", "yt_dlp_ejs")
# `-X fetchr_ytdlp_dir=<dir>`, which fetchr_py_init sets to the installed update it put ahead of app_packages;
# absent when the bundled copy runs.
DIR_OPTION = "fetchr_ytdlp_dir"

# Why the installed update was dropped for the bundled copy at boot, or None.
dropped = None


def is_package_module(name):
    return any(name == package or name.startswith(package + ".") for package in _PACKAGES)


def _installed_dir():
    value = sys._xoptions.get(DIR_OPTION)
    return value if isinstance(value, str) and value else None


def _inside(path, folder):
    return bool(path) and os.path.realpath(path).startswith(os.path.realpath(folder) + os.sep)


def _import():
    # What the bridge imports from yt-dlp, so an update missing any of it fails here and not in api's imports.
    import yt_dlp
    import yt_dlp.downloader.external  # noqa: F401
    import yt_dlp.networking.exceptions  # noqa: F401
    import yt_dlp.utils  # noqa: F401
    import yt_dlp.version  # noqa: F401
    import yt_dlp_ejs  # noqa: F401

    # The names the bridge takes from them; a missing one raises AttributeError here.
    _ = (yt_dlp.parse_options, yt_dlp.utils.DownloadCancelled, yt_dlp.downloader.external.FFmpegFD,
         yt_dlp.networking.exceptions.TransportError)


def load():
    """Imports yt-dlp before the bridge does; an installed update that fails to import gives way to the bundled one."""
    global dropped
    folder = _installed_dir()
    try:
        _import()
        return
    except Exception as exc:
        if not folder or folder not in sys.path:
            raise
        dropped = f"yt-dlp {os.path.basename(folder)} failed to import: {type(exc).__name__}: {exc}"
    log(dropped)
    sys.path.remove(folder)
    for name, module in list(sys.modules.items()):
        if is_package_module(name) or _inside(getattr(module, "__file__", None), folder):
            del sys.modules[name]
    importlib.invalidate_caches()
    _import()


def _root(module):
    return os.path.realpath(os.path.dirname(os.path.dirname(module.__file__)))


def _js_problem(jsc, options):
    if jsc is None:
        return "the JS challenge provider did not load"
    import yt_dlp
    from yt_dlp.extractor.youtube.jsc._registry import _jsc_providers

    provider = jsc._provider
    if _jsc_providers.value.get(provider.PROVIDER_KEY) is not provider:
        return "the JS challenge provider is not registered"
    with yt_dlp.YoutubeDL(options) as ydl:
        if not provider(ydl.get_info_extractor("Youtube"), Silent(), {}).is_available():
            return "the JS challenge provider is not available"
    return None


def _problem(jsc, options):
    import yt_dlp
    import yt_dlp.utils
    import yt_dlp_ejs

    from .inproc_popen import InProcPopen

    # After a fallback the installed folder is not what runs; the bundled copy is checked as usual.
    folder = None if dropped else _installed_dir()
    roots = {_root(yt_dlp), _root(yt_dlp_ejs)}
    if len(roots) != 1:
        return "yt_dlp and yt_dlp_ejs come from different folders"
    if folder and roots != {os.path.realpath(folder)}:
        return f"yt-dlp did not load from {os.path.basename(folder)}"
    # The probe task, as yt-dlp's own version check uses: a cancel can never reach it.
    if not issubclass(yt_dlp.utils.Popen, InProcPopen) or not yt_dlp.utils.get_exe_version("ffmpeg", args=["-version"]):
        return "the in-process ffmpeg shim is not active"
    return _js_problem(jsc, options)


def run(jsc, options):
    """{"ok", "version", "reason"} for the yt-dlp that booted; `options` are the bridge's YoutubeDL options."""
    import yt_dlp.version

    version = yt_dlp.version.__version__
    began = time.perf_counter()
    try:
        reason = _problem(jsc, options)
    except Exception as exc:
        reason = f"the selftest raised {exc!r}"
    if dropped:
        reason = f"{dropped}; {reason}" if reason else dropped
    log(f"yt-dlp {version} from {_root(yt_dlp.version)} selftest took {round((time.perf_counter() - began) * 1000)} ms")
    if reason:
        log(f"yt-dlp {version} selftest failed: {reason}")
        return {"ok": False, "version": version, "reason": reason}
    return {"ok": True, "version": version, "reason": ""}
