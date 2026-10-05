/** Render the claymore's blast, its placing and the detonator's click from the multiplayer bank.
 * Run from the repository root:
 * TSX_TSCONFIG_PATH=previous/recovery/reports/decoder-tsconfig.json node --import
 * ./previous/recovery/research/socom-unzipped/web/node_modules/tsx/dist/loader.mjs
 * tools/recovery/prepare_claymore_audio.ts
 */
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { parseBankFile } from '../../previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src/bank';
import { SampleCache, renderSound } from '../../previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src/render';

const source = 'previous/recovery/native/audio/disc/BNKSTORE.ZAR-06e793c85d/00053-MP2_fx.bnk.bin';
const bytes = readFileSync(source);
const bank = parseBankFile(bytes);
const samples = new SampleCache(bank.vag);
const directory = 'audio/claymore';
mkdirSync(directory, { recursive: true });

// The claymore's zAnim plays .M18_CLAYMORE; placing plays c4_start's .PLACE_CHARGE. The
// bank has no detonator sound: .GUN_EMPTY's dry click stands in for the clacker.
const EVENTS: Record<string, { file: string, variants: number, note?: string }> = {
  '.M18_CLAYMORE': { file: 'm18_claymore', variants: 3 },
  '.PLACE_CHARGE': { file: 'place_charge', variants: 1 },
  '.GUN_EMPTY': { file: 'detonator_click', variants: 1, note: 'Adaptation: no detonator event exists in the banks' },
};
const sounds: Record<string, any> = {};
for (const [name, spec] of Object.entries(EVENTS)) {
  const index = bank.names.get(name);
  if (index === undefined) throw new Error(`Missing ${name}`);
  const sound = sounds[name] = { index, note: spec.note, files: [] as any[] };
  for (let variant = 0; variant < spec.variants; variant++) {
    const choice = [0.1, 0.5, 0.9][variant];
    const pcm = renderSound(bank, index, samples, { random: () => choice, maxSeconds: 8 });
    if (!pcm.voices || pcm.left.length / pcm.sampleRate >= 8) throw new Error(`Empty or truncated ${name}`);
    const mono = Float32Array.from(pcm.left, (x, i) => (x + pcm.right[i]) * 0.5);
    let peak = 0;
    for (const value of mono) peak = Math.max(peak, Math.abs(value));
    // Bank gain, envelope and pitch kept; no normalization.
    if (peak > 1) throw new Error(`Clipping ${name}: ${peak}`);
    const wav = Buffer.alloc(44 + mono.length * 2);
    wav.write('RIFF', 0); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
    wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
    wav.writeUInt32LE(pcm.sampleRate, 24); wav.writeUInt32LE(pcm.sampleRate * 2, 28);
    wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34); wav.write('data', 36);
    wav.writeUInt32LE(mono.length * 2, 40);
    for (let i = 0; i < mono.length; i++) wav.writeInt16LE(Math.round(mono[i] * 32767), 44 + i * 2);
    const file = spec.variants > 1 ? `${spec.file}_${variant + 1}.wav` : `${spec.file}.wav`;
    writeFileSync(`${directory}/${file}`, wav);
    sound.files.push({ path: `res://${directory}/${file}`, choice, seconds: mono.length / pcm.sampleRate, peak,
      sample_offsets: pcm.samples, sha256: createHash('sha256').update(wav).digest('hex') });
  }
}
writeFileSync(`${directory}/sources.json`, JSON.stringify({
  recipe: 'tools/recovery/prepare_claymore_audio.ts', source, sha256: createHash('sha256').update(bytes).digest('hex'),
  decoder: 'previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src',
  note: 'Dry mono 48 kHz PCM at bank gain; deterministic sequencer choices. No PS2 room reverb.', sounds,
}, null, 2) + '\n');
console.log(JSON.stringify(Object.fromEntries(Object.entries(sounds).map(([n, s]) => [n, s.files.map((f: any) => [f.seconds.toFixed(2), f.peak.toFixed(2)])]))));
