#!/usr/bin/env python3
"""Download Google's arm64 Chrome and unpack it into a directory.

  fetch-google-chrome.py CHANNEL DEST   -> prints "google-chrome-<channel> <version>"

CHANNEL is stable, beta, unstable (Dev) or canary, or auto: the most stable
channel whose version has the Linux OpenXR code (MIN_VERSION or newer).
Downloads the .deb from Google's apt repository, checks its SHA-256 against
the repository index, and unpacks the browser directory into DEST, which must
not exist yet. Python stdlib only: no root, no ar or dpkg.
"""
import hashlib, io, os, shutil, sys, tarfile, urllib.request

REPO = 'https://dl.google.com/linux/chrome/deb/'
CHANNELS = ['stable', 'beta', 'unstable', 'canary']
# The first release with the upstream Linux OpenXR changes.
MIN_VERSION = '157.0.8088.0'


def log(msg):
    print(msg, file=sys.stderr)


def vkey(v):
    return tuple(int(x) for x in v.split('.'))


def packages():
    index = urllib.request.urlopen(REPO + 'dists/stable/main/binary-arm64/Packages', timeout=60)
    found = {}
    for stanza in index.read().decode().split('\n\n'):
        fields = dict(line.split(': ', 1) for line in stanza.splitlines()
                      if ': ' in line and not line.startswith(' '))
        if 'Package' in fields:
            fields['version'] = fields['Version'].split('-')[0]
            found[fields['Package']] = fields
    return found


def pick(channel, found):
    if channel != 'auto':
        pkg = found.get('google-chrome-' + channel)
        if not pkg:
            sys.exit(f'no google-chrome-{channel} for arm64 in Google\'s repository')
        if vkey(pkg['version']) < vkey(MIN_VERSION):
            log(f'Warning: Chrome {channel} is {pkg["version"]}; WebXR needs {MIN_VERSION} or newer.')
        return pkg
    for ch in CHANNELS:
        pkg = found.get('google-chrome-' + ch)
        if pkg and vkey(pkg['version']) >= vkey(MIN_VERSION):
            return pkg
    sys.exit(f'no Chrome channel for arm64 is at {MIN_VERSION} or newer yet')


def unpack(deb, dest):
    # A .deb is an ar archive; the files are in its data.tar.* member.
    if deb[:8] != b'!<arch>\n':
        sys.exit('not a .deb')
    pos, data = 8, None
    while pos + 60 <= len(deb):
        name = deb[pos:pos + 16].decode().strip().rstrip('/')
        size = int(deb[pos + 48:pos + 58])
        if name.startswith('data.tar'):
            data = deb[pos + 60:pos + 60 + size]
            break
        pos += 60 + size + size % 2
    if data is None:
        sys.exit('no data.tar in the .deb')

    # Keep only the browser directory, opt/google/chrome[-<channel>]. Unpack
    # into a temporary directory, so an interrupted run leaves no DEST.
    tmp = dest + '.partial'
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
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


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in CHANNELS + ['auto']:
        sys.exit(f'usage: {sys.argv[0]} auto|{"|".join(CHANNELS)} DEST')
    channel, dest = sys.argv[1:]
    if os.path.exists(dest):
        sys.exit(f'{dest} already exists')
    pkg = pick(channel, packages())
    log(f'Downloading {pkg["Package"]} {pkg["version"]} ({int(pkg["Size"]) >> 20} MB)')
    deb = urllib.request.urlopen(REPO + pkg['Filename'], timeout=60).read()
    if hashlib.sha256(deb).hexdigest() != pkg['SHA256']:
        sys.exit('download is corrupt: SHA-256 does not match the repository index')
    unpack(deb, dest)
    print(pkg['Package'], pkg['version'])


if __name__ == '__main__':
    main()
