#!/bin/bash
# Helpers for .github/workflows/build.yml.
#
# The build takes longer than a GitHub-hosted job may run (6 h), so each job
# builds for about 5 h, then packs the whole tree and hands it to the next job
# as an artifact. The idea comes from ungoogled-chromium-portablelinux.
#
#   ci.sh setup               free disk space, pick CHROMIUM_XR_DIR
#   ci.sh restore             unpack the previous job's tree
#   ci.sh build FIRST LAST    build until done or out of time; sets the
#                             step output status=running|completed
#   ci.sh save                pack the tree for the next job
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
# On the root disk, so it doesn't take space from the tree on /mnt.
CACHE_DIR=$RUNNER_TEMP/build-tree
CACHE=$CACHE_DIR/build-tree.tar.zst
# Stop building this long after the job starts, leaving time to save the tree.
DEADLINE=$((5 * 3600 + 15 * 60))

case $1 in
  setup)
    echo "JOB_START=$(date +%s)" >> "$GITHUB_ENV"
    # Preinstalled SDKs the build doesn't use; removing them frees about 30 GB.
    sudo rm -rf /usr/local/lib/android /usr/local/.ghcup /usr/lib/jvm \
      /usr/lib/google-cloud-sdk /usr/lib/dotnet /usr/share/swift \
      /opt/hostedtoolcache /usr/local/share/powershell /usr/local/share/chromium
    # The runner's second disk has the most free space, when there is one.
    if mountpoint -q /mnt; then dir=/mnt/chromium-xr; else dir=$HOME/chromium-xr; fi
    sudo mkdir -p "$dir"
    sudo chown "$(id -u):$(id -g)" "$dir"
    echo "CHROMIUM_XR_DIR=$dir" >> "$GITHUB_ENV"
    df -h / "$dir"
    ;;

  restore)
    tree=$(find "$CACHE_DIR" -name '*.tar.zst' | head -n 1)
    zstd -d -c "$tree" | tar -xf - -C "$CHROMIUM_XR_DIR"
    rm -rf "$CACHE_DIR"
    df -h "$CHROMIUM_XR_DIR"
    ;;

  build)
    first=$2 last=$3
    if [ "$first" = true ]; then
      CHROMIUM_XR_STEPS=prepare "$REPO/build/build.sh"
      # Not needed to compile, and a large share of the tree to pass on.
      find "$CHROMIUM_XR_DIR/src" -name .git -prune -exec rm -rf {} +
    fi
    rc=0
    CHROMIUM_XR_STEPS=build BUILD_TIMEOUT=$((JOB_START + DEADLINE - $(date +%s))) \
      "$REPO/build/build.sh" || rc=$?
    if [ "$rc" = 124 ] && [ "$last" != true ]; then
      echo "status=running" >> "$GITHUB_OUTPUT"
      exit 0
    fi
    [ "$rc" = 0 ] || exit "$rc"
    CHROMIUM_XR_STEPS=package "$REPO/build/build.sh"
    echo "status=completed" >> "$GITHUB_OUTPUT"
    ;;

  save)
    mkdir -p "$CACHE_DIR"
    tar -cf - -C "$CHROMIUM_XR_DIR" . | zstd -T0 -3 -f -o "$CACHE"
    ls -la "$CACHE"
    ;;

  *)
    echo "usage: $0 setup|restore|build FIRST LAST|save" >&2
    exit 2
    ;;
esac
