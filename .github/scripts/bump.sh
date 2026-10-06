#!/bin/bash
# Checks for a newer Chromium to build, for .github/workflows/bump.yml.
#
# Picks the newest Linux release on Stable, or on Beta while Stable is older
# than MIN_VERSION (the first release with the upstream Linux OpenXR
# changes). If it's newer than CHROMIUM_VERSION in build/build.sh, checks that
# the local patches still apply to it, without a checkout.
#
# Step outputs: version=<newer release> (empty when there's none) and
# patches=ok|fail.
set -euo pipefail

MIN_VERSION=${MIN_VERSION:-157.0.8088.0}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${GITHUB_OUTPUT:-/dev/stdout}

# True if version $1 is newer than $2.
newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]; }

current=$(sed -n 's/^CHROMIUM_VERSION=${CHROMIUM_VERSION:-\(.*\)}$/\1/p' "$REPO/build/build.sh")
[ -n "$current" ] || { echo "::error::CHROMIUM_VERSION not found in build/build.sh"; exit 1; }

version=
for channel in Stable Beta; do
  v=$(curl -fsS "https://chromiumdash.appspot.com/fetch_releases?channel=$channel&platform=Linux&num=1" |
    jq -r '.[0].version')
  echo "$channel: $v"
  if ! newer "$MIN_VERSION" "$v"; then version=$v; break; fi
done
echo "pinned: $current"

if [ -z "$version" ]; then
  echo "No Stable or Beta release at $MIN_VERSION or newer yet."
  echo "version=" >> "$OUT"
  exit 0
fi
if ! newer "$version" "$current"; then
  echo "Nothing newer to build."
  echo "version=" >> "$OUT"
  exit 0
fi
echo "version=$version" >> "$OUT"

# Fetch only the files the patches touch, at the new tag, and try them there.
tree=$(mktemp -d)
trap 'rm -rf "$tree"' EXIT
result=ok
for p in "$REPO"/patches/*.patch; do
  for f in $(sed -n 's|^+++ b/||p' "$p"); do
    mkdir -p "$tree/$(dirname "$f")"
    # A 404 leaves the file out, so a patch to a removed file fails below.
    curl -fsS "https://chromium.googlesource.com/chromium/src/+/refs/tags/$version/$f?format=TEXT" |
      base64 -d > "$tree/$f" || rm -f "$tree/$f"
  done
  if git -C "$tree" apply --check "$p"; then
    echo "$(basename "$p") applies to $version"
  else
    echo "::error::$(basename "$p") doesn't apply to Chromium $version"
    result=fail
  fi
done
echo "patches=$result" >> "$OUT"
