# Recovered recoil, accuracy and fire modes

The original `ZWEAPON.ZAR/zweapon.rdr` records now supply every playable recovered gun's firing modes, shot interval and standing/crouched/prone accuracy tables. All **39 firearm designs / 65 geometry variants** resolve to a record, including the seven standard loadout guns. The independent runtime catalogue retains all **86 original records**, their raw tokens and the source SHA-256; 42 firearm records are selectable across the installed models. Launchers remain inspection-only.

Press **B / L3** to cycle the equipped gun's supported modes. The HUD shows SEMI, BURST or AUTO. Primary weapons start on burst when supported, otherwise the highest supported mode; sidearms start on their highest mode. Modes persist through swaps. A burst fires up to three rounds while held and stops immediately on release. Semi requires a new pull. Switching mode, swapping or reloading cannot continue a held trigger into unintended shots; scoped view refuses mode changes.

In **Recovery Lab → Tab → Guns**, the profile selector appears when several original records share one mesh (552/552SD, SR-25 SD/SR-25, M63A/.PKM, 226/SR-1). This selects the source behavior, without adding accessory geometry. The separate `SP10_gyuraz` mesh explicitly uses record 13, SR-1 Gyurza, whose disc `ModelName` actually points to `sig226`; the override is recorded in the manifest.

## Rebuild and evidence

```sh
python3 tools/recovery/prepare_weapon_profiles.py
tools/dev import
tools/dev check
tools/dev test recovered_accuracy_regression recovered_hud_regression feel_regression weapons_regression
```

Source: `previous/recovery/native/scripts/disc/ZWEAPON.ZAR-496d80a9db/00000-zweapon.rdr.json`. Output: `resources/recovered/weapon_profiles.json`. No mesh rebuild or offline recovery directory is needed to run the game. Raw tokens are preserved because some records contain unpaired comment fragments; the extractor recognizes a field by a string followed by a list, instead of assuming even token indices. Numeric mode flags are normalized to integers in Godot, whose array membership checks distinguish floats from integers.

Behavioral evidence is the local `previous/recovery/research/socom-unzipped/web/redotcom/docs/research/84-accuracy-and-recoil.md`, which cites the SOCOM II ELF and reader parser. Principal functions: record parser `0x3cda30`; inherited stance tables `0x3c59c0` / `0x3c5a50`; accuracy tick `0x5c2670`; per-shot accuracy `0x5c3360`; tangent conversion `0x5bd100`; square sampling `0x592260`; mode counts/waits `0x5c0940` / `0x5c09f0`; mode cycling `0x5c4600`; scoped kick/sway `0x5b9280`. Runtime equations were independently implemented; no viewer implementation was copied.

## What the game uses

- Stance tables inherit stand → crouch → prone. The recorded defaults for movement multiplier, knock count and entry strength are 1, 3 and 1. `MaxFireMode` enables all modes through its value; explicit Single/Burst/Auto flags add their modes. This matters for the Glock, which declares `MaxFireMode 1` **and** `AutoMode`.
- Source `FireWait` is seconds for semi; burst and auto use `0.8 × FireWait`, with interval overshoot carried across physics ticks. M4A1: 0.12 / 0.096 s, or 625 rpm in auto. MP5: 0.1 / 0.08 s, or 750 rpm. Glock: 0.06 / 0.048 s, or 1,250 rpm.
- `recovered_accuracy.gd` stores reticle size and knock in original 640×448 HUD pixels. Movement targets `|velocity × 10|² / 65 × TargetDilateUponMovementMult`; turning/pitch adds `158.7 × angular_rate²`. Size opens at the recovered per-60Hz-tick dilation and closes at `TargetConstrict` per second, clamped by the stance's `TargetMin/Max`.
- Shots add `TargetDilateUponFire` plus the source burst scalar from weapon-wide `AccBurstCnt_*` / `AccScalar_*`. The similarly named **per-stance** `AccuracyBurstCnt_*` / `AccuracyScalar_*` fields were not read by the original engine and are preserved only as raw data.
- Unscoped shots move the whole reticle upward using `ReticuleKnock`, `KnockCount`, `KnockEntryStrength` and `ReticuleKnockMax`, returning at `ReticuleKnockReturn`. They do not pitch the camera. The first standing M4 shot climbs 4.8 px, subsequent shots 12 px, returning at 70 px/s. `RecoilPct` is preserved, but is not treated as an angle: its original destination was another body accumulator.
- Actual rays use the source's center-weighted square distribution (`u × abs(u)` independently per axis), its unnormalized cross-product basis, and `tan(tan(hfov))` conversion. The native branch applies the same pattern to each shotgun pellet, without adding the old prototype pellet cone. Spread in the debug digest means maximum square-corner angle at level aim.
- Reticle arms use exactly half the native size in third person; disc and arms share the native knock offset. No extra display easing is added on top of the accuracy state. The source's wider-than-drawn distribution is retained; the arms are not a hard bullet boundary.
- Scoped shots have zero random spread and use recovered `SniperDist*` sway divided by current magnification. `FireRifleKick*` supplies the first round's rise, distance and return. A second held round drops the scope until the trigger is released. Sway changes the round's direction, while the scope graphic stays fixed, matching the available reverse-engineering evidence.
- F1 exposes recoil and spread multipliers: **1 = recovered values**, 0 disables that contribution. They serialize with settings. Legacy angular knobs remain readable for old saves and non-recovered profiles, but the recovered path does not apply them a second time. Body recoil animation strength remains separate.

## Adaptations and limits

This ports weapon behavior into the existing controller, not the entire original kit/view state machine. Damage, ammunition, reloads, projectile speed/drop, pellet count, sounds and available scope zoom levels retain prototype family settings. Launchers, underbarrel fire and accessory states remain unimplemented.

Projection uses the recovered reference half-horizontal FOV 0.6109, preserving those angular profiles independently of the prototype's adjustable camera. The original aim/muzzle depth ratio is approximated as 1. HUD pixels map to the project's 640×480 presentation. Existing focus aim does not apply the retired 0.75 accuracy multiplier.

Movement and turn rates come from the current Godot controller. The original carried-air-velocity term is approximated by current horizontal velocity; look changes over 45° in one tick are treated as teleports. Scoped exertion uses current move input and angular motion as an approximation for original controller throttles; recovered decay, sway limits, oscillation, shot/entry increments and the 0.2 freeze threshold are retained. Original scope input-follow, breathing audio, complete zoom/view transitions and screen-shake fields are not ported. These limits should remain explicit in future fidelity comparisons.

## Validation

`recovered_accuracy_regression` pins source values and inheritance, coverage of every playable model, explicit flags, shared-model records, cadence, burst release/reload interruption, semi trigger edges, mode persistence, unscoped camera stability, scoped kick and square/sway direction equations. Combat movement tests measure actual Jolt impact patterns. Existing weapon, controller, HUD, swap and scope suites exercise the integration.

Rendered checks on 2026-10-05 covered a three-round M4 burst (27/30 remaining), reticle climb with stationary camera, a 552SD selected and equipped from its shared mesh, and the M40A1 scope's kick/sway. The hidden MCP session stopped without runtime errors.

Final load check passed (115 files). Deterministic extraction matched the checked-in JSON. All 31 recovered-accuracy checks passed, along with weapon, recovered-model, HUD, combat-movement, camera, harness and live-tuning checks. The new settings serialization check passed. The full 27-suite run and targeted rechecks also encountered concurrent work outside this port: a jump landing at 0.79 m on the 0.85 m obstacle, a `context_hud.gd:51` index error, and subsequently two old Y/route-timer expectations after Y was reassigned to contextual actions. Campaign-map and prone-lean failures from the initial run passed on recheck. Those implementations/assets were left untouched. A final `tools/dev shot lab_range --state` verified the complete BURST caption but also logged the context-HUD error; the earlier burst/browser/scope MCP inspection had no errors.
