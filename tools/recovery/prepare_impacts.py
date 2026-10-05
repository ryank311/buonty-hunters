#!/usr/bin/env python3
"""Decode the original bullet impacts into resources/recovered/impacts.json.

Surfaces: materials.rdr's SOILS table names every surface; a collision polygon's
material id is its SOILS index + 2, and id 0 is the map's DefaultMaterial. Each
surface plays bullet_hit_<name> from MZANIM.ZAR (Anim_Sets/mission), which may
just alias another (plaster and carpet play stone's with their own sound).

Effects: each bullet_hit_* sequence spawns particle emitters. An emitter record
starts with a word 1b00xxxx; at fixed word offsets from it are the particle count
(+8), direction jitter per axis in degrees (+14..+19), drag (+32), acceleration in
source units/s^2 (+33..+35), launch speed (+36), life min/max seconds (+39, +40)
and size min/max in source units (+43, +44). The texture reference follows, then
three colour keys (time, r, g, b, a). The meaning of the remaining fields is not
decoded; these are the ones a port needs.

Textures the emitters use are copied to art/effects/impacts/.
Run with previous/recovery/.venv/bin/python from the repository root.
"""
import json
from pathlib import Path
import re
import shutil
import struct

ROOT = Path(__file__).resolve().parents[2]
RECOVERY = ROOT / 'previous/recovery'
OUT = ROOT / 'resources/recovered/impacts.json'
TEXTURES = ROOT / 'art/effects/impacts'
SCALE = 0.1
# Surfaces with no bullet_hit_* of their own, by the nearest that has one.
FALLBACK = {'GRASS_VOL': 'grass', 'BUSH_VOL': 'leaves', 'SNOWY_GRASS_VOL': 'snow', 'SNOWY_TREE': 'snow',
            'UNDERWATER': 'water', 'METAL_RAILING': 'metal_thin', 'METAL_GRATE': 'metal_thick',
            'METAL_GRATE_THIN': 'metal_thin', 'CHAINLINK_FENCE': 'metal_thin', 'CAMO_NET': 'fabric_heavy',
            'ITEM': 'wood_thin', 'GLASS': 'glass', 'GLASS_THICK': 'glass', 'GLASS_OPAQUE': 'glass',
            'GLASS_MEDIUM': 'glass', 'BROKEN GLASS': 'glass'}
# Bullets pass through these (SOILS opacity 0, penetration 1): no impact at all.
NO_IMPACT = {'ACTION', 'INVISIBLE_DI'}


def soils():
    record = json.loads(next((RECOVERY / 'native/scripts/disc').glob('READERC.ZAR-*/*-materials.rdr.json')).read_text())
    return re.findall(r'"NAME", \["([^"]*)"\]', json.dumps(record))


def effects():
    index = json.loads(next((RECOVERY / 'native/indexes').glob('MZANIM.ZAR-*.json')).read_text())
    data = (RECOVERY / index['source']).read_bytes()

    def find(node, path):
        for part in path:
            node = next(c for c in node['children'] if c['name'] == part)
        return node

    def blob(node):
        return data[index['dataOffset'] + node['offset']:index['dataOffset'] + node['offset'] + node['size']]

    mission = find(index['root'], ['Anim_Sets', 'mission'])
    names = [c['name'] for c in find(mission, ['Name_Table'])['children']]
    result = {}
    for anim in find(mission, ['Animation_List'])['children']:
        if not anim['name'].startswith('bullet_hit_'):
            continue
        parts = {c['name']: c for c in anim['children']}
        count = struct.unpack('<I', blob(parts['Name_Index_Table_Count']))[0]
        refs = [names[i] for i in struct.unpack('<%dH' % count, blob(parts['Name_Index_Table'])[:2 * count])]
        result[anim['name']] = {'refs': refs, 'seq': blob(parts['Seq_Data']) if 'Seq_Data' in parts else b''}
    return result


def emitters(effect):
    seq, refs = effect['seq'], effect['refs']
    words = [seq[i:i + 4] for i in range(0, len(seq) - 3, 4)]
    as_float = [struct.unpack('<f', w)[0] for w in words]
    as_int = [struct.unpack('<I', w)[0] for w in words]
    layers = []
    for start, word in enumerate(words):
        if word[0] != 0x1b or word[1] != 0 or start + 60 > len(words):
            continue
        node = refs[words[start + 3][0]] if words[start + 3][0] < len(refs) else ''
        texture = None
        for j in range(start + 45, min(start + 75, len(words))):
            if 0 < as_int[j] < len(refs) and refs[as_int[j]].endswith('.tif'):
                texture = j
                break
        if texture is None:
            continue
        # Two or three keys; the first is at time 0. Stop at the first that is not a key.
        keys = []
        for k in range(3):
            base = texture + 2 + k * 5
            t, r, g, b, a = as_float[base:base + 5]
            t = 0.0 if k == 0 else t
            valid = all(0.0 <= v <= 1.001 for v in (t, r, g, b, a)) and (not keys or t > keys[-1][0])
            if not valid:
                break
            keys.append([round(t, 3), round(r, 3), round(g, 3), round(b, 3), round(a, 3)])
        layers.append({
            'node': node,
            'texture': refs[as_int[texture]].replace('.tif', ''),
            'count': int(round(as_float[start + 8])),
            'spread_deg': [round(v, 2) for v in as_float[start + 14:start + 20]],
            'drag': round(as_float[start + 32], 4),
            'acceleration': [round(v * SCALE, 3) for v in as_float[start + 33:start + 36]],
            'speed': round(as_float[start + 36] * SCALE, 3),
            'life': [round(as_float[start + 39], 3), round(as_float[start + 40], 3)],
            'size': [round(as_float[start + 43] * SCALE, 3), round(as_float[start + 44] * SCALE, 3)],
            'colors': keys,
        })
    return layers


def main():
    names = soils()
    effect_data = effects()
    resolved, sounds = {}, {}

    def resolve(effect):
        refs = effect_data[effect]['refs']
        alias = next((r for r in refs[2:] if r.startswith('bullet_hit_') and r != effect), None)
        return alias if alias and alias in effect_data and not emitters(effect_data[effect]) else effect

    surfaces = {}
    for index, name in enumerate(names):
        key = name.lower().replace(' ', '_')
        if name in NO_IMPACT:
            surfaces[key] = {'id': index + 2, 'effect': None, 'sound': None}
            continue
        effect = 'bullet_hit_' + key
        if effect not in effect_data:
            effect = 'bullet_hit_' + FALLBACK.get(name, 'stone')
        if effect not in effect_data:
            effect = 'bullet_hit_stone'
        sound = next((r for r in effect_data[effect]['refs'] if r.startswith('.')), None)
        target = resolve(effect)
        surfaces[key] = {'id': index + 2, 'effect': target, 'sound': sound}
        resolved[target] = True
    library = {}
    TEXTURES.mkdir(parents=True, exist_ok=True)
    for effect in sorted(resolved):
        layers = emitters(effect_data[effect])
        library[effect] = layers
        for layer in layers:
            source = next((RECOVERY / 'converted/textures').glob(f"effects/*/*/{layer['texture']}.tif.png"), None)
            if source is not None:
                shutil.copyfile(source, TEXTURES / (layer['texture'] + '.png'))
            else:
                layer['texture'] = None
    OUT.write_text(json.dumps({'source': 'materials.rdr SOILS (collision id = index + 2; 0 = the map DefaultMaterial), '
                                         'MZANIM.ZAR Anim_Sets/mission bullet_hit_*',
                               'surfaces': surfaces, 'effects': library}, indent=1) + '\n')
    for effect, layers in library.items():
        print(effect, [(l['node'], l['texture'], l['count'], l['speed'], l['life'], l['size']) for l in layers])
    print(len(surfaces), 'surfaces,', len(library), 'effects ->', OUT.relative_to(ROOT))


if __name__ == '__main__':
    main()
