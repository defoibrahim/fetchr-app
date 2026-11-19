#!/usr/bin/env bash
# Installs the pinned pure-Python packages of tool/ios/requirements.txt into ios/app_packages
# (gitignored), always from scratch, with their bytecode compiled.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
minor="$(cut -d . -f 1,2 "$root/tool/ios/python-version")"
dest="$root/ios/app_packages"
command -v uv >/dev/null || { echo "vendor_python: uv not found (brew install uv)" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

uv pip install --target "$work" --no-deps --require-hashes --only-binary :all: \
  --python-version "$minor" --python-platform arm64-apple-ios -r "$root/tool/ios/requirements.txt"

# Console scripts carry a shebang to the host Python, and share/ holds man pages and completions:
# neither is usable inside the app.
rm -rf "$work/bin" "$work/share"

native="$(find "$work" -type f \( -name '*.so' -o -name '*.dylib' \))"
if [ -n "$native" ]; then
  echo "vendor_python: native extensions are not allowed in app_packages:" >&2
  echo "$native" >&2
  exit 1
fi

# The app runs with write_bytecode off, so it only reads these; a signed bundle never changes, so
# unchecked-hash skips checking each pyc against its source.
uv run --no-project --python "$minor" python -m compileall -q -j0 --invalidation-mode unchecked-hash "$work"

rm -rf "$dest"
mv "$work" "$dest"
echo "vendor_python: installed $(ls -d "$dest"/*.dist-info | wc -l | tr -d ' ') packages in ios/app_packages"
