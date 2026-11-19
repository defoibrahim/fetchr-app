#!/usr/bin/env bash
# Builds FFmpegKitNext (FFmpeg plus libmp3lame) from a pinned tag into ios/Frameworks/ffmpegkit
# (gitignored): ffmpegkit.xcframework and the libav*/libsw* xcframeworks, arm64 device and
# arm64 simulator slices only. A no-op when the stamp file already matches. A fresh build takes a few
# minutes on an Apple silicon Mac.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
repo="https://github.com/arthenica/ffmpeg-kit-next"
tag="v9.0.2"
sha="9f04bf1e3c97def70b98e198cb80a57b43ef5b45"
min_ios="26.0"
# No --enable-gpl: libmp3lame is LGPL and no GPL-only library is enabled, so the build stays LGPL.
flags=(
  -x
  --enable-lib-lame
  --enable-lib-ios-zlib
  --target="$min_ios"
  --disable-arch-arm64-mac-catalyst
  --disable-arch-arm64e
  --disable-arch-x86-64
  --disable-arch-x86-64-mac-catalyst
)

dest="$root/ios/Frameworks/ffmpegkit"
stamp="$dest/.fetchr-version"
want="$tag $sha ${flags[*]}"
# Keep in step with FFMPEG_XCFRAMEWORKS in configure_xcode.rb.
names=(ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)

all_present() {
  local name
  for name in "${names[@]}"; do [ -d "$1/$name.xcframework" ] || return 1; done
}

if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$want" ] && all_present "$dest"; then
  echo "build_ffmpeg: FFmpegKitNext $tag already in ios/Frameworks/ffmpegkit"
  exit 0
fi

# The same tools upstream's Nix shell puts first on PATH: GNU sed and libtoolize under their plain
# names, and gettext's m4 macros (lame's configure.in needs AM_ICONV, or autoreconf keeps its 2015
# config.sub, which rejects arm64-ios-darwin).
if command -v brew >/dev/null; then
  for formula in gnu-sed libtool; do
    gnubin="$(brew --prefix "$formula")/libexec/gnubin"
    if [ -d "$gnubin" ]; then PATH="$gnubin:$PATH"; fi
  done
  gettext="$(brew --prefix gettext)"
  for dir in "$gettext/share/gettext/m4" "$gettext/share/aclocal"; do
    if [ -d "$dir" ]; then ACLOCAL_PATH="$dir${ACLOCAL_PATH:+:$ACLOCAL_PATH}"; fi
  done
  export PATH ACLOCAL_PATH
fi
missing=()
for tool in autoconf automake libtoolize pkg-config git xcodebuild; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
sed --version >/dev/null 2>&1 || missing+=("GNU sed")
found_iconv=""
IFS=: read -r -a aclocal_dirs <<< "${ACLOCAL_PATH:-}"
for dir in ${aclocal_dirs[@]+"${aclocal_dirs[@]}"}; do
  if [ -f "$dir/iconv.m4" ]; then found_iconv=1; fi
done
[ -n "$found_iconv" ] || missing+=("gettext m4 macros")
if [ ${#missing[@]} -gt 0 ]; then
  echo "build_ffmpeg: missing ${missing[*]} (brew install autoconf automake libtool pkgconf gnu-sed gettext)" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
src="$work/ffmpeg-kit-next"

echo "build_ffmpeg: cloning $repo at $tag"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" "$repo" "$src"
got="$(git -C "$src" rev-parse HEAD)"
if [ "$got" != "$sha" ]; then
  echo "build_ffmpeg: $tag is $got, expected $sha" >&2
  exit 1
fi

start=$SECONDS
echo "build_ffmpeg: ios.sh ${flags[*]}"
if ! (cd "$src" && ./ios.sh "${flags[@]}"); then
  tail -n 80 "$src/build.log" >&2 || true
  trap - EXIT
  echo "build_ffmpeg: ios.sh failed; the clone and its full build.log are kept in $src" >&2
  exit 1
fi
echo "build_ffmpeg: built in $(((SECONDS - start) / 60)) min"

out="$src/prebuilt/bundle-apple-xcframework-ios-$min_ios"
if ! all_present "$out"; then
  echo "build_ffmpeg: $out lacks one of ${names[*]} (.xcframework)" >&2
  exit 1
fi
xcfs=()
for name in "${names[@]}"; do xcfs+=("$out/$name.xcframework"); done
for xcf in "${xcfs[@]}"; do
  for slice in ios-arm64 ios-arm64-simulator; do
    [ -d "$xcf/$slice" ] || { echo "build_ffmpeg: $(basename "$xcf") has no $slice slice" >&2; exit 1; }
  done
done

rm -rf "$dest"
mkdir -p "$dest"
cp -R "${xcfs[@]}" "$dest/"
echo "$want" > "$stamp"
echo "build_ffmpeg: installed $(cd "$dest" && ls -d ./*.xcframework | sed 's|^\./||' | tr '\n' ' ')"
echo "build_ffmpeg: total $(du -sh "$dest" | cut -f 1) in ios/Frameworks/ffmpegkit"
