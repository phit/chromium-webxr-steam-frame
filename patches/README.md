# Patches

Local changes applied on top of Chromium
[CL 8132979](https://chromium-review.googlesource.com/c/chromium/src/+/8132979)
and [CL 8441736](https://chromium-review.googlesource.com/c/chromium/src/+/8441736)
by `build/build.sh`, in file-name order.

- `0001-xr-sandbox-allow-getsockopt-SO_PEERCRED.patch`: lets the XR process
  call `getsockopt(SOL_SOCKET, SO_PEERCRED)`, which SteamVR's OpenXR runtime
  needs. See [docs/technical-notes.md](../docs/technical-notes.md).

These patches modify Chromium source and are under
[Chromium's BSD-style license](https://chromium.googlesource.com/chromium/src/+/main/LICENSE),
Copyright The Chromium Authors.
