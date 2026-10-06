#!/bin/bash
# Run on the Steam Frame to remove what frame/install.sh added: Chrome,
# the launcher, the menu entry and the Steam shortcut. Your Chrome XR
# profile (~/.config/chrome-xr: settings, logins, history) is kept unless
# you pass --remove-profile.
#
# install.sh keeps a copy of this script in ~/.local/share/chrome-xr, so it
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
state=$HOME/.local/share/chrome-xr

python3 "$here/steam-shortcut.py" remove "Chrome XR" "$state/steam-appid" ||
  echo "Couldn't remove the Steam shortcut; delete Chrome XR from the library by hand." >&2
rm -rf "$HOME/chrome-xr" "$state"
rm -f "$HOME/.local/bin/chrome-xr" "$HOME/.local/share/applications/chrome-xr.desktop"
if $remove_profile; then
  rm -rf "$HOME/.config/chrome-xr"
  echo "Chrome XR and its profile removed."
else
  echo "Chrome XR removed. Your profile is still in ~/.config/chrome-xr."
fi
