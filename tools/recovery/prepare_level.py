#!/usr/bin/env python3
"""Prepare recovered maps for the Blender level recipe and the game.

Run with previous/recovery/.venv/bin/python. For each map this writes, under
previous/recovery/staging/levels/<ID>/, Blender-space OBJ files for the world,
the sky and the solid collision. --batch then writes staging/levels/batch_call.py:
submit its text to the Blender MCP execute_blender_code tool to save
art/blender/recovered_map_<id>.blend for each named map. It also writes the
committed runtime description resources/recovered/levels/<id>.json: name,
original lighting, fog, draw distance, spawns and per-texture blend modes.

    prepare_level.py MP72 MP1        # named maps
    prepare_level.py --all           # every assembled map
    prepare_level.py --batch MP1 MP2 # one Blender call that builds both

Geometry selection: intact states only. Destroyed/debris branches, shadow and
pulse helpers, camera-following rain/dust and night-vision masks are omitted;
the sky dome is split into its own mesh; collision skips camera/trigger
volumes and water (the Crossroads pilot's filters, extended to every map).
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RECOVERY = ROOT / 'previous/recovery'
LEVELS = RECOVERY / 'converted/levels'
STAGING = RECOVERY / 'staging/levels'
RUNTIME = ROOT / 'resources/recovered/levels'
SCALE = 0.1
# Source Y-up -> Blender Z-up. The glTF export turns Blender Z-up back into
# Y-up, so Godot coordinates are simply (source - origin) * SCALE.
C = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], dtype=float)
DROP = re.compile(r'destroyed|_shadow|_pulse|healthy_explosive|whats_left|(?<!good)_parts(?![a-z])|_part_?\d+$|_part_?\d+_'
                  r'|bad_parts|parts_bad|rain_follow|dustfollow|nvg_mask', re.I)
SKY = re.compile(r'(^|_)(sky|sky_\d+|skydome|skyhorizon|sky_follow|sky_model|sky_mark|sky_m72|cyl_sky|plane_sky|cloudlayer)(_|$)', re.I)
# Sky, cloud, star and moon textures; not skylight windows or the North Star sign.
SKY_TEXTURE = re.compile(r'^(?!.*skylight)(\w*sky\w*|\w*cloud\w*|stars?\d*|\w*_star|moon)\.(tif|bmp|png)', re.I)
# Original mission titles for the campaign maps (the records hold string ids).
TITLES = {'M51': 'Seeding Chaos', 'M52': 'Terminal Transaction', 'M53': 'Upland Assault', 'M61': 'Urban Sweep',
          'M62': 'Stranglehold', 'M63': 'Hydroelectric', 'M71': 'Guardian Angels', 'M72': 'Protect and Serve',
          'M73': 'Against the Tide', 'M81': 'Lockdown', 'M82': 'Guided Tour', 'M83': 'Doomsday Delivery'}


def rdr(map_id, stem):
    found = sorted((RECOVERY / 'native/scripts' / map_id).glob(f'READERM.ZAR-*/*-{stem}.rdr.json'))
    return json.loads(found[0].read_text()) if found else None


def pairs(values):
    """Reader records alternate key, value; values are lists of strings."""
    result = {}
    for i in range(0, len(values) - 1, 2):
        if isinstance(values[i], str):
            result[values[i]] = values[i + 1]
    return result


def world_params(map_id):
    """world_params plus its sibling blocks (camera, fog, grid) from <map>.rdr."""
    record = rdr(map_id, map_id.lower())
    if not record:
        return {}
    top = pairs(record[0])
    return {**top, **pairs(top.get('world_params', []))}


def rgb(values):
    return [round(float(v) / 255.0, 4) for v in values]


def ambience(map_id):
    params = world_params(map_id)
    lighting = pairs(params.get('GlobalLighting', []))
    camera = pairs(params.get('camera', []))
    fog = pairs(camera.get('fog_standard', []))
    lights = []
    for key in ('light0', 'light1', 'light2'):
        light = pairs(lighting.get(key, []))
        if light and light.get('active', ['0'])[0] == '1':
            lights.append({'color': rgb(light['RGB']), 'direction': [float(v) for v in light['dir']]})
    return {
        'night': params.get('NightMission', ['0'])[0] == '1',
        'ambient': rgb(pairs(lighting.get('ambient', [])).get('RGB', ['40', '40', '40'])),
        'lights': lights,
        'fog': {'enabled': fog.get('enabled', ['0'])[0] == '1', 'color': rgb(fog.get('RGB', ['0', '0', '0'])),
                'begin': float(fog.get('range', ['300', '800'])[0]) * SCALE, 'end': float(fog.get('range', ['300', '800'])[1]) * SCALE},
        'far_clip': float(camera.get('clip', ['4', '1000'])[1]) * SCALE,
    }


def blend_modes(map_id):
    """Texture name -> original blend mode, from every library record the map loads."""
    modes = {}
    for path in (RECOVERY / 'native/scripts' / map_id).glob('READERM.ZAR-*/*_lib.rdr.json'):
        record = json.loads(path.read_text())
        for lib in record if isinstance(record, list) else []:
            if not isinstance(lib, list) or 'textures' not in lib:
                continue
            for entry in lib[lib.index('textures') + 1]:
                fields = pairs(entry)
                if 'name' in fields and 'blendmode' in fields:
                    modes[fields['name'][0].lower()] = fields['blendmode'][0]
    return modes


def views(map_id):
    record = rdr(map_id, 'mission')
    if not record:
        return []
    result = []
    for block in record:
        fields = pairs(block) if isinstance(block, list) else {}
        for view in fields.get('Scenic_Views', []):
            view = pairs(view)
            result.append({'name': view['Desc'][0], 'source': [float(v) for v in view['Pos']]})
    return result


def read_obj(path):
    vertices, uv, faces = [], [], []
    name, material = '', ''
    with path.open() as handle:
        for line in handle:
            if line.startswith('v '):
                vertices.append(line[2:].split()[:3])
            elif line.startswith('vt '):
                uv.append(line[3:].split()[:2])
            elif line.startswith('f '):
                faces.append(([[int(x) - 1 for x in w.split('/')[:2]] for w in line[2:].split()], material, name))
            elif line.startswith('o '):
                name = line[2:].strip()
            elif line.startswith('usemtl '):
                material = line[7:].strip()
    return np.array(vertices, dtype=float), np.array(uv, dtype=float), faces


def read_materials(obj):
    result, key = {}, None
    for line in obj.with_suffix('.mtl').read_text().splitlines():
        if line.startswith('newmtl '):
            key = line.split()[1]
            result[key] = {'name': key}
        elif line.startswith('# ') and key:
            result[key]['name'] = line[2:].strip()
        elif line.startswith('map_Kd ') and key:
            result[key]['source'] = (obj.parent / line[7:].strip()).resolve()
    return result


def install_texture(spec, asset):
    """Copy a source PNG into the Blender texture tree, content addressed."""
    source = spec.get('source')
    if source is None or not source.exists():
        return None
    data = source.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    target = ROOT / 'art/blender/textures' / asset / (sha[:10] + '_' + source.name)
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    with Image.open(source) as image:
        alpha = np.array(image.convert('RGBA'))[:, :, 3]
    return {'image': str(target), 'source': str(source.relative_to(ROOT)), 'sha256': sha,
            'cutout': bool(alpha.min() < 128), 'translucent': bool(((alpha > 8) & (alpha < 247)).mean() > 0.1)}


def triangles(points):
    for i in range(1, len(points) - 1):
        tri = np.array([points[0], points[i], points[i + 1]])
        if np.linalg.norm(np.cross(tri[1, :3] - tri[0, :3], tri[2, :3] - tri[0, :3])) > 1e-6:
            yield tri


class Mesh:
    """Triangles grouped by material, deduplicated, in Blender metres."""

    def __init__(self):
        self.groups, self.seen, self.count = {}, set(), 0

    def add(self, material, tri):
        signature = (material, tuple(sorted(tuple(np.round(v[:3], 4)) for v in tri)))
        if signature in self.seen:
            return
        self.seen.add(signature)
        self.groups.setdefault(material, []).append(tri)
        self.count += 1

    def bounds(self):
        points = np.array([v[:3] for tris in self.groups.values() for tri in tris for v in tri])
        return points.min(axis=0), points.max(axis=0)

    def write(self, path, prefix, origin, titles):
        lines, base = ['mtllib level.mtl\n'], 1
        for material, tris in sorted(self.groups.items()):
            lines.append(f'o {prefix}{titles[material]}\nusemtl {titles[material]}\n')
            for tri in tris:
                for v in tri:
                    p = (v[:3] - origin) @ C.T * SCALE
                    lines.append(f'v {p[0]:.4f} {p[1]:.4f} {p[2]:.4f}\nvt {v[3]:.5f} {v[4]:.5f}\n')
                lines.append(f'f {base}/{base} {base+1}/{base+1} {base+2}/{base+2}\n')
                base += 3
        path.write_text(''.join(lines))


def sky_model(map_id):
    """Some maps keep the sky as a separate model in their zone library."""
    for path in sorted((RECOVERY / 'converted/models').glob(f'*/{map_id}/*/*.obj')):
        if re.fullmatch(r'(sky|sky_m\d+|mp\d+_sky|alaska4d_sky|sky_follow)', path.stem, re.I):
            return path
    return None


def ground(points, normals, position, below=True):
    """Highest upward-facing collision surface under (x, z) at or below position[1]."""
    a, b, c = points[:, 0], points[:, 1], points[:, 2]
    x, z = position[0], position[2]
    v0, v1 = c[:, [0, 2]] - a[:, [0, 2]], b[:, [0, 2]] - a[:, [0, 2]]
    v2 = np.array([x, z]) - a[:, [0, 2]]
    d00, d01, d11 = (v0 * v0).sum(1), (v0 * v1).sum(1), (v1 * v1).sum(1)
    d02, d12 = (v0 * v2).sum(1), (v1 * v2).sum(1)
    det = d00 * d11 - d01 * d01
    with np.errstate(divide='ignore', invalid='ignore'):
        u = (d11 * d02 - d01 * d12) / det
        v = (d00 * d12 - d01 * d02) / det
        inside = (u >= 0) & (v >= 0) & (u + v <= 1) & (normals[:, 1] > 0.7) & (np.abs(det) > 1e-9)
        heights = a[:, 1] + u * (c[:, 1] - a[:, 1]) + v * (b[:, 1] - a[:, 1])
    if below:
        inside &= heights <= position[1]
    if not inside.any():
        return None
    return float(heights[inside].max())


def clear_above(points, position, height=18.0):
    """No collision triangle crosses the standing column above position (source units)."""
    low, high = points.min(axis=1), points.max(axis=1)
    near = ((low[:, 0] <= position[0] + 3) & (high[:, 0] >= position[0] - 3) & (low[:, 2] <= position[2] + 3)
            & (high[:, 2] >= position[2] - 3) & (high[:, 1] > position[1] + 1) & (low[:, 1] < position[1] + height))
    return not near.any()


def open_direction(points, position, centre, reach=400.0):
    """The horizontal direction with the longest clear line of sight at eye
    height (1.6 m), so a spawn does not face a wall; ties lean to the centre."""
    eye = np.array([position[0], position[1] + 16.0, position[2]])
    a, e1, e2 = points[:, 0], points[:, 1] - points[:, 0], points[:, 2] - points[:, 0]
    best, best_score = None, -1.0
    towards = np.array([centre[0] - eye[0], centre[2] - eye[2]])
    towards = towards / max(np.linalg.norm(towards), 1e-6)
    for step in range(16):
        angle = step * np.pi / 8
        direction = np.array([np.sin(angle), 0.0, -np.cos(angle)])
        p = np.cross(direction, e2)
        det = (e1 * p).sum(1)
        with np.errstate(divide='ignore', invalid='ignore'):
            inv = 1.0 / det
            t_vec = eye - a
            u = (t_vec * p).sum(1) * inv
            q = np.cross(t_vec, e1)
            v = (q * direction).sum(1) * inv
            t = (e2 * q).sum(1) * inv
        hit = (np.abs(det) > 1e-9) & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0.5)
        distance = min(reach, float(t[hit].min())) if hit.any() else reach
        score = distance + 20.0 * float(towards @ direction[[0, 2]])
        if score > best_score:
            best, best_score = direction, score
    return [round(float(best[0]), 3), round(float(best[2]), 3)]


def spawns(map_id, solid, origin):
    points = solid
    normals = np.cross(points[:, 1] - points[:, 0], points[:, 2] - points[:, 0])
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
    normals *= np.where(normals[:, 1:2] < 0, -1, 1)
    result = []
    for view in sorted(views(map_id), key=lambda v: 0 if 'base' in v['name'].lower() and 'overlook' not in v['name'].lower() else 1):
        y = ground(points, normals, view['source'])
        if y is None:
            continue
        position = np.array([view['source'][0], y, view['source'][2]])
        if clear_above(points, position):
            result.append({'name': view['name'], 'source': position.tolist()})
    if len(result) < 3:
        # Campaign starts are not decoded yet, and some views have no clear
        # ground: add clear walkable surfaces nearest the centre of the
        # walkable area, at least 15 m from every other spawn.
        walk = (normals[:, 1] > 0.85)
        centres = points[walk].mean(axis=1)
        area = np.linalg.norm(np.cross(points[walk, 1] - points[walk, 0], points[walk, 2] - points[walk, 0]), axis=1)
        target = (centres * area[:, None]).sum(0) / area.sum()
        for index in np.argsort(np.linalg.norm((centres - target)[:, [0, 2]], axis=1))[:6000]:
            position = centres[index]
            if area[index] < 4 or any(np.linalg.norm((np.array(s['source']) - position)[[0, 2]]) < 150 for s in result):
                continue
            y = ground(points, normals, position + [0, 0.5, 0])
            if y is not None and clear_above(points, [position[0], y, position[2]]):
                centre = sum(1 for s in result if s['name'].startswith('Map centre'))
                result.append({'name': 'Map centre' + (' %d' % (centre + 1) if centre else ''), 'source': [float(position[0]), y, float(position[2])]})
                if len(result) == 3:
                    break
    for spawn in result:
        spawn['position'] = ((np.array(spawn['source']) - origin) * SCALE).round(3).tolist()
        spawn['facing'] = open_direction(points, spawn['source'], origin)
    return result


def blender_call(maps):
    """The bounded code for the Blender MCP execute_blender_code tool. Every
    map needs a sky: all 34 have one (a sky.obj is written for each)."""
    code = (ROOT / 'tools/recovery/blender_level.py').read_text()
    code = code.replace("ROOT = '/Users/king/socom'", 'ROOT = ' + repr(str(ROOT)))
    code = code.replace("MAPS = ['__MAPS__']", 'MAPS = ' + repr(list(maps)))
    if len(code.encode()) >= 200000:
        raise ValueError('Blender call exceeds the MCP 200 KB limit')
    return code


def prepare(map_id):
    folder = LEVELS / map_id
    report = json.loads((folder / 'level-report.json').read_text())
    asset = 'recovered_map_' + map_id.lower()
    out = STAGING / map_id
    out.mkdir(parents=True, exist_ok=True)
    verts, uv, faces = read_obj(folder / 'level.obj')
    materials = read_materials(folder / 'level.obj')
    world, sky = Mesh(), Mesh()
    dropped = 0
    for ids, material, name in faces:
        if DROP.search(name):
            dropped += 1
            continue
        target = sky if SKY.search(name) or SKY_TEXTURE.match(materials.get(material, {}).get('name', '')) else world
        points = [np.r_[verts[p], uv[t]] for p, t in ids]
        for tri in triangles(points):
            target.add(material, tri)
    separate = None
    if sky.count == 0 and (separate := sky_model(map_id)):
        sky_verts, sky_uv, sky_faces = read_obj(separate)
        for key, spec in read_materials(separate).items():
            materials['sky_' + key] = spec
        for ids, material, name in sky_faces:
            for tri in triangles([np.r_[sky_verts[p], sky_uv[t]] for p, t in ids]):
                sky.add('sky_' + material, tri)
    modes = blend_modes(map_id)
    titles, runtime_materials, mtl = {}, {}, []
    for key in sorted(set(world.groups) | set(sky.groups)):
        spec = materials.get(key, {'name': key})
        texture = install_texture(spec, asset) or {}
        title = base = re.sub(r'[^A-Za-z0-9_]', '_', re.sub(r'\.(tif|png|bmp)$', '', spec['name'], flags=re.I))
        while title in runtime_materials:
            title = f'{base}_{len([t for t in runtime_materials if t.startswith(base)]) + 1}'
        titles[key] = title
        mode = modes.get(spec['name'].lower(), '') or ('ALPHACLIP' if texture.get('cutout') else 'OPAQUE')
        runtime_materials[title] = {'mode': mode, 'sky': key in sky.groups, 'translucent': texture.get('translucent', False),
                                    'texture': texture.get('source', '')}
        mtl.append(f'newmtl {title}\nKd 1 1 1\nKs 0 0 0\nillum 1\n')
        if texture:
            mtl.append(f"map_Kd {texture['image']}\n" + (f"map_d {texture['image']}\n" if texture['cutout'] else ''))
    (out / 'level.mtl').write_text(''.join(mtl))
    low, high = world.bounds()
    # Horizontal centre of the map; vertical source zero stays at Godot zero.
    origin = np.array([(low[0] + high[0]) / 2, 0.0, (low[2] + high[2]) / 2])
    world.write(out / 'world.obj', 'W_', origin, titles)
    sky_info = None
    if sky.count:
        sky_low, sky_high = sky.bounds()
        # The dome follows the camera horizontally; centre it on its own axis.
        sky_origin = np.array([(sky_low[0] + sky_high[0]) / 2, 0.0, (sky_low[2] + sky_high[2]) / 2])
        if separate is not None:
            # A separate model is authored around its own origin; seat it at the map floor.
            sky_origin[1] = 0.0
        sky.write(out / 'sky.obj', 'S_', sky_origin, titles)
        sky_info = {'triangles': sky.count, 'source': str(separate.relative_to(ROOT)) if separate else 'level',
                    'radius': round(float(max(sky_high[0] - sky_low[0], sky_high[2] - sky_low[2])) * SCALE / 2, 2),
                    'height': [round(float(sky_low[1]) * SCALE, 2), round(float(sky_high[1]) * SCALE, 2)]}
    source = json.loads(gzip.decompress((folder / 'collision.json.gz').read_bytes()))
    solid, skipped, seen = [], 0, set()
    for poly in source:
        if DROP.search(poly['path'].replace('/', '_').replace('=', '_')) or SKY.search(poly['path'].replace('/', '_')) \
                or poly['poly']['cameratype'] & 1 or poly['poly']['material'] == 11:
            skipped += 1
            continue
        for tri in triangles(list(np.array(poly['points']).reshape(-1, 3))):
            signature = tuple(sorted(tuple(np.round(v, 4)) for v in tri))
            if signature not in seen:
                seen.add(signature)
                solid.append(tri)
    solid = np.array(solid)
    lines = [f'o {asset}-colonly\n']
    for tri in solid:
        for v in tri:
            p = (v - origin) @ C.T * SCALE
            lines.append(f'v {p[0]:.4f} {p[1]:.4f} {p[2]:.4f}\n')
    lines += [f'f {i*3+1} {i*3+2} {i*3+3}\n' for i in range(len(solid))]
    (out / 'collision.obj').write_text(''.join(lines))
    spawn_list = spawns(map_id, solid, origin)
    mission_name = report['name'] if map_id.startswith('MP') else TITLES.get(map_id, map_id)
    runtime = {
        'id': map_id, 'name': ' '.join(w.capitalize() for w in mission_name.split()) if mission_name.isupper() else mission_name,
        'mode': 'Multiplayer' if map_id.startswith('MP') else 'Campaign',
        'model': f'res://art/models/{asset}.glb', 'source': report['path'], 'source_origin': origin.tolist(),
        'scale': SCALE, 'bounds': [((low - origin) * SCALE).round(2).tolist(), ((high - origin) * SCALE).round(2).tolist()],
        'kill_height': round(float(min(low[1], solid[:, :, 1].min())) * SCALE - 10, 2),
        'ambience': ambience(map_id), 'sky': sky_info, 'spawns': spawn_list, 'materials': runtime_materials,
        'counts': {'triangles': world.count, 'sky_triangles': sky.count, 'collision_triangles': len(solid),
                   'dropped_faces': dropped, 'skipped_collision_polygons': skipped},
    }
    RUNTIME.mkdir(parents=True, exist_ok=True)
    (RUNTIME / f'{map_id.lower()}.json').write_text(json.dumps(runtime, indent=1) + '\n')
    print(json.dumps({'map': map_id, 'name': runtime['name'], **runtime['counts'], 'spawns': [s['name'] for s in spawn_list],
                      'sky': sky_info and sky_info['source']}))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('maps', nargs='*')
    parser.add_argument('--all', action='store_true')
    parser.add_argument('--batch', action='store_true',
                        help='only write staging/levels/batch_call.py: one Blender call building the named, already prepared maps')
    args = parser.parse_args()
    maps = sorted(p.name for p in LEVELS.iterdir() if p.is_dir()) if args.all else [m.upper() for m in args.maps]
    if args.batch:
        missing = [m for m in maps if not (STAGING / m / 'sky.obj').exists()]
        if missing:
            raise SystemExit(f'prepare these first, or give them a sky: {missing}')
        (STAGING / 'batch_call.py').write_text(blender_call(maps))
        print(STAGING / 'batch_call.py')
        return
    for map_id in maps:
        prepare(map_id)


if __name__ == '__main__':
    main()
