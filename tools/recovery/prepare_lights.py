#!/usr/bin/env python3
"""Recover placed CLight nodes, including lights omitted by the mesh extractor.

Run with previous/recovery/.venv/bin/python tools/recovery/prepare_lights.py.
Only installed multiplayer maps are processed. No Blender re-export is needed.
"""
import argparse
import json
import math
import re
import struct
import numpy as np

from prepare_level import ROOT, RECOVERY, RUNTIME, DROP

# Explicit fixture profiles only; these are approximations, never native values.
# Offsets are in the model's source coordinates. Crossroads' retained spherical
# bounds still locate the former emitter and its radius. Fluorescent tubes have
# a retained 40-unit influence box below the fixture, centered on the room.
WARM = [1.0, 0.82, 0.57]
COOL = [0.79, 0.89, 1.0]
FIRE = [1.0, 0.42, 0.12]
FIXTURES = {
    'MP72': {'light_bright': ([0, -23.5, 0], 6.0, WARM, 1.0),
             'light_dim': ([0, -16, 0], 3.0, WARM, 0.5)},
    'MP81': {'flolight1': ([0, 0, 0], 4.0, COOL, 1.0),
             'flolight2': ([0, 0, 0], 4.0, COOL, 1.0)},
    'MP82': {'hanginglite_nobeam': ([-3.1346, -16, -0.23038], 4.5, WARM, 1.0),
             'lightpost': ([0, 76, -10], 6.0, WARM, 1.0)},
    'MP6': {'mp6_light_outside': ([0, -4, 0], 5.0, WARM, 1.0),
            'mp6_light_hangdown': ([0, -10, 0], 4.5, WARM, 1.0),
            'mp6_light_hangout': ([0, -10, 0], 4.5, WARM, 1.0),
            'mp6_light_neck': ([0, -6, -5], 3.5, WARM, 0.8),
            'mp6_rubble_burning1': ([0, 8, 0], 4.0, FIRE, 1.0),
            'mp6_barrel_fire': ([0, 4, 0], 4.0, FIRE, 1.0)},
    'MP7': {'afghan2r_firepit_small': ([0, 6, 0], 4.0, FIRE, 1.0)},
    'MP2': {'r_tower_flames': ([0, 4, 0], 5.0, FIRE, 1.0)},
}


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
        path = path + ('' if path.endswith('=') else '/') + node['name']
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
    for node in nodes:
        profile = FIXTURES.get(level['id'], {}).get(node['name'])
        if profile is None or node['kind'] not in (1, 7):
            continue
        offset, radius, color, energy = profile
        source_position = (np.array([*offset, 1.0]) @ node['world'])[:3]
        position = (source_position - origin) * scale
        # A profile must not duplicate an original light at the same fixture.
        if any(l['path'].startswith(node['path'] + '/') for l in lights):
            continue
        lights.append({'path': node['path'], 'position': position.round(5).tolist(),
                       'color': color, 'range': radius, 'inner_range': radius * 0.25,
                       'energy': energy, 'kind': 'fire' if color == FIRE else 'lamp',
                       'evidence': 'fixture', 'nparams_offset': node['offset']})
    return {'name': level['name'], 'source': nodes[0]['source'], 'lights': lights}, nodes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true', help='Compare composed transforms with recovered geometry placements before writing')
    args = parser.parse_args()
    maps = {}
    checked, worst = 0, 0.0
    for path in sorted(RUNTIME.glob('mp*.json')):
        level = json.loads(path.read_text())
        assert level['mode'] == 'Multiplayer'
        maps[level['id']], nodes = recover(level)
        if args.verify:
            by_path = {}
            for node in nodes:
                by_path.setdefault(node['path'], []).append(node['world'])
            placements = json.loads((RECOVERY / 'converted/levels' / level['id'] / 'placements.json').read_text())
            for placement in placements:
                matrices = by_path.get(placement['path'], [])
                if not matrices:
                    continue
                expected = np.array(placement['rowMajor']).reshape(4, 4)
                error = min(np.max(np.abs(expected - matrix)) for matrix in matrices)
                if error > 0.01:
                    raise ValueError(f"Transform differs from recovered geometry: {level['id']}/{placement['path']}: {error}")
                checked += 1
                worst = max(worst, error)
        lights = maps[level['id']]['lights']
        native = sum(l['evidence'] == 'native' for l in lights)
        print(level['id'], level['name'], native, 'native +', len(lights) - native, 'fixture lights')
    output = ROOT / 'resources/recovered/lighting.json'
    output.write_text(json.dumps({'version': 1, 'maps': maps}, indent=1) + '\n')
    if args.verify:
        print(f'Verified {checked} placed transforms; maximum source-unit error {worst:.8f}')


if __name__ == '__main__':
    main()
