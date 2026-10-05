#!/usr/bin/env python3
"""Deduplicate staged native guns, copy textures and prepare bounded Blender calls."""
import hashlib
import json
from pathlib import Path
import re

import numpy as np

from prepare_pilot import ROOT, RECOVERY, materials

STAGING = RECOVERY / 'staging/weapons'
PISTOLS = {'M11_p228', 'SP10_gyuraz', 'a_mark23', 'a_mark23sd', 'baretta_m9',
           'desert_eagle', 'fiveseven', 'glock18', 'hkp9s', 'sig226'}
LAUNCHERS = {'AT4', 'RPG7', 'm79', 'mglmk1'}
SHOTGUNS = {'jackhammer', 'remington870', 'spas12'}
SNIPERS = {'Dragunov', 'barretm82A1', 'mcmillanM87', 'remington700', 'stoner_sr25'}
SMGS = {'fnp90', 'hk5k', 'mp5', 'mp5sd', 'steyr_aug9', 'uzi'}


def category(name):
    for label, names in [('Pistols', PISTOLS), ('Launchers', LAUNCHERS), ('Shotguns', SHOTGUNS),
                         ('Sniper rifles', SNIPERS), ('Submachine guns', SMGS),
                         ('Machine guns', {'m60e', 'stoner_m63a'})]:
        if name in names:
            return label
    return 'Assault rifles'


def main():
    records = json.loads((STAGING / 'native.json').read_text())
    reader = next((RECOVERY / 'native/scripts/disc').glob('ZWEAPON*/*.json'))
    rdr = json.loads(reader.read_text())
    names = {}
    for row in rdr[rdr.index('ZWEAPON') + 1]:
        if 'ModelName' in row and 'InternalName' in row:
            names.setdefault(row[row.index('ModelName') + 1][0].lower(), row[row.index('InternalName') + 1][0])
    mat_cache, groups, geometry_cache = {}, {}, {}
    for record in records:
        asset = record['source']
        path = RECOVERY / asset['path']
        if str(path) not in mat_cache:
            mat_cache[str(path)] = {m['name'].lower(): m for m in materials(path, 'recovered_weapons').values()}
        mats = mat_cache[str(path)]
        raw_key = hashlib.sha256(json.dumps([record['meshes'], record['firepoint'],
                    [mats[m['texture'].lower()]['sha256'] for m in record['meshes']]]).encode()).hexdigest()
        if raw_key in geometry_cache:
            key = (asset['name'], geometry_cache[raw_key])
            if key in groups:
                groups[key]['occurrences'].append(asset)
                continue
        # GPU packet padding/order differs between maps. Compare actual textured triangles.
        triangles = {}
        for mesh in record['meshes']:
            material = mats[mesh['texture'].lower()]
            v = np.array(mesh['positions'])
            uv = np.array(mesh['uv']).reshape(-1, 2)
            for ids in np.array(mesh['indices']).reshape(-1, 3):
                points = v[ids]
                if np.linalg.norm(np.cross(points[1] - points[0], points[2] - points[0])) < 1e-7:
                    continue
                values = tuple(tuple(round(float(x), 6) for x in p) for p in np.c_[points, uv[ids]])
                signature = (material['sha256'], tuple(sorted(values)))
                triangles.setdefault(signature, (material, values))
        signature = hashlib.sha256(json.dumps([sorted(triangles), record['firepoint']], separators=(',', ':')).encode()).hexdigest()
        geometry_cache[raw_key] = signature
        key = (asset['name'], signature)
        if key in groups:
            groups[key]['occurrences'].append(asset)
            continue
        groups[key] = dict(record=record, triangles=triangles, occurrences=[asset], sha256=signature)
    entries, builds = [], []
    counts = {}
    for (source_name, _), group in sorted(groups.items(), key=lambda item: (item[0][0], -len(item[1]['occurrences']), item[0][1])):
        base_id = re.sub('[^a-z0-9_]+', '_', source_name.lower())
        counts[base_id] = counts.get(base_id, 0) + 1
        ident = base_id if counts[base_id] == 1 else base_id + '_' + group['sha256'][:8]
        asset_name = 'recovered_gun_' + ident
        meshes, used = {}, {}
        for material, tri in group['triangles'].values():
            key = material['sha256'][:12]
            used[key] = material
            mesh = meshes.setdefault(key, dict(name='Gun_' + key, material=key, vertices=[], uv=[], faces=[]))
            base = len(mesh['vertices'])
            # Preserve native attachment origin; +X source -> +Y Blender -> -Z Godot.
            mesh['vertices'].extend([[p[2] * .1, p[0] * .1, p[1] * .1] for p in tri])
            mesh['uv'].extend([[p[3], 1 - p[4]] for p in tri])
            mesh['faces'].append([base, base + 1, base + 2])
        verts = np.array([v for m in meshes.values() for v in m['vertices']])
        low, high = verts.min(0), verts.max(0)
        point = group['record']['firepoint']
        label = names.get(source_name.lower(), source_name)
        if counts[base_id] > 1:
            label += ' [' + group['record']['source']['path'].split('/')[3] + ' variant]'
        entry = dict(id=ident, name=label, source_name=source_name,
                     category=category(source_name), hold='pistol' if source_name in PISTOLS else 'long',
                     playable=source_name not in LAUNCHERS, path='res://art/models/' + asset_name + '.glb',
                     blend='art/blender/' + asset_name + '.blend',
                     muzzle=[point[2] * .1, point[1] * .1, -point[0] * .1],
                     bounds_min=[low[0], low[2], -high[1]], bounds_max=[high[0], high[2], -low[1]],
                     triangles=sum(len(m['faces']) for m in meshes.values()), sha256=group['sha256'],
                     selected=group['record']['selected'], omitted=group['record']['omitted'],
                     textures=[dict(m, image=str(Path(m['image']).relative_to(ROOT))) for m in used.values()], occurrences=group['occurrences'])
        entries.append(entry)
        builds.append(dict(name=asset_name, source_name=source_name, materials=used, meshes=list(meshes.values()),
                           muzzle_blender=[point[2] * .1, point[0] * .1, point[1] * .1]))
    entries.sort(key=lambda e: (e['category'], e['name'], e['id']))
    out = ROOT / 'resources/recovered/weapons.json'
    out.write_text(json.dumps(dict(scale=.1, origin='Native attachment origin; source +X becomes Godot -Z',
                                  reader=str(reader.relative_to(RECOVERY)), weapons=entries), indent=2) + '\n')
    recipe = (ROOT / 'tools/recovery/blender_weapons.py').read_text()
    calls = STAGING / 'calls'
    calls.mkdir(parents=True, exist_ok=True)
    # Only these generated recipes belong to this pipeline.
    for old in calls.glob('recovered_gun_*.py'):
        old.unlink()
    for build in builds:
        obj_path = STAGING / (build['name'] + '.obj')
        lines, base = [], 1
        for mesh in build['meshes']:
            lines.append('o ' + mesh['name'])
            lines.extend('v ' + ' '.join(str(x) for x in v) for v in mesh['vertices'])
            lines.extend('vt ' + ' '.join(str(x) for x in uv) for uv in mesh['uv'])
            lines.extend('f ' + ' '.join(f'{base+i}/{base+i}' for i in face) for face in mesh['faces'])
            base += len(mesh['vertices'])
        obj_path.write_text('\n'.join(lines) + '\n')
        build['obj'] = str(obj_path)
        build['meshes'] = [dict(name=m['name'], material=m['material']) for m in build['meshes']]
        code = recipe.replace("DATA_JSON = '__DATA__'", 'DATA_JSON = ' + repr(json.dumps(build, separators=(',', ':'))))
        code = code.replace("ROOT = '__ROOT__'", 'ROOT = ' + repr(str(ROOT)))
        if len(code.encode()) >= 200000:
            raise ValueError('Blender call too large: ' + build['name'])
        (calls / (build['name'] + '.py')).write_text(code)
    print(f'{len(records)} occurrences -> {len(entries)} textured gun models; {len(PISTOLS)} pistol names, {len(LAUNCHERS)} launcher names.')
    for e in entries:
        print(e['id'], e['triangles'], 'triangles', len(e['occurrences']), 'occurrences')


if __name__ == '__main__':
    main()
