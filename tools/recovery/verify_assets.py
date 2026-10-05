#!/usr/bin/env python3
"""Check recovered files and build an offline, searchable HTML asset catalogue.

Run with the recovery venv (Pillow). Verifies PNGs, OBJ indices/material paths,
skin weight arrays, animation JSON and byte hashes of all unpacked ZDB members.
"""
import argparse
from collections import Counter
import gzip
import hashlib
import html
import json
import math
from pathlib import Path
import re
from PIL import Image, ImageDraw


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            h.update(block)
    return h.hexdigest()


def verify_obj(path):
    vertices, uv, faces, lines = 0, 0, 0, 0
    maximum, maxuv = 0, 0
    materials, used = set(), set()
    with path.open() as stream:
        for row in stream:
            fields = row.split()
            if not fields:
                continue
            tag = fields[0]
            if tag in ('v', 'vt'):
                if not all(math.isfinite(float(v)) for v in fields[1:]):
                    raise ValueError('Nonfinite coordinates')
                vertices += tag == 'v'
                uv += tag == 'vt'
            elif tag == 'f':
                if len(fields) != 4:
                    raise ValueError('Expected triangles')
                faces += 1
                for field in fields[1:]:
                    p, t = (int(v) for v in field.split('/'))
                    if min(p, t) < 1:
                        raise ValueError('Invalid OBJ index')
                    maximum, maxuv = max(maximum, p), max(maxuv, t)
            elif tag == 'l':
                lines += 1
                maximum = max(maximum, *(int(v) for v in fields[1:]))
            elif tag == 'usemtl':
                used.add(fields[1])
            elif tag == 'mtllib':
                mtl = path.parent / ' '.join(fields[1:])
                for line in mtl.read_text().splitlines():
                    values = line.split()
                    if values and values[0] == 'newmtl':
                        materials.add(values[1])
                    if values and values[0] == 'map_Kd' and not (mtl.parent / ' '.join(values[1:])).is_file():
                        raise ValueError(f'Missing MTL image: {line}')
    if maximum > vertices or maxuv > uv or not used.issubset(materials):
        raise ValueError('Out-of-range indices or missing material definitions')
    if not vertices:
        raise ValueError('Empty OBJ')
    return vertices, faces, lines


def verify_skin(path):
    data = json.loads(gzip.decompress(path.read_bytes()))
    parts = data['parts']
    worst = 0
    for sub in data['mesh']['subMeshes']:
        start = sub['influenceStart']
        weights, bones = sub['influenceWeight'], sub['influenceBone']
        if len(start) != sub['vertexCount']+1 or start[0] != 0 or start[-1] != len(weights) or len(weights) != len(bones):
            raise ValueError('Skin influence array mismatch')
        for i in range(sub['vertexCount']):
            if start[i] >= start[i+1]:
                raise ValueError('Vertex has no influences')
            w = weights[start[i]:start[i+1]]
            if not all(math.isfinite(x) and x >= 0 for x in w):
                raise ValueError('Invalid skin weight')
            worst = max(worst, abs(sum(w)-1))
        if any(b < 0 or b >= len(parts) for b in bones):
            raise ValueError('Skin bone outside skeleton')
    if worst > 0.001:
        raise ValueError(f'Skin weights do not sum to unity: max error {worst}')
    return worst


def catalogue(out, assets, validation):
    reduced = [{k: a[k] for k in ('type', 'category', 'name', 'path', 'source', 'skin', 'collision',
                'width', 'height', 'triangles', 'bones', 'frames', 'status', 'missingTextures') if k in a} for a in assets]
    encoded = json.dumps(reduced).replace('<', '\\u003c')
    counts = Counter(a['type'] for a in assets)
    summary = ' · '.join(f'{v:,} {k}' for k, v in counts.items())
    status = f"{len(validation['errors'])} validation errors · {len(validation['warnings'])} flagged exports. Counts include LODs and library variants."
    previews = ''.join(
        f'<a href="reports/{filename}"><img src="reports/{filename}" alt="{label}"><span>{label}</span></a>'
        for filename, label in [('seal_A_scuba.png', 'Recovered soldier'),
                                ('m4_side.png', 'Recovered M4'),
                                ('crossroads.png', 'Assembled Crossroads')]
        if (out / 'reports' / filename).is_file())
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SOCOM II — Recovered assets</title><style>
*{box-sizing:border-box}body{margin:0;background:#121a20;color:#e5ecef;font:15px system-ui,sans-serif}
header,main{max-width:1400px;margin:auto;padding:26px}header{padding-bottom:10px}h1{font-size:32px;margin:0 0 10px}
p{line-height:1.5;color:#b1c0c7}a{color:#8fd2b3}nav{display:flex;gap:12px;flex-wrap:wrap;margin:18px 0}
input,select,button{padding:12px;border:1px solid #53636a;background:#202d34;color:white;border-radius:5px}
input{flex:1;min-width:240px}button{cursor:pointer}#grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(235px,1fr));gap:16px}
article{background:#202d34;border:1px solid #34454e;border-radius:8px;overflow:hidden;padding:14px;min-width:0}
article img{width:100%;height:180px;object-fit:contain;background:repeating-conic-gradient(#475158 0% 25%,#364047 0% 50%) 50%/20px 20px}
h2{font-size:16px;overflow-wrap:anywhere}small{color:#a8bec8;overflow-wrap:anywhere;display:block;margin:8px 0}
.badge{font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:#8fd2b3}.notice{border-left:3px solid #d4b05d;padding:10px 16px}
.links{display:flex;gap:12px;flex-wrap:wrap}.pager{display:flex;gap:15px;align-items:center;margin:20px 0}
.previews{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px;margin:24px 0}.previews a{background:#202d34;border-radius:8px;overflow:hidden;text-decoration:none}.previews img{display:block;width:100%;height:190px;object-fit:contain}.previews span{display:block;padding:12px}
</style><header><div class="badge">Local recovery collection</div><h1>SOCOM II: recovered assets</h1>
<p>SUMMARY</p><p class="notice">Original disc files and named native records are preserved. Models are OBJ/MTL staging exports in original Y-up units. Character rigs and weights are in .skin.json.gz sidecars; animation tracks are separate JSON. Level exports include alternate states and LODs together. Final material effects and Blender/Godot integration remain to be configured.</p>
<p>VALIDATION</p><div class="previews">PREVIEWS</div>
<div class="links"><a href="reports/conversion-summary.json">Conversion report</a><a href="reports/validation.json">Verification</a><a href="reports/conversion-errors.json">Unconverted records</a><a href="reports/assets.json">Full manifest</a><a href="reports/native-index.json">Native archive index</a></div>
<nav><input id="search" type="search" placeholder="Search name, map ID, or original path" aria-label="Search assets"><select id="type" aria-label="Asset type"><option value="">All types</option></select><select id="category" aria-label="Category"><option value="">All categories</option></select></nav>
</header><main><div class="pager"><button id="prev">Previous</button><span id="count"></span><button id="next">Next</button></div><div id="grid"></div></main>
<script>const assets=DATA;let page=0;const size=96;const $=id=>document.getElementById(id);
for(const key of ['type','category'])for(const v of [...new Set(assets.map(a=>a[key]).filter(Boolean))].sort()){const o=document.createElement('option');o.value=v;o.textContent=v;$(key).append(o)}
function link(parent,text,path){const a=document.createElement('a');a.textContent=text;a.href=path.split('/').map(encodeURIComponent).join('/');parent.append(a)}
function draw(){const q=$('search').value.toLowerCase(),t=$('type').value,c=$('category').value;
const filtered=assets.filter(a=>(!t||a.type===t)&&(!c||a.category===c)&&(!q||[a.name,a.source].join(' ').toLowerCase().includes(q)));
page=Math.max(0,Math.min(page,Math.ceil(filtered.length/size)-1));$('grid').replaceChildren();
for(const a of filtered.slice(page*size,(page+1)*size)){const el=document.createElement('article');
if(a.type==='texture'){const im=document.createElement('img');im.src=a.path.split('/').map(encodeURIComponent).join('/');im.loading='lazy';im.alt=a.name;el.append(im)}
const tag=document.createElement('div');tag.className='badge';tag.textContent=a.type+(a.category?' / '+a.category:'');el.append(tag);
const name=document.createElement('h2');name.textContent=a.name;el.append(name);
const detail=document.createElement('small');detail.textContent=a.width?a.width+' × '+a.height:a.triangles!==undefined?a.triangles.toLocaleString()+' triangles'+(a.bones?' · '+a.bones+' bones':''):a.frames?a.frames+' frames':'';el.append(detail);
const source=document.createElement('small');source.textContent=a.source;el.append(source);
if(a.missingTextures?.length){const warning=document.createElement('p');warning.textContent='Unresolved textures: '+a.missingTextures.join(', ');el.append(warning)}
const links=document.createElement('div');links.className='links';link(links,'Open asset',a.path);if(a.skin)link(links,'Rig data',a.skin);if(a.collision)link(links,'Collision',a.collision);link(links,'Native library',a.source);el.append(links);$('grid').append(el)}
$('count').textContent=filtered.length.toLocaleString()+' matches · page '+(page+1)+' / '+Math.max(1,Math.ceil(filtered.length/size));$('prev').disabled=page===0;$('next').disabled=(page+1)*size>=filtered.length}
for(const id of ['search','type','category'])$(id).addEventListener('input',()=>{page=0;draw()});$('prev').onclick=()=>{page--;draw()};$('next').onclick=()=>{page++;draw()};draw();</script></html>'''
    (out / 'index.html').write_text(page.replace('SUMMARY', html.escape(summary))
                                  .replace('VALIDATION', html.escape(status))
                                  .replace('PREVIEWS', previews).replace('DATA', encoded))
    # Labelled texture samples across categories, for a quick visual corruption check.
    chosen = []
    for category in sorted(set(a.get('category') for a in assets if a['type'] == 'texture')):
        group = [a for a in assets if a['type'] == 'texture' and a.get('category') == category]
        chosen += [group[i] for i in sorted(set(round(k*(len(group)-1)/5) for k in range(6)))]
    sheet = Image.new('RGB', (6*220, math.ceil(len(chosen)/6)*250), '#202830')
    draw = ImageDraw.Draw(sheet)
    for i, a in enumerate(chosen):
        x, y = (i % 6)*220, (i//6)*250
        with Image.open(out / a['path']) as original:
            im = original.convert('RGBA'); im.thumbnail((204, 204))
            sheet.paste(im, (x+8, y+8), im)
        draw.text((x+8, y+214), a['name'][:30], fill='white')
        draw.text((x+8, y+231), a.get('category', ''), fill='#90c7b0')
    sheet.save(out / 'reports/texture-contact-sheet.jpg', quality=90)


def organize_native(out, assets):
    """Upgrade the first recovery run's generic record folders to the final categories."""
    changed = False
    for folder in sorted((out / 'native/records').glob('*/*')):
        if not folder.is_dir():
            continue
        stem = folder.name.split('.ZAR-')[0]
        kind = None
        if stem in ('VAGSTORE', 'BNKSTORE'):
            kind = 'audio'
        elif re.fullmatch(r'MOTION_.+|.*ZANIM', stem):
            kind = 'animations'
        elif re.fullmatch(r'READER.*|ZWEAPON|SOUNDRDR|.*LOC', stem):
            kind = 'scripts'
        if not kind:
            continue
        target = out / 'native' / kind / folder.parent.name / folder.name
        if target.exists():
            raise ValueError(f'Cannot merge existing native folders: {folder} and {target}')
        target.parent.mkdir(parents=True, exist_ok=True)
        before, after = folder.relative_to(out).as_posix()+'/', target.relative_to(out).as_posix()+'/'
        folder.rename(target)
        for asset in assets:
            if asset['path'].startswith(before):
                asset['path'] = after + asset['path'][len(before):]
        changed = True
    if changed:
        (out / 'reports/assets.json').write_text(json.dumps(assets, indent=2)+'\n')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('out', type=Path, nargs='?', default=Path('previous/recovery'))
    args = ap.parse_args(); out = args.out
    assets = json.loads((out / 'reports/assets.json').read_text())
    organize_native(out, assets)
    errors, warnings = [], []
    members = json.loads((out / 'reports/members.json').read_text())
    for item in members:
        p = out / item['path']
        if p.stat().st_size != item['size'] or digest(p) != item['sha256']:
            errors.append({'path': item['path'], 'error': 'Extracted member hash mismatch'})
    counts = Counter()
    worst_weight = 0
    for i, asset in enumerate(assets):
        p = out / asset['path']
        try:
            if asset['type'] == 'texture':
                with Image.open(p) as image:
                    if image.size != (asset['width'], asset['height']):
                        raise ValueError('PNG dimensions differ from source record')
                    image.verify()
                if digest(p) != asset['sha256']:
                    raise ValueError('PNG hash mismatch')
            elif asset['type'] in ('model', 'character', 'level'):
                vertices, faces, lines = verify_obj(p)
                if (vertices, faces, lines) != (asset['vertices'], asset['triangles'], asset['lineStrips']):
                    raise ValueError('OBJ counts differ from manifest')
                if asset.get('skin'):
                    worst_weight = max(worst_weight, verify_skin(out / asset['skin']))
                if asset.get('collision'):
                    verify_obj(out / asset['collision'])
                if asset.get('failedChunks') or asset.get('missingTextures'):
                    warnings.append({'path': asset['path'], 'failedChunks': asset.get('failedChunks', 0),
                                     'missingTextures': asset.get('missingTextures', [])})
            elif asset['type'] == 'animation':
                decoded = json.loads(gzip.decompress(p.read_bytes()))
                if decoded['frameCount'] != asset['frames'] or decoded['version'] != 5:
                    raise ValueError('Animation metadata mismatch')
            elif asset['type'] == 'script':
                json.loads(p.read_text())
            counts[asset['type']] += 1
        except (ValueError, OSError, KeyError, IndexError) as error:
            errors.append({'path': asset['path'], 'error': str(error)})
        if i % 2000 == 0:
            print(f'Verified {i:,}/{len(assets):,}', flush=True)
    report = {'checked': dict(counts), 'archiveMembersHashed': len(members),
              'maxSkinWeightSumError': worst_weight, 'errors': errors, 'warnings': warnings}
    (out / 'reports/validation.json').write_text(json.dumps(report, indent=2)+'\n')
    catalogue(out, assets, report)
    print(json.dumps({'checked': dict(counts), 'errors': len(errors), 'warnings': len(warnings)}))
    if errors:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
