#!/usr/bin/env python3
"""Write bounded recipes to submit, in order, to Blender MCP execute_blender_code.

This generates code; it does not run Blender. Each data transfer stays below the
MCP safe-mode 200 KB limit. Prepared data are ordinary JSON, never executable text.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('asset', choices=['recovered_m4', 'recovered_seal', 'recovered_crossroads'])
    args = ap.parse_args()
    staging = ROOT/'previous/recovery/staging/pilot'
    data = json.loads((staging/(args.asset+'.blender.json')).read_text())
    recipe = (ROOT/'tools/recovery/blender_pilot.py').read_text().replace("ASSET = 'recovered_m4'", 'ASSET = '+repr(args.asset))
    recipe = recipe.replace("ROOT = '/Users/king/socom'", 'ROOT = '+repr(str(ROOT)))
    calls = []
    if data.get('parts'):
        meshes, references = data.pop('meshes'), data.pop('references')
        code = 'import bpy\nbpy.ops.wm.read_homefile(use_empty=True)\n'
        code += 'bpy.context.scene["pilot_meta"] = '+repr(json.dumps(data, separators=(',', ':'))) + '\n'
        code += f'bpy.context.scene["pilot_mesh_count"] = {len(meshes)}\nbpy.context.scene["pilot_reference_count"] = {len(references)}\n'
        calls.append(code)
        code = 'import bpy\n'
        for group, values in [('mesh', meshes), ('reference', references)]:
            for i, value in enumerate(values):
                line = f'bpy.context.scene["pilot_{group}_{i}"] = '+repr(json.dumps(value, separators=(',', ':'))) + '\n'
                if len((code+line).encode()) > 170000:
                    calls.append(code)
                    code = 'import bpy\n'
                code += line
        calls.append(code)
    else:
        recipe = recipe.replace("PILOT_DATA_JSON = '__PREPARED_JSON__'", 'PILOT_DATA_JSON = '+repr(json.dumps(data, separators=(',', ':'))))
    calls.append(recipe)
    folder = staging/'calls'/args.asset
    folder.mkdir(parents=True, exist_ok=True)
    for i, code in enumerate(calls):
        if len(code.encode()) >= 200000:
            raise ValueError('A prepared operation exceeds Blender MCP safe-mode size')
        target = folder/f'{i:02d}.py'
        target.write_text(code)
        print(target.relative_to(ROOT), len(code.encode()))


if __name__ == '__main__':
    main()
