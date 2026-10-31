"""Create/verify portable release SHA256SUMS without third-party dependencies."""
import argparse
import hashlib
from pathlib import Path


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def create(root):
    files = sorted(p for p in root.rglob('*') if p.is_file() and p.name != 'SHA256SUMS')
    if not files:
        raise ValueError('No artifacts to hash')
    (root / 'SHA256SUMS').write_text(''.join(
        f'{digest(p)}  {p.relative_to(root).as_posix()}\n' for p in files), encoding='utf-8')


def verify(root):
    root = root.resolve()
    seen = set()
    for line in (root / 'SHA256SUMS').read_text(encoding='utf-8').splitlines():
        expected, name = line.split('  ', 1)
        path = (root / name).resolve()
        if (len(expected) != 64 or any(c not in '0123456789abcdef' for c in expected)
                or not path.is_relative_to(root) or name in seen or path.is_symlink()
                or not path.is_file() or digest(path) != expected):
            raise ValueError('Unsafe path or checksum mismatch')
        seen.add(name)
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*')
              if p.is_file() and p.name != 'SHA256SUMS'}
    if not seen or seen != actual:
        raise ValueError('Manifest does not cover exactly the artifact set')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('command', choices=['create', 'verify'])
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    (create if args.command == 'create' else verify)(args.directory)
    print(f'Integrity {args.command}: PASS')
