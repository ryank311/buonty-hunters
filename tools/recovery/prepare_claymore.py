#!/usr/bin/env python3
"""Stage the native M18 claymore and its detonator; submit each staged recipe via
Blender MCP, then export. Run with previous/recovery/.venv/bin/python.
"""
import hashlib
import json
from prepare_pilot import ROOT, RECOVERY, read_obj, materials

assets = json.loads((RECOVERY / 'reports/assets.json').read_text())
stage = RECOVERY / 'staging/claymore'
stage.mkdir(parents=True, exist_ok=True)
# The claymore stands on the ground: source Y-up kept, its convex face (source -Z) is
# Godot forward. The detonator is held: gun convention, source +X becomes Godot -Z.
AXES = {
    'claymore': ('placed', lambda x, y, z: [x * .1, -z * .1, y * .1]),
    'detonator': ('held', lambda x, y, z: [z * .1, x * .1, y * .1]),
}
manifest = dict(recipe='tools/recovery/prepare_claymore.py', scale=.1, models={})
for source_name, (use, axes) in AXES.items():
    name = 'recovered_' + source_name
    asset = next(a for a in assets if a['type'] == 'model' and a['name'] == source_name and '/MP2/' in a['path'])
    path = RECOVERY / asset['path']
    vertices, uv, faces = read_obj(path)
    mats = materials(path, name)
    chunks = {}
    for ids, material, label in faces:
        chunk = chunks.setdefault(material, dict(name=source_name.title() + '_' + material, material=material, vertices=[], uv=[], faces=[]))
        base = len(chunk['vertices'])
        for point, tex in ids:
            chunk['vertices'].append(axes(*vertices[point]))
            chunk['uv'].append(uv[tex].tolist())
        for i in range(1, len(ids) - 1):
            chunk['faces'].append([base, base + i, base + i + 1])
    data = dict(name=name, source='MP2 WEAP_MDL.ZED / ' + source_name, materials=mats, meshes=list(chunks.values()))
    recipe = (ROOT / 'tools/recovery/blender_claymore.py').read_text().replace('__DATA__', json.dumps(data))
    (stage / f'{source_name}.py').write_text(recipe)
    manifest['models'][source_name] = dict(
        model=asset, model_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), use=use,
        path=f'res://art/models/{name}.glb', triangles=sum(len(c['faces']) for c in chunks.values()),
        origin='Native origin; Y-up kept, front (source -Z) is Godot -Z' if use == 'placed' else 'Native attachment origin; source +X becomes Godot -Z')
    print(stage / f'{source_name}.py')
(ROOT / 'resources/recovered/claymore.json').write_text(json.dumps(manifest, indent=2) + '\n')
