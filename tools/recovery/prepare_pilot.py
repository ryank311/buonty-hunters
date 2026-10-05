#!/usr/bin/env python3
"""Prepare a small, repeatable Blender pilot from the recovered disc collection.

Run with previous/recovery/.venv/bin/python. Blender itself is only driven through
the MCP server, using blender_pilot.py; this step only prepares source data/images.
"""
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
STAGING = RECOVERY / 'staging/pilot'
SCALE = 0.1
CENTER = np.array([1275.0, 43.5, 1445.0])
HALF_WIDTH = 300.0
C = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], dtype=float)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, separators=(',', ':')) + '\n')


def materials(obj, asset_name):
    result = {}
    key = None
    for line in obj.with_suffix('.mtl').read_text().splitlines():
        if line.startswith('newmtl '):
            key = line.split()[1]
            result[key] = {'name': key}
        elif line.startswith('# ') and key:
            result[key]['name'] = line[2:]
        elif line.startswith('map_Kd '):
            source = (obj.parent / line[7:]).resolve()
            sha = hashlib.sha256(source.read_bytes()).hexdigest()
            target = ROOT / 'art/blender/textures' / asset_name / (sha[:10] + '_' + source.name)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            with Image.open(source) as im:
                alpha = np.array(im.convert('RGBA'))[:, :, 3]
                result[key]['cutout'] = bool(np.min(alpha) < 128)
            result[key].update(image=str(target), source=str(source.relative_to(ROOT)), sha256=sha)
    return result


def read_obj(path):
    vertices, uv, faces = [], [], []
    name, material = '', ''
    for line in path.read_text().splitlines():
        words = line.split()
        if not words:
            continue
        if words[0] == 'v':
            vertices.append([float(x) for x in words[1:4]])
        elif words[0] == 'vt':
            uv.append([float(x) for x in words[1:3]])
        elif words[0] == 'o':
            name = ' '.join(words[1:])
        elif words[0] == 'usemtl':
            material = words[1]
        elif words[0] == 'f':
            ids = [[int(x)-1 for x in w.split('/')] for w in words[1:]]
            faces.append((ids, material, name))
    return np.array(vertices), np.array(uv), faces


def clip_polygon(points):
    """Sutherland-Hodgman, retaining interpolated UVs as well as positions."""
    for axis in (0, 2):
        for sign in (-1, 1):
            plane = CENTER[axis] + sign * HALF_WIDTH
            clipped = []
            for i, end in enumerate(points):
                start = points[i-1]
                ds, de = sign*(start[axis]-plane), sign*(end[axis]-plane)
                if (ds <= 0) != (de <= 0):
                    clipped.append(start+(end-start)*(ds/(ds-de)))
                if de <= 0:
                    clipped.append(end)
            points = clipped
            if not points:
                return []
    return points


def excluded(name):
    return bool(re.search(r'destroyed|_shadow|_pulse|healthy_explosive', name, re.I))


def triangulate(points):
    for i in range(1, len(points)-1):
        tri = np.array([points[0], points[i], points[i+1]])
        if np.linalg.norm(np.cross(tri[1, :3]-tri[0, :3], tri[2, :3]-tri[0, :3])) > 1e-7:
            yield tri


def prepare_static(asset, name, crop=False):
    path = RECOVERY / asset['path']
    verts, uv, faces = read_obj(path)
    mats = materials(path, name)
    chunks, seen = {}, set()
    center = CENTER if crop else np.array([(verts[:, 0].min()+verts[:, 0].max())/2, verts[:, 1].min(), 0])
    # Source rifle muzzle points +X. Rotate it to Blender +Y / Godot -Z.
    conversion = C if crop else np.array([[0, 0, 1], [1, 0, 0], [0, 1, 0]], dtype=float)
    for ids, material, label in faces:
        if crop and (excluded(label) or re.search(r'sky|cloud|moon|stars', mats[material]['name'], re.I)):
            continue
        points = [np.r_[verts[p], uv[t]] for p, t in ids]
        if crop:
            points = clip_polygon(points)
        for tri in triangulate(points):
            signature = (material, tuple(sorted(tuple(np.round(v, 6)) for v in tri)))
            if signature in seen:
                continue
            seen.add(signature)
            chunk = chunks.setdefault(material, {'name': material, 'material': material, 'vertices': [], 'uv': [], 'faces': []})
            base = len(chunk['vertices'])
            chunk['vertices'].extend(((tri[:, :3]-center) @ conversion.T * SCALE).tolist())
            chunk['uv'].extend(tri[:, 3:].tolist())
            chunk['faces'].append([base, base+1, base+2])
    used = {k: mats[k] for k in chunks}
    data = {'name': name, 'source': asset, 'scale': SCALE, 'source_origin': center.tolist(),
            'materials': used, 'meshes': list(chunks.values())}
    if crop:
        vertices, triangles, seen = [], [], set()
        source = json.loads(gzip.decompress((path.parent / 'collision.json.gz').read_bytes()))
        skipped = 0
        for poly in source:
            # Camera/trigger volumes and water surfaces are not solid walking geometry.
            if excluded(poly['path']) or poly['poly']['cameratype'] & 1 or poly['poly']['material'] == 11:
                skipped += 1
                continue
            points = clip_polygon(list(np.array(poly['points']).reshape(-1, 3)))
            for tri in triangulate(points):
                signature = tuple(sorted(tuple(np.round(v, 6)) for v in tri))
                if signature in seen:
                    continue
                seen.add(signature)
                base = len(vertices)
                vertices.extend(((tri-CENTER) @ C.T*SCALE).tolist())
                triangles.append([base, base+1, base+2])
        data['collision'] = {'vertices': vertices, 'faces': triangles, 'skipped_non_solid_polygons': skipped}
    write_json(STAGING / (name+'.json'), data)
    return {'asset': name, 'source': asset['path'], 'triangles': sum(len(m['faces']) for m in chunks.values()),
            'materials': len(used), 'collision_triangles': len(data.get('collision', {}).get('faces', []))}


def frame_worlds(skin, clip, frame):
    tracks = {p['name']: p for p in clip['parts']}
    worlds = []
    for part in skin['parts']:
        track = tracks.get(part['name'])
        local = np.array(part['bindLocal']).reshape(4, 4).T.copy()
        if track:
            ts, qs = track['translations'], track['rotations']
            t = np.array(ts[0:3] if len(ts) == 3 else ts[frame*3:frame*3+3], dtype=float)
            q = np.array(qs[0:4] if len(qs) == 4 else qs[frame*4:frame*4+4], dtype=float)
            q /= np.linalg.norm(q)
            x, y, z, w = q
            local[:3, :3] = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                             [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                             [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]
            if part['name'] == 'skel_root':
                # Inspection clips run in place. Preserve vertical movement and archive keys.
                t[[0, 2]] = [part['bindLocal'][12], part['bindLocal'][14]]
            local[:3, 3] = t
        parent = worlds[part['parent']] if part['parent'] >= 0 else np.array(skin['modelMatrix']).reshape(4, 4).T
        worlds.append(parent @ local)
    return worlds


def skin_positions(sub, worlds):
    result = []
    starts, bones, weights = sub['influenceStart'], sub['influenceBone'], sub['influenceWeight']
    positions = np.array(sub['influencePosition']).reshape(-1, 3)
    for i in range(sub['vertexCount']):
        value = np.zeros(3)
        for j in range(starts[i], starts[i+1]):
            value += (worlds[bones[j]] @ np.r_[positions[j], 1])[:3] * weights[j]
        value /= sum(weights[starts[i]:starts[i+1]])
        result.append((C @ value * SCALE).tolist())
    return result


def prepare_character(asset, assets):
    name = 'recovered_seal'
    skin = json.loads(gzip.decompress((RECOVERY/asset['skin']).read_bytes()))
    mats = materials(RECOVERY/asset['path'], name)
    bind = [np.array(b).reshape(4, 4).T for b in skin['bindWorld']]
    meshes = []
    for sub in skin['mesh']['subMeshes']:
        key = next(k for k, m in mats.items() if m['name'] == sub['textureName'])
        weights = []
        for i in range(sub['vertexCount']):
            start, end = sub['influenceStart'][i:i+2]
            total = sum(sub['influenceWeight'][start:end])
            weights.append([[sub['influenceBone'][j], sub['influenceWeight'][j]/total] for j in range(start, end)])
        meshes.append({'name': sub['textureName'].replace('.tif', ''), 'material': key,
                       'vertices': skin_positions(sub, bind),
                       'faces': np.array(sub['indices']).reshape(-1, 3).tolist(),
                       'uv': [[u, 1-v] for u, v in np.array(sub['uvs']).reshape(-1, 2)], 'weights': weights})
    clips, references = [], []
    for clip_name in ['seal_stand', 'seal_walk', 'seal_run', 'seal_crouch']:
        entry = next(a for a in assets if a['type'] == 'animation' and a['name'] == clip_name)
        clip = json.loads(gzip.decompress((RECOVERY/entry['path']).read_bytes()))
        clip['source'] = entry['path']
        clips.append(clip)
        for frame in [0, clip['frameCount']//4, clip['frameCount']//2]:
            worlds = frame_worlds(skin, clip, frame)
            references.append({'clip': clip_name, 'frame': frame+1,
                               'positions': [skin_positions(sub, worlds) for sub in skin['mesh']['subMeshes']]})
    data = {'name': name, 'source': asset, 'scale': SCALE, 'materials': mats, 'meshes': meshes,
            'parts': skin['parts'], 'bindWorld': skin['bindWorld'], 'modelMatrix': skin['modelMatrix'],
            'clips': clips, 'references': references, 'max_influences': skin['mesh']['maxInfluences']}
    write_json(STAGING/(name+'.json'), data)
    return {'asset': name, 'source': asset['path'], 'bones': len(skin['parts']),
            'triangles': asset['triangles'], 'clips': [c['name'] for c in clips],
            'max_influences': skin['mesh']['maxInfluences']}


def blender_input(name):
    """Use Blender's approved OBJ importer for large static data, inline JSON for rigs."""
    data = json.loads((STAGING/(name+'.json')).read_text())
    if data.get('parts'):
        for sample in data['references']:
            indices = [sorted(set(np.linspace(0, len(p)-1, min(32, len(p))).astype(int).tolist())) for p in sample['positions']]
            sample['positions'] = [[p[i] for i in ids] for p, ids in zip(sample['positions'], indices)]
            sample['indices'] = indices
    else:
        obj = STAGING/(name+'.obj')
        rows, base = [], 1
        for mesh in data['meshes']:
            rows.append('o '+mesh['name'])
            rows.extend('v '+' '.join(str(x) for x in p) for p in mesh['vertices'])
            rows.extend('vt '+' '.join(str(x) for x in p) for p in mesh['uv'])
            rows.extend('f '+' '.join(f'{i+base}/{i+base}' for i in face) for face in mesh['faces'])
            base += len(mesh['vertices'])
        obj.write_text('\n'.join(rows)+'\n')
        data['obj'] = str(obj)
        data['meshes'] = [{k: v for k, v in m.items() if k in ('name', 'material')} for m in data['meshes']]
        if data.get('collision'):
            helper = STAGING/(name+'_collision.obj')
            coll = data['collision']
            rows = ['o RecoveredPlaza-colonly']
            rows.extend('v '+' '.join(str(x) for x in p) for p in coll['vertices'])
            rows.extend('f '+' '.join(str(i+1) for i in face) for face in coll['faces'])
            # Godot must enable ConcavePolygonShape3D.backface_collision for PS2
            # probe semantics. Opposite duplicate faces are removed by Blender.
            helper.write_text('\n'.join(rows)+'\n')
            data['collision'] = {'obj': str(helper)}
    write_json(STAGING/(name+'.blender.json'), data)


def main():
    assets = json.loads((RECOVERY/'reports/assets.json').read_text())
    weapon = next(a for a in assets if a['type'] == 'model' and a['name'] == 'm4Acarbine' and '/M83/' in a['path'])
    character = next(a for a in assets if a['type'] == 'character' and a['name'] == 'seal_A_scuba')
    level = next(a for a in assets if a['type'] == 'level' and a['context'] == 'MP72')
    reports = [prepare_static(weapon, 'recovered_m4'), prepare_character(character, assets),
               prepare_static(level, 'recovered_crossroads', crop=True)]
    write_json(STAGING/'manifest.json', {'scale': SCALE, 'plaza_origin': CENTER.tolist(),
               'crop_half_width': HALF_WIDTH, 'assets': reports})
    for report in reports:
        blender_input(report['asset'])
    print(json.dumps(reports, indent=2))


if __name__ == '__main__':
    main()
