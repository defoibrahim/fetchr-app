#!/usr/bin/env bash
# Downloads the official CPython iOS XCframework into ios/Python.xcframework (gitignored), minus
# the parts of the stdlib an app never imports. A no-op when the stamp file already matches.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
version="$(cat "$root/tool/ios/python-version")"
minor="${version%.*}"
# Bump together with tool/ios/python-version.
sha256="0f9fc7f61ceb8278a69fc7ec6089aad81789a96fa42f31cfe6d2f5f860d20a62"
url="https://www.python.org/ftp/python/$version/python-$version-iOS-XCframework.tar.gz"

dest="$root/ios/Python.xcframework"
stamp="$dest/.fetchr-version"
# The suffix changes whenever the pruning below does, so existing checkouts fetch again.
want="$version $sha256 pruned1"

if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$want" ]; then
  echo "fetch_python: Python $version already in ios/Python.xcframework"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "fetch_python: downloading $url"
curl --fail --location --retry 3 --silent --show-error -o "$work/python.tar.gz" "$url"

got="$(shasum -a 256 "$work/python.tar.gz" | cut -d ' ' -f 1)"
if [ "$got" != "$sha256" ]; then
  echo "fetch_python: sha256 mismatch for $url: expected $sha256, got $got" >&2
  exit 1
fi

mkdir "$work/x"
tar -xzf "$work/python.tar.gz" -C "$work/x" ./Python.xcframework
[ -f "$work/x/Python.xcframework/build/utils.sh" ] || {
  echo "fetch_python: the archive has no Python.xcframework/build/utils.sh" >&2
  exit 1
}

xcf="$work/x/Python.xcframework"
for dir in test idlelib tkinter turtledemo ensurepip pydoc_data; do
  rm -rf "${xcf:?}/lib/python$minor/$dir"
done
for dynload in "$xcf"/*/lib-*/"python$minor"/lib-dynload; do
  for mod in '_test*' 'xxlimited*' '_ctypes_test*' '_remote_debugging*' 'xxsubtype*' '_xxtestfuzz*'; do
    # shellcheck disable=SC2086
    rm -f "$dynload"/$mod
  done
done

rm -rf "$dest"
mv "$xcf" "$dest"
echo "$want" > "$stamp"
echo "fetch_python: installed Python $version in ios/Python.xcframework"
