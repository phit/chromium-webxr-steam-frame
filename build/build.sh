#!/bin/bash
# Cross-compile arm64 Chromium with WebXR over OpenXR on Linux, for the
# Steam Frame. Runs on an x86-64 Linux machine, no root needed.
#
#   build/build.sh            # checkout, patch, build, package
#
# Needs about 90 GB free disk and several hours (about 9.5 h on a 6-core
# machine for the first build). Run it detached, e.g. in tmux:
#   tmux new -d -s chromium-xr 'build/build.sh > ~/chromium-xr/build.log 2>&1'
#
# Progress lines go to $CHROMIUM_XR_DIR/stage. The result is
# $CHROMIUM_XR_DIR/chromium-xr-arm64.tar.xz. Re-running resumes: the
# existing checkout and out/XR are reused, so a rebuild takes minutes.
# Set CL_REF to build a different patch set of CL 8132979 (see README).
set -euo pipefail

W=${CHROMIUM_XR_DIR:-$HOME/chromium-xr}
PATCHES=$(cd "$(dirname "$0")/../patches" && pwd)
# Chromium CL 8132979 (WebXR OpenXR provider on Linux), patch set 44. It sits
# on top of CL 8441736 (the XR process sandbox), so fetching it gets both.
CL_REF=${CL_REF:-refs/changes/79/8132979/44}

mkdir -p "$W"
cd "$W"
stage() { echo "$(date -Is) $*" | tee -a "$W/stage"; }
# Stops the build before the disk fills up.
guard() {
  avail=$(df --output=avail -BG "$W" | tail -n 1 | tr -dc 0-9)
  if [ "$avail" -lt 12 ]; then stage "ABORT: only ${avail}G free for $W"; return 3; fi
}

# Checks for a file, not the directory, so an interrupted clone is retried.
if [ ! -x depot_tools/gclient ]; then
  rm -rf depot_tools
  git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH="$W/depot_tools:$PATH" DEPOT_TOOLS_UPDATE=1 DEPOT_TOOLS_METRICS=0

if [ ! -f .gclient ]; then
  cat > .gclient <<'G'
solutions = [{ "name": "src", "url": "https://chromium.googlesource.com/chromium/src.git",
  "managed": False, "custom_deps": {}, "custom_vars": { "checkout_nacl": False } }]
target_os = ["linux"]
target_cpu = ["arm64"]
G
fi

# Fetch when there's no checkout yet (or the first fetch was interrupted), or
# when CL_REF names a different patch set than last time.
if ! git -C src rev-parse -q --verify HEAD >/dev/null 2>&1 ||
    [ "$(cat "$W/cl-ref" 2>/dev/null)" != "$CL_REF" ]; then
  stage "fetch src at $CL_REF"
  mkdir -p src
  [ -d src/.git ] || git -C src init -q
  git -C src remote get-url origin >/dev/null 2>&1 ||
    git -C src remote add origin https://chromium.googlesource.com/chromium/src.git
  git -C src fetch -q --depth=1 origin "$CL_REF"
  # Drops the local patches; they're re-applied below.
  git -C src checkout -q --force FETCH_HEAD
  echo "$CL_REF" > "$W/cl-ref"
fi
guard
stage "src at $(git -C src log -1 --format='%h %s')"

rev=$(git -C src rev-parse HEAD)
# Sync once per revision. After the patches below are applied, gclient sync
# refuses to run on the modified checkout, so re-runs must skip it.
if [ "$(cat "$W/synced" 2>/dev/null)" != "$rev" ]; then
  stage "gclient sync"
  gclient sync --nohooks --no-history -D --shallow --revision "src@$rev" -j 8
  guard
  stage "runhooks"
  gclient runhooks
  src/build/linux/sysroot_scripts/install-sysroot.py --arch=arm64
  echo "$rev" > "$W/synced"
fi
guard

cd src
# Local fixes on top of the CLs. Each is applied once; re-runs skip it.
for p in "$PATCHES"/*.patch; do
  if ! git apply --reverse --check "$p" 2>/dev/null; then
    git apply "$p"
    stage "applied $(basename "$p")"
  fi
done

mkdir -p out/XR
# Rewritten on every run: change build settings here, not in out/XR/args.gn.
cat > out/XR/args.gn <<'A'
target_os = "linux"
target_cpu = "arm64"
is_debug = false
is_official_build = false
is_component_build = false
dcheck_always_on = false
symbol_level = 0
blink_symbol_level = 0
v8_symbol_level = 0
proprietary_codecs = true
ffmpeg_branding = "Chrome"
enable_nacl = false
use_remoteexec = false
use_siso = true
treat_warnings_as_errors = false
A
stage "gn gen"
gn gen out/XR
gn args out/XR --list=enable_openxr --short | tee -a "$W/stage"

stage "build"
( while sleep 600; do guard || { pkill -u "$(id -u)" -f "(siso|ninja).*out/XR"; exit 3; }; done ) &
GUARD=$!
trap 'kill $GUARD 2>/dev/null || true' EXIT
autoninja -C out/XR chrome chrome_sandbox chrome_crashpad_handler

stage "package"
cp chrome/app/theme/chromium/product_logo_256.png out/XR/product_logo_256.png
cd out/XR
files=(chrome chrome_sandbox chrome_crashpad_handler *.pak *.bin icudtl.dat locales product_logo_256.png)
# GPU libraries aren't produced by every config; pack the ones that exist.
for f in libEGL.so libGLESv2.so libvk_swiftshader.so libvulkan.so.1 vk_swiftshader_icd.json; do
  [ -e "$f" ] && files+=("$f")
done
tar -cJf "$W/chromium-xr-arm64.tar.xz" "${files[@]}"
stage "DONE $(ls -la "$W/chromium-xr-arm64.tar.xz")"
