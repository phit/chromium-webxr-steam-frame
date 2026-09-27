# Technical notes

What we found getting WebXR working on the Steam Frame, for anyone picking
this up or taking it upstream. Tested with Chromium 156.0.8071.0 (arm64),
SteamOS 0.3.0 (build 20260922.6101926) and SteamVR 2.17.10.

## Why stock Chromium on Linux has no immersive WebXR

Chromium 154 was the first release to compile OpenXR on Linux
(`enable_openxr` includes Linux). But
`content/services/isolated_xr_device/xr_runtime_provider.cc` only creates an
OpenXR device when `ENABLE_OPENXR && IS_WIN`. Nothing on Linux calls the
OpenXR code, so the linker drops it. Flathub's arm64 Chromium contains no
OpenXR loader code at all, and flags such as `--force-webxr-runtime=openxr`
can't bring it back.

The two Gerrit changes this repo builds fill that gap:

- [CL 8132979](https://chromium-review.googlesource.com/c/chromium/src/+/8132979)
  creates the OpenXR device on Linux, using the Vulkan graphics binding
  (`XR_KHR_vulkan_enable2`). `device::features::kOpenXR` stays off by
  default, so it needs `--enable-features=OpenXR`.
- [CL 8441736](https://chromium-review.googlesource.com/c/chromium/src/+/8441736)
  runs the XR device service in its own sandbox (`xr_compositing`, with the
  `XrProcessPolicy` seccomp policy and a file broker), instead of requiring
  `--no-sandbox`.

The build uses patch set 44 of CL 8132979, which sits on top of CL 8441736.

## The SO_PEERCRED crash

With both CLs, the XR utility process crashed inside `xrCreateInstance` on
system call 0xd1 (`getsockopt` on arm64). SteamVR's IPC client calls
`getsockopt(fd, SOL_SOCKET, SO_PEERCRED, …)` to check which process is on the
other end of its socket, and `XrProcessPolicy` refuses every `getsockopt`.
[`patches/0001-xr-sandbox-allow-getsockopt-SO_PEERCRED.patch`](../patches/0001-xr-sandbox-allow-getsockopt-SO_PEERCRED.patch)
allows exactly `SOL_SOCKET`/`SO_PEERCRED` and still returns `EPERM` for
everything else.

## Why the seccomp filter is still off

With the patch, `xrCreateInstance` gets further but fails with
`Unable to init path manager: VRInitError_Init_Internal`. SteamVR's client
reads `/proc/self/status` to find its own process ID. Inside the seccomp
sandbox, file opens go through Chrome's broker process, so `/proc/self` is
the broker's, and SteamVR registers the broker's PID instead of the XR
process's. Granting the broker `/proc/self` doesn't help, because the broker
can only answer for itself.

Fixing this properly needs a change in Chromium: for example, having the
broker client rewrite `/proc/self` to `/proc/<caller pid>`, or opening the
needed `/proc` files before the sandbox seals. Until then the launcher passes
`--disable-seccomp-filter-sandbox`. The namespace sandbox still works:
SteamOS allows unprivileged user namespaces, so the setuid `chrome_sandbox`
isn't needed.

## What a working session looks like

- The page's `isSessionSupported("immersive-vr")` resolves `true`.
- After the **Allow VR?** prompt, `requestSession("immersive-vr")` succeeds.
  The first frame has a viewer pose with 2 views and a 2880 × 1440 framebuffer
  (1440 × 1440 per eye).
- SteamVR's log (`~/.local/share/Steam/logs/vrserver.txt`) shows the app move
  from `VRApplication_OpenXRInstance` to `VRApplication_OpenXRScene`, followed
  by controller binding files being created for
  `system.generated.openxr.chromium 156.chrome`.
- If nobody is wearing the headset, SteamVR keeps it in standby: the session
  stays at `XR_SESSION_STATE_SYNCHRONIZED`, the page sees
  `visibilityState: "hidden"`, and only the first frame runs. Put the headset
  on to see it.

## Graphics

Chromium's GPU process uses ANGLE on OpenGL, which runs on zink over the
Turnip Vulkan driver (Adreno 750). Chromium's own Vulkan backend stays off;
that doesn't stop the session. The OpenXR runtime uses Vulkan.

## Panels and the Steam library

The Frame's compositor (gamescope) gives every Steam app ID its own SteamVR
overlay, named `valve.steam.desktopgame.<appid>`, which appears as a panel in
the headset. A non-Steam shortcut gets an app ID like any game, so launching
Chromium XR from the library gives it a panel. `frame/steam-shortcut.py` adds
the shortcut through the Steam client's DevTools port (`127.0.0.1:8080`,
page `SharedJSContext`) with `SteamClient.Apps.AddShortcut`, so Steam doesn't
need restarting. (`steam steam://addnonsteamgame/<path>` adds nothing.)

Steam preloads its in-game overlay, `gameoverlayrenderer.so`, into everything
it launches through `LD_PRELOAD`. In Chromium it segfaults the zygote during
library initialisation. The GPU process then fails to launch
(`GPU process launch failed: error_code=1002`), and after a few tries
Chromium quits with `GPU process isn't usable. Goodbye.` about 30 seconds
after starting. The `chromium-xr` launcher removes the overlay from
`LD_PRELOAD` before starting Chromium, keeping anything else that was
preloaded.

## Debugging

- `chromium-xr --remote-debugging-port=9223 URL` opens DevTools on the Frame's
  loopback. It has no password, so close the browser when you're done. If a
  VPN such as userspace Tailscale forwards traffic to loopback, other devices
  can reach it.
- `chrome://gpu` and `chrome://webxr-internals` show the graphics setup and
  the XR runtime Chromium picked.
- SteamVR's logs are in `~/.local/share/Steam/logs/`. `vrserver.txt` shows
  the session starting and which app SteamVR bound it to.
