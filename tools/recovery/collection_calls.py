#!/usr/bin/env python3
"""Generate bounded, reviewable Blender MCP recipes; does not launch Blender."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--base', action='store_true', help='Prepare the player base export, before prepare_characters.py')
    ap.add_argument('--batch-size', type=int, default=25)
    ap.add_argument('--legacy-retarget', action='store_true')
    args = ap.parse_args()
    if args.batch_size < 1 or args.batch_size > 40:
        ap.error('Use batches of 1–40 models')
    staging = ROOT/'previous/recovery/staging/characters'
    folder = staging/'calls'
    folder.mkdir(parents=True, exist_ok=True)
    if args.base:
        code = 'import bpy\n'
        code += 'bpy.ops.wm.open_mainfile(filepath='+repr(str(ROOT/'art/blender/soldier.blend'))+')\n'
        code += 'bpy.ops.export_scene.gltf(filepath='+repr(str(staging/'soldier_base.glb'))+', export_animations=False, export_extras=True, export_all_influences=True)\n'
        path = folder/'base.py'
        path.write_text(code)
        print(path)
        return
    manifest = json.loads((staging/'manifest.json').read_text())
    names = [entry['id'] for entry in manifest['characters']]
    batches = [names[i:i+args.batch_size] for i in range(0, len(names), args.batch_size)]
    masters = ['recovered_motion_library'] + (['soldier_recovered'] if args.legacy_retarget else [])
    batches.append(masters)
    template = (ROOT/'tools/recovery/blender_characters.py').read_text()
    template = template.replace("ROOT = '/Users/king/socom'", 'ROOT = '+repr(str(ROOT)))
    for index, batch in enumerate(batches):
        code = template.replace("NAMES = ['recovered_char_alban_informant']", 'NAMES = '+repr(batch))
        path = folder/f'collection_{index:02d}.py'
        path.write_text(code)
        print(path)
    (staging/'export_names.txt').write_text('\n'.join(names+masters)+'\n')


if __name__ == '__main__':
    main()
