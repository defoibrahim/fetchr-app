#!/usr/bin/env bash
# Body of Runner's "Process Python libraries" build phase. Copies the stdlib, ios/app and
# ios/app_packages into the app and turns every .so into a signed framework (CPython's utils.sh).
set -euo pipefail

xcf="$PROJECT_DIR/Python.xcframework"
if [ ! -f "$xcf/build/utils.sh" ] || [ ! -d "$PROJECT_DIR/app_packages" ]; then
  echo "error: ios/Python.xcframework or ios/app_packages is missing: run tool/ios/fetch_python.sh and tool/ios/vendor_python.sh" >&2
  exit 1
fi
# utils.sh copies lib-$ARCHS, which only exists for one architecture at a time.
case "$ARCHS" in
  *" "*)
    echo "error: Process Python libraries supports one architecture per build, got ARCHS='$ARCHS'" >&2
    exit 1
    ;;
esac

# ios/app's __pycache__ is whatever the host's pytest wrote; app_packages ships its compiled bytecode.
rsync -a --delete --exclude __pycache__ "$PROJECT_DIR/app/" "$CODESIGNING_FOLDER_PATH/app/"
rsync -a --delete "$PROJECT_DIR/app_packages/" "$CODESIGNING_FOLDER_PATH/app_packages/"

# utils.sh reads optional Xcode variables that may be unset.
set +u
# shellcheck disable=SC1091
source "$xcf/build/utils.sh"
install_python Python.xcframework app app_packages
set -u
