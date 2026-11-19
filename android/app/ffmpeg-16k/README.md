# 16 KB-aligned libwebp for the ffmpeg package

youtubedl-android 0.18.1 ships ffmpeg as a zip (`jni/<abi>/libffmpeg.zip.so`) that is unpacked on the phone. Its 16 KB page-size work (0.18.0) aligned every library except libwebp's five, which are still 4 KB aligned. On a 16 KB page-size device the linker then refuses `libavcodec`, so every download fails at the convert or merge step ("program alignment (4096) cannot be smaller than system page size (16384)"). Upstream issue: yausername/youtubedl-android#365.

The `patch<Variant>FfmpegZip` task in `../build.gradle.kts` copies the upstream zip entry by entry (symlinks and modes kept) and swaps in these files for arm64-v8a and x86_64. 32-bit ABIs have no 16 KB pages and keep the upstream zip.

Source: Termux `libwebp` 1.6.0.0.0.1+really1.6.0, the same libwebp 1.6.0 as the bundled copy, rebuilt by Termux with 16 KB alignment. SONAMEs, NEEDED entries and exported symbols match the bundled libraries exactly.

| ABI | .deb | sha256 |
| --- | --- | --- |
| arm64-v8a | `pool/main/libw/libwebp/libwebp_1.6.0.0.0.1+really1.6.0_aarch64.deb` | `8ba7fcfadd1a9957a7632c6407d6ef3e41d34dbd96a41769b245592ed4559045` |
| x86_64 | `pool/main/libw/libwebp/libwebp_1.6.0.0.0.1+really1.6.0_x86_64.deb` | `3274f3b6b3b765ed5cfb3d33cf309a2222de7766ad53f0eaefcbe89563f2f7a3` |

from `https://packages.termux.dev/apt/termux-main/`, files taken from `data/data/com.termux/files/usr/lib/`.

When bumping youtubedl-android: unpack the new `libffmpeg.zip.so` and check its libraries' LOAD alignment. If upstream fixed libwebp, delete this folder and the task. If these files change, bump `FFMPEG_PKG_REV` in `YtDlp.kt` so installed apps unpack ffmpeg again.
