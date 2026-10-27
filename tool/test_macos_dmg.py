#!/usr/bin/env python3
"""Verify the real release DMG and copying its app off the mounted volume."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def verify_app(app):
    subprocess.run(
        ['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    signature = subprocess.run(
        ['codesign', '--display', '--verbose=4', str(app)],
        check=True, capture_output=True, text=True)
    if 'Signature=adhoc' not in signature.stderr.splitlines():
        raise SystemExit(f'Expected ad hoc signature: {app}')


def main():
    if sys.platform != 'darwin':
        raise SystemExit('DMG integration verification requires macOS.')
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python3 tool/test_macos_dmg.py <release.dmg>')
    image = Path(sys.argv[1]).resolve(strict=True)
    subprocess.run(['hdiutil', 'verify', str(image)], check=True)
    with tempfile.TemporaryDirectory(prefix='shiping-dmg-test-') as folder:
        root = Path(folder)
        mount = root / 'mounted'
        mount.mkdir()
        subprocess.run([
            'hdiutil', 'attach', '-readonly', '-nobrowse',
            '-mountpoint', str(mount), str(image),
        ], check=True)
        try:
            shortcut = mount / '应用程序'
            if not shortcut.is_symlink() or os.readlink(shortcut) != '/Applications':
                raise SystemExit('DMG must contain an 应用程序 link to /Applications.')
            info = (mount / 'BUILD-INFO.txt').read_text()
            for expected in ['ad hoc', '未公证', '未 stapling', '拖到旁边']:
                if expected not in info:
                    raise SystemExit(f'Missing build/installation notice: {expected}')
            verify_app(mount / '拾屏.app')
            # Exercise the same bundle copy used by drag installation without
            # modifying the user's real /Applications directory.
            installed = root / 'installed' / '拾屏.app'
            installed.parent.mkdir()
            subprocess.run(['ditto', str(mount / '拾屏.app'), str(installed)], check=True)
            verify_app(installed)
        finally:
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True)
    print('DMG mount, Applications link, notices and copied app signatures passed.')


if __name__ == '__main__':
    main()
