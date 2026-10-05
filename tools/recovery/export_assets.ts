/** Disc recovery adapter. Uses the pinned GPL-3.0 redotcom decoder; see README.md. */
import { readFileSync, writeFileSync, mkdirSync, openSync, writeSync, closeSync, existsSync } from 'node:fs';
import { join, dirname, basename, relative, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { Zar, parseRdr, rdrGet } from '@s2u/archive';
import { PaletteTable, parseTextureRecord, decodeTexture, decodeTex0 } from '@s2u/gs';
import { modelNodes, walkChain, interpretChainPartsAs, readMeshLibrary, skinSubMesh,
  unpackVif, interpretPacket, interpretLinePacket, isLineStripPacket, packetPrimitive } from '@s2u/mesh';
import { parseSceneGraph, placeInstances, loadModelLibrary, resolveChunk, readSkeleton,
  IDENTITY, transformPoint, parseClutter, placeClutter, placeCollision, parseMotionClip } from '@s2u/scene';
import { encodePng } from '@recovery/png';

const out = resolve(process.argv[2] ?? 'previous/recovery');
const only = process.argv[3]?.startsWith('--') ? undefined : process.argv[3];
const reuseNative = process.argv.includes('--reuse-native');
const libs = JSON.parse(readFileSync(join(out, 'reports/libraries.json'), 'utf8'));
const errors: any[] = [], assets: any[] = [], indexes: any[] = [];
const adaptations: any[] = [];
if (reuseNative) {
  indexes.push(...JSON.parse(readFileSync(join(out, 'reports/native-index.json'), 'utf8')));
  assets.push(...JSON.parse(readFileSync(join(out, 'reports/assets.json'), 'utf8')).filter((a: any) => ['script', 'animation'].includes(a.type)));
  errors.push(...JSON.parse(readFileSync(join(out, 'reports/conversion-errors.json'), 'utf8')).filter((e: any) => ['reader', 'animation', 'library'].includes(e.stage)));
}
const paths = new Map(libs.map((x: any) => [x.path.toLowerCase(), x]));
const slug = (s: string) => s.replace(/[^a-zA-Z0-9_.-]/g, '_').replace(/^\.+/, '_') || '_';
const stringify = (v: any) => JSON.stringify(v, (_, x) => ArrayBuffer.isView(x) ? Array.from(x as any) : typeof x === 'bigint' ? x.toString() : x, 2) + '\n';
const save = (p: string, data: any) => { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, data); };
const json = (p: string, v: any) => save(p, stringify(v));
const rel = (p: string) => relative(out, p).split('\\').join('/');
const note = (stage: string, source: string, error: any) => errors.push({ stage, source, error: String(error?.message ?? error) });
const hash = (b: Uint8Array) => createHash('sha256').update(b).digest('hex');
const cache = new Map<string, Zar>();
function zar(lib: any): Zar {
  if (!lib) throw Error('Matching archive is absent');
  let z = cache.get(lib.sha256);
  if (!z) { z = Zar.parse(readFileSync(join(out, lib.path))); cache.set(lib.sha256, z); }
  return z;
}
function peer(lib: any, suffix: string) {
  return paths.get(lib.path.replace(/_(TXR|PAL|MDL|GEO)\.ZED$/i, suffix).toLowerCase());
}
function category(lib: any) {
  const n = basename(lib.path);
  if (/^CLIB_/.test(n)) return 'characters';
  if (/^WEAP_/.test(n)) return 'weapons';
  if (/^FLIB_/.test(n)) return 'equipment';
  if (/\/UI\//.test(lib.path)) return 'ui';
  if (/^EFFE_|^ALPH_/.test(n)) return 'effects';
  if (/^(MP\d+|M\d+|WORL)_/.test(n)) return 'levels';
  return 'shared';
}
function destination(lib: any, type: string, variant = '') {
  return join(out, 'converted', type, category(lib), lib.context,
    basename(lib.path, '.ZED') + '-' + lib.sha256.slice(0, 10) + variant);
}

function nativeCategory(path: string) {
  if (/_MDL\.ZED$/.test(path)) return 'models';
  if (/\/(VAGSTORE|BNKSTORE)\.ZAR$/.test(path)) return 'audio';
  if (/\/(?:MOTION_[^/]+|[^/]*ZANIM)\.ZAR$/.test(path)) return 'animations';
  if (/\/(?:READER[^/]*|ZWEAPON|SOUNDRDR|[^/]*LOC)\.ZAR$/.test(path)) return 'scripts';
  return 'records';
}

// Index every key, with exact offsets into the preserved native library. Named payloads in
// MDL and ZAR files are also split out, so raw assets remain usable if a converter rejects them.
const seenNative = new Set<string>();
for (const lib of libs.filter((l: any) => !reuseNative && (!only || l.context === only))) {
  if (seenNative.has(lib.sha256)) continue;
  seenNative.add(lib.sha256);
  try {
    const z = zar(lib);
    let keyBytes = 0;
    z.walk(k => { z.data(k); keyBytes += k.size; });
    const index = join(out, 'native/indexes', `${basename(lib.path)}-${lib.sha256.slice(0, 12)}.json`);
    json(index, { source: lib.path, sha256: lib.sha256, dataOffset: z.dataOffset, keyCount: z.keyCount, root: z.root });
    indexes.push({ source: lib.path, sha256: lib.sha256, index: rel(index), keys: z.keyCount, payloadBytes: keyBytes });
    const nativeDir = join(out, 'native', nativeCategory(lib.path), lib.context,
      basename(lib.path) + '-' + lib.sha256.slice(0, 10));
    if (/_MDL\.ZED$|\.ZAR$/.test(lib.path)) {
      let i = 0;
      const visit = (key: any, parent: string) => {
        const path = join(parent, `${String(i++).padStart(5, '0')}-${slug(key.name)}`);
        if (key.size) save(path + '.bin', z.data(key));
        if (key.size && /\.rdr$/i.test(key.name)) {
          try {
            const decoded = parseRdr(z.data(key));
            json(path + '.json', decoded);
            assets.push({ type: 'script', name: key.name, source: lib.path, path: rel(path + '.json') });
          } catch (e) { note('reader', `${lib.path}:${key.name}`, e); }
        }
        if (/MOTION_[^/]*\.ZAR$/i.test(lib.path) && key.size) {
          try {
            const clip = parseMotionClip(z.data(key), key.name);
            const output = join(out, 'converted/animations', lib.context, basename(lib.path) + '-' + lib.sha256.slice(0, 10), slug(key.name) + '.json.gz');
            save(output, gzipSync(stringify(clip)));
            assets.push({ type: 'animation', name: key.name, source: lib.path, path: rel(output), frames: clip.frameCount, duration: clip.duration });
          } catch (e) { note('animation', `${lib.path}:${key.name}`, e); }
        }
        for (const c of key.children) visit(c, path);
      };
      for (const k of z.root.children) visit(k, nativeDir);
    }
  } catch (e) { note('library', lib.path, e); }
}
console.log(`Indexed ${indexes.length} unique libraries; ${errors.length} diagnostics`);
json(join(out, 'reports/native-index.json'), indexes);

// A texture is deduplicated together with its palette dependency, never by its name alone.
const textureByLib = new Map<string, Map<string, any>>();
const textureSets = new Map<string, Map<string, any>>();
for (const lib of libs.filter((l: any) => /_TXR\.ZED$/.test(l.path) && (!only || l.context === only))) {
  try {
    const pal: any = peer(lib, '_PAL.ZED');
    const id = `${lib.sha256}:${pal?.sha256 ?? 'none'}`;
    if (textureSets.has(id)) { textureByLib.set(lib.path, textureSets.get(id)!); continue; }
    const z = zar(lib), palettes = PaletteTable.fromZars(pal ? [zar(pal)] : []);
    const records = new Map<string, any>();
    const dir = destination(lib, 'textures', '-' + (pal?.sha256.slice(0, 8) ?? 'direct'));
    for (const key of z.find('textures')?.children ?? []) {
      try {
        const tk = z.child(key, 'texdat');
        if (!tk) throw Error('Missing texdat');
        const texdat = z.data(tk);
        const record = parseTextureRecord(key.name, texdat);
        // Arjan's 128x56 upload lives in a 128x64 GS texture. Read the actual A+D
        // TEX0 register instead of requiring stored height == 2^TH.
        if (!record.tex0) {
          const dv = new DataView(texdat.buffer, texdat.byteOffset, texdat.byteLength);
          const matches: any[] = [];
          for (let at = 32 + record.size; at + 16 <= texdat.length; at += 16) {
            const reg = dv.getUint32(at+8, true);
            if (reg !== 6 && reg !== 7) continue;
            const t = decodeTex0(dv.getBigUint64(at, true));
            if (t.tbp0 === record.gsaddr && t.tw === Math.ceil(Math.log2(record.width)) && t.th === Math.ceil(Math.log2(record.height))) matches.push(t);
          }
          if (matches.length === 1) {
            record.tex0 = matches[0];
            adaptations.push({ source: lib.path, name: key.name, kind: 'partial-height TEX0 register', storedHeight: record.height, gsHeight: 1 << record.tex0.th });
          }
        }
        if (record.palettized && record.tex0 && !palettes.get(record.tex0.cbp)) {
          const matches: any[] = [];
          for (const candidate of libs.filter((l: any) => l.context === lib.context && /_PAL\.ZED$/.test(l.path))) {
            const found = PaletteTable.fromZars([zar(candidate)]).get(record.tex0.cbp);
            if (found) matches.push({ palette: found, source: candidate.path, hash: hash(found.rgba) });
          }
          if (matches.length && new Set(matches.map(m => m.hash)).size === 1) {
            palettes.add(matches[0].palette);
            adaptations.push({ source: lib.path, name: key.name, kind: 'cross-library palette', paletteSource: matches[0].source, cbp: record.tex0.cbp });
          }
        }
        const decoded = decodeTexture(record, palettes);
        if (decoded.diagnostics.length) throw Error(decoded.diagnostics.join('; '));
        const png = encodePng(decoded.rgba.width, decoded.rgba.height, decoded.rgba.data);
        const target = join(dir, slug(key.name) + '.png');
        save(target, png);
        const { pixels, ...metadata } = record;
        const item = { type: 'texture', category: category(lib), name: key.name, source: lib.path,
          paletteSource: pal?.path ?? null, path: rel(target), width: record.width, height: record.height,
          bpp: record.bpp, sha256: hash(png), transparent: record.transparent, metadata };
        records.set(key.name.toLowerCase(), item); assets.push(item);
      } catch (e) { note('texture', `${lib.path}:${key.name}`, e); }
    }
    textureSets.set(id, records); textureByLib.set(lib.path, records);
  } catch (e) { note('texture-library', lib.path, e); }
}
console.log(`Decoded ${assets.filter(a => a.type === 'texture').length} textures; ${errors.length} diagnostics`);
json(join(out, 'reports/assets.json'), assets);

function texturesFor(lib: any) {
  const result = new Map<string, any>();
  const pair: any = peer(lib, '_TXR.ZED');
  const candidates = [pair, ...libs.filter((l: any) => l.context === lib.context && /_TXR\.ZED$/.test(l.path))].filter(Boolean);
  for (const l of candidates) for (const [name, item] of textureByLib.get(l.path) ?? []) if (!result.has(name)) result.set(name, item);
  // Unused prototypes sometimes cite a texture omitted from that level's load. Resolve
  // across the disc only when every recovered texture of that exact name has identical pixels.
  const elsewhere = new Map<string, any[]>();
  for (const set of textureSets.values()) for (const [name, item] of set) {
    if (!result.has(name)) { const list = elsewhere.get(name) ?? []; list.push(item); elsewhere.set(name, list); }
  }
  for (const [name, items] of elsewhere) if (new Set(items.map(i => i.sha256)).size === 1) result.set(name, items[0]);
  return result;
}

function prototypeChunk(entry: any, chunk: string) {
  const exact = resolveChunk(entry, chunk);
  if (exact) return exact;
  const match = /^N(\d{3})_(?:I\d{3}_V(\d{2})|(\d{3}))$/.exec(chunk);
  if (!match) return null;
  const visual = Number(match[2] ?? match[3]);
  const pattern = new RegExp(`^N${match[1]}_(?:I\\d{3}_V${String(visual).padStart(2,'0')}|${String(visual).padStart(3,'0')})(_L)?$`);
  const candidate = entry.nodes.filter((n: any) => pattern.test(n.name)).sort((a: any,b: any) => a.name.localeCompare(b.name))[0];
  return candidate ? { offset: candidate.offset, lit: candidate.name.endsWith('_L') } : null;
}

function decodeParts(chain: any, form: 'bias' | 'scale') {
  try { return interpretChainPartsAs(chain, form); }
  catch (original) {
    const meshes: any[] = [], lines: any[] = [];
    for (const packet of unpackVif(chain)) {
      if (packet.kind !== 'mscnt') continue;
      const count = packet.mem[4] & 0x7fff;
      const floats = packet.unpacks.find(u => u.addr === 2 && u.vn === 3 && u.vl === 0 && u.cl === 3 && u.wl === 2 && u.num === count*2);
      if (isLineStripPacket(packet)) {
        if (floats) lines.push(interpretLinePacket(packet));
        else {
          // The same campaign wire also contains an indexed fixed-point line packet.
          // Its vertex/index layout is the mesh layout, but GS PRIM=2 draws each
          // indexed triple as a line strip, not as a filled triangle.
          const indexed = packet.unpacks.find(u => u.addr === 4 && u.vn === 3 && u.vl === 1 && u.cl === 3 && u.wl === 2 && u.num === packet.mem[10]*2);
          if (!indexed) throw original;
          const decoded = interpretPacket(packet, form);
          for (let at=0; at<decoded.indices.length; at+=3) {
            const ids = decoded.indices.slice(at,at+3);
            const gather = (v: any, stride: number) => Float32Array.from([...ids].flatMap(i => [...v.slice(i*stride,(i+1)*stride)]));
            lines.push({ positions: gather(decoded.positions,3), uvs: gather(decoded.uvs,2), textureName: decoded.textureName });
          }
        }
        continue;
      }
      // M61 wire4 has one non-indexed float TRIANGLE packet among its line strips.
      // Two GIF headers, three quadwords per vertex, NLOOP vertices, no index tail.
      if (floats && packetPrimitive(packet,0) === 5 && packetPrimitive(packet,1) === 3 && count > 0 && count % 3 === 0) {
        const decoded = interpretLinePacket(packet);
        meshes.push({ ...decoded, indices: Uint32Array.from({length: count}, (_,i) => i), faceNormals: null });
      } else meshes.push(interpretPacket(packet, form));
    }
    return { meshes, lines };
  }
}

// OBJ is a staging format: right-handed Y-up original units; UV V is flipped for OBJ's
// bottom-left convention. Vertex colours, skinning and animation stay in sidecar data/native records.
class ObjWriter {
  fd: number; vertices = 0; triangles = 0; lines = 0; missing = new Set<string>(); mats = new Map<string, number>();
  constructor(readonly file: string, readonly textures: Map<string, any>) {
    mkdirSync(dirname(file), { recursive: true }); this.fd = openSync(file, 'w');
    writeSync(this.fd, `# SOCOM II recovered geometry; Y-up, original game units\nmtllib ${basename(file, '.obj')}.mtl\n`);
  }
  material(name: string | null) {
    const n = name ?? '__untextured__';
    if (!this.mats.has(n)) this.mats.set(n, this.mats.size);
    return `material_${this.mats.get(n)}`;
  }
  add(mesh: any, matrix: any, name: string, line = false) {
    const positions = mesh.positions, count = positions.length / 3;
    if (!count) return;
    if (!Number.isInteger(count) || [...positions].some(v => !Number.isFinite(v))) throw Error('Invalid vertex coordinates');
    if (!line && [...mesh.indices].some(i => !Number.isInteger(i) || i < 0 || i >= count)) throw Error('Triangle index outside vertex array');
    const rows = [`o ${slug(name)}`, `usemtl ${this.material(mesh.textureName)}`];
    for (let i = 0; i < count; i++) {
      const p = transformPoint(matrix, positions[3*i], positions[3*i+1], positions[3*i+2]);
      if (!p.every(Number.isFinite)) throw Error('Nonfinite transformed vertex');
      rows.push(`v ${p.map(x => Number(x.toFixed(7))).join(' ')}`);
    }
    const tex = this.textures.get((mesh.textureName ?? '').toLowerCase());
    const us = tex?.metadata.tex0 ? (1 << tex.metadata.tex0.tw)/tex.width : 1;
    const vs = tex?.metadata.tex0 ? (1 << tex.metadata.tex0.th)/tex.height : 1;
    for (let i = 0; i < count; i++) rows.push(`vt ${(mesh.uvs?.[2*i] ?? 0)*us} ${1 - (mesh.uvs?.[2*i+1] ?? 0)*vs}`);
    if (line) {
      rows.push('l ' + Array.from({ length: count }, (_, i) => this.vertices + i + 1).join(' ')); this.lines++;
    } else {
      const m = matrix;
      const det = m[0]*(m[5]*m[10]-m[6]*m[9])-m[1]*(m[4]*m[10]-m[6]*m[8])+m[2]*(m[4]*m[9]-m[5]*m[8]);
      for (let i = 0; i < mesh.indices.length; i += 3) {
        const tri = Array.from(mesh.indices.slice(i, i+3)) as number[];
        if (det < 0) [tri[1], tri[2]] = [tri[2], tri[1]];
        rows.push('f ' + tri.map(x => { const n = x + this.vertices + 1; return `${n}/${n}`; }).join(' '));
      }
      this.triangles += mesh.indices.length / 3;
    }
    this.vertices += count;
    writeSync(this.fd, rows.join('\n') + '\n');
  }
  finish() {
    closeSync(this.fd);
    const rows: string[] = [];
    for (const [name, id] of this.mats) {
      rows.push(`newmtl material_${id}`, `# ${name}`, 'Kd 1 1 1', 'Ka 0 0 0', 'Ks 0 0 0', 'illum 1');
      const tex = this.textures.get(name.toLowerCase());
      if (tex) rows.push(`map_Kd ${relative(dirname(this.file), join(out, tex.path))}`);
      else if (name !== '__untextured__') this.missing.add(name);
      rows.push('');
    }
    save(this.file.replace(/\.obj$/, '.mtl'), rows.join('\n'));
    return { path: rel(this.file), vertices: this.vertices, triangles: this.triangles, lineStrips: this.lines,
      missingTextures: [...this.missing], normals: 'Recompute on import; native normals preserved in source',
      coordinates: 'Y-up, original game units; OBJ V = 1 - source V' };
  }
}

const seenModels = new Set<string>();
let currentContext = '', contextLibrary: any = null;
for (const lib of libs.filter((l: any) => /_MDL\.ZED$/.test(l.path) && (!only || l.context === only))) {
  const geo: any = peer(lib, '_GEO.ZED');
  const signature = `${lib.sha256}:${geo?.sha256 ?? 'none'}`;
  if (seenModels.has(signature)) continue;
  seenModels.add(signature);
  try {
    const z = zar(lib), textures = texturesFor(lib), dir = destination(lib, 'models');
    if (currentContext !== lib.context) {
      currentContext = lib.context;
      contextLibrary = loadModelLibrary(libs.filter((l: any) => l.context === lib.context && /_MDL\.ZED$/.test(l.path)).map(zar));
    }
    let graph: any[] = [];
    if (geo) {
      try { graph = parseSceneGraph(zar(geo)); json(join(dir, 'scene-graph.json'), graph); }
      catch (e) { note('scene-graph', geo.path, e); }
    }
    const library = loadModelLibrary([z]);
    for (const entry of readMeshLibrary(z)) {
      const name = entry.name;
      if (!entry.mesh) { note('skinned-mesh', `${lib.path}:${name}`, entry.error); continue; }
      try {
        const skeleton = readSkeleton(zar(geo), name);
        const sidecar = join(dir, slug(name) + '.skin.json.gz');
        save(sidecar, gzipSync(stringify({ source: lib.path, geometrySource: geo.path,
          mesh: entry.mesh, parts: skeleton.parts, modelMatrix: skeleton.modelMatrix, bindWorld: skeleton.bindWorld })));
        const writer = new ObjWriter(join(dir, slug(name) + '.obj'), textures);
        for (const sub of entry.mesh.subMeshes) {
          const posed = skinSubMesh(sub, skeleton.palette());
          writer.add({ ...sub, ...posed }, IDENTITY, name);
        }
        const exported = writer.finish();
        assets.push({ type: 'character', category: 'characters', name, source: lib.path, ...exported,
          bones: skeleton.size, skin: rel(sidecar), status: 'bind-pose OBJ; original influences and skeleton in skin sidecar' });
      } catch (e) { note('character', `${lib.path}:${name}`, e); }
    }
    for (const name of library.names()) {
      const entry = library.get(name)!;
      if (!entry.nodes.length) continue;
      const writer = new ObjWriter(join(dir, slug(name) + '.obj'), textures);
      let failures = 0;
      try {
        // Use prototype transforms where a GEO counterpart exists. Model packets alone remain
        // useful, but their local chunks are explicitly marked unassembled.
        const placements = graph.some(n => n.name === name) ? placeInstances(graph, name) : [];
        const jobs: any[] = placements.length ? placements.flatMap(p => p.chunks.map(c => {
          const part = p.modelName === name ? entry : library.get(p.modelName) ?? contextLibrary.get(p.modelName);
          const found = part ? prototypeChunk(part, c) : null;
          return { entry: part, offset: found?.offset, chunk: c, matrix: p.rowMajor };
        })) : entry.nodes.filter(n => !/_I(?!000)/.test(n.name)).map(n => ({ entry, offset: n.offset, chunk: n.name, matrix: IDENTITY }));
        for (const job of jobs) {
          try {
            if (job.offset === undefined) throw Error(`Missing chunk ${job.chunk}`);
            const form = /^(WEAP|FLIB|UI)_MDL\.ZED$/.test(basename(lib.path)) ? 'scale' : 'bias';
            const parts = decodeParts(walkChain(job.entry.buffer, job.offset, job.chunk), form);
            for (const part of parts.meshes) writer.add(part, job.matrix, job.chunk);
            for (const line of parts.lines) writer.add(line, job.matrix, job.chunk, true);
          } catch (e) { failures++; note('model-chunk', `${lib.path}:${name}:${job.chunk}`, e); }
        }
        assets.push({ type: 'model', category: category(lib), name, source: lib.path, ...writer.finish(),
          failedChunks: failures, assembly: placements.length ? 'GEO prototype transforms' : 'local chunks; no matching GEO',
          status: failures ? 'partial' : 'converted' });
      } catch (e) { writer.finish(); note('model', `${lib.path}:${name}`, e); }
    }
  } catch (e) { note('model-library', lib.path, e); }
  cache.clear();
  console.log(`Models ${lib.context}/${basename(lib.path)}; ${assets.length} assets; ${errors.length} diagnostics`);
}

// Assemble each level using its own hierarchy and per-instance transforms, including clutter.
for (const lib of libs.filter((l: any) => /\/(MP\d+|M\d+)_GEO\.ZED$/.test(l.path) && (!only || l.context === only))) {
  try {
    const models = parseSceneGraph(zar(lib));
    if (!models.some(m => m.name === 'worldmodel')) continue;
    const mdl = libs.filter((l: any) => l.context === lib.context && /_MDL\.ZED$/.test(l.path));
    const library = loadModelLibrary(mdl.map(zar));
    const placements = placeInstances(models);
    const clutter = libs.find((l: any) => l.context === lib.context && /\/CLUTTER\.ZAR$/.test(l.path));
    if (clutter) {
      const placed = placeClutter(models, parseClutter(zar(clutter)));
      placements.push(...placed.placed);
      for (const m of placed.missing) note('clutter', lib.path, `Missing model ${m}`);
      for (const m of placed.malformed) note('clutter', lib.path, `Malformed ${m.modelName}: ${m.instances}`);
    }
    const dir = join(out, 'converted/levels', lib.context);
    json(join(dir, 'placements.json'), placements);
    const collisions = placeCollision(models);
    save(join(dir, 'collision.json.gz'), gzipSync(stringify(collisions)));
    const collision = new ObjWriter(join(dir, 'collision.obj'), new Map());
    for (const p of collisions) {
      const n = p.points.length / 3;
      const indices: number[] = [];
      for (let i = 1; i < n-1; i++) indices.push(0, i, i+1);
      collision.add({ positions: p.points, indices, textureName: null }, IDENTITY, p.path);
    }
    const collisionResult = collision.finish();
    const writer = new ObjWriter(join(dir, 'level.obj'), texturesFor(lib));
    let failed = 0;
    for (const p of placements) for (const chunk of p.chunks) {
      try {
        const entry = library.get(p.modelName);
        if (!entry) throw Error(`Missing model ${p.modelName}`);
        const found = resolveChunk(entry, chunk);
        if (!found) throw Error(`Missing chunk ${chunk}`);
        const parts = decodeParts(walkChain(entry.buffer, found.offset, chunk), 'bias');
        for (const m of parts.meshes) writer.add(m, p.rowMajor, p.path);
        for (const l of parts.lines) writer.add(l, p.rowMajor, p.path, true);
      } catch (e) { failed++; note('level-chunk', `${lib.path}:${p.path}:${chunk}`, e); }
    }
    const result = writer.finish();
    let displayName = lib.context;
    const reader = libs.find((l: any) => l.context === lib.context && /\/READERM\.ZAR$/.test(l.path));
    if (reader) { const r = zar(reader), k = r.find('mission.rdr'); if (k) { const d = rdrGet(parseRdr(r.data(k)), 'description'); if (typeof d === 'string') displayName = d; } }
    const entry = { type: 'level', name: displayName, context: lib.context, source: lib.path, ...result,
      placements: placements.length, failedChunks: failed, collision: collisionResult.path,
      status: failed ? 'partial' : 'converted; all hierarchy states retained' };
    assets.push(entry); json(join(dir, 'level-report.json'), entry);
    console.log(`Level ${lib.context}: ${result.triangles} triangles; ${failed} failed chunks`);
  } catch (e) { note('level', lib.path, e); }
  cache.clear();
}
const counts: Record<string, number> = {};
for (const asset of assets) counts[asset.type] = (counts[asset.type] ?? 0) + 1;
json(join(out, 'reports/assets.json'), assets);
json(join(out, 'reports/conversion-errors.json'), errors);
json(join(out, 'reports/format-adaptations.json'), adaptations);
json(join(out, 'reports/conversion-summary.json'), { counts, uniqueLibraries: indexes.length, diagnostics: errors.length,
  limitation: 'OBJ exports are staging assets. Engine material effects, LOD/state selection and final Blender/Godot integration remain separate.' });
console.log(JSON.stringify({ counts, diagnostics: errors.length }));
