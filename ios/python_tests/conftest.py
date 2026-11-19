import sys
from pathlib import Path

ios = Path(__file__).resolve().parent.parent
# Same order as the app's search path: the bridge, then the vendored packages.
for folder in (ios / "app_packages", ios / "app"):
    sys.path.insert(0, str(folder))

# The app imports the bridge, which installs InProcPopen, before anything imports yt_dlp; tests that import
# yt_dlp first would otherwise build yt_dlp.utils.Popen on the real subprocess.Popen.
import fetchr_bridge  # noqa: E402,F401
