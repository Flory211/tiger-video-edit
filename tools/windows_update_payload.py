"""Validate an application-only Windows update; never print private values."""
import argparse
import hashlib
import json
from pathlib import Path

BASE_PATHS = {
    'tiger_video_edit.exe', 'data/app.so', 'data/icudtl.dat',
    'data/flutter_assets/AssetManifest.bin', 'data/flutter_assets/FontManifest.json',
    'data/flutter_assets/NativeAssetsManifest.json', 'data/flutter_assets/NOTICES.Z',
    'data/flutter_assets/fonts/MaterialIcons-Regular.otf',
    'data/flutter_assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
    'data/flutter_assets/packages/media_kit/assets/web/hls1.4.10.js',
    'data/flutter_assets/shaders/ink_sparkle.frag',
    'data/flutter_assets/shaders/stretch_effect.frag',
}


def validate(root, *, blocked_values=(), base=None):
    required = {'tiger_video_edit.exe', 'data/app.so', 'data/icudtl.dat',
                'data/flutter_assets/NOTICES.Z'}
    result = {}
    for file in root.rglob('*'):
        if file.is_symlink():
            raise ValueError('Symlinks are not update payload files')
        if not file.is_file():
            continue
        name = file.relative_to(root).as_posix()
        if name not in BASE_PATHS:
            raise ValueError(f'Path is not part of the supported base installation: {name}')
        if name != 'tiger_video_edit.exe' and not name.startswith('data/'):
            raise ValueError(f'Not an application update file: {name}')
        if file.suffix.lower() in {'.dll', '.exe', '.so'} and name not in {
            'tiger_video_edit.exe', 'data/app.so'
        }:
            raise ValueError(f'Unexpected executable in update: {name}')
        if base is not None and not (base / name).is_file():
            raise ValueError(f'New path not owned by the existing uninstaller: {name}')
        data = file.read_bytes()
        for value in blocked_values:
            if value and any(value.encode(encoding) in data for encoding in ('utf-8', 'utf-16le')):
                raise ValueError(f'Private build value in update file: {name}')
        result[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    if not required.issubset(result):
        raise ValueError('Missing application update files')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--base', type=Path)
    parser.add_argument('--private-config', type=Path)
    parser.add_argument('--manifest', type=Path, required=True)
    args = parser.parse_args()
    blocked = []
    if args.private_config and args.private_config.is_file():
        blocked.append(json.loads(args.private_config.read_text(encoding='utf-8-sig'))['clientId'])
    files = validate(args.directory, blocked_values=blocked, base=args.base)
    args.manifest.write_text(json.dumps(files, indent=2) + '\n', encoding='utf-8')
    print(f'Application-only update payload: PASS ({len(files)} files)')
