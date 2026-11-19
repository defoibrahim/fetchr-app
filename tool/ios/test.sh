#!/usr/bin/env bash
# Usage: tool/ios/test.sh [--swift|--python]   (both by default)
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
run_swift=1
run_python=1
case "${1:-}" in
  --swift) run_python=0 ;;
  --python) run_swift=0 ;;
  "") ;;
  *) echo "usage: $0 [--swift|--python]" >&2; exit 2 ;;
esac

if [ "$run_swift" = 1 ]; then
  if [ ! -d ios/Python.xcframework ] || [ ! -d ios/app_packages ]; then
    echo "test.sh: run tool/ios/fetch_python.sh and tool/ios/vendor_python.sh" >&2
    exit 1
  fi
  if [ ! -d ios/Frameworks/ffmpegkit/ffmpegkit.xcframework ]; then
    echo "test.sh: run tool/ios/build_ffmpeg.sh" >&2
    exit 1
  fi
  if [ ! -f ios/Flutter/Generated.xcconfig ] || [ ! -d ios/Pods ]; then
    fvm flutter build ios --simulator --debug --config-only
  fi
  xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
    -destination "platform=iOS Simulator,name=${FETCHR_SIM:-iPhone 17}" -quiet
fi

if [ "$run_python" = 1 ]; then
  [ -d ios/python_tests ] || { echo "test.sh: ios/python_tests is missing" >&2; exit 1; }
  uv run --python "$(cut -d . -f 1,2 tool/ios/python-version)" --with pytest pytest ios/python_tests -q
fi
