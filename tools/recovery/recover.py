#!/usr/bin/env python3
"""Repeatable local SOCOM II recovery: ISO -> native files -> PNG/OBJ/JSON."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

from extract_disc import extract, write_json

DECODER_URL = 'https://github.com/Scotho/socom-unzipped.git'
DECODER_COMMIT = 'a519c9bf0bdf94f5a7ba39037c942b970bfa1031'
HERE = Path(__file__).resolve().parent


def prepare_decoder(out):
    checkout = out / 'research/socom-unzipped'
    if not (checkout / '.git').is_dir():
        checkout.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['git', 'clone', '--no-checkout', DECODER_URL, str(checkout)], check=True)
        subprocess.run(['git', '-C', str(checkout), 'checkout', '--detach', DECODER_COMMIT], check=True)
    commit = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
    if commit != DECODER_COMMIT:
        raise ValueError(f'Decoder checkout is {commit}, expected {DECODER_COMMIT}; preserve it and use a fresh output directory')
    web = checkout / 'web'
    loader = web / 'node_modules/tsx/dist/loader.mjs'
    if not loader.exists():
        subprocess.run(['npm', 'ci', '--ignore-scripts', '--no-audit', '--no-fund'], cwd=web, check=True)
    # Some npm lockfiles omit optional binaries for platforms other than the author's.
    # Install exactly the binary version required by the resolved local esbuild package.
    platform = subprocess.check_output(['node', '-p', 'process.platform+"-"+process.arch'], text=True).strip()
    version = json.loads((web / 'node_modules/esbuild/package.json').read_text())['version']
    if not (web / f'node_modules/@esbuild/{platform}/package.json').exists():
        subprocess.run(['npm', 'install', '--no-save', '--ignore-scripts', '--no-audit', '--no-fund',
                        f'@esbuild/{platform}@{version}'], cwd=web, check=True)
    base = web / 'redotcom'
    paths = {f'@s2u/{n}': [str(base / f'packages/{n}/src/index.ts')]
             for n in ('archive', 'gs', 'mesh', 'scene', 'sound')}
    paths['@recovery/png'] = [str(base / 'tools/png.ts')]
    config = out / 'reports/decoder-tsconfig.json'
    write_json(config, {'compilerOptions': {'target': 'ES2022', 'module': 'ESNext',
               'moduleResolution': 'Bundler', 'baseUrl': str(base), 'paths': paths}})
    write_json(out / 'reports/decoder-provenance.json', {'repository': DECODER_URL,
               'commit': commit, 'license': 'GPL-3.0', 'esbuild': version,
               'adapter': str(HERE / 'export_assets.ts')})
    return loader, config


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('iso', type=Path)
    ap.add_argument('--out', type=Path, default=HERE.parents[1] / 'previous/recovery')
    ap.add_argument('--convert-only', action='store_true', help='Use the previously verified disc extraction')
    args = ap.parse_args()
    out = args.out.resolve()
    if not args.convert_only:
        extract(args.iso.resolve(), out)
    elif not (out / 'reports/libraries.json').exists():
        ap.error('--convert-only needs an existing extraction')
    loader, config = prepare_decoder(out)
    env = dict(os.environ, TSX_TSCONFIG_PATH=str(config))
    subprocess.run(['node', '--max-old-space-size=6144', '--import', str(loader),
                    str(HERE / 'export_assets.ts'), str(out)], env=env, check=True)
    print(f'Assets: {out / "converted"}')
    print(f'Coverage and limitations: {out / "reports/conversion-summary.json"}')


if __name__ == '__main__':
    main()
