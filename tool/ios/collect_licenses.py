#!/usr/bin/env python3
"""Copies the licences of what the iOS build bundles into assets/licenses/ios, with a manifest the app reads.

Run after fetch_python.sh, vendor_python.sh and build_ffmpeg.sh, and again whenever a pin changes; the output is
committed, so a clean clone shows the licences without the gitignored artefacts.
"""

import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "ios"
OUT = ROOT / "assets" / "licenses" / "ios"


def one(pattern: str) -> Path:
    found = sorted(IOS.glob(pattern))
    if not found:
        sys.exit(f"collect_licenses: nothing matches ios/{pattern}; run the tool/ios fetch, vendor and build scripts")
    return found[0]


def dist_info(package: str) -> Path:
    return one(f"app_packages/{package}-*.dist-info")


def version_of(info: Path) -> str:
    return info.name.split("-", 1)[1].removesuffix(".dist-info")


def licence_texts(info: Path) -> str:
    files = sorted((info / "licenses").iterdir())
    return "\n\n".join(f.read_text(encoding="utf-8").strip() for f in files if f.is_file())


def ejs_notices(info: Path) -> str:
    # The solver bundles third-party JS; its leading /*! */ block carries their licences.
    blocks = []
    for js in sorted((IOS / "app_packages/yt_dlp_ejs/yt/solver").glob("*.js")):
        match = re.match(r"/\*!(.*?)\*/", js.read_text(encoding="utf-8"), re.S)
        if match:
            lines = [re.sub(r"^\s*\* ?", "", line) for line in match.group(1).splitlines()]
            blocks.append(f"{js.name}:\n" + "\n".join(lines).strip())
    return licence_texts(info) + "\n\n" + "\n\n".join(blocks)


def main() -> None:
    entries = []

    def add(name: str, slug: str, text: str) -> None:
        (OUT / f"{slug}.txt").write_text(text.strip() + "\n", encoding="utf-8")
        entries.append({"name": name, "file": f"assets/licenses/ios/{slug}.txt"})

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    python = (ROOT / "tool/ios/python-version").read_text().strip()
    add(f"CPython {python}", "cpython", one("Python.xcframework/lib/python3.*/LICENSE.txt").read_text(encoding="utf-8"))

    lgpl = one("Frameworks/ffmpegkit/ffmpegkit.xcframework/ios-arm64/ffmpegkit.framework/LICENSE")
    add(
        "FFmpeg, FFmpegKit and LAME (libmp3lame)",
        "ffmpeg",
        "FFmpeg (libavcodec, libavdevice, libavfilter, libavformat, libavutil, libswresample, libswscale) and "
        "FFmpegKit are used under the GNU LGPL version 3, and LAME (libmp3lame, linked into libavcodec) under the "
        "GNU LGPL version 2 or later. They are dynamic frameworks inside the app and can be replaced; the build "
        "script is tool/ios/build_ffmpeg.sh.\n\n" + lgpl.read_text(encoding="utf-8")
        # The LGPL v3 is a set of additions to the GPL v3, so the GPL's text travels with it.
        + "\n\n" + (ROOT / "tool/ios/licenses/gpl-3.0.txt").read_text(encoding="utf-8"),
    )

    for package, name in [
        ("yt_dlp", "yt-dlp"),
        ("yt_dlp_ejs", "yt-dlp-ejs"),
        ("certifi", "certifi"),
        ("charset_normalizer", "charset-normalizer"),
        ("idna", "idna"),
        ("mutagen", "mutagen"),
        ("requests", "requests"),
        ("urllib3", "urllib3"),
        ("websockets", "websockets"),
    ]:
        info = dist_info(package)
        text = ejs_notices(info) if package == "yt_dlp_ejs" else licence_texts(info)
        add(f"{name} {version_of(info)}", package.replace("_", "-"), text)

    (OUT / "manifest.json").write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")
    print(f"collect_licenses: wrote {len(entries)} licences to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
