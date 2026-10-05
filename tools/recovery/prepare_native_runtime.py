#!/usr/bin/env python3
"""Stage unretargeted archive tracks, rig calibrations and independent pose checks."""
import gzip
import json
from pathlib import Path

import numpy as np

from prepare_pilot import RECOVERY, ROOT, SCALE, frame_worlds


def read(path):
    return json.loads(gzip.decompress((RECOVERY / path).read_bytes()))


def matrix(value):
    m = np.asarray(value, dtype=float).reshape(4, 4).T.copy()
    m[:3, 3] *= SCALE
    return m.T.flatten().tolist()


def main():
    catalogue = json.loads((ROOT / 'resources/recovered/catalogue.json').read_text())
    assets = json.loads((RECOVERY / 'reports/assets.json').read_text())
    sources = {a['path']: a for a in assets if a['type'] == 'character'}
    rigs, native, checks = {}, [], []
    clips = {e['name']: read(e['source']) for e in catalogue['motions']}
    selected = ['seal_stand', 'seal_walk', 'seal_run', 'seal_crouch',
                'seal_prone_crawl', 'seal_reload', 'civ_walk']
    for entry in catalogue['characters']:
        skin = read(sources[entry['source']]['skin'])
        rigs[entry['path']] = {
            'names': [p['name'] for p in skin['parts']],
            'parents': [p['parent'] for p in skin['parts']],
            'locals': [matrix(p['bindLocal']) for p in skin['parts']],
            'worlds': [matrix(v) for v in skin['bindWorld']],
        }
        # Compare the skinning transforms in Godot with archive bone-local data,
        # independently of the Blender bone-axis calibration used at runtime.
        inverse_bind = [np.linalg.inv(np.array(v).reshape(4, 4).T) for v in skin['bindWorld']]
        for name in selected:
            clip = clips[name]
            frame = clip['frameCount'] // 2
            worlds = frame_worlds(skin, clip, frame)
            deform = []
            for posed, inverse in zip(worlds, inverse_bind):
                value = posed @ inverse
                value[:3, 3] *= SCALE
                deform.append(value.T.flatten().tolist())
            checks.append({'model': entry['path'], 'clip': name, 'time': frame / 30,
                           'names': rigs[entry['path']]['names'], 'deform': deform})
    scuba = 'res://art/models/recovered_char_seal_a_scuba.glb'
    rigs['res://art/models/recovered_seal.glb'] = rigs[scuba]
    # The pilot's different Blender bone axes caused the original regression.
    checks.extend([{**c, 'model': 'res://art/models/recovered_seal.glb'}
                   for c in list(checks) if c['model'] == scuba])
    for entry in catalogue['motions']:
        clip = clips[entry['name']]
        native.append({'name': entry['name'], 'duration': clip['duration'],
                       'frames': clip['frameCount'], 'parts': clip['parts']})
    output = RECOVERY / 'staging/characters/native_runtime.json'
    output.write_text(json.dumps({'scale': SCALE, 'rigs': rigs, 'motions': native}, separators=(',', ':')) + '\n')
    fixture = ROOT / 'tests/fixtures/recovered_fidelity.json'
    fixture.parent.mkdir(parents=True, exist_ok=True)
    # Keep representative independent checks in the repo. Audit every model now.
    representatives = {scuba, 'res://art/models/recovered_seal.glb',
                       'res://art/models/recovered_char_seal_a_cqb.glb',
                       'res://art/models/recovered_char_thai_biologist01.glb',
                       'res://art/models/recovered_char_afg_taliban03_mp.glb'}
    fixture.write_text(json.dumps([c for c in checks if c['model'] in representatives], separators=(',', ':')) + '\n')
    (RECOVERY / 'staging/characters/all_fidelity.json').write_text(json.dumps(checks, separators=(',', ':')) + '\n')
    print(f'{len(rigs)} rigs, {len(native)} native clips, {len(checks)} independent pose samples')


if __name__ == '__main__':
    main()
