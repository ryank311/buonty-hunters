/** Decode the equipped guns' named 989snd events, with reproducible provenance.
 * TSX_TSCONFIG_PATH=previous/recovery/reports/decoder-tsconfig.json node --import
 * ./previous/recovery/research/socom-unzipped/web/node_modules/tsx/dist/loader.mjs
 * tools/recovery/prepare_weapon_audio.ts [--audit]
 */
import { readFileSync, readdirSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { parseBankFile } from '../../previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src/bank';
import { SampleCache, renderSound } from '../../previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src/render';

const root = 'previous/recovery/native/audio/disc/BNKSTORE.ZAR-06e793c85d';
// Prefer one complete multiplayer bank, then borrow exact names from other MP banks.
const paths = readdirSync(root).filter(p => /-MP\d+_fx\.bnk\.bin$/.test(p)).sort((a, b) =>
  Number(!a.includes('-MP2_fx.')) - Number(!b.includes('-MP2_fx.')) || a.localeCompare(b));
const banks = paths.map(path => {
  const bytes = readFileSync(`${root}/${path}`);
  const bank = parseBankFile(bytes);
  return { path: `${root}/${path}`, sha256: createHash('sha256').update(bytes).digest('hex'), bank, samples: new SampleCache(bank.vag) };
});
const profiles = JSON.parse(readFileSync('resources/recovered/weapon_profiles.json', 'utf8'));
const guns = JSON.parse(readFileSync('resources/recovered/weapons.json', 'utf8')).weapons;
const ids = new Set<string>(guns.filter((g: any) => g.playable).flatMap((g: any) => profiles.models[g.id] ?? []));
const keys = { fire_close: 'FireSoundClose', fire_med: 'FireSoundMed', fire_far: 'FireSoundFar', reload: 'ReloadSound' };
const records: Record<string, any> = {};
const sounds: Record<string, any> = {};
const missing: string[] = [];
for (const id of [...ids].sort((a, b) => Number(a) - Number(b))) {
  const profile = profiles.records[id];
  const record: Record<string, any> = { name: profile.name };
  for (const [event, key] of Object.entries(keys)) {
    const index = profile.raw.indexOf(key);
    const name = index >= 0 ? profile.raw[index + 1]?.[0] : null;
    record[event] = typeof name === 'string' && /^[.~!]/.test(name) ? name : null;
    if (!record[event] || sounds[name]) continue;
    const source = banks.find(b => b.bank.names.has(name));
    if (!source) { missing.push(`${profile.name}: ${key} ${name}`); continue; }
    sounds[name] = { source: source.path, sha256: source.sha256, bank: source.bank.name, index: source.bank.names.get(name), files: [] };
  }
  records[id] = record;
}
console.log(JSON.stringify({ guns: ids.size, sounds: Object.keys(sounds).length, missing, records }, null, 2));
if (missing.length) throw new Error('Unresolved weapon sounds; do not substitute another gun');
if (!process.argv.includes('--audit')) {
  mkdirSync('audio/weapons', { recursive: true });
  for (const [name, sound] of Object.entries(sounds)) {
    const source = banks.find(b => b.path === sound.source)!;
    for (let variant = 0; variant < 3; variant++) {
      const choice = [0.1, 0.5, 0.9][variant];
      const pcm = renderSound(source.bank, sound.index, source.samples, { random: () => choice, maxSeconds: 8 });
      if (!pcm.voices || !pcm.peak || pcm.left.length / pcm.sampleRate >= 8) throw new Error(`Empty or truncated event ${name}`);
      const mono = Float32Array.from(pcm.left, (x, i) => (x + pcm.right[i]) * 0.5);
      let peak = 0;
      for (const value of mono) peak = Math.max(peak, Math.abs(value));
      // Keep the bank's relative gain, envelope, timing and pitch; no normalization.
      if (peak > 1) throw new Error(`Clipping event ${name}: ${peak}`);
      const wav = Buffer.alloc(44 + mono.length * 2);
      wav.write('RIFF', 0); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
      wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
      wav.writeUInt32LE(pcm.sampleRate, 24); wav.writeUInt32LE(pcm.sampleRate * 2, 28);
      wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34); wav.write('data', 36);
      wav.writeUInt32LE(mono.length * 2, 40);
      for (let i = 0; i < mono.length; i++) wav.writeInt16LE(Math.round(mono[i] * 32767), 44 + i * 2);
      const file = `${name.charCodeAt(0)}_${name.slice(1).toLowerCase().replace(/[^a-z0-9_]/g, '_')}_${variant + 1}.wav`;
      writeFileSync(`audio/weapons/${file}`, wav);
      sound.files.push({ path: `res://audio/weapons/${file}`, choice, seconds: mono.length / pcm.sampleRate,
        peak, sample_offsets: pcm.samples, sha256: createHash('sha256').update(wav).digest('hex') });
    }
  }
  writeFileSync('resources/recovered/weapon_audio.json', JSON.stringify({
    recipe: 'tools/recovery/prepare_weapon_audio.ts',
    decoder: 'previous/recovery/research/socom-unzipped/web/redotcom/packages/sound/src',
    weapon_source: profiles.source, weapon_sha256: profiles.sha256,
    note: 'Dry mono 48 kHz PCM from named multiplayer bank events. Original pitch/envelope/gain, three deterministic sequencer choices. No PS2 room reverb. MP2 preferred; exact names borrowed when absent.',
    distance_med: 9, distance_far: 50, records, sounds,
  }, null, 2) + '\n');
  console.log(`Rendered ${Object.keys(sounds).length * 3} weapon sounds`);
}
