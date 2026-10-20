#!/usr/bin/env python3
"""Reject library data and unexpected app payloads before uploading a release."""
import argparse
from pathlib import Path, PurePosixPath
import zipfile

DATA_DIRS = {'secure-data', 'public-pdfs', 'public-texts', 'vault-spaces', 'spaces', 'books', 'backups', 'logs'}
DATA_FILES = {'catalog.json', 'progress.json', 'preferences.json', 'vault.json', 'vault.key', 'appearance-icon.png', 'startup.log', 'smoke-ok.txt'}
ICONS = {'fish', 'book', 'night', 'leaf', 'coffee', 'star', 'pencil', 'music', 'sunrise', 'cloud'}


def check_name(name):
    p = PurePosixPath(name)
    if p.is_absolute() or '..' in p.parts or '\\' in name:
        raise ValueError('Unsafe archive path')
    if set(p.parts) & DATA_DIRS or p.name in DATA_FILES or p.suffix.lower() in {'.pdf', '.epub', '.book', '.progress', '.sqlite', '.db', '.log'}:
        raise ValueError('Library or personal-data file found')


def allowed_mac(name):
    check_name(name)
    if name in {'Contents/Info.plist', 'Contents/MacOS/LocalLibrary', 'Contents/CodeResources'}:
        return True
    if name.startswith(('Contents/Frameworks/Sparkle.framework/', 'Contents/_CodeSignature/')):
        return True
    prefix = 'Contents/Resources/'
    if not name.startswith(prefix):
        return False
    resource = name[len(prefix):]
    return resource in {'index.html', 'settings.js', 'settings.css', 'reader-appearance.js', 'reader-appearance.css', 'rename-helper.sh', 'AppIcon.icns', 'web-plugins.js', 'community-plugins.json', 'fanqie-font-map.json'} or resource.startswith('Licenses/') or resource in {f'Icons/{icon}.png' for icon in ICONS}


def allowed_windows(name):
    check_name(name)
    prefix = 'resources/app/'
    if name.startswith(prefix):
        app = name[len(prefix):]
        if app.startswith(('node_modules/', 'LICENSES/')):
            return True
        return app in {'main.js', 'preload.js', 'reading-appearance.js', 'epub.js', 'import-plugins.js', 'web-import.js', 'assets/web-plugins.js', 'assets/community-plugins.json', 'assets/fanqie-font-map.json', 'library.js', 'vault.js', 'package.json', 'package-lock.json', 'README.md',
                       'scripts/prepare-assets.js', 'scripts/copy-package-lock.js', 'scripts/smoke.ps1',
                       'assets/index.html', 'assets/settings.js', 'assets/settings.css', 'assets/reader-appearance.js', 'assets/reader-appearance.css', 'assets/pdf.html', 'assets/app.ico'} or app in {f'assets/Icons/{icon}.png' for icon in ICONS}
    if '/' not in name:
        return name in {'FishTouching Reader.exe', 'LICENSE', 'LICENSES.chromium.html', 'version'} or Path(name).suffix in {'.dll', '.pak', '.bin', '.dat', '.json'}
    return name.startswith('locales/') and name.endswith('.pak') or name == 'resources/default_app.asar'


def check_zip(archive):
    mac = 'macos' in archive.name.lower()
    count = 0
    with zipfile.ZipFile(archive) as z:
        for entry in z.infolist():
            if entry.is_dir():
                continue
            name = entry.filename
            if name.startswith('__MACOSX/'):
                name = name[len('__MACOSX/'):]
                parts = name.split('/')
                parts[-1] = parts[-1].removeprefix('._')
                name = '/'.join(parts)
                # ditto may store Finder metadata for the root app/directory.
                if name == 'FishTouching Reader.app' or any(item.filename == name+'/' for item in z.infolist()):
                    continue
            if mac:
                prefix = 'FishTouching Reader.app/'
                allowed = name.startswith(prefix) and allowed_mac(name[len(prefix):])
            else:
                allowed = allowed_windows(name)
            if not allowed:
                raise ValueError(f'Unexpected release entry: {name}')
            count += 1
    print(f'Privacy check passed: {archive.name} ({count} app/runtime/license entries; no book files)')


def check_app(app):
    count = 0
    for file in app.rglob('*'):
        if file.is_dir():
            continue
        if not allowed_mac(file.relative_to(app).as_posix()):
            raise ValueError(f'Unexpected app entry: {file.relative_to(app)}')
        count += 1
    print(f'App privacy check passed: {count} entries')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path)
    parser.add_argument('archives', nargs='*', type=Path)
    args = parser.parse_args()
    if not args.app and not args.archives:
        parser.error('Provide an app or ZIP archive')
    if args.app:
        check_app(args.app)
    for archive in args.archives:
        check_zip(archive)
