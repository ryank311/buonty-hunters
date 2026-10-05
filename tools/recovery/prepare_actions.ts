/** Decode original action placement and door motions, without changing map exports.
 * TSX_TSCONFIG_PATH=previous/recovery/reports/decoder-tsconfig.json node --import
 * ./previous/recovery/research/socom-unzipped/web/node_modules/tsx/dist/loader.mjs tools/recovery/prepare_actions.ts
 * Then: previous/recovery/.venv/bin/python tools/recovery/prepare_actions.py
 */
import { readFileSync, readdirSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { Zar } from '@s2u/archive';
import { parseSceneGraph, flattenScene, parseAnimSets, decodeEffectProgram } from '@s2u/scene';

const root = 'previous/recovery';
const output = `${root}/staging/actions`;
mkdirSync(output, { recursive: true });
const pairs = (a: any[]): Record<string, any> => Object.fromEntries(Array.from({ length: a.length / 2 }, (_, i) => [a[i * 2], a[i * 2 + 1]]));
for (const filename of readdirSync('resources/recovered/levels').filter(x => /^mp\d+\.json$/.test(x))) {
  const map = JSON.parse(readFileSync(`resources/recovered/levels/${filename}`, 'utf8'));
  if (!map.id) continue;
  const folder = `${root}/archives/${map.id}/RUN/${map.id.startsWith('MP') ? 'MP' : 'SP'}/${map.id}`;
  const scripts = `${root}/native/scripts/${map.id}`;
  const reader = readdirSync(scripts).find(x => x.startsWith('READERM.ZAR-'));
  const actionFile = reader && readdirSync(join(scripts, reader)).find(x => x.endsWith('-actions.rdr.json'));
  if (!actionFile || !existsSync(`${folder}/${map.id}_GEO.ZED`)) continue;
  const records = pairs(JSON.parse(readFileSync(join(scripts, reader!, actionFile), 'utf8'))[0]).actions ?? [];
  const flat = flattenScene(parseSceneGraph(Zar.parse(readFileSync(`${folder}/${map.id}_GEO.ZED`))), 'worldmodel');
  const programs = new Map<string, any>();
  if (existsSync(`${folder}/MZANIM.ZAR`)) {
    // Decode only the door programs. Unrelated campaign cutscene records include
    // node-reference formats this decoder does not support; leave those untouched.
    const wanted = new Set(records.filter((r: any[]) => pairs(r).type?.[0] === 'DOOR').flatMap((r: any[]) => (pairs(r).anim ?? []).map((name: string) => name.toLowerCase())));
    const archive = Zar.parse(readFileSync(`${folder}/MZANIM.ZAR`));
    for (const set of archive.child(archive.root, 'Anim_Sets')!.children) {
      const list = archive.child(set, 'Animation_List')!;
      list.children = list.children.filter(x => wanted.has(x.name.toLowerCase()));
      new DataView(archive.data(archive.child(set, 'Animation_List_Count')!).buffer,
        archive.data(archive.child(set, 'Animation_List_Count')!).byteOffset, 4).setUint32(0, list.children.length, true);
    }
    for (const set of parseAnimSets(archive).sets)
      for (const anim of set.anims) programs.set(anim.name.toLowerCase(), decodeEffectProgram(anim));
  }
  const actions = records.map((record: any[]) => {
    const fields = pairs(record);
    const node = flat.find(x => x.node.name.toLowerCase() === fields.node?.[0]?.toLowerCase());
    return { fields, path: node?.path, world: node ? Array.from(node.world) : null,
      programs: (fields.anim ?? []).map((name: string) => programs.get(name.toLowerCase()) ?? { name, missing: true }) };
  });
  writeFileSync(`${output}/${map.id}.json`, JSON.stringify({ id: map.id, actions }, null, 1) + '\n');
  console.log(`${map.id}: ${actions.length} actions, ${actions.filter((x: any) => x.fields.type?.[0] === 'DOOR').length} doors`);
}
