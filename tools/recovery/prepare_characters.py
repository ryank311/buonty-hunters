#!/usr/bin/env python3
"""Prepare the complete recovered character/motion collection for Blender import.

Writes glTF interchange files under previous/recovery/staging, never final GLBs.
Import those with Blender MCP, save .blend sources, then use tools/dev blender
export. The target base is exported by Blender from art/blender/soldier.blend.
"""
import argparse
import collections
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import struct
from urllib.parse import quote

import numpy as np

from prepare_pilot import ROOT, RECOVERY, SCALE, materials, frame_worlds

OUT = RECOVERY / 'staging/characters'
MAP = {
    'Hips': 'hips', 'Spine': 'spinelo', 'Chest': 'spinehi',
    'Neck': 'neck', 'Head': 'head',
    'LeftShoulder': 'lscap', 'RightShoulder': 'rscap',
    'LeftUpperArm': 'lbicep', 'LeftLowerArm': 'lforearm', 'LeftHand': 'lhand',
    'RightUpperArm': 'rbicep', 'RightLowerArm': 'rforearm', 'RightHand': 'rhand',
    'LeftUpperLeg': 'lthigh', 'LeftLowerLeg': 'lcalf', 'LeftFoot': 'lfoot',
    'RightUpperLeg': 'rthigh', 'RightLowerLeg': 'rcalf', 'RightFoot': 'rfoot',
}


def read_source(entry):
    return json.loads(gzip.decompress((RECOVERY / entry.get('skin', entry['path'])).read_bytes()))


def digest(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def source_matrix(values):
    matrix = np.array(values, dtype=float).reshape(4, 4).T.copy()
    matrix[:3, 3] *= SCALE
    return matrix


def rotation(q):
    q = np.array(q, dtype=float)
    q /= np.linalg.norm(q)
    x, y, z, w = q
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])


def quaternion(matrix):
    # Symmetric eigenproblem avoids the unstable trace branch near 180 degrees.
    m = matrix[:3, :3]
    m = m / np.linalg.norm(m, axis=0)
    a, b, c = m[0]; d, e, f = m[1]; g, h, i = m[2]
    k = np.array([[a-e-i, b+d, c+g, h-f], [b+d, e-a-i, f+h, c-g],
                  [c+g, f+h, i-a-e, d-b], [h-f, c-g, d-b, a+e+i]]) / 3
    _, vectors = np.linalg.eigh(k)
    q = vectors[:, -1]
    return q if q[3] >= 0 else -q


def trs(matrix):
    return {'translation': matrix[:3, 3].tolist(), 'rotation': quaternion(matrix).tolist(),
            'scale': np.linalg.norm(matrix[:3, :3], axis=0).tolist()}


class Gltf:
    def __init__(self, data=None, binary=b''):
        self.data = data or {'asset': {'version': '2.0', 'generator': 'SOCOM recovery interchange'},
                             'scene': 0, 'scenes': [{'nodes': []}], 'nodes': [],
                             'meshes': [], 'materials': [], 'images': [], 'textures': [],
                             'bufferViews': [], 'accessors': [], 'animations': []}
        self.binary = bytearray(binary)
        self.data.setdefault('animations', [])

    def accessor(self, values, kind, dtype='<f4', bounds=False):
        array = np.asarray(values, dtype=dtype)
        if not np.isfinite(array).all():
            raise ValueError('Non-finite glTF samples')
        self.binary.extend(b'\0' * ((-len(self.binary)) % 4))
        views = self.data['bufferViews']
        view = {'buffer': 0, 'byteOffset': len(self.binary), 'byteLength': array.nbytes}
        views.append(view)
        self.binary.extend(array.tobytes())
        access = {'bufferView': len(views)-1, 'componentType': {'<f4': 5126, '<u2': 5123, '<u4': 5125}[dtype],
                  'count': len(array), 'type': kind}
        if bounds:
            access['min'] = np.atleast_1d(array.min(axis=0)).tolist()
            access['max'] = np.atleast_1d(array.max(axis=0)).tolist()
        self.data['accessors'].append(access)
        return len(self.data['accessors'])-1

    def animation(self, name, times, tracks, extras):
        anim = {'name': name, 'channels': [], 'samplers': [], 'extras': extras}
        time = self.accessor(times, 'SCALAR', bounds=True)
        short_time = None
        for node, path, samples in tracks:
            samples = np.array(samples)
            if path == 'rotation':
                for index in range(1, len(samples)):
                    if np.dot(samples[index-1], samples[index]) < 0:
                        samples[index] *= -1
            input_time = time
            if np.max(np.abs(samples - samples[0])) < 1e-7:
                samples = samples[[0, -1]]
                if short_time is None:
                    short_time = self.accessor([times[0], times[-1]], 'SCALAR', bounds=True)
                input_time = short_time
            output = self.accessor(samples, 'VEC4' if path == 'rotation' else 'VEC3')
            anim['channels'].append({'sampler': len(anim['samplers']), 'target': {'node': node, 'path': path}})
            anim['samplers'].append({'input': input_time, 'output': output, 'interpolation': 'LINEAR'})
        self.data['animations'].append(anim)

    def save(self, name):
        target = OUT / (name + '.gltf')
        binary = target.with_suffix('.bin')
        binary.write_bytes(self.binary)
        self.data['buffers'] = [{'uri': binary.name, 'byteLength': len(self.binary)}]
        target.write_text(json.dumps(self.data, separators=(',', ':')) + '\n')
        return target


def base_character(asset, skin, mats):
    doc = Gltf()
    data = doc.data
    nodes = data['nodes']
    nodes.append({'name': 'RecoveredRig', **trs(source_matrix(skin['modelMatrix'])), 'children': []})
    worlds = [source_matrix(x) for x in skin['bindWorld']]
    for part in skin['parts']:
        nodes.append({'name': part['name'], **trs(source_matrix(part['bindLocal'])), 'children': []})
    for part in skin['parts']:
        nodes[part['parent'] + 1]['children'].append(part['index'] + 1)
    data['scenes'][0]['nodes'].append(0)
    inv_bind = doc.accessor([np.linalg.inv(w).T.flatten() for w in worlds], 'MAT4')
    data['skins'] = [{'name': 'RecoveredSkeleton', 'skeleton': 0, 'joints': list(range(1, len(nodes))),
                     'inverseBindMatrices': inv_bind}]
    mat_ids = {}
    for key, spec in mats.items():
        mat = {'name': spec['name'].replace('.tif', ''), 'doubleSided': True,
               'pbrMetallicRoughness': {'metallicFactor': 0, 'roughnessFactor': 0.9}}
        if spec.get('image'):
            image = len(data['images'])
            data['images'].append({'uri': quote(os.path.relpath(spec['image'], OUT))})
            data['textures'].append({'source': image})
            mat['pbrMetallicRoughness']['baseColorTexture'] = {'index': image}
            if spec.get('cutout'):
                mat.update(alphaMode='MASK', alphaCutoff=0.5)
        mat_ids[spec['name']] = len(data['materials'])
        data['materials'].append(mat)
    max_weights, skin_error = 0, 0.0
    for sub in skin['mesh']['subMeshes']:
        positions, weights, joints = [], [], []
        for vertex in range(sub['vertexCount']):
            begin, end = sub['influenceStart'][vertex:vertex+2]
            by_bone = collections.defaultdict(float)
            point = np.zeros(3)
            total = sum(sub['influenceWeight'][begin:end])
            if total <= 0:
                raise ValueError('Unweighted vertex')
            for index in range(begin, end):
                bone, weight = sub['influenceBone'][index], sub['influenceWeight'][index] / total
                local = np.r_[np.array(sub['influencePosition'][index*3:index*3+3]) * SCALE, 1]
                point += (worlds[bone] @ local)[:3] * weight
                by_bone[bone] += weight
            influences = sorted(((bone, weight) for bone, weight in by_bone.items() if weight > 0),
                                key=lambda value: -value[1])
            max_weights = max(max_weights, len(influences))
            if len(influences) > 8:
                raise ValueError('More than eight positive influences; do not truncate')
            positions.append(point)
            joints.append([x[0] for x in influences] + [0] * (8-len(influences)))
            weights.append([x[1] for x in influences] + [0] * (8-len(influences)))
            # The recovered vertex has a separate bind-local coordinate per influence.
            # Measure whether one glTF bind position represents all of them faithfully.
            for index in range(begin, end):
                if sub['influenceWeight'][index] > 0:
                    expected = (worlds[sub['influenceBone'][index]] @ np.r_[np.array(sub['influencePosition'][index*3:index*3+3])*SCALE, 1])[:3]
                    skin_error = max(skin_error, np.linalg.norm(expected-point))
        joints, weights = np.array(joints), np.array(weights)
        attributes = {'POSITION': doc.accessor(positions, 'VEC3', bounds=True),
                      'TEXCOORD_0': doc.accessor(np.array(sub['uvs']).reshape(-1, 2), 'VEC2'),
                      'JOINTS_0': doc.accessor(joints[:, :4], 'VEC4', '<u2'),
                      'WEIGHTS_0': doc.accessor(weights[:, :4], 'VEC4')}
        if np.any(weights[:, 4:] > 0):
            attributes['JOINTS_1'] = doc.accessor(joints[:, 4:], 'VEC4', '<u2')
            attributes['WEIGHTS_1'] = doc.accessor(weights[:, 4:], 'VEC4')
        # glTF UV's top-left convention matches the raw archive, unlike OBJ.
        data['meshes'].append({'name': sub['textureName'].replace('.tif', ''), 'primitives': [{
            'attributes': attributes, 'indices': doc.accessor(sub['indices'], 'SCALAR', '<u4'),
            'material': mat_ids[sub['textureName']]}]})
        data['scenes'][0]['nodes'].append(len(nodes))
        nodes.append({'name': sub['textureName'].replace('.tif', '') + '_mesh',
                      'mesh': len(data['meshes'])-1, 'skin': 0})
    data['extras'] = {'recovered_source': asset['path'], 'source_units_to_meters': SCALE}
    return doc, {'max_positive_influences': max_weights, 'bind_influence_error_m': float(skin_error)}


def clip_category(name):
    for category, expression in [
        ('First person', r'^seal_p?fp_'), ('Death / reaction', r'death|hit|flinch|flashbang|restrain|surrender'),
        ('Traversal', r'climb|ladder|hang|ledge|jump|land|fall|slide|hopdown|dive|getup'),
        ('Weapons / equipment', r'reload|recoil|pump|throw|toss|grenade|claymore|launcher|rifle2|pistol2|knife|cqb|defuse'),
        ('Locomotion / stance', r'walk|run|jog|strafe|step|crouch$|prone$|stand$|lean|turn'),
        ('Gesture / interaction', r'signal|victory|door|switch|buddy|binocular|turret')]:
        if re.search(expression, name):
            return category
    return 'Civilian / other'


def clip_info(asset, clip, source_names):
    tracks = {part['name'] for part in clip['parts']}
    missing = sorted(set(MAP.values()) - tracks)
    root = next((p for p in clip['parts'] if p['name'] == 'skel_root'), None)
    travel = np.zeros(3) if root is None else (np.array(root['translations'][-3:])-root['translations'][:3])*SCALE
    return {'name': asset['name'], 'source': asset['path'], 'duration': clip['duration'],
            'frames': clip['frameCount'], 'category': clip_category(asset['name']),
            'partial': bool(missing), 'missing_body_tracks': missing,
            'extra_tracks': sorted(tracks-set(source_names)), 'root_travel_m': travel.tolist(),
            'review': 'Native motion for inspection; event timing and gameplay layering require review'}


def original_animation(doc, skin, clip, info):
    tracks = {p['name']: p for p in clip['parts']}
    count = clip['frameCount'] + 1
    samples = []
    for part in skin['parts']:
        track = tracks.get(part['name'])
        bind = source_matrix(part['bindLocal'])
        ts = np.tile(bind[:3, 3], (count, 1))
        qs = np.tile(quaternion(bind), (count, 1))
        if track:
            ts = np.array(track['translations']).reshape(-1, 3) * SCALE
            qs = np.array(track['rotations'], dtype=float).reshape(-1, 4)
            if len(ts) == 1:
                ts = np.repeat(ts, count, axis=0)
            if len(qs) == 1:
                qs = np.repeat(qs, count, axis=0)
            if len(ts) != count or len(qs) != count:
                raise ValueError('Unexpected track sample count: ' + clip['name'])
            qs /= np.linalg.norm(qs, axis=1)[:, None]
            if part['name'] == 'skel_root':
                ts[:, [0, 2]] = bind[[0, 2], 3]
        samples.extend([(part['index']+1, 'translation', ts), (part['index']+1, 'rotation', qs)])
    doc.animation(clip['name'], np.linspace(0, clip['duration'], count), samples,
                  {'source': info['source'], 'root_motion': 'in_place', 'partial': info['partial']})


def read_glb(path):
    blob = path.read_bytes()
    magic, version, size = struct.unpack_from('<III', blob)
    assert magic == 0x46546c67 and version == 2 and size == len(blob)
    offset, data, binary = 12, None, None
    while offset < size:
        length, kind = struct.unpack_from('<II', blob, offset)
        value = blob[offset+8:offset+8+length]
        if kind == 0x4e4f534a:
            data = json.loads(value)
        elif kind == 0x004e4942:
            binary = value
        offset += 8+length
    return Gltf(data, binary)


def target_bind(doc):
    nodes = doc.data['nodes']
    local, parents = [], {}
    for index, node in enumerate(nodes):
        mat = np.array(node.get('matrix', np.eye(4).T.flatten())).reshape(4, 4).T.copy()
        if 'matrix' not in node:
            mat[:3, :3] = rotation(node.get('rotation', [0, 0, 0, 1])) @ np.diag(node.get('scale', [1, 1, 1]))
            mat[:3, 3] = node.get('translation', [0, 0, 0])
        local.append(mat)
        parents.update({child: index for child in node.get('children', [])})
    worlds = {}
    def world(index):
        if index not in worlds:
            worlds[index] = (world(parents[index]) if index in parents else np.eye(4)) @ local[index]
        return worlds[index]
    for index in range(len(nodes)):
        world(index)
    ids = {n['name']: i for i, n in enumerate(nodes) if n.get('name') in MAP}
    assert len(ids) == len(MAP), ids
    order = sorted(ids.values(), key=lambda i: _depth(i, parents))
    return local, parents, worlds, ids, order


def _depth(index, parents):
    return 1 + _depth(parents[index], parents) if index in parents else 0


def retarget(doc, skin, clip, info, binding):
    local, parents, rest, ids, order = binding
    source_ids = {part['name']: part['index'] for part in skin['parts']}
    source_bind = [source_matrix(w) for w in skin['bindWorld']]
    corrections = {index: np.linalg.inv(source_bind[source_ids[MAP[name]]][:3, :3]) @ rest[index][:3, :3]
                   for name, index in ids.items()}
    hip = ids['Hips']
    source_hip = source_ids['hips']
    ratio = rest[hip][1, 3] / source_bind[source_hip][1, 3]
    ts, qs = {i: [] for i in order}, {i: [] for i in order}
    names = {i: name for name, i in ids.items()}
    for frame in range(clip['frameCount']+1):
        source = [np.array(value, dtype=float) for value in frame_worlds(skin, clip, frame)]
        for value in source:
            value[:3, 3] *= SCALE
        posed = dict(rest)
        for index in order:
            value = np.eye(4)
            value[:3, :3] = source[source_ids[MAP[names[index]]]][:3, :3] @ corrections[index]
            parent = posed[parents[index]] if index in parents else np.eye(4)
            value[:3, 3] = (parent @ np.r_[local[index][:3, 3], 1])[:3]
            if index == hip:
                value[:3, 3] = rest[index][:3, 3] + (source[source_hip][:3, 3]-source_bind[source_hip][:3, 3])*ratio
            posed[index] = value
            pose = np.linalg.inv(parent) @ value
            ts[index].append(pose[:3, 3])
            qs[index].append(quaternion(pose))
    samples = [(i, path, values[i]) for i in order for path, values in [('translation', ts), ('rotation', qs)]]
    doc.animation(clip['name'], np.linspace(0, clip['duration'], clip['frameCount']+1), samples,
                  {'source': info['source'], 'root_motion': 'in_place', 'partial': info['partial'],
                   'retarget': 'global bind rotation correction, target segment lengths, scaled hip travel'})


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--characters-only', action='store_true')
    ap.add_argument('--motions-only', action='store_true', help='Reuse the prepared character manifest')
    ap.add_argument('--legacy-retarget', action='store_true', help='Also rebuild the retired prototype-rig experiment')
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    assets = json.loads((RECOVERY/'reports/assets.json').read_text())
    character_groups, motion_groups = {}, {}
    for asset in assets:
        if asset['type'] not in ('character', 'animation'):
            continue
        if args.motions_only and asset['type'] == 'character' and asset['name'] != 'seal_A_scuba':
            continue
        raw = read_source(asset)
        if asset['type'] == 'character':
            relevant = {k: raw[k] for k in ['modelMatrix', 'bindWorld']}
            relevant['parts'] = [{k: p[k] for k in ['index', 'name', 'parent', 'bindLocal']} for p in raw['parts']]
            relevant['mesh'] = raw['mesh']['subMeshes']
            mats = materials(RECOVERY/asset['path'], 'recovered_characters')
            relevant['textures'] = {m['name']: m.get('sha256') for m in mats.values()}
            key = digest(relevant)
            group = character_groups.setdefault(key, {'asset': asset, 'skin': raw, 'materials': mats, 'occurrences': []})
        else:
            key = digest({k: v for k, v in raw.items() if k != 'name'})
            group = motion_groups.setdefault(key, {'asset': asset, 'clip': raw, 'occurrences': []})
        group['occurrences'].append({'name': asset['name'], 'source': asset['source'], 'path': asset['path']})
    manifest = {'scale': SCALE, 'legacy_bone_map': MAP, 'characters': [], 'motions': [], 'errors': []}
    if args.motions_only:
        manifest = json.loads((OUT/'character_manifest.json').read_text())
        manifest['motions'] = []
        manifest['legacy_bone_map'] = manifest.pop('bone_map', manifest.get('legacy_bone_map', MAP))
    used = set()
    for key, group in sorted(character_groups.items(), key=lambda pair: pair[1]['asset']['name'].lower()):
        if args.motions_only:
            break
        asset, skin = group['asset'], group['skin']
        name = 'recovered_char_' + re.sub(r'[^a-z0-9_]', '_', asset['name'].lower())
        if name in used:
            name += '_' + key[:8]
        used.add(name)
        try:
            doc, quality = base_character(asset, skin, group['materials'])
            doc.save(name)
            manifest['characters'].append({'name': asset['name'], 'id': name, 'path': 'res://art/models/'+name+'.glb',
                'source': asset['path'], 'triangles': asset['triangles'], 'bones': len(skin['parts']),
                'occurrences': group['occurrences'], **quality})
        except Exception as error:
            manifest['errors'].append({'name': asset['name'], 'error': str(error)})
    print('Prepared characters:', len(manifest['characters']), 'errors:', len(manifest['errors']), flush=True)
    (OUT/'character_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    if not args.characters_only:
        group = next(g for g in character_groups.values() if g['asset']['name'] == 'seal_A_scuba')
        skin = group['skin']
        original, _ = base_character(group['asset'], skin, group['materials'])
        target = read_glb(OUT/'soldier_base.glb') if args.legacy_retarget else None
        for image in target.data.get('images', []) if target else []:
            texture = ROOT/'art/blender/textures/soldier'/(image['name']+'.png')
            if not texture.is_file():
                raise ValueError('Missing original player texture: ' + str(texture))
            image.pop('bufferView', None)
            image['uri'] = quote(os.path.relpath(texture, OUT))
        binding = target_bind(target) if target else None
        names = [p['name'] for p in skin['parts']]
        for group in sorted(motion_groups.values(), key=lambda group: group['asset']['name']):
            asset, clip = group['asset'], group['clip']
            info = clip_info(asset, clip, names)
            original_animation(original, skin, clip, info)
            if target:
                retarget(target, skin, clip, info, binding)
            info['occurrences'] = group['occurrences']
            manifest['motions'].append(info)
            if len(manifest['motions']) % 50 == 0:
                print('Prepared motions:', len(manifest['motions']), flush=True)
        original.save('recovered_motion_library')
        if target:
            target.save('soldier_recovered')
    manifest['counts'] = {'source_characters': sum(a['type'] == 'character' for a in assets),
                          'source_motions': sum(len(g['occurrences']) for g in motion_groups.values()),
                          'characters': len(manifest['characters']), 'motions': len(manifest['motions']),
                          'partial_motions': sum(m['partial'] for m in manifest['motions'])}
    (OUT/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    (ROOT/'resources/recovered/catalogue.json').write_text(json.dumps(manifest, separators=(',', ':'))+'\n')
    print(json.dumps(manifest['counts']), flush=True)
    if manifest['errors']:
        raise SystemExit(json.dumps(manifest['errors']))


if __name__ == '__main__':
    main()
