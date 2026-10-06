#!/bin/bash
# Try Google's own arm64 Chrome in place of our build, to see whether WebXR
# works with it on the Frame. Since 157.0.8088.0 (Canary), Chrome for arm64
# Linux contains the OpenXR code; it lacks our sandbox patch, which the
# launcher's --disable-seccomp-filter-sandbox makes unnecessary.
#
#   frame/try-google-chrome.sh [canary|unstable|beta|stable] [URL...]
#
# Downloads google-chrome-<channel> (default canary) from Google's apt
# repository, checks it, unpacks it into ~/chromium-xr-google/<version>, and
# starts it through the chromium-xr launcher, with the same flags, but its own
# profile (~/.config/chromium-xr-google) so your Chromium XR profile is left
# alone. No root needed. Opens the WebXR Samples unless you give URLs.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
channel=canary
case ${1:-} in
  canary|unstable|beta|stable) channel=$1; shift ;;
esac
base=$HOME/chromium-xr-google

dir=$(python3 - "$channel" "$base" <<'EOF'
import hashlib, io, os, sys, tarfile, urllib.request

channel, base = sys.argv[1:]
repo = 'https://dl.google.com/linux/chrome/deb/'
log = lambda msg: print(msg, file=sys.stderr)

index = urllib.request.urlopen(repo + 'dists/stable/main/binary-arm64/Packages').read().decode()
for stanza in index.split('\n\n'):
    fields = dict(line.split(': ', 1) for line in stanza.splitlines()
                  if ': ' in line and not line.startswith(' '))
    if fields.get('Package') == 'google-chrome-' + channel:
        break
else:
    sys.exit(f'no google-chrome-{channel} for arm64 in Google\'s repository')

version = fields['Version'].split('-')[0]
dest = os.path.join(base, version)
if os.access(os.path.join(dest, 'chrome'), os.X_OK):
    log(f'Chrome {channel} {version} is already in {dest}')
    print(dest)
    sys.exit()

log(f'Downloading Chrome {channel} {version} ({int(fields["Size"]) >> 20} MB)')
deb = urllib.request.urlopen(repo + fields['Filename']).read()
if hashlib.sha256(deb).hexdigest() != fields['SHA256']:
    sys.exit('download is corrupt: SHA-256 does not match the repository index')

# A .deb is an ar archive; the files are in its data.tar.* member.
assert deb[:8] == b'!<arch>\n', 'not a .deb'
pos, data = 8, None
while pos < len(deb):
    name = deb[pos:pos + 16].decode().strip().rstrip('/')
    size = int(deb[pos + 48:pos + 58])
    if name.startswith('data.tar'):
        data = deb[pos + 60:pos + 60 + size]
        break
    pos += 60 + size + size % 2
if data is None:
    sys.exit('no data.tar in the .deb')

# Keep only the browser directory (opt/google/chrome-<channel>), unpacked into
# a temporary directory first so an interrupted run leaves nothing half done.
tmp = dest + '.partial'
os.makedirs(tmp, exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(data)) as tar:
    members = []
    for m in tar.getmembers():
        parts = m.name.lstrip('./').split('/')
        if parts[:2] == ['opt', 'google'] and len(parts) > 3:
            m.name = '/'.join(parts[3:])
            members.append(m)
    # The 'tar' filter refuses paths outside tmp and drops setuid bits.
    kwargs = {'filter': 'tar'} if hasattr(tarfile, 'tar_filter') else {}
    tar.extractall(tmp, members=members, **kwargs)
os.rename(tmp, dest)
log(f'Unpacked into {dest}')
print(dest)
EOF
)

echo "Starting Chrome from $dir. In VR, check SteamVR's log for VRApplication_OpenXRScene:" >&2
echo "  grep -i openxr ~/.local/share/Steam/logs/vrserver.txt | tail" >&2
CHROMIUM_XR_HOME=$dir CHROMIUM_XR_PROFILE=$HOME/.config/chromium-xr-google \
  exec "$here/chromium-xr" --enable-logging=stderr \
  "${@:-https://immersive-web.github.io/webxr-samples/}"
