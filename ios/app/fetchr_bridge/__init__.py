# yt_dlp.utils.Popen subclasses subprocess.Popen when yt_dlp is first imported, and api imports it at its top.
from . import inproc_popen

inproc_popen.install()

from . import selftest  # noqa: E402

selftest.load()
