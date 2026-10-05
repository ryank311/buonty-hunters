#!/usr/bin/env python3
"""Preserve an ISO tree, unpack SOCOM II ZDBs, and inventory every file.

Python standard library + bsdtar. Does not modify the ISO or import assets into Godot.
ZDB 0xfc layout independently checked against this disc and SOCOM archive readers.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import struct
import subprocess


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def safe_path(name):
    p = PurePosixPath(name.replace('\\', '/'))
    if p.is_absolute() or any(x in ('..', '') or ':' in x for x in p.parts):
        raise ValueError(f'Unsafe archive path: {name!r}')
    return Path(*p.parts)


def zdb_entries(data):
    if len(data) < 160 or struct.unpack_from('<I', data)[0] != 0xfc:
        raise ValueError('Unsupported ZDB header (expected 0xfc)')
    count = struct.unpack_from('<I', data, 0x98)[0]
    if count > (len(data) - 160) // 76:
        raise ValueError('ZDB entry count exceeds file bounds')
    pos, names = 0xa0, set()
    for index in range(count):
        if pos + 76 > len(data):
            raise ValueError('Truncated ZDB directory')
        stride = struct.unpack_from('<I', data, pos)[0]
        raw_name = data[pos + 4:pos + 68]
        if b'\0' not in raw_name:
            raise ValueError('Unterminated ZDB filename')
        name = raw_name.split(b'\0')[0].decode('ascii')
        target = safe_path(name)
        offset, size = struct.unpack_from('<II', data, pos + 68)
        if stride < 76 or pos + stride > len(data) or offset + size > len(data):
            raise ValueError(f'Invalid ZDB bounds: {name}')
        if target.as_posix().lower() in names:
            raise ValueError(f'Duplicate ZDB path: {name}')
        names.add(target.as_posix().lower())
        yield dict(index=index, name=target.as_posix(), offset=offset, size=size)
        pos += stride


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


def iso_files(iso):
    """Read this PS2 disc's ISO9660 extents independently of bsdtar."""
    with iso.open('rb') as f:
        f.seek(16 * 2048)
        pvd = f.read(2048)
        if pvd[:7] != b'\x01CD001\x01':
            raise ValueError('Expected ISO9660 primary volume descriptor')
        seen = set()

        def walk(record, parent):
            sector = struct.unpack_from('<I', record, 2)[0]
            size = struct.unpack_from('<I', record, 10)[0]
            if record[25] & 2:
                if sector in seen:
                    raise ValueError('Cyclic ISO directory')
                seen.add(sector)
                f.seek(sector * 2048)
                directory = f.read(size)
                at = 0
                while at < size:
                    length = directory[at]
                    if not length:
                        at = (at // 2048 + 1) * 2048
                        continue
                    child = directory[at:at + length]
                    name = child[33:33 + child[32]]
                    if name not in (b'\x00', b'\x01'):
                        yield from walk(child, parent / safe_path(name.decode('ascii').split(';')[0].rstrip('.')))
                    at += length
            else:
                if record[25] & 128:
                    raise ValueError('Multi-extent ISO file unsupported')
                yield parent, sector * 2048, size
        yield from walk(pvd[156:156 + pvd[156]], Path())


def extract(iso, out):
    out.mkdir(parents=True, exist_ok=True)
    (out / '.gdignore').touch()
    disc = out / 'disc'
    disc.mkdir(exist_ok=True)
    listed = subprocess.check_output(['bsdtar', '-tf', str(iso)], text=True).splitlines()
    for name in listed:
        if name != '.':
            safe_path(name)
    # Reruns verify existing files; never silently overwrite a changed recovery tree.
    marker = out / 'reports/disc-manifest.json'
    iso_hash = sha256(iso)
    if marker.exists():
        prior = json.loads(marker.read_text())
        if prior['iso_sha256'] != iso_hash:
            raise ValueError('Output belongs to another ISO; use a fresh output directory')
        for entry in prior['files']:
            p = out / entry['path']
            if not p.is_file() or sha256(p) != entry['sha256']:
                raise ValueError(f'Preserved disc file changed: {p}')
    elif not any(disc.iterdir()):
        subprocess.run(['bsdtar', '-xf', str(iso), '-C', str(disc)], check=True)
    # Compare every extracted byte with its ISO9660 extent using an independent reader.
    extents = list(iso_files(iso))
    with iso.open('rb') as source:
        for name, offset, size in extents:
            target = disc / name
            if not target.is_file() or target.stat().st_size != size:
                raise ValueError(f'Missing or wrong-sized ISO file: {name}')
            source.seek(offset)
            remaining = size
            with target.open('rb') as recovered:
                while remaining:
                    n = min(remaining, 1024 * 1024)
                    if source.read(n) != recovered.read(n):
                        raise ValueError(f'ISO byte comparison failed: {name}')
                    remaining -= n
    files = []
    for p in sorted(disc.rglob('*')):
        if not p.is_file():
            continue
        files.append(dict(path=p.relative_to(out).as_posix(), size=p.stat().st_size,
                          sha256=sha256(p)))
    listed_set = {name.lstrip('./') for name in listed if name != '.'}
    missing = listed_set - {p.relative_to(disc).as_posix() for p in disc.rglob('*')}
    if missing:
        raise ValueError(f'Missing disc entries: {sorted(missing)}')
    write_json(marker, dict(iso=str(iso.resolve()), iso_size=iso.stat().st_size,
                           iso_sha256=iso_hash, files=files))
    members, failures = [], []
    for p in sorted(disc.rglob('*.ZDB')):
        data = p.read_bytes()
        context = p.stem
        try:
            entries = list(zdb_entries(data))
            for entry in entries:
                target = out / 'archives' / context / safe_path(entry['name'])
                target.parent.mkdir(parents=True, exist_ok=True)
                payload = data[entry['offset']:entry['offset'] + entry['size']]
                if target.exists() and target.read_bytes() != payload:
                    raise ValueError(f'Existing extracted member differs: {target}')
                if not target.exists():
                    target.write_bytes(payload)
                members.append(dict(entry, path=target.relative_to(out).as_posix(),
                                    context=context, archive=p.relative_to(out).as_posix(),
                                    sha256=hashlib.sha256(payload).hexdigest()))
            print(f'{context}: {len(entries)} members', flush=True)
        except (ValueError, UnicodeError) as error:
            failures.append(dict(path=str(p), error=str(error)))
    libraries = [dict(x, context='disc', name=x['path'].removeprefix('disc/'))
                 for x in files if Path(x['path']).suffix in ('.ZED', '.ZAR')]
    libraries += [x for x in members if Path(x['path']).suffix in ('.ZED', '.ZAR')]
    write_json(out / 'reports/members.json', members)
    write_json(out / 'reports/libraries.json', libraries)
    write_json(out / 'reports/extraction-errors.json', failures)
    print(f'{len(files)} disc files; {len(members)} archive members; {len(libraries)} library occurrences; {len(failures)} errors')
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('iso', type=Path)
    ap.add_argument('--out', type=Path, default=Path('previous/recovery'))
    a = ap.parse_args()
    extract(a.iso, a.out)
