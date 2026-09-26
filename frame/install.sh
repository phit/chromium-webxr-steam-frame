#!/bin/bash
# Run on the Steam Frame (Desktop Mode terminal or SSH), as the normal user:
#
#   frame/install.sh chromium-xr-arm64.tar.xz
#
# Unpacks the build into ~/chromium-xr, installs the `chromium-xr` launcher
# in ~/.local/bin, adds a desktop menu entry, and adds "Chromium XR" to the
# Steam library. Safe to rerun, e.g. to install a newer build.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tarball=${1:-}
[[ -n "$tarball" && -f "$tarball" ]] || { echo "usage: $0 chromium-xr-arm64.tar.xz" >&2; exit 2; }
[[ $(uname -m) == aarch64 ]] || { echo "This is for the Steam Frame (arm64); this machine is $(uname -m)." >&2; exit 1; }

dest=$HOME/chromium-xr
state=$HOME/.local/share/chromium-xr
launcher=$HOME/.local/bin/chromium-xr

echo "Unpacking into $dest"
rm -rf "$dest.new"
mkdir -p "$dest.new"
tar -xJf "$tarball" -C "$dest.new"
# Check the new build runs at all before replacing the old one.
"$dest.new/chrome" --version
rm -rf "$dest"
mv "$dest.new" "$dest"

mkdir -p "$HOME/.local/bin" "$state" "$HOME/.local/share/applications"
install -m 755 "$here/chromium-xr" "$launcher"
# Keep the uninstaller, so removing works after the repo clone is deleted.
install -m 755 "$here/uninstall.sh" "$here/steam-shortcut.py" "$state/"

icon=''
for candidate in "$dest/product_logo_256.png" \
    /var/lib/flatpak/exports/share/icons/hicolor/256x256/apps/org.chromium.Chromium.png \
    "$HOME/.local/share/flatpak/exports/share/icons/hicolor/256x256/apps/org.chromium.Chromium.png"; do
  if [[ -f "$candidate" ]]; then icon=$candidate; break; fi
done

cat > "$HOME/.local/share/applications/chromium-xr.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Chromium XR
Comment=Chromium with WebXR (immersive VR) through SteamVR
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

echo "Done. Open Chromium XR from your Steam library, or run: chromium-xr URL"
