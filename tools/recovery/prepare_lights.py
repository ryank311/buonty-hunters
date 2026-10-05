#!/usr/bin/env python3
"""Recover placed CLight nodes, including lights omitted by the mesh extractor.

Run with previous/recovery/.venv/bin/python tools/recovery/prepare_lights.py.
Only installed multiplayer maps are processed. No Blender re-export is needed.
"""
import json
import math
import re
import struct
from collections import Counter

import numpy as np

from prepare_level import ROOT, RECOVERY, RUNTIME, DROP


def children(node):
    return {child['name']: child for child in node.get('children', [])}


def placed_nodes(map_id):
    """Yield active scene nodes with their fully composed source-space transform.

    Native matrices use row vectors: child_world = child_local @ parent_world.
    Instances include the referenced model root transform, like mesh recovery.
    Unplaced library prototypes must never become lights in the world.
    """
    index_path = next((RECOVERY / 'native/indexes').glob(f'{map_id}_GEO.ZED-*.json'))
    index = json.loads(index_path.read_text())
    data = (RECOVERY / index['source']).read_bytes()
    base = index['dataOffset']
    models = children(children(index['root'])['models'])

    def blob(node):
        return data[base + node['offset']:base + node['offset'] + node['size']]

    def visit(node, parent, path, stack):
        fields = children(node)
        if 'nparams' not in fields or DROP.search(node['name']):
            return
        values = struct.unpack('<22f2I', blob(fields['nparams']))
        kind, flags = values[22:24]
        if not flags & 1:
            return
        world = np.array(values[:16]).reshape(4, 4) @ parent
        path = path + '/' + node['name']
        record = {'path': path.lstrip('/'), 'name': node['name'], 'kind': kind & 0xffff,
                  'world': world, 'bounds': values[16:22], 'flags': flags,
                  'offset': fields['nparams']['offset'], 'source': index['source']}
        if kind == 8:
            record['color'] = struct.unpack('<3f', blob(fields['diffuse']))
            record['inner'] = struct.unpack('<f', blob(fields['min_range']))[0]
            record['radius'] = math.sqrt(struct.unpack('<f', blob(fields['max_range_sq']))[0])
        yield record
        if kind == 2:
            model_name = blob(fields['model_name']).rstrip(b'\0').decode('utf-8')
            if model_name in models:
                if model_name in stack:
                    raise ValueError(f'Recursive model instance: {path} -> {model_name}')
                yield from visit(models[model_name], world, path + '=', stack + (model_name,))
        for child in fields.get('children', {}).get('children', []):
            yield from visit(child, world, path, stack)

    yield from visit(models['worldmodel'], np.eye(4), '', ('worldmodel',))


def recover(level):
    origin = np.array(level['source_origin'])
    scale = level['scale']
    nodes = list(placed_nodes(level['id']))
    lights = []
    seen = set()
    for node in nodes:
        if node['kind'] != 8:
            continue
        position = (node['world'][3, :3] - origin) * scale
        color = node['color']
        radius = node['radius'] * scale
        if radius <= 0 or max(color) <= 0:
            continue
        assert np.isfinite(position).all() and math.isfinite(radius)
        # Identical duplicated source nodes must not double the illumination.
        key = (*position.round(4), *np.round(color, 4), round(radius, 4))
        if key in seen:
            continue
        seen.add(key)
        lights.append({'path': node['path'], 'position': position.round(5).tolist(),
                       'color': list(np.round(color, 6)), 'range': round(radius, 5),
                       'inner_range': round(node['inner'] * scale, 5),
                       'kind': 'fire' if re.search(r'torch|fire|flame', node['path'], re.I) else 'lamp',
                       'evidence': 'native', 'nparams_offset': node['offset']})
    return {'name': level['name'], 'source': nodes[0]['source'], 'lights': lights}, nodes


def main():
    maps = {}
    for path in sorted(RUNTIME.glob('mp*.json')):
        level = json.loads(path.read_text())
        assert level['mode'] == 'Multiplayer'
        maps[level['id']], nodes = recover(level)
        print(level['id'], level['name'], len(maps[level['id']]['lights']), 'native lights')
    output = ROOT / 'resources/recovered/lighting.json'
    output.write_text(json.dumps({'version': 1, 'maps': maps}, indent=1) + '\n')


if __name__ == '__main__':
    main()
