/** Stage original gun geometry through the pinned offline decoder. See WEAPONS.md. */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { Zar } from '@s2u/archive';
import { walkChain, interpretChainPartsAs } from '@s2u/mesh';
import { parseSceneGraph, placeInstances, loadModelLibrary, resolveChunk, transformPoint, flattenScene } from '@s2u/scene';

const root = resolve(process.argv[2] ?? 'previous/recovery');
const assets = JSON.parse(readFileSync(join(root, 'reports/assets.json'), 'utf8'));
// These are projectiles, explosives, ammunition or tools, not held gun models.
const excluded = new Set(['AT4_Heat', 'HEgrenade', 'M203', 'PMN_mine', 'RPGrenade', 'a_smoke_grenade',
  'artillery_shell', 'bleu_chem', 'c4', 'claymore', 'detonator', 'fiftycal_box', 'flashbang', 'footbomb',
  'grenade', 'laser_designator']);
const sources = assets.filter((a: any) => a.type === 'model' && a.category === 'weapons' && !excluded.has(a.name));
const output: any[] = [];
for (const source of [...new Set<string>(sources.map((a: any) => a.source))].sort()) {
  const library = loadModelLibrary([Zar.parse(readFileSync(join(root, source)))]);
  const graph = parseSceneGraph(Zar.parse(readFileSync(join(root, source.replace('_MDL.', '_GEO.')))));
  for (const asset of sources.filter((a: any) => a.source === source)) {
    const placements = placeInstances(graph, asset.name);
    const meshes: any[] = [], selected: string[] = [], omitted: string[] = [];
    for (const p of placements) {
      if (/(?:_low|_lo|thermal_scope|silencer)(?:\/|$)/i.test(p.path)) { omitted.push(p.path); continue; }
      selected.push(p.path);
      const entry = library.get(p.modelName)!;
      for (const chunk of p.chunks) {
        const found = resolveChunk(entry, chunk);
        if (!found) throw Error(`Missing ${asset.name}:${chunk}`);
        const parts = interpretChainPartsAs(walkChain(entry.buffer, found.offset, chunk), 'scale');
        if (parts.lines.length) throw Error(`Unexpected gun line strips: ${asset.name}`);
        for (const mesh of parts.meshes) {
          const positions: number[][] = [];
          for (let i = 0; i < mesh.positions.length; i += 3)
            positions.push(transformPoint(p.rowMajor, ...Array.from(mesh.positions.slice(i, i + 3)) as [number, number, number]));
          meshes.push({ texture: mesh.textureName, positions, uv: Array.from(mesh.uvs), indices: Array.from(mesh.indices) });
        }
      }
    }
    const marker = flattenScene(graph, asset.name).find((p: any) => ['firepoint', 'firepont'].includes(p.node.name));
    if (!marker || !meshes.length) throw Error(`Missing geometry/firepoint: ${asset.name}`);
    output.push({ source: asset, meshes, selected, omitted, firepoint: transformPoint(marker.world, 0, 0, 0) });
  }
}
const staging = join(root, 'staging/weapons');
mkdirSync(staging, { recursive: true });
writeFileSync(join(staging, 'native.json'), JSON.stringify(output));
console.log(`Staged ${output.length} gun occurrences (${new Set(output.map(a => a.source.name)).size} names).`);
