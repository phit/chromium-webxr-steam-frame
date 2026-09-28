# Chromium with WebXR for the Steam Frame

A build recipe and installer for **Chromium with immersive WebXR on Valve's
Steam Frame** headset. Press the
**Enter VR** button on a WebXR site and it opens in the headset, through
SteamVR, as a full VR experience.

The Chromium that SteamOS offers (Flathub) can't do this. Websites see
`navigator.xr`, but `isSessionSupported("immersive-vr")` returns `false`, so
VR buttons are greyed out or missing. Upstream Chromium only wires up its
OpenXR backend on Windows and Android. This repo builds Chromium with the
in-progress Linux OpenXR changes, adds a small fix so it works with SteamVR,
and installs it on the Frame as a normal app in your Steam library.

## What you can do with it

The web has a lot of VR content that only needs a browser:

- **360° and 3D video.** Travel, nature, concerts, sports and documentaries
  from players that support WebXR, shown around you instead of in a flat
  window.
- **Games and toys.** WebXR games and experiments made with
  [three.js](https://threejs.org/examples/?q=webxr),
  [A-Frame](https://aframe.io/) or [Babylon.js](https://www.babylonjs.com/),
  with nothing to install.
- **Learning.** Virtual museum tours, space and anatomy explorers, and other
  educational experiences built for the web.
- **Art and music.** Painting, sculpting and music toys that run in a page.
- **Building WebXR sites.** Test your own WebXR app on real headset hardware
  from a normal URL, with Chromium's DevTools.

## Status

Tested on a Steam Frame (SteamOS 0.3.0, build 20260922.6101926,
SteamVR 2.17.10) with Chromium **156.0.8071.0**, built for arm64:

| | |
|---|---|
| `isSessionSupported("immersive-vr")` | `true` |
| [WebXR Samples](https://immersive-web.github.io/webxr-samples/) Immersive VR Session | shows its scene in the headset |
| three.js [stereo 360 video](https://threejs.org/examples/webxr_vr_video.html) | plays in 3D |
| Launch from the Steam library | opens as its own panel, like any app; WebXR renders in the headset |
| Controllers inside WebXR pages | tracked pose every frame; squeeze events and button state reach the page (trigger, thumbstick and left controller not tested) |
| Laser pointer on the browser panel | reaches Chromium as a touchscreen, so trigger-and-drag scrolls the page (set up and checked on the Frame; the drag itself not yet tried in the headset) |
| Frame rate | 72 fps, every frame 13.9–14 ms over 16 s (simple scene); SteamVR dropped frames only at startup |

This is an unofficial, experimental build. See [Limitations](#limitations)
before you use it for anything other than VR sites.

## Requirements

- A Steam Frame with SteamVR, and a way to run commands on it: the terminal
  in Desktop Mode, or SSH.
- To build: an **x86-64 Linux machine** with about **90 GB free disk**, git,
  Python 3, tmux (or another way to keep a long job running) and a few
  hours. No root access is needed. The first build took about 9.5 hours on
  a 6-core, 12-thread desktop CPU; rebuilds take minutes.

## Build

On the Linux build machine:

```sh
git clone https://github.com/saphid/chromium-webxr-steam-frame
cd chromium-webxr-steam-frame
mkdir -p ~/chromium-xr
tmux new -d -s chromium-xr 'build/build.sh > ~/chromium-xr/build.log 2>&1'
```

`build.sh` fetches Chromium with the Linux OpenXR changes, applies the patch
in [`patches/`](patches), cross-compiles for arm64 and packs the result into
`~/chromium-xr/chromium-xr-arm64.tar.xz` (about 145 MB).

- Follow progress with `tail -F ~/chromium-xr/stage` (milestones) or
  `tail -F ~/chromium-xr/build.log` (everything).
- If it stops (reboot, full disk, network), run the same command again. It
  picks up where it left off.
- To build on another disk, set `CHROMIUM_XR_DIR` and use that directory
  in place of `~/chromium-xr` in the commands above, including the log path.
- It stops itself if free disk space drops below 12 GB.

## Install on the Frame

Copy the tarball and this repo to the Frame, then run the installer there.
For example, over SSH from the build machine (replace `steamframe` with your
Frame's hostname or IP address):

```sh
scp ~/chromium-xr/chromium-xr-arm64.tar.xz steamos@steamframe:
ssh steamos@steamframe
git clone https://github.com/saphid/chromium-webxr-steam-frame
chromium-webxr-steam-frame/frame/install.sh ~/chromium-xr-arm64.tar.xz
```

The installer:

- unpacks the build into `~/chromium-xr`, after checking the new binary runs;
- installs the `chromium-xr` launcher in `~/.local/bin`;
- adds **Chromium XR** to the Desktop Mode app menu;
- adds **Chromium XR** to your Steam library, without restarting Steam.

Run it again with a newer tarball to update. Your profile
(`~/.config/chromium-xr`) and the Steam shortcut are kept. You can delete
the repo clone afterwards; the installer keeps what it needs to uninstall.

If the Steam shortcut can't be added automatically, add it by hand: in
Desktop Mode, open Steam, choose **Games → Add a Non-Steam Game to My
Library**, and pick Chromium XR.

## Use it

1. Open **Chromium XR** from your Steam library. It appears as a panel in
   the headset.
2. Go to a WebXR site, for example the
   [WebXR Samples](https://immersive-web.github.io/webxr-samples/).
3. Press the site's **Enter VR** button. It opens in the headset straight
   away: the launcher sets Chromium's VR permission to Allow for every site,
   so there's no **Allow VR?** prompt.
4. To leave VR, use the site's exit button or the Steam button.

The first time you launch it, Steam may show an **External Controller
Translation** notice. It's only information about controller button icons;
choose OK.

Point at the panel and pull the trigger to click. Hold the trigger and drag
to scroll, as on a touchscreen.

From a terminal on the Frame, `chromium-xr https://example.com` opens a
page directly.

## Limitations

- **Part of the sandbox is off.** The launcher passes
  `--disable-seccomp-filter-sandbox`, which turns off Chrome's system-call
  filter for every process; the namespace sandbox stays on. Without it,
  SteamVR refuses the session (details in
  [docs/technical-notes.md](docs/technical-notes.md)). Use Chromium XR for VR
  sites and keep another browser for everyday browsing.
- **Saved passwords aren't encrypted.** The launcher uses
  `--password-store=basic` so startup doesn't stop at a keyring prompt, so
  passwords you save are stored unencrypted in `~/.config/chromium-xr`.
- **No automatic updates.** It won't get Chromium security fixes until you
  rebuild it.
- **No controller vibration.** SteamVR reports no haptic actuators to the page.
- **No DRM video.** There's no Widevine, so paid streaming services that
  need it won't play.
- **Its panel isn't Steam's app panel.** gamescope sends the laser to apps
  Steam launches as mouse clicks, so dragging would select text. The
  launcher therefore runs Chromium outside Steam's process tree, where each
  window gets a plain gamescope panel and the laser acts as a touchscreen.
  Steam still shows Chromium XR as running, and stopping it there closes
  Chromium. Chromium's output goes to the journal
  (`journalctl --user -u 'chromium-xr-*'`). Start it with
  `CHROMIUM_XR_STEAM_PANEL=1` in the shortcut's launch options (as
  `CHROMIUM_XR_STEAM_PANEL=1 %command%`) to keep it in Steam's panel, with
  mouse clicks.
- **Every site can start VR.** Each launch sets the VR permission's default
  to Allow and removes any per-site Block, so any page can take over the
  headset when you press its button (or, on some sites, without one). You
  can still block a site in `chrome://settings/content/vr`, but only until
  the next launch.
- **One window at a time per profile.** If Chromium XR is already open,
  launching it again opens the page in the existing window.
- **Not a default browser.** It works as one (the desktop entry registers
  for web links), but for the reasons above it's better kept for VR.

## Remove it

```sh
~/.local/share/chromium-xr/uninstall.sh                   # keeps your profile
~/.local/share/chromium-xr/uninstall.sh --remove-profile  # also deletes settings and logins
```

This removes the build, the launcher, the menu entry and the Steam shortcut.

## Updating

The Chromium changes are still under review upstream, so this repo pins one
revision of them (`CL_REF` in [`build/build.sh`](build/build.sh), currently
patch set 44 of CL 8132979). To build a newer patch set, set `CL_REF` when
you run the build, for example
`CL_REF=refs/changes/79/8132979/45 build/build.sh`. The script fetches it,
syncs, re-applies the local patch and rebuilds. A newer patch set may need
the patch in [`patches/`](patches) updated. Then install the new tarball on
the Frame as above.

## How it works

- **Chromium changes.** [CL 8441736](https://chromium-review.googlesource.com/c/chromium/src/+/8441736)
  (a sandboxed XR process on Linux) and
  [CL 8132979](https://chromium-review.googlesource.com/c/chromium/src/+/8132979)
  (the OpenXR device provider on Linux, patch set 44), tracked in Chromium
  [issue 506004811](https://issues.chromium.org/issues/506004811). CL 8441736
  has since merged; CL 8132979 is still in review. The OpenXR device is behind
  `--enable-features=OpenXR`, which the launcher passes.
- **SteamVR fix.** SteamVR's OpenXR runtime asks the kernel who is on the
  other end of its socket (`getsockopt(SO_PEERCRED)`). The XR sandbox policy
  blocks all `getsockopt` calls, which crashed the XR process.
  [`patches/0001-…`](patches/0001-xr-sandbox-allow-getsockopt-SO_PEERCRED.patch)
  allows only that one option. It's reported upstream, with the seccomp
  issue below, in
  [utzcoz/chromium-webxr-linux#7](https://github.com/utzcoz/chromium-webxr-linux/issues/7).
- **Steam integration.** `frame/steam-shortcut.py` adds the shortcut through
  the Steam client's local DevTools port, the same API the Steam UI uses.
  Steam runs each app as its own panel, so Chromium gets one too.

More detail, including why the seccomp filter is off, is in
[docs/technical-notes.md](docs/technical-notes.md).

## Related work

- [utzcoz/chromium-webxr-linux](https://github.com/utzcoz/chromium-webxr-linux):
  a fuller patch series for WebXR over OpenXR on Linux desktops, including
  the in-headset permission UI and crash fixes, tested with
  [Monado](https://monado.dev/). If you're on an x86-64 Linux PC rather than
  the Steam Frame, start there.
- [Chromium issue 506004811](https://issues.chromium.org/issues/506004811):
  upstream tracking for WebXR on Linux.

## License

The scripts in this repo are under the [BSD 3-Clause License](LICENSE). The
patch in [`patches/`](patches) modifies Chromium and is under
[Chromium's license](https://chromium.googlesource.com/chromium/src/+/main/LICENSE).
Chromium is a trademark of Google LLC; this project is not affiliated with
Google or Valve.
