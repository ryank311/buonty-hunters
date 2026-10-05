#!/usr/bin/env python3
"""Decode the original muzzle flashes into resources/recovered/muzzle_flashes.json.

Each weapon entry also carries its Sound_Radius (zweapon.rdr; read as metres: rifles
100-170, pistols 45-80, suppressed guns 4-40) and whether it is suppressed (its fire
sequence shows no flash and it is quieter than 45 m), which
decide tracers and who hears the shot. The tracer streak texture (EFFE_TXR
tracer.tif: a red row and a green row, bright at the head) is copied to
art/effects/recovered_tracer.png.

Each weapon record in ZWEAPON.ZAR (zweapon.rdr) names a FireAnimName such as
muzzle_glock. That zAnim sequence (CZANIM.ZAR, Anim_Sets/common) spawns a
flash_fire_* effect, which in turn shows one of three flash models
(muzzle_flash_m4, _hider, _break from EFFE_MDL) with a random roll and one of
three random sizes, and a short muzzle light. The sequence bytecode is not fully
decoded; this reads the parts it needs by their opcodes:

  13005200 01000200 <angle>          a roll choice (radians), picked uniformly
  38000000 <seconds> <from xyz> <to xyz> <...>   a scale choice: grow over <seconds>
  2000xx01 ... <r g b a> ... <seconds> ... <inner outer>   the light (source units)

Run with python3 from the repository root; needs previous/recovery/.
"""
import json
from pathlib import Path
import re
import shutil
import struct

ROOT = Path(__file__).resolve().parents[2]
RECOVERY = ROOT / 'previous/recovery'
OUT = ROOT / 'resources/recovered/muzzle_flashes.json'
TRACER = ROOT / 'art/effects/recovered_tracer.png'
# The suppressed guns' Sound_Radius is 4-40; the quietest open gun's is 45.
QUIET_BELOW = 45.0
SCALE = 0.1


def zanim():
    index = json.loads(next((RECOVERY / 'native/indexes').glob('CZANIM.ZAR-*.json')).read_text())
    data = (RECOVERY / index['source']).read_bytes()

    def find(node, path):
        for part in path:
            node = next(c for c in node['children'] if c['name'] == part)
        return node

    def blob(node):
        return data[index['dataOffset'] + node['offset']:index['dataOffset'] + node['offset'] + node['size']]

    common = find(index['root'], ['Anim_Sets', 'common'])
    names = [c['name'] for c in find(common, ['Name_Table'])['children']]
    anims = {}
    for anim in find(common, ['Animation_List'])['children']:
        parts = {c['name']: c for c in anim['children']}
        count = struct.unpack('<I', blob(parts['Name_Index_Table_Count']))[0]
        refs = [names[i] for i in struct.unpack('<%dH' % count, blob(parts['Name_Index_Table'])[:2 * count])]
        anims[anim['name']] = {'refs': refs, 'seq': blob(parts['Seq_Data']) if 'Seq_Data' in parts else b''}
    return anims


def words(seq):
    return [seq[i:i + 4] for i in range(0, len(seq) - 3, 4)]


def floats(ws):
    return [struct.unpack('<f', w)[0] for w in ws]


def flash(anim):
    ws = words(anim['seq'])
    hexes = [w.hex() for w in ws]
    model = next(r for r in anim['refs'] if r.startswith('muzzle_flash'))
    rolls = [round(floats([ws[i + 2]])[0], 4) for i in range(len(ws) - 2) if hexes[i] == '13005200' and hexes[i + 1] == '01000200']
    sizes, grow = [], 0.05
    for i, h in enumerate(hexes):
        if h == '38000000':
            grow, _, _, _, size = floats(ws[i + 1:i + 6])
            sizes.append(round(size, 3))
    light = next(i for i, h in enumerate(hexes) if re.fullmatch(r'2000[0-9a-f]{2}01', h))
    values = [f for f in floats(ws[light + 1:]) if 1e-3 < abs(f) < 1e4]
    r, g, b, a, seconds = values[:5]
    inner, outer = values[8], values[9]
    return {
        'model': model,
        # Unique rolls; the original weighs each choice equally (1/8, 1/7, ... 1/2).
        'rolls': sorted(set(rolls + [0.0])),
        'sizes': sizes,
        'grow_seconds': round(grow, 3),
        'light': {'color': [round(r / 255, 3), round(g / 255, 3), round(b / 255, 3)], 'strength': round(a / 128, 3),
                  'seconds': round(seconds, 3), 'range_m': [round(inner * SCALE, 2), round(outer * SCALE, 2)]},
    }


def main():
    anims = zanim()
    record = json.loads(next((RECOVERY / 'native/scripts/disc').glob('ZWEAPON.ZAR-*/*-zweapon.rdr.json')).read_text())
    text = json.dumps(record)
    weapons = {}
    flashes = {}
    for name, radius, model, fire in re.findall(r'"InternalName", \["([^"]*)"\].*?"Sound_Radius", \["([^"]*)"\].*?"ModelName", \["([^"]*)"\], "FireAnimName", \["([^"]*)"\]', text):
        if not fire.startswith('muzzle_') or fire not in anims:
            continue
        effect = next((r for r in anims[fire]['refs'] if r in ('flash_fire', 'shotgun_fire') or r.startswith('flash_fire_')), None)
        if effect and effect not in flashes:
            flashes[effect] = flash(anims[effect])
        entry = {'weapon': name, 'fire_anim': fire, 'flash': effect, 'sound_radius_m': float(radius),
                 # A suppressed gun has no flash in its fire sequence and is quiet; the
                 # SR-25 and the turrets also lack a flash_fire but are loud.
                 'suppressed': effect is None and float(radius) < QUIET_BELOW}
        weapons.setdefault(model.lower(), []).append(entry)
    TRACER.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(next((RECOVERY / 'converted/textures/effects').glob('*/EFFE_TXR-*/tracer.tif.png')), TRACER)
    OUT.write_text(json.dumps({'source': 'ZWEAPON.ZAR zweapon.rdr FireAnimName -> CZANIM.ZAR Anim_Sets/common',
                               'flashes': flashes, 'weapons': weapons}, indent=1) + '\n')
    for effect, spec in sorted(flashes.items()):
        print(effect, spec)
    print(len(weapons), 'weapon models ->', OUT.relative_to(ROOT))


if __name__ == '__main__':
    main()
