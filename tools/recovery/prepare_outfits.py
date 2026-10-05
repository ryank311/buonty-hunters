#!/usr/bin/env python3
"""Compile native character LOD choices, worn gear and untouched recovered meshes.

The already decoded, assembled OBJ triangles are staged as glTF for Blender,
at the original attachment origin. character.rdr supplies the bone and offset.
"""
import hashlib
import json
import re
from pathlib import Path

import numpy as np

from prepare_pilot import ROOT, RECOVERY, materials, read_obj, triangulate
from prepare_characters import Gltf

READER = 'native/scripts/disc/READERC.ZAR-1b7df1c973/00005-character.rdr.json'
STAGING = RECOVERY / 'staging/outfits'


def fields(row):
    return dict(zip(row[::2], row[1::2]))


def stem(name):
    return Path(name).stem.lower()


def group(name, bone):
    if 'eye' in name or 'teeth' in name:
        return 'face'
    if 'hat' in name or 'helmet' in name:
        return 'headwear'
    if 'goggles' in name or 'headset' in name:
        return 'eyewear'
    if 'holster' in name:
        return 'holster'
    if 'knife' in name:
        return 'knife'
    if name.lower() == 'satchel' or 'pack' in name:
        return 'pack'
    return 'belt' if bone == 'hips' else 'vest' if bone == 'spinehi' else 'other'


def mesh(asset, cache):
    source = RECOVERY / asset['path']
    verts, uv, faces = read_obj(source)
    mats = materials(source, 'recovered_gear')
    chunks, seen = {}, set()
    for ids, mat, _ in faces:
        for tri in triangulate([np.r_[verts[p], uv[t]] for p, t in ids]):
            signature = (mats[mat]['sha256'], tuple(sorted(tuple(np.round(v, 6)) for v in tri)))
            if signature in seen:
                continue
            seen.add(signature)
            chunks.setdefault(mat, []).extend(tri.tolist())
    digest = hashlib.sha256(repr(sorted(seen)).encode()).hexdigest()[:12]
    if digest in cache:
        return cache[digest]
    name = 'recovered_gear_' + re.sub('[^a-z0-9_]', '_', asset['name'].lower()) + '_' + digest
    doc = Gltf()
    data = doc.data
    data['nodes'] = [{'name': asset['name'], 'mesh': 0}]
    data['scenes'][0]['nodes'] = [0]
    primitives = []
    for mat, points in chunks.items():
        spec = mats[mat]
        # Embed the exact recovered PNG bytes; no recolouring or resizing.
        doc.binary.extend(b'\0' * (-len(doc.binary) % 4))
        png = Path(spec['image']).read_bytes()
        view = len(data['bufferViews'])
        data['bufferViews'].append({'buffer': 0, 'byteOffset': len(doc.binary), 'byteLength': len(png)})
        doc.binary.extend(png)
        index = len(data['materials'])
        data['images'].append({'bufferView': view, 'mimeType': 'image/png'})
        data['textures'].append({'source': index})
        material = {'name': spec['name'], 'doubleSided': True,
                    'pbrMetallicRoughness': {'metallicFactor': 0, 'roughnessFactor': .9,
                                            'baseColorTexture': {'index': index}}}
        if spec.get('cutout'):
            material.update(alphaMode='MASK', alphaCutoff=.5)
        data['materials'].append(material)
        points = np.array(points)
        pos = points[:, :3] * .1
        norms = []
        for tri in pos.reshape(-1, 3, 3):
            n = np.cross(tri[1] - tri[0], tri[2] - tri[0])
            norms.extend([n / np.linalg.norm(n)] * 3)
        primitives.append({'attributes': {'POSITION': doc.accessor(pos, 'VEC3', bounds=True),
                                          'NORMAL': doc.accessor(norms, 'VEC3'),
                                          'TEXCOORD_0': doc.accessor(np.c_[points[:, 3], 1 - points[:, 4]], 'VEC2')},
                           'material': index, 'mode': 4})
    data['meshes'] = [{'name': asset['name'], 'primitives': primitives}]
    data.pop('animations', None)
    STAGING.mkdir(parents=True, exist_ok=True)
    target = STAGING / (name + '.gltf')
    data['buffers'] = [{'uri': name + '.bin', 'byteLength': len(doc.binary)}]
    target.with_suffix('.bin').write_bytes(doc.binary)
    target.write_text(json.dumps(data, separators=(',', ':')) + '\n')
    result = dict(path='res://art/models/' + name + '.glb', blend='art/blender/' + name + '.blend', source=asset['path'],
                  triangles=len(seen), sha256=digest)
    cache[digest] = result
    return result


def main():
    source = fields(json.loads((RECOVERY / READER).read_text())[0])
    records, chars, i = source['characters'], {}, 0
    while i < len(records):
        name = records[i]
        inherited = records[i + 1] == ':'
        chars[name] = (records[i + 2] if inherited else None, fields(records[i + 3 if inherited else i + 1]))
        i += 4 if inherited else 2

    def resolved(name):
        base, own = chars[name]
        return {**(resolved(base) if base in chars else {}), **own}

    presets, lods = {}, set()
    for name in chars:
        row = resolved(name)
        if 'model_name' in row:
            presets[name] = dict(model=stem(row['model_name'][0]), gear=row.get('default_gear', []))
        for lod in row.get('lods', []):
            lods.add(stem(lod[0]))
    catalogue = json.loads((ROOT / 'resources/recovered/catalogue.json').read_text())
    assets = json.loads((RECOVERY / 'reports/assets.json').read_text())
    equipment = [a for a in assets if a['type'] == 'model' and a.get('category') == 'equipment']
    cache, gear, missing, sockets = {}, {}, [], {}
    for record in source['gear']:
        row = fields(record)
        name = row['name'][0]
        bone, translation, rotation = row['ofs']
        if row['model'][0] == 'NONAME.flt':
            sockets[name] = dict(bone=bone, translation=[float(x) * .1 for x in translation],
                                 rotation=[float(x) for x in rotation])
            continue
        candidates = [a for a in equipment if a['name'].lower() == stem(row['model'][0])]
        if not candidates:
            missing.append(name)
            continue
        models = {}
        for a in candidates:
            models[a['path'].split('/')[3]] = mesh(a, cache)['path']
        gear[name] = dict(bone=bone, translation=[float(x) * .1 for x in translation],
                          rotation=[float(x) for x in rotation], group=group(name, bone),
                          path=models.get('MP2', next(iter(models.values()))), models=models)
    characters, excluded = {}, []
    for entry in catalogue['characters']:
        name = entry['name'].lower()
        # Explicit native LOD lists take precedence. The triangle audit catches
        # orphan LODs whose parent model wasn't present in the recovered set.
        if name in lods or entry['triangles'] < 1000:
            excluded.append(dict(name=entry['name'], triangles=entry['triangles'],
                                 reason='character.rdr lods' if name in lods else 'orphan reduced mesh'))
            continue
        context = entry['source'].split('/')[3]
        candidates = [n for n, p in presets.items() if p['model'] == name]
        candidates.sort(key=lambda n: (not n.startswith(context.lower() + '_'), n))
        preset = candidates[0] if candidates else ''
        characters[entry['path']] = dict(name=entry['name'], triangles=entry['triangles'], context=context,
                                         preset=preset, gear=presets[preset]['gear'] if preset else [])
    grenades = {}
    for kind, name in [('frag', 'grenade'), ('flash', 'flashbang'), ('smoke', 'a_smoke_grenade')]:
        asset = next(a for a in assets if a['type'] == 'model' and a['name'] == name and a.get('category') == 'weapons')
        grenades[kind] = mesh(asset, cache)['path']
    output = dict(reader=READER, characters=characters, excluded=excluded, gear=gear,
                  missing_gear=missing, weapon_sockets=sockets, grenades=grenades, assets=list(cache.values()))
    (ROOT / 'resources/recovered/outfits.json').write_text(json.dumps(output, indent=2) + '\n')
    names = [Path(a['path']).stem for a in cache.values()]
    (STAGING / 'export_names.txt').write_text('\n'.join(names) + '\n')
    recipe = (ROOT / 'tools/recovery/blender_outfits.py').read_text()
    for start in range(0, len(names), 8):
        code = recipe.replace("NAMES = []", 'NAMES = ' + repr(names[start:start + 8]))
        code = code.replace("ROOT = '__ROOT__'", 'ROOT = ' + repr(str(ROOT)))
        (STAGING / ('build_%02d.py' % (start // 8))).write_text(code)
    print(f'{len(characters)} full-detail characters; {len(excluded)} LODs excluded; {len(gear)} gear definitions; {len(cache)} textured assets')
    print('Unavailable source gear:', ', '.join(missing))


if __name__ == '__main__':
    main()
