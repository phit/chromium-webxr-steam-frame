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
- `requestSession("immersive-vr")` succeeds. (Chromium asks **Allow VR?**
  first unless the site's VR permission is Allow; the launcher makes Allow
  the default, see below.)
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

## Input and frame rate (2026-09-27)

Measured with a session that clears to red, with `hand-tracking` and
`local-floor` requested:

- **Frame rate:** 72 fps. Over 16.6 s the median frame interval was 13.9 ms,
  p99 14 ms and max 14 ms, with no frame longer than 1.5× the median.
  SteamVR's `vrcmd --stats` counted 2,940 submits, 4 dropped frames (all at
  startup) and 2 reprojected.
- **Controllers:** the right controller appears as a `tracked-pointer` input
  source with profiles `oculus-touch` and
  `generic-trigger-squeeze-thumbstick`, an `xr-standard` gamepad (7 buttons,
  4 axes), a grip space, and a 25-joint `hand`. Its target-ray and grip
  poses were available on every frame, and not emulated. A physical squeeze
  produced `squeezestart`/`squeeze` events and set button 1 as pressed.
- **Not covered:** trigger (`select`), thumbstick axes, face buttons, the left
  controller (not connected during the test) and bare-hand tracking.
- **Haptics:** `gamepad.hapticActuators` is empty, so pages can't vibrate
  the controllers.
- Requesting `hand-tracking` makes Chromium ask **Allow hand tracking?** in
  the browser panel before the session starts.

## The laser pointer on the browser panel (2026-09-28)

gamescope (3.16.28 on the Frame) turns SteamVR's laser events for a panel
into input for the app. A trigger press is `VREvent_MouseButtonDown` with the
left button, which gamescope sends as a Wayland touch, then Xwayland passes
it on as an XInput 2 touch. What happens next depends on gamescope's *touch
click mode* for that panel (`GetTouchClickMode` in
`src/Backends/OpenVRBackend.cpp`):

- **Windows of an app Steam launched** (app id taken from the `STEAM_GAME`
  property, the `app-steam-app<id>-<pid>.scope` cgroup, or a
  `reaper SteamLaunch AppId=<id>` ancestor): forced to *left click*, in a
  code path commented as a workaround for Steam not setting
  `STEAM_TOUCH_CLICK_MODE` on the Frame. The touch becomes a left mouse
  button, so holding the trigger and dragging selects text.
- **Windows with no app id**: *passthrough*. Each gets its own panel
  (`gamescope.gamescope-0.window.<n>`) and receives real touches. The
  Desktop Mode panel is one of these, which is why a browser there scrolls
  when you drag.

The thumbstick sends `VREvent_ScrollSmooth`, which gamescope turns into mouse
wheel events in either mode.

Chromium registers itself in a systemd scope of its own
(`app-org.chromium.Chromium-<pid>.scope`), so gamescope finds the app id by
walking up to Steam's `reaper`. Forking can't escape that, because `reaper`
is a subreaper. When `SteamAppId` is set, the `chromium-xr` launcher starts
Chromium with `systemd-run --user` instead, and waits for it to exit.
Chromium's parent is then the user's systemd, and its windows get no app id.
Chromium's menus and bubbles are override-redirect windows, which gamescope
shows only over a focused window with the same app id. They come from the
same process, so they get app id 0 as well.

Verified on the Frame (SteamOS build 20260922.6101926), without wearing the
headset:

- Launched from Steam, the old launcher's window had app id 2349681812 and
  panel `valve.steam.desktopgame.2349681812`. Setting `STEAM_GAME` to 0 on
  it destroyed that panel and created `gamescope.gamescope-0.window.70`.
- With the new launcher, Chromium's parent is `systemd`, not `reaper`. Its
  panel is `gamescope.gamescope-0.window.88`, `GAMESCOPE_FOCUSABLE_APPS` is
  empty, and `SIGTERM` to the launcher, which is what Steam's Stop does,
  closes Chromium and removes the service.
- Xwayland 24.1.9 gives every device the XI1 type `xwayland-pointer`,
  including `xwayland-touch`. Chromium's X11 hotplug code only counts
  `TOUCHSCREEN` or `xwayland-touch` as a touchscreen, so it reports
  `navigator.maxTouchPoints` 0 and leaves out the touch API. Its XI2 touch
  handling (`TouchFactory`) still accepts the device's touches. The launcher
  passes `--touch-events=enabled`, and pages then see `ontouchstart`.
- Chromium's `--touch-devices=<id>` switch isn't a way around this. It
  would make every button of the shared `xwayland-pointer` a touch,
  including wheel and right-click.

Not yet checked in the headset: dragging a page, fling, and menus and
permission prompts showing on the new panel.

## The VR permission (2026-09-28)

Chromium's VR permission is the `vr` content setting, default Ask, with
Allow, Ask and Block all valid defaults
(`components/content_settings/core/browser/content_settings_registry.cc`).
No policy or command-line switch sets it, and managed policies would have to
go in `/etc/chromium`, which is on the Frame's read-only root. So before each
start, if Chromium isn't already running (its `SingletonLock` link names a
live process), the launcher sets `profile.default_content_setting_values.vr`
to 1 (Allow) in `Default/Preferences` and deletes `vr` exceptions whose
setting is 2 (Block). **Verified on the Frame:** aframe.io, which had no
saved exception, started an immersive session from `requestSession` with no
prompt, and the value was still 1 after Chromium quit and rewrote the file.
It doesn't cover **Allow hand tracking?** (the `hand_tracking` setting).

The same test showed WebXR still works with Chromium outside Steam's
process tree. The launcher keeps Steam's environment, including
`SteamAppId`, and SteamVR still bound the session to
`steam.app.2349681812`.

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

- **Testing without wearing the headset.** In standby SteamVR keeps the
  session hidden. With `vrcmd` from `/opt/steamvr/bin/linuxarm64`:
  `vrcmd --set-settings-bool power.pauseCompositorOnStandby 0`,
  `vrcmd --set-settings-float power.turnOffScreensTimeout 3600`, then
  `vrcmd --handlewakeup`. The session becomes visible and renders at the
  headset's rate. If it stays `visible-blurred`, the Steam dashboard is open
  over it: run `SteamClient.OpenVR.VROverlay.HideDashboard()` in the Steam
  client's DevTools (`127.0.0.1:8080`, page `SharedJSContext`). Undo with
  `--set-settings-bool power.pauseCompositorOnStandby 1` and
  `--set-settings-float power.turnOffScreensTimeout 5`. (The bool setter
  reads `true` as false; use 1 and 0.) Verified 2026-09-27: a WebXR session
  clearing to red filled both eyes in SteamVR's stereo screenshot.
- If the headset is outside its playspace, SteamVR shows the passthrough
  camera wherever a page leaves transparent pixels.

- `chromium-xr --remote-debugging-port=9223 URL` opens DevTools on the Frame's
  loopback. It has no password, so close the browser when you're done. If a
  VPN such as userspace Tailscale forwards traffic to loopback, other devices
  can reach it.
- `chrome://gpu` and `chrome://webxr-internals` show the graphics setup and
  the XR runtime Chromium picked.
- SteamVR's logs are in `~/.local/share/Steam/logs/`. `vrserver.txt` shows
  the session starting and which app SteamVR bound it to.
