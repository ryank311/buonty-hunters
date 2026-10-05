/** Render the recovered stone footfalls, then make three gameplay gait mixes.
 * Run from the repository root:
 * TSX_TSCONFIG_PATH=previous/recovery/reports/decoder-tsconfig.json node --import
 * ./previous/recovery/research/socom-unzipped/web/node_modules/tsx/dist/loader.mjs
 * tools/recovery/prepare_footsteps.ts
 */
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { parseBankFile } from '../../previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src/bank';
import { SampleCache, renderSound } from '../../previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src/render';

const source = 'previous/recovery/native/audio/disc/BNKSTORE.ZAR-06e793c85d/00001-M51_am.bnk.bin';
const bytes = readFileSync(source);
const bank = parseBankFile(bytes);
const samples = new SampleCache(bank.vag);
const directory = 'audio/footsteps';
mkdirSync(directory, { recursive: true });
const outputs = [];
for (const gait of ['walk', 'jog', 'sprint']) {
  for (let variant = 0; variant < 3; variant++) {
    const sound = gait === 'walk' ? '.STEALTH_STONE' : '.STEP_STONE';
    // Fixed sequencer choices keep extraction reproducible, including alternate tones.
    const choice = [0.1, 0.5, 0.9][variant];
    const rendered = renderSound(bank, bank.names.get(sound)!, samples, {
      random: () => choice, pitchMod: gait === 'sprint' ? -128 : 0, maxSeconds: 1,
    });
    const mono = Float32Array.from(rendered.left, (x, i) => (x + rendered.right[i]) * 0.5);
    // The sprint mix emphasizes the boot's low impact; it is an adaptation of STEP,
    // not a claim that the source bank contains a separately named sprint event.
    let low = 0;
    const smoothing = 1 - Math.exp(-2 * Math.PI * 350 / rendered.sampleRate);
    for (let i = 0; i < mono.length; i++) {
      low += smoothing * (mono[i] - low);
      if (gait === 'sprint') mono[i] += low * 0.65;
    }
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
    const file = `${gait}_${variant + 1}.wav`;
    writeFileSync(`${directory}/${file}`, wav);
    outputs.push({ file, sound, choice, sampleOffsets: rendered.samples, seconds: mono.length / rendered.sampleRate,
      peak: peak * gain, rms: Math.sqrt(power / mono.length) * gain });
  }
}
writeFileSync(`${directory}/sources.json`, JSON.stringify({ source, sha256: createHash('sha256').update(bytes).digest('hex'),
  decoder: 'previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src',
  recipe: 'tools/recovery/prepare_footsteps.ts',
  note: 'Stone surface only. Walk uses STEALTH; jog uses STEP; sprint adapts STEP down one semitone with extra low impact. Runtime supplies gait volume and contact timing.', outputs }, null, 2) + '\n');
console.log(`Rendered ${outputs.length} recovered footfalls to ${directory}`);
