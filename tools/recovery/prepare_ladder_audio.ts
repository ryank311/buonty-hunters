/** Render the recovered ladder sounds: the rung under a hand or boot, and the slide.
 * Run from the repository root:
 * TSX_TSCONFIG_PATH=previous/recovery/reports/decoder-tsconfig.json node --import
 * ./previous/recovery/research/socom-unzipped/web/node_modules/tsx/dist/loader.mjs
 * tools/recovery/prepare_ladder_audio.ts
 *
 * The climb clip's "ladder_rung" callbacks play .STEP_LADDER twice a cycle, and the
 * slide plays ~LADDER_SLIDE (local research 86-traversal.md, section 7).
 */
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { parseBankFile } from '../../previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src/bank';
import { SampleCache, renderSound } from '../../previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src/render';

const source = 'previous/recovery/native/audio/disc/BNKSTORE.ZAR-06e793c85d/00001-M51_am.bnk.bin';
const bytes = readFileSync(source);
const bank = parseBankFile(bytes);
const samples = new SampleCache(bank.vag);
const directory = 'audio/ladder';
const found = [...bank.names.keys()].filter((name) => /ladder/i.test(name));
console.log(`Ladder sounds in the bank: ${found.join(', ') || 'none'}`);
mkdirSync(directory, { recursive: true });
const outputs = [];
const wanted: [string, string, number][] = [
  ['rung_1.wav', '.STEP_LADDER', 0.1], ['rung_2.wav', '.STEP_LADDER', 0.5], ['rung_3.wav', '.STEP_LADDER', 0.9],
  ['slide.wav', '~LADDER_SLIDE', 0.5],
];
for (const [file, sound, choice] of wanted) {
  const id = bank.names.get(sound);
  if (id === undefined) {
    console.log(`${sound} is not in the bank; ${file} not written`);
    continue;
  }
  const rendered = renderSound(bank, id, samples, { random: () => choice, pitchMod: 0, maxSeconds: sound.startsWith('~') ? 3 : 1 });
  const mono = Float32Array.from(rendered.left, (x, i) => (x + rendered.right[i]) * 0.5);
  let peak = 0, power = 0;
  for (const value of mono) { peak = Math.max(peak, Math.abs(value)); power += value * value; }
  const gain = Math.min(0.85 / peak, 0.09 / Math.sqrt(power / mono.length));
  const wav = Buffer.alloc(44 + mono.length * 2);
  wav.write('RIFF', 0); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
  wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(rendered.sampleRate, 24); wav.writeUInt32LE(rendered.sampleRate * 2, 28);
  wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34); wav.write('data', 36);
  wav.writeUInt32LE(mono.length * 2, 40);
  for (let i = 0; i < mono.length; i++) wav.writeInt16LE(Math.round(mono[i] * gain * 32767), 44 + i * 2);
  writeFileSync(`${directory}/${file}`, wav);
  outputs.push({ file, sound, choice, sampleOffsets: rendered.samples, seconds: mono.length / rendered.sampleRate,
    peak: peak * gain, rms: Math.sqrt(power / mono.length) * gain });
}
writeFileSync(`${directory}/sources.json`, JSON.stringify({ source, sha256: createHash('sha256').update(bytes).digest('hex'),
  decoder: 'previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src',
  recipe: 'tools/recovery/prepare_ladder_audio.ts',
  note: 'The rung is the original STEP_LADDER, played at each "ladder_rung" callback of the climb cycle. The slide is one pass of LADDER_SLIDE; runtime loops it while sliding.', outputs }, null, 2) + '\n');
console.log(`Rendered ${outputs.length} recovered ladder sounds to ${directory}`);
