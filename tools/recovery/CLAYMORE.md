# Claymore and remote

The M18 claymore uses its recovered **model**, **placing clip**, **HUD icon** and **sounds**, and follows the original's rules as `85-grenades.md` §9.7 reads them from the decompiled game: the claymore is **remote** (no tripwire, no proximity, no fuse); placing plays the kneel and the charge goes down under the right hand at 1.3 s with the SEAL's facing; the **Detonator** (record 193) joins the kit while one of the soldier's claymores is down and is selected at once; firing it sets off that soldier's claymores within 500 units (50 m), then the claymore slot comes back up (the rifle when none are left). Up to four can be down; none is placed while moving faster than 3.2 units/s (0.32 m/s) or onto ground more than 10 units (1 m) below the feet.

In game the Detonator is **CLAYMORE REMOTE** (`resources/weapons/claymore_remote.tres`, kind `detonator`). `PracticeWeapon` appends it after the class's slots while a claymore is down and removes it when none is (key 5, or D-pad right through the equipment). Its count is the claymores down. Moving off before the charge is down takes the claymore back up, unused.

## Recovery evidence

`resources/recovered/claymore.json` records paths, hashes and archive provenance. MP2 `WEAP_MDL.ZED` supplies `claymore` (80 triangles, 30 × 7 × 33 cm) and `detonator` (74 triangles), both textured by the unchanged 64×64 `claymore.tif`. The claymore keeps source Y-up; its convex face (source −Z) is Godot forward, so a claymore placed facing the soldier's way fires away from them. The detonator keeps the gun convention (source +X becomes Godot −Z) and is turned 90° in the hand by `practice_weapon.gd`. The HUD uses the already-imported `hudw/claymore_icon.png` and `hudw/detonator_icon.png`.

`scripts/actors/recovered_place.gd` layers `seal_p_place_claymore` (the pistol-carry variant; equipment is held in the pistol posture) over the body, whole while standing and upper body only otherwise. The right hand is lowest exactly at 1.3 s at native speed, the original's placing timer. The research also lists `playback 2.7` / 2.60 s for the clip; that reading does not put the hand on the ground at 1.3 s, so the clip plays at native speed (1.8 s).

`tools/recovery/prepare_claymore_audio.ts` renders from MP2_fx at bank gain: `.M18_CLAYMORE` (the claymore zAnim's report, three sequencer choices), `.PLACE_CHARGE` (`c4_start`, when the charge is down) and `.GUN_EMPTY`. No bank holds a detonator event; the dry trigger click stands in for the clacker and is marked as an adaptation in `audio/claymore/sources.json`.

Damage keeps the game's tunable values (260 within 10 m, cone `BLAST_DOT` 0.35, about 70° either side). The original's are `Explosion_Damage` 16 to 25 m, an 84.4° cone and 1/32 outside it; they are not adopted. The blast's look is an authored fan (`blast_fx.gd` `cone()`), not the original `claymore` zAnim (sparks, dust, fire, flying bits).

## Rebuild

1. `previous/recovery/.venv/bin/python tools/recovery/prepare_claymore.py`
2. Submit `previous/recovery/staging/claymore/claymore.py` and `detonator.py` through Blender MCP (paste the text; safe mode refuses `exec`). They save `art/blender/recovered_claymore.blend` and `recovered_detonator.blend`.
3. `tools/dev blender export recovered_claymore recovered_detonator`
4. `TSX_TSCONFIG_PATH=previous/recovery/reports/decoder-tsconfig.json node --import ./previous/recovery/research/socom-unzipped/web/node_modules/tsx/dist/loader.mjs tools/recovery/prepare_claymore_audio.ts`
5. `tools/dev import`, `tools/dev check`, `tools/dev test weapons_regression`.
