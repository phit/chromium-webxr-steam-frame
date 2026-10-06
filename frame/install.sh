#!/bin/bash
# Run on the Steam Frame (Desktop Mode terminal or SSH), as the normal user:
#
#   frame/install.sh                            # Google's arm64 Chrome
#   frame/install.sh beta                       # a given Chrome channel
#   frame/install.sh chromium-xr-arm64.tar.xz   # our own Chromium build
#
# With no argument, downloads Google's arm64 Chrome from the most stable
# channel that has WebXR on Linux (157 or newer; see fetch-google-chrome.py).
# A channel name (stable, beta, unstable, canary) picks one instead, and a
# tarball from build/build.sh installs that build.
#
# Unpacks the browser into ~/chromium-xr, installs the `chromium-xr` launcher
# in ~/.local/bin, adds a desktop menu entry, and adds "Chromium XR" to the
# Steam library. Safe to rerun, e.g. to update to a newer version.
set -euo pipefail

usage() { echo "usage: $0 [auto|stable|beta|unstable|canary|chromium-xr-arm64.tar.xz]" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
source=${1:-auto}
[[ $# -le 1 ]] || usage
case $source in
  auto|stable|beta|unstable|canary) ;;
  *) [[ -f "$source" ]] || usage ;;
esac
[[ $(uname -m) == aarch64 ]] || { echo "This is for the Steam Frame (arm64); this machine is $(uname -m)." >&2; exit 1; }

dest=$HOME/chromium-xr
state=$HOME/.local/share/chromium-xr
launcher=$HOME/.local/bin/chromium-xr

rm -rf "$dest.new"
if [[ -f "$source" ]]; then
  echo "Unpacking $source into $dest"
  mkdir -p "$dest.new"
  tar -xJf "$source" -C "$dest.new"
  installed="Chromium build $(basename "$source")"
else
  installed=$(python3 "$here/fetch-google-chrome.py" "$source" "$dest.new")
fi
# Check the new browser runs at all before replacing the old one.
"$dest.new/chrome" --version
rm -rf "$dest"
mv "$dest.new" "$dest"

mkdir -p "$HOME/.local/bin" "$state" "$HOME/.local/share/applications"
echo "$installed" > "$state/installed"
install -m 755 "$here/chromium-xr" "$launcher"
# Keep the uninstaller, so removing works after the repo clone is deleted.
install -m 755 "$here/uninstall.sh" "$here/steam-shortcut.py" "$state/"

icon=''
# Our build ships product_logo_256.png; Chrome's channels name theirs with a
# suffix, such as product_logo_256_canary.png.
for candidate in "$dest"/product_logo_256*.png \
    /var/lib/flatpak/exports/share/icons/hicolor/256x256/apps/org.chromium.Chromium.png \
    "$HOME/.local/share/flatpak/exports/share/icons/hicolor/256x256/apps/org.chromium.Chromium.png"; do
  if [[ -f "$candidate" ]]; then icon=$candidate; break; fi
done

cat > "$HOME/.local/share/applications/chromium-xr.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Chromium XR
Comment=Web browser with WebXR (immersive VR) through SteamVR
Exec=$launcher %U
Icon=${icon:-web-browser}
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
EOF

echo "Adding Chromium XR to the Steam library"
if appid=$(python3 "$here/steam-shortcut.py" ensure "Chromium XR" "$launcher" "$HOME" "$icon" "$state/steam-appid"); then
  echo "Steam shortcut ready (app id $appid)"
else
  echo "Couldn't add the Steam shortcut automatically. In Desktop Mode, open Steam and use" >&2
  echo "Games > Add a Non-Steam Game to My Library, then pick Chromium XR." >&2
fi

echo "Installed $installed."
echo "Done. Open Chromium XR from your Steam library, or run: chromium-xr URL"
