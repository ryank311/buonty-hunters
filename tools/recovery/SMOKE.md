# Smoke grenade

The AN-M8 now uses its recovered **canister model**, **HUD icon** and **cloudpuff01** texture. The former effect was fourteen unshaded polygon spheres. Its replacement is a depth-clipped 3D density field rendered with 48-step ray integration on the project's Mobile renderer; it does not require Forward+ volumetric fog.

Smoke begins as a narrow feed at the canister cap. The body expands from that source, rolls upward through animated noise, builds an opaque core, and keeps spreading/rising while its density falls during the last 32% of its lifetime. The feed stops before the cloud clears. The configurable defaults are an 8 m radius and 18 s lifetime: about three times the former ground area, with vertical growth capped to keep the screen low. Rays and grain share 3×3 game-pixel cells, with stepped shading and nearest-filtered recovered puff detail to fit the game's art. Looking from inside integrates the same volume from the camera. Floors, walls and opaque characters still clip against full-resolution scene depth.

The burning canister remains a projectile: if its fuse expires in flight, it keeps falling and bouncing, and the plume follows it until it rests. The cloud and spent canister are removed at expiry, reset or map change. This is an authored smoke effect, not fluid simulation or an exact recreation of the PS2 particle engine; the whole young plume follows a moving source, and smoke transport does not solve around walls.

## Recovery evidence

`resources/recovered/smoke.json` records paths, hashes and archive provenance. The multiplayer MP2 `WEAP_MDL.ZED` supplies `a_smoke_grenade`: all 50 triangles retained, native attachment origin and 0.1 m/source-unit scale. The result is 8.7 × 7.4 × 21 cm. The export's below-origin note is intentional for a held/projectile attachment; the gameplay ray/bounce solver supplies collision. MP2 `ALPH_TXR.ZED` supplies the unchanged 64×64 `cloudpuff01.tif` alpha texture. The already-imported `hudw/grenade_smoke_icon.png` replaces the drawn grenade silhouette for smoke.

Recovery research `89-effects.md` §12 identifies `smoke_grenade → smoke_stream`: two sources emitting 2.5 puffs/s each, 5–7 s puff lifetime, growing about tenfold, with 20 s of emission. `85-grenades.md` §9.6 identifies `cloudpuff01.tif`, grey 0.6/0.4, and original Timer2 40 s. These inform the source feed, rolling detail and delayed dispersal; the current game keeps its existing tunable duration. The puff alpha modulates the volumetric density, combined with a small seamless 3D noise texture.

## Rebuild

1. `previous/recovery/.venv/bin/python tools/recovery/prepare_smoke.py`
2. Submit `previous/recovery/staging/smoke/canister.py` through Blender MCP. This saves `art/blender/recovered_smoke_grenade.blend`.
3. `tools/dev blender export recovered_smoke_grenade`
4. `tools/dev import`, then `tools/dev check` and `tools/dev test weapons_regression throw_regression`.

Initial checks covered the first jet, growth, mature screen, inside view and late wisps. A forced airborne ignition fell from 2.6 m to rest at 0.07 m with one cloud and zero emitter-position error. Before the wider pixelated refinement, the hidden 640×480 Lab view on the Radeon Pro 560X averaged 2.47 ms viewport GPU time without smoke and 4.56 ms with one mature plume (30 frames after warmup). Those measurements describe the original narrower effect. The recovered canister was inspected through the Blender preview and in game.

The wider pixelated refinement passed `tools/dev check` (137 files) and all five prototype smoke, movement, harness, throw and weapon suites. Hidden Crossroads views covered the vent at 0.35 s, growing cloud at 2 s, mature cloud, inside view and dispersal at 16.5/17.5 s. Held frag, smoke and flash throws all limited forward speed to the profile's 2.6 m/s walk, returning to 6.5 m/s after release. Crouch and prone stayed at their slower profile speeds; firearm movement remained unrestricted. The cap includes the initial press and removes carried running momentum.

The weapon equipment test now waits for the native throw's actual release instead of assuming a projectile exists after half a second. This prevents an empty-array error from skipping the later smoke assertions. Its final direct headless run completed with zero failures and no runtime errors, explicitly passing smoke growth, canister attachment and expiry cleanup.
