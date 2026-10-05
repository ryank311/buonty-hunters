#!/usr/bin/env python3
"""Stage native AN-M8/puff assets; submit canister.py via Blender MCP, then export.
Run with previous/recovery/.venv/bin/python.
"""
import hashlib
import json
import shutil
from prepare_pilot import ROOT, RECOVERY, read_obj, materials

assets = json.loads((RECOVERY / 'reports/assets.json').read_text())
asset = next(a for a in assets if a['type'] == 'model' and a['name'] == 'a_smoke_grenade' and '/MP2/' in a['path'])
path = RECOVERY / asset['path']
vertices, uv, faces = read_obj(path)
mats = materials(path, 'recovered_smoke_grenade')
chunks = {}
for ids, material, label in faces:
    chunk = chunks.setdefault(material, dict(name='Canister_' + material, material=material, vertices=[], uv=[], faces=[]))
    base = len(chunk['vertices'])
    for point, tex in ids:
        x, y, z = vertices[point]
        chunk['vertices'].append([z * .1, x * .1, y * .1])
        chunk['uv'].append(uv[tex].tolist())
    for i in range(1, len(ids) - 1):
        chunk['faces'].append([base, base + i, base + i + 1])
data = dict(name='recovered_smoke_grenade', materials=mats, meshes=list(chunks.values()))
recipe = (ROOT / 'tools/recovery/blender_smoke.py').read_text().replace('__DATA__', json.dumps(data))
stage = RECOVERY / 'staging/smoke'
stage.mkdir(parents=True, exist_ok=True)
(stage / 'canister.py').write_text(recipe)
puff = next(a for a in assets if a['type'] == 'texture' and a['name'] == 'cloudpuff01.tif' and '/MP2/' in a['path'])
target = ROOT / 'art/effects/recovered/cloudpuff01.png'
target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(RECOVERY / puff['path'], target)
manifest = dict(model=asset, model_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                scale=.1, origin='Native attachment origin; source +X becomes Godot -Z',
                path='res://art/models/recovered_smoke_grenade.glb', puff=puff,
                puff_path='res://art/effects/recovered/cloudpuff01.png',
                recipe='tools/recovery/prepare_smoke.py',
                note='All 50 source triangles retained; plume is a volumetric adaptation, not a PS2 particle-engine reconstruction.')
(ROOT / 'resources/recovered/smoke.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(stage / 'canister.py')
