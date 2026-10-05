#!/usr/bin/env python3
"""Compile the decoded map actions and source triangle ownership for runtime doors.

Run prepare_actions.ts first, then this with previous/recovery/.venv/bin/python.
The existing Blender/GLB exports are unchanged: runtime partitions their original
triangles, including collision, using this small ownership manifest.
"""
import gzip
import json
import re
from pathlib import Path
import numpy as np
from prepare_level import ROOT, RECOVERY, DROP, read_obj, read_materials, triangles, pairs, rdr

OUT = ROOT / 'resources/recovered/actions'
OUT.mkdir(parents=True, exist_ok=True)
summary = []
for source in sorted((RECOVERY / 'staging/actions').glob('*.json')):
    decoded = json.loads(source.read_text())
    map_id = decoded['id']
    level_path = ROOT / f'resources/recovered/levels/{map_id.lower()}.json'
    # Old campaign staging stays available offline, outside the runtime project.
    if not map_id.startswith('MP') or not level_path.exists():
        continue
    level = json.loads(level_path.read_text())
    origin = np.array(level['source_origin'])
    valves = {}
    valve_record = rdr(map_id, 'valves')
    if valve_record:
        for record in pairs(valve_record[0]).get('valves', []):
            fields = pairs(record)
            valves[fields['name'][0].lower()] = int(fields.get('value', ['0'])[0])
    doors, unavailable = [], []
    for action in decoded['actions']:
        fields = action['fields']
        node = fields.get('node', [''])[0]
        kind = fields.get('type', ['SCRIPT'])[0]
        if kind != 'DOOR':
            unavailable.append({'node': node, 'type': kind, 'reason': 'Mission/objective executor not implemented'})
            continue
        program = action['programs'][0]
        motions = [op for seq in program.get('sequences', []) if seq['name'].lower() == 'open'
                   for op in seq['ops'] if op['op'] == 'fromTo' and op.get('rotation') and op['node'] == -6 and op['flags'] & 1]
        if not action.get('world') or len(motions) != 1:
            unavailable.append({'node': node, 'type': kind, 'reason': 'Missing placement or unsupported multi-node door program', 'animation': program['name']})
            continue
        motion = motions[0]
        world = action['world'][:]
        world[12:15] = ((np.array(world[12:15]) - origin) * 0.1).tolist()
        valve = fields.get('valve', [node])[0]
        doors.append({'node': node, 'path': action['path'], 'valve': valve, 'initial': valves.get(valve.lower(), 0),
                      'world': world, 'range': float(fields.get('range', ['30'])[0]) * 0.1,
                      'elevation': float(fields['elevation'][0]) * 0.1 if 'elevation' in fields else -1.0,
                      'team': int(fields.get('team', ['-1'])[0]),
                      'bitmap': fields.get('bitmap', ['action_door_open.tif'])[0].lower().replace('.tif', '.png'),
                      'animation': program['name'], 'rotation': motion['rotation']['to'], 'seconds': motion['seconds'],
                      'render': [], 'render_materials': [], 'collision': []})
    if doors:
        verts, uv, faces = read_obj(RECOVERY / f'converted/levels/{map_id}/level.obj')
        materials = read_materials(RECOVERY / f'converted/levels/{map_id}/level.obj')
        prefixes = [(d['path'].replace('/', '_').replace('=', '_'), d) for d in doors]
        for ids, material, name in faces:
            if DROP.search(name):
                continue
            door = next((d for prefix, d in prefixes if name == prefix or name.startswith(prefix + '_')), None)
            if door is None:
                continue
            for triangle in triangles([verts[p] for p, _ in ids]):
                door['render'].append(np.round((triangle - origin) * 0.1, 4).reshape(-1).tolist())
                title = re.sub(r'[^A-Za-z0-9_]', '_', re.sub(r'\.(tif|png|bmp)$', '', materials[material]['name'], flags=re.I))
                door['render_materials'].append(title)
        collision = json.loads(gzip.decompress((RECOVERY / f'converted/levels/{map_id}/collision.json.gz').read_bytes()))
        for polygon in collision:
            if DROP.search(polygon['path'].replace('/', '_').replace('=', '_')) or polygon['poly']['cameratype'] & 1 or polygon['poly']['material'] == 11:
                continue
            door = next((d for d in doors if polygon['path'] == d['path'] or polygon['path'].startswith(d['path'] + '/')), None)
            if door is None:
                continue
            for triangle in triangles(np.array(polygon['points']).reshape(-1, 3)):
                door['collision'].append(np.round((triangle - origin) * 0.1, 4).reshape(-1).tolist())
        for door in doors[:]:
            if not door['render'] or not door['collision']:
                unavailable.append({'node': door['node'], 'type': 'DOOR', 'reason': 'No installed visual or collision geometry'})
                doors.remove(door)
    result = {'map': map_id, 'source': f'native/scripts/{map_id}/READERM.ZAR/actions.rdr; archives/{map_id}/RUN/*/{map_id}/MZANIM.ZAR',
              'scale': 0.1, 'doors': doors, 'unavailable': unavailable}
    (OUT / (map_id.lower() + '.json')).write_text(json.dumps(result, separators=(',', ':')) + '\n')
    summary.append({'map': map_id, 'doors': len(doors), 'unavailable': unavailable})
    print(f'{map_id}: {len(doors)} doors; {len(unavailable)} unsupported actions')
(OUT / 'catalogue.json').write_text(json.dumps(summary, indent=2) + '\n')
