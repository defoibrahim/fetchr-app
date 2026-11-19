#!/usr/bin/env bash
# Syncs ios/Runner.xcodeproj with the files under ios/Runner/{Fetchr,Pigeon} and
# ios/RunnerTests/Fetchr, embeds Python.xcframework with its build phase and settings, and embeds
# the FFmpegKit xcframeworks from ios/Frameworks/ffmpegkit.
# Idempotent: run it after adding or removing Swift/C files.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
pods="$(brew --prefix cocoapods 2>/dev/null || true)"
if [ -z "$pods" ] || [ ! -d "$pods/libexec" ]; then
  echo "configure_xcode: CocoaPods not found (brew install cocoapods)" >&2
  exit 1
fi

# The Ruby CocoaPods runs on (its shebang); bundled gems such as rexml live in its own gem dir.
ruby_bin="$(sed -n '1s/^#!//p' "$pods/libexec/bin/pod")"
[ -x "$ruby_bin" ] || ruby_bin="$(command -v ruby)"
export GEM_HOME="$pods/libexec"
export GEM_PATH="$pods/libexec:$("$ruby_bin" -e 'puts Gem.default_dir')"

if ! "$ruby_bin" -e 'require "xcodeproj"' 2>/dev/null; then
  echo "configure_xcode: cannot require xcodeproj from $GEM_HOME with $ruby_bin" >&2
  exit 1
fi

exec "$ruby_bin" "$root/tool/ios/configure_xcode.rb" "$root"
