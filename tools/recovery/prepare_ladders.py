#!/usr/bin/env python3
"""Find every ladder of the installed maps and write resources/recovered/ladders.json.

Run with previous/recovery/.venv/bin/python tools/recovery/prepare_ladders.py

The original marks a ladder on its collision polygons, not by name: `m_appflags` 2
(local research 86-traversal.md, section 2). Each ladder is two quads in one vertical
plane: the span, from the floor it stands on to the floor it reaches, and above it a
cap about one metre tall. A ladder is climbed from the side its top floor is not on.
Positions are written in game metres: (source - map origin) x 0.1.
"""
import gzip
import json
import math
import numpy as np
from prepare_level import ROOT, RECOVERY, DROP, SKY, SCALE, triangles, ground

OUT = ROOT / 'resources/recovered/ladders.json'
APP_LADDER = 2
# How far either side of the plane a floor is looked for, and how near the height it
# must be (source units), as the research viewer's findLadders does.
SIDE_STEP, FLOOR_TOLERANCE = 6.0, 2.5
SAME = 1.0


def part(polygon):
    points = np.array(polygon['points']).reshape(-1, 3)
    normal = np.zeros(3)
    for i in range(len(points)):
        a, b = points[i], points[(i + 1) % len(points)]
        normal += np.cross(a, b)
    flat = math.hypot(normal[0], normal[2])
    if flat < 1e-9 or flat / np.linalg.norm(normal) < 0.7:
        return None
    nx, nz = normal[0] / flat, normal[2] / flat
    along = -nz * points[:, 0] + nx * points[:, 2]
    middle, depth = (along.min() + along.max()) / 2, nx * points[:, 0].mean() + nz * points[:, 2].mean()
    return {'path': polygon['path'], 'x': nx * depth - nz * middle, 'z': nz * depth + nx * middle,
            'bottom': float(points[:, 1].min()), 'top': float(points[:, 1].max()), 'nx': nx, 'nz': nz,
            'half': float(along.max() - along.min()) / 2}


def floor_near(solid, normals, x, z, height):
    found = ground(solid, normals, (x, height + FLOOR_TOLERANCE, z))
    return found is not None and abs(found - height) <= FLOOR_TOLERANCE


def ladders_of(map_id):
    source = json.loads(gzip.decompress((RECOVERY / f'converted/levels/{map_id}/collision.json.gz').read_bytes()))
    solid, parts = [], []
    for polygon in source:
        name = polygon['path'].replace('/', '_').replace('=', '_')
        if DROP.search(name) or SKY.search(polygon['path'].replace('/', '_')):
            continue
        if polygon['poly'].get('appflags', 0) == APP_LADDER:
            found = part(polygon)
            if found:
                parts.append(found)
            continue
        if polygon['poly']['cameratype'] & 1 or polygon['poly']['material'] == 11:
            continue
        solid.extend(triangles(list(np.array(polygon['points']).reshape(-1, 3))))
    solid = np.array(solid)
    normals = np.cross(solid[:, 1] - solid[:, 0], solid[:, 2] - solid[:, 0])
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)
    # Collision is two-sided in the game; a floor counts whichever way it is wound.
    normals[:, 1] = np.abs(normals[:, 1])
    groups = []
    for item in parts:
        group = next((g for g in groups if any(abs(abs(o['nx'] * item['nx'] + o['nz'] * item['nz']) - 1) < 1e-3
                                                and math.hypot(o['x'] - item['x'], o['z'] - item['z']) < SAME + o['half'] for o in g)), None)
        if group is None:
            groups.append([item])
        else:
            group.append(item)
    result = []
    for group in groups:
        span = max(group, key=lambda p: p['top'] - p['bottom'])
        ladder = dict(span, cap_top=max(p['top'] for p in group), sided=False)
        if ladder['cap_top'] - ladder['top'] < 1.0 and len(group) < 2:
            # A cap on its own, with no span under it.
            continue

        def floor(side, height):
            return floor_near(solid, normals, ladder['x'] + ladder['nx'] * SIDE_STEP * side, ladder['z'] + ladder['nz'] * SIDE_STEP * side, height)
        deck_front, deck_back = floor(1, ladder['top']), floor(-1, ladder['top'])
        if deck_front != deck_back:
            ladder['sided'] = True
            flip = deck_front
        else:
            flip = not floor(1, ladder['bottom']) and floor(-1, ladder['bottom'])
        if flip:
            ladder['nx'], ladder['nz'] = -ladder['nx'], -ladder['nz']
        if not any(math.hypot(o['x'] - ladder['x'], o['z'] - ladder['z']) < SAME and abs(o['top'] - ladder['top']) < SAME for o in result):
            result.append(ladder)
    return result


def main():
    maps, total = {}, 0
    for level_path in sorted((ROOT / 'resources/recovered/levels').glob('mp*.json')):
        level = json.loads(level_path.read_text())
        if level.get('mode') != 'Multiplayer':
            continue
        origin = np.array(level['source_origin'])
        found = ladders_of(level['id'])
        if not found:
            continue
        maps[level['id']] = [{
            'path': ladder['path'],
            'centre': [round((ladder['x'] - origin[0]) * SCALE, 4), round((ladder['z'] - origin[2]) * SCALE, 4)],
            'bottom': round((ladder['bottom'] - origin[1]) * SCALE, 4),
            'top': round((ladder['top'] - origin[1]) * SCALE, 4),
            'cap_top': round((ladder['cap_top'] - origin[1]) * SCALE, 4),
            'normal': [round(ladder['nx'], 5), round(ladder['nz'], 5)],
            'half_width': round(ladder['half'] * SCALE, 4),
            'sided': ladder['sided'],
            'source': {'x': round(ladder['x'], 1), 'z': round(ladder['z'], 1), 'bottom': round(ladder['bottom'], 1), 'top': round(ladder['top'], 1)},
        } for ladder in found]
        total += len(found)
        print(f"{level['id']}: {len(found)} ladders")
        for ladder in found:
            print(f"   {ladder['path']:58s} x {ladder['x']:7.1f} z {ladder['z']:7.1f}  {ladder['bottom']:6.1f} -> {ladder['top']:6.1f}"
                  f"  from ({ladder['nx']:.2f}, {ladder['nz']:.2f}){'' if ladder['sided'] else '  side from the foot only'}")
    OUT.write_text(json.dumps({
        'source': 'converted/levels/<map>/collision.json.gz: the polygons whose m_appflags is 2 (research 86-traversal.md, section 2)',
        'scale': SCALE, 'maps': maps}, indent=1) + '\n')
    print(f'{total} ladders on {len(maps)} maps -> {OUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
