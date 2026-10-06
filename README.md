# Chrome XR: WebXR for the Steam Frame

An installer for **Google's arm64 Chrome with immersive WebXR on Valve's
Steam Frame** headset, as **Chrome XR**. Press the **Enter VR** button on a
WebXR site and it opens in the headset, through SteamVR, as a full VR
experience.

The Chromium that SteamOS offers (Flathub) can't do this. Websites see
`navigator.xr`, but `isSessionSupported("immersive-vr")` returns `false`, so
VR buttons are greyed out or missing. Chrome and Chromium only gained OpenXR
on Linux in version 157, and it's off unless the browser is started with the
right flags. This installer downloads Google's arm64 Chrome and sets it up on
the Frame with those flags, as a normal app in your Steam library.

This is the `google` branch. The `main` branch builds and installs Chromium
instead, as **Chromium XR**. The two use different names, folders and
profiles, so both can be installed at once.

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

The table above is for the Chromium build on the `main` branch. Google
Chrome Canary 157.0.8088.0 for arm64, with the same launcher, also starts
immersive VR sessions on the Frame (first test; the rows above haven't all
been repeated with it).

This is unofficial and experimental, and not affiliated with Google. See
[Limitations](#limitations) before you use it for anything other than VR
sites.

## Requirements

A Steam Frame with SteamVR, and a way to run commands on it: the terminal in
Desktop Mode, or SSH. Nothing to build.

## Install on the Frame

On the Frame:

```sh
git clone -b google https://github.com/phit/chromium-webxr-steam-frame
chromium-webxr-steam-frame/frame/install.sh
```

The installer:

- downloads Google's arm64 Chrome from Google's apt repository, from the
  most stable channel that has WebXR on Linux (Chrome 157 or newer; Canary
  for now), checks it against the repository's SHA-256, and unpacks it into
  `~/chrome-xr`, after checking the new binary runs;
- installs the `chrome-xr` launcher in `~/.local/bin`;
- adds **Chrome XR** to the Desktop Mode app menu;
- adds **Chrome XR** to your Steam library, without restarting Steam.

To pick a channel, name it: `install.sh beta` (or `stable`, `unstable`,
`canary`).

Chrome XR keeps its profile in `~/.config/chrome-xr`, apart from Chromium
XR's `~/.config/chromium-xr`. Run the installer again to update; the profile
and the Steam shortcut are kept. You can delete the repo clone afterwards;
the installer keeps what it needs to uninstall.

If the Steam shortcut can't be added automatically, add it by hand: in
Desktop Mode, open Steam, choose **Games → Add a Non-Steam Game to My
Library**, and pick Chrome XR.

## Use it

1. Open **Chrome XR** from your Steam library. It appears as a panel in
   the headset.
2. Go to a WebXR site, for example the
   [WebXR Samples](https://immersive-web.github.io/webxr-samples/).
3. Press the site's **Enter VR** button. It opens in the headset straight
   away: the launcher makes Allow the default for Chrome's VR permission,
   so there's no **Allow VR?** prompt.
4. To leave VR, use the site's exit button or the Steam button.

The first time you launch it, Steam may show an **External Controller
Translation** notice. It's only information about controller button icons;
choose OK.

Point at the panel and pull the trigger to click. Hold the trigger and drag
to scroll, as on a touchscreen.

From a terminal on the Frame, `~/.local/bin/chrome-xr https://example.com`
opens a page directly. SteamOS doesn't put `~/.local/bin` on the `PATH`; to
type just `chrome-xr`, add `export PATH="$HOME/.local/bin:$PATH"` to
`~/.bashrc`.

## Limitations

- **Part of the sandbox is off.** The launcher passes
  `--disable-seccomp-filter-sandbox`, which turns off Chrome's system-call
  filter for every process; the namespace sandbox stays on. Without it,
  SteamVR refuses the session (details in
  [docs/technical-notes.md](docs/technical-notes.md)). Use Chrome XR for VR
  sites and keep another browser for everyday browsing. Valve has
  [changed SteamVR](https://github.com/utzcoz/chromium-webxr-linux/issues/7#issuecomment-5958394261)
  so this should become unnecessary with a coming Steam Frame OS Beta. To
  try with the filter on, start it with `CHROME_XR_SECCOMP=1`, for example
  `CHROME_XR_SECCOMP=1 ~/.local/bin/chrome-xr`.
- **Saved passwords aren't encrypted.** The launcher uses
  `--password-store=basic` so startup doesn't stop at a keyring prompt, so
  passwords you save are stored unencrypted in `~/.config/chrome-xr`.
- **No automatic updates on the Frame.** It won't get security fixes until
  you run the installer again (see [Updating](#updating)).
- **Google's Chrome is Google's.** The default install is Google Chrome,
  with its Google services and terms, not Chromium. The `main` branch
  builds Chromium instead, if you'd rather not.
- **No controller vibration.** SteamVR reports no haptic actuators to the page.
- **DRM video untested.** Google's Chrome ships Widevine for arm64, but it
  hasn't been tried with streaming services yet.
- **Its panel isn't Steam's app panel.** gamescope sends the laser to apps
  Steam launches as mouse clicks, so dragging would select text. The
  launcher therefore runs Chrome outside Steam's process tree, where each
  window gets a plain gamescope panel and the laser acts as a touchscreen.
  Steam still shows Chrome XR as running, and stopping it there closes
  Chrome. Chrome's output goes to the journal
  (`journalctl --user -u 'chrome-xr-*'`). Start it with
  `CHROME_XR_STEAM_PANEL=1` in the shortcut's launch options (as
  `CHROME_XR_STEAM_PANEL=1 %command%`) to keep it in Steam's panel, with
  mouse clicks.
- **Sites can start VR without asking.** Each launch sets the VR
  permission's default to Allow, so any page can take over the headset when
  you press its button (or, on some sites, without one). To stop a site,
  block it in `chrome://settings/content/vr`; the launcher leaves per-site
  Blocks alone.
- **One window at a time per profile.** If Chrome XR is already open,
  launching it again opens the page in the existing window.
- **Not a default browser.** It works as one (the desktop entry registers
  for web links), but for the reasons above it's better kept for VR.

## Remove it

```sh
~/.local/share/chrome-xr/uninstall.sh                   # keeps your profile
~/.local/share/chrome-xr/uninstall.sh --remove-profile  # also deletes settings and logins
```

This removes the browser, the launcher, the menu entry and the Steam shortcut.

## Updating

Run `frame/install.sh` again (with the same channel, if you picked one). It
downloads the newest version and moves to a more stable channel once that
one has Chrome 157. Chrome doesn't update itself here: on Linux it relies on
the package manager for that.

## How it works

- **Chromium changes.** [CL 8441736](https://chromium-review.googlesource.com/c/chromium/src/+/8441736)
  (a sandboxed XR process on Linux) and
  [CL 8132979](https://chromium-review.googlesource.com/c/chromium/src/+/8132979)
  (the OpenXR device provider on Linux), tracked in Chromium
  [issue 506004811](https://issues.chromium.org/issues/506004811). Both have
  merged and ship from Chromium 157. The OpenXR device is behind
  `--enable-features=OpenXR`, which the launcher passes.
- **SteamVR and the sandbox.** SteamVR's OpenXR client makes calls that the
  XR process's seccomp filter refuses: `getsockopt(SO_PEERCRED)`, and reads
  of `/proc/self` that the sandbox's broker answers for the wrong process.
  The launcher passes `--disable-seccomp-filter-sandbox`, which avoids both,
  so Google's unmodified Chrome works. (The `main` branch's Chromium build
  also carries [`patches/0001-…`](patches/0001-xr-sandbox-allow-getsockopt-SO_PEERCRED.patch)
  for the first.) Reported upstream in
  [utzcoz/chromium-webxr-linux#7](https://github.com/utzcoz/chromium-webxr-linux/issues/7).
- **Steam integration.** `frame/steam-shortcut.py` adds the shortcut through
  the Steam client's local DevTools port, the same API the Steam UI uses.
  Steam runs each app as its own panel, so Chrome gets one too.

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
