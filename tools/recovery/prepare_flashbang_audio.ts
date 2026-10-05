/** Render the Mk141 flashbang report and the ringing-ears loop from the multiplayer banks.
 * Run from the repository root:
 * TSX_TSCONFIG_PATH=previous/recovery/reports/decoder-tsconfig.json node --import
 * ./previous/recovery/research/socom-unzipped/web/node_modules/tsx/dist/loader.mjs
 * tools/recovery/prepare_flashbang_audio.ts
 */
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { parseBankFile } from '../../previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src/bank';
import { SampleCache, renderSound } from '../../previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src/render';

const root = 'previous/recovery/native/audio/disc/BNKSTORE.ZAR-06e793c85d';
const directory = 'audio/flashbang';
mkdirSync(directory, { recursive: true });

function load(file: string) {
  const path = `${root}/${file}`;
  const bytes = readFileSync(path);
  const bank = parseBankFile(bytes);
  return { path, sha256: createHash('sha256').update(bytes).digest('hex'), bank, samples: new SampleCache(bank.vag) };
}

function write(file: string, left: Float32Array, right: Float32Array, rate: number, gain: number) {
  const mono = Float32Array.from(left, (x, i) => (x + right[i]) * 0.5 * gain);
  let peak = 0;
  for (const value of mono) peak = Math.max(peak, Math.abs(value));
  if (!peak) throw new Error(`Empty render ${file}`);
  if (peak > 1) throw new Error(`Clipping ${file}: ${peak}`);
  const wav = Buffer.alloc(44 + mono.length * 2);
  wav.write('RIFF', 0); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
  wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(rate, 24); wav.writeUInt32LE(rate * 2, 28);
  wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34); wav.write('data', 36);
  wav.writeUInt32LE(mono.length * 2, 40);
  for (let i = 0; i < mono.length; i++) wav.writeInt16LE(Math.round(mono[i] * 32767), 44 + i * 2);
  writeFileSync(`${directory}/${file}`, wav);
  return { path: `res://${directory}/${file}`, seconds: mono.length / rate, peak, sha256: createHash('sha256').update(wav).digest('hex') };
}

// The grenade's own report, as the bank authors it: original gain, no normalization.
const fx = load('00053-MP2_fx.bnk.bin');
const report = { sound: '.MARK_141_FLASH', source: fx.path, sha256: fx.sha256, index: fx.bank.names.get('.MARK_141_FLASH'), files: [] as any[] };
for (let variant = 0; variant < 3; variant++) {
  const choice = [0.1, 0.5, 0.9][variant];
  const pcm = renderSound(fx.bank, report.index!, fx.samples, { random: () => choice, maxSeconds: 8 });
  if (!pcm.voices || pcm.left.length / pcm.sampleRate >= 8) throw new Error('Empty or truncated .MARK_141_FLASH');
  report.files.push({ choice, sample_offsets: pcm.samples, ...write(`mark141_flash_${variant + 1}.wav`, pcm.left, pcm.right, pcm.sampleRate, 1) });
}

// The ringing is one looping sample that the console holds until the game stops it.
// The event swells for about 6 s, fades by about 11 s, then holds steady; the steady
// tail is taken from SETTLED and folded into a seamless buffer, and the game drives
// the envelope. The bank's level is very low (peak ~0.001), so it is raised here.
const am = load('00052-MP2_am.bnk.bin');
const ringIndex = am.bank.names.get('.RINGING_EARS')!;
const SETTLED = 14, LOOP = 6, FADE = 0.5;
const held = renderSound(am.bank, ringIndex, am.samples, { random: () => 0.5, loop: true, maxSeconds: SETTLED + LOOP + FADE, vol: 0x400, pan: 0 });
const fold = (x: Float32Array) => {
  const start = SETTLED * held.sampleRate, frames = LOOP * held.sampleRate, fade = FADE * held.sampleRate;
  const y = x.slice(start, start + frames);
  for (let i = 0; i < fade; i++) {
    const t = i / fade;
    y[i] = x[start + i] * Math.sin((t * Math.PI) / 2) + x[start + frames + i] * Math.cos((t * Math.PI) / 2);
  }
  return y;
};
const ring = { left: fold(held.left), right: fold(held.right) };
let ringPeak = 0;
for (let i = 0; i < ring.left.length; i++) ringPeak = Math.max(ringPeak, Math.abs(ring.left[i]), Math.abs(ring.right[i]));
const ringGain = 0.5 / ringPeak;
const ringing = { sound: '.RINGING_EARS', source: am.path, sha256: am.sha256, index: ringIndex, sample_offsets: held.samples,
  settled_from_seconds: SETTLED, source_peak: ringPeak, gain: ringGain, loop: true,
  ...write('ringing_ears.wav', ring.left, ring.right, held.sampleRate, ringGain) };

writeFileSync(`${directory}/sources.json`, JSON.stringify({
  recipe: 'tools/recovery/prepare_flashbang_audio.ts',
  decoder: 'previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src',
  note: 'Dry mono 48 kHz PCM. The report keeps the bank gain with three deterministic sequencer choices; the ringing loop is the event steady tail from 14 s, folded seamless (6 s, 0.5 s crossfade) and raised to peak 0.5; its authored 11 s swell is not used. No PS2 room reverb. How long the original rang is not decoded; the game sets it.',
  report, ringing,
}, null, 2) + '\n');
console.log(JSON.stringify({ report: report.files.map(f => f.seconds), ringing: ringing.seconds, ringPeak }));
