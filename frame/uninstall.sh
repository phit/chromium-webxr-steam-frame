#!/bin/bash
# Run on the Steam Frame to remove what frame/install.sh added: the build,
# the launcher, the menu entry and the Steam shortcut. Your Chromium XR
# profile (~/.config/chromium-xr: settings, logins, history) is kept unless
# you pass --remove-profile.
#
# install.sh keeps a copy of this script in ~/.local/share/chromium-xr, so it
# works even after the repo clone is deleted.
set -euo pipefail

remove_profile=false
[[ $# -le 1 ]] || { echo "usage: $0 [--remove-profile]" >&2; exit 2; }
case "${1:-}" in
  '') ;;
  --remove-profile) remove_profile=true ;;
  *) echo "usage: $0 [--remove-profile]" >&2; exit 2 ;;
esac

here=$(cd "$(dirname "$0")" && pwd)
state=$HOME/.local/share/chromium-xr

python3 "$here/steam-shortcut.py" remove "Chromium XR" "$state/steam-appid" ||
  echo "Couldn't remove the Steam shortcut; delete Chromium XR from the library by hand." >&2
rm -rf "$HOME/chromium-xr" "$state"
rm -f "$HOME/.local/bin/chromium-xr" "$HOME/.local/share/applications/chromium-xr.desktop"
if $remove_profile; then
  rm -rf "$HOME/.config/chromium-xr"
  echo "Chromium XR and its profile removed."
else
  echo "Chromium XR removed. Your profile is still in ~/.config/chromium-xr."
fi
