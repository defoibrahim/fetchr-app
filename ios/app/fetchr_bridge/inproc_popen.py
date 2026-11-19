"""yt-dlp's ffmpeg and ffprobe subprocesses as in-process FFmpegKit sessions; an iOS app cannot spawn one."""

import contextvars
import errno
import io
import os
import subprocess
import threading

current_task = contextvars.ContextVar("fetchr_task", default="none")

_PROGRAMS = ("ffmpeg", "ffprobe")
_CANCELLED = 255
# yt-dlp caches the detected version for the whole process, so these never run under a task that a cancel
# could stop: a cancelled detection would hide ffmpeg until the app restarts.
_VERSION_PROBES = (["-bsfs"], ["-version"])
_PROBE_TASK = "version-probe"

_cancelled = set()
_lock = threading.Lock()


def cancel_task(task_id):
    """Stops the task's running sessions and every session it starts until forget_task."""
    with _lock:
        _cancelled.add(task_id)
    import _fetchr

    _fetchr.cancel_session(task_id)


def forget_task(task_id):
    """Clears the cancel mark here and in the bridge; call it when the task ends or before a retry reuses its id."""
    with _lock:
        _cancelled.discard(task_id)
    import _fetchr

    _fetchr.forget_session(task_id)


def is_cancelled(task_id):
    with _lock:
        return task_id in _cancelled


def _not_found(name):
    return FileNotFoundError(errno.ENOENT, os.strerror(errno.ENOENT), name)


class InProcPopen:
    """The subprocess.Popen surface yt-dlp uses; the session runs to completion inside the constructor."""

    def __init__(self, args, *, stdin=None, stdout=None, stderr=None, env=None, shell=False, text=False,
                 encoding=None, errors=None, cwd=None, **kw):
        argv = [args] if isinstance(args, (str, bytes, os.PathLike)) else list(args)
        argv = [os.fsdecode(arg) for arg in argv]
        self.args = args
        # No process exists; None keeps os.kill from ever reaching a real pid.
        self.pid = None
        program = os.path.basename(argv[0]) if argv else ""
        if shell or program not in _PROGRAMS:
            raise _not_found(argv[0] if argv else "")
        try:
            import _fetchr
        except ImportError:
            raise _not_found(argv[0]) from None

        options = argv[1:]
        self._task = _PROBE_TASK if options in _VERSION_PROBES else current_task.get()
        if is_cancelled(self._task):
            code, out = _CANCELLED, ""
        elif program == "ffmpeg":
            code, out = _fetchr.ffmpeg(["-nostdin", *options], self._task)
        else:
            code, out = _fetchr.ffprobe(options, self._task)
        self.returncode = code

        if program == "ffmpeg":
            # yt-dlp raises the last stderr line of a failed run; an empty log would make that an IndexError.
            if code != 0 and not out.strip():
                out = "ffmpeg was cancelled" if code == _CANCELLED else f"ffmpeg exited with code {code}"
            printed, logged = "", out
        else:
            printed, logged = out, ""
        if stderr == subprocess.STDOUT:
            printed, logged = printed + logged, ""

        self._text = bool(text or encoding or errors or kw.get("universal_newlines"))
        self.stdin = self._stream("") if stdin == subprocess.PIPE else None
        self.stdout = self._stream(printed) if stdout == subprocess.PIPE else None
        self.stderr = self._stream(logged) if stderr == subprocess.PIPE else None

    def _stream(self, value):
        if self._text:
            return io.StringIO(value.replace("\r\n", "\n").replace("\r", "\n"))
        return io.BytesIO(value.encode("utf-8"))

    # The session ended inside the constructor, so "q", kill and terminate have nothing left to stop; cancelling
    # here would stop the task's next session instead. cancel_task is the way to stop a task.
    def communicate(self, input=None, timeout=None):
        return tuple(stream.read() if stream else None for stream in (self.stdout, self.stderr))

    def wait(self, timeout=None):
        return self.returncode

    def poll(self):
        return self.returncode

    def kill(self):
        pass

    def terminate(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        for stream in (self.stdin, self.stdout, self.stderr):
            if stream:
                stream.close()
        return False


def install():
    subprocess.Popen = InProcPopen
