# Recovered firearm audio

Every selectable firearm now uses its original `ZWEAPON` record's `FireSoundClose` and `ReloadSound`. All **42 records** resolve in the multiplayer **MP2_FX** bank: **138 named events**, rendered with three deterministic sequencer choices each (**414 WAVs**). Medium and far reports are also installed and mapped at the original 9 m / 50 m thresholds. Own-gun playback uses the close report. Suppressed guns deliberately lack medium/far events in the source.

The M4A1 uses `.M4A1` / `.M4A1_RLD`, M9 `.M9_GUN` / `.M9_GUN_RLD`, and 552SD `.SIG_552_SIL` / `.SIG_552_SIL_RL`. Shared sounds are preserved as authored: F90 uses MP5 reports, Gyurza uses SIG 226 reports, and PKM shares the M63A reload. They are not unresolved fallbacks.

`resources/recovered/weapon_audio.json` records every gun/event mapping, bank path and SHA-256, sound index, sample offsets, sequencer choice, output duration, peak and SHA-256. The source is `previous/recovery/native/audio/disc/BNKSTORE.ZAR-06e793c85d/00053-MP2_fx.bnk.bin`. The existing recovery's `packages/sound/src` decoder runs the named 989snd grain sequences, SPU ADPCM, envelopes and pitch at 48 kHz. Rebuild from the repo root:

```sh
TSX_TSCONFIG_PATH=previous/recovery/reports/decoder-tsconfig.json node --import ./previous/recovery/research/socom-unzipped/web/node_modules/tsx/dist/loader.mjs tools/recovery/prepare_weapon_audio.ts
tools/dev import
tools/dev check
tools/dev test recovered_accuracy_regression
```

Add `--audit` to resolve all references without writing audio. Any missing name, empty render, clipping or truncated sequence fails extraction. Outputs are dry mono PCM for Godot spatial playback, without normalization or the old prototype pitch offsets. Godot supplies spatial attenuation; PS2 room reverb and its distance-volume curves are not reproduced. Three fixed sequencer choices approximate runtime bank randomness. Reloads start with the gameplay action and stop on swap, replacement, reset or death; their original timing is retained, while the gameplay reload duration remains editable. Shot tails overlap across rounds and swaps.

`recovered_weapon_audio.gd` caches streams by path and maps by source record ID, so shared meshes and suppressed profiles retain the right sounds. The Linux export inventory now includes every WAV as well as recovery JSON. `recovered_accuracy_regression` loads every variant and checks event dispatch, suppressed mappings and reload cancellation. Impact and casing effects are outside this firearm port; frag and claymore explosions still use prototype audio.

## Flashbang

`prepare_flashbang_audio.ts` (same command line as above) renders `.MARK_141_FLASH` from MP2_fx at bank gain, three sequencer choices, and `.RINGING_EARS` from MP2_am into `audio/flashbang/`, with provenance in `audio/flashbang/sources.json`. The ringing event swells for about 6 s, fades by about 11 s and then holds one looping sample; the recipe takes that steady tail from 14 s, folds it into a seamless 6 s loop (the import loops it forward) and raises it from its very low bank level. How long the original rang is not decoded. `combat_overlay.gd` rings the player's ears for twice the whiteout and drives the envelope itself. Gunfire, footsteps and blasts play on the `World` bus (`default_bus_layout.tres`); while ringing, that bus is ducked and low-passed, with a short attack so the bang still lands, and the ringing plays on Master past it. New world sounds should use the `World` bus.

Verification: the load check passed (120 files), and all 29 regression suites passed. A hidden rendered session captured nonzero mixer output from the M4A1 and 870, checked M9/AK-47/552SD event dispatch, and verified that swapping stops reload audio. It also inspected both debug pages, swapped to the scuba character, and confirmed a typed recoil value reaches the per-gun saved configuration. No runtime errors were reported. The exported Linux bundle itself was not rebuilt in this pass.
