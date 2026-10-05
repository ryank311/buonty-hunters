# Recovered HUD and crosshairs

The game now draws the original rifle, sidearm, shotgun, grenade and scope textures. Open [the HUD catalogue](../../art/ui/recovered/index.html) locally in a browser to inspect all **174 textures**; filter `ret_` for crosshairs. Each image links to its unchanged native-resolution PNG. The remaining HUD graphics are available for integration; the minimap, health strips, weapon silhouettes and menus still use the prototype UI.

## Assets and rebuilding

`art/ui/recovered/` contains `hud/` (37 textures), `hud2/` (72) and `hudw/` (65 weapon/equipment icons). All 5,916 recovered HUD texture occurrences across 34 map archives resolve to these same 174 names and PNG hashes; no conflicting palette variants were found. `resources/recovered/hud_catalogue.json` records the source TXR/PAL archives, recovery path, dimensions, SHA-256, original GS flags and occurrence count for every texture. The representative copies come from M51. Nothing loads from the ignored recovery tree at runtime.

Rebuild from the existing recovery without Blender:

```sh
python3 tools/recovery/prepare_hud.py
tools/dev import
tools/dev check
tools/dev test recovered_hud_regression combat_movement_regression camera_gait_regression weapons_regression
```

The preparation script verifies the recovered hashes before copying, rejects conflicting same-name variants and regenerates the HTML catalogue. It preserves the decoded RGBA PNG bytes, including the extraction's PS2 alpha conversion. Do not paint over those source textures to fix placement; their transparent padding is meaningful.

## Runtime behavior

- `scripts/ui/spread_reticle.gd` selects rifle/SMG/unscoped sniper, sidearm, shotgun or equipment from the equipped profile. The original rifle uses a 64×64 fixed disc and four 32×32 arm quads; the pistol uses 32×32 and 16×16. The visible rifle stripe lies 1.5 pixels inside its texture's right edge, and the pistol stripe 1 pixel inside. Center these stripes on the cardinal axes; centering the entire bitmap produces a pinwheel.
- Coordinates map the original 640×448 HUD into the project's fixed 640×480 presentation, independently of window size. Recoil moves the disc and arms together using the existing shot-aligned aim projection. The source third-person convention halves the accuracy displacement; movement/fire use the actual weapon cone, and the shotgun includes pellet spread. The disc never scales with bloom.
- Arms use recovered engine color readings: neutral `(200,200,24)`, friendly `(24,200,44)`, enemy `(200,24,44)`. The tint queries the real unobstructed muzzle/aim ray, recognizes living combat actors within 32 m, and stays neutral for dead actors or practice boards. It is not an aim assist or a hit-confirmation flash.
- The recovered `ret_accuracy` pip projects a nearby muzzle obstruction onto the HUD, clamps its displacement to ±200 source pixels, hides inside the fixed disc, and fades when the obstruction clears. Random pellet rays never control the pip or target tint.
- The original grenade aiming cross is at the top of `ret_grenade_02`; its meter hangs below the aim point. `ret_grenade_01` fills from the bottom as the existing throw charge rises and clears on release. Equipment has no firearm spread arms. Claymore currently shares the unfilled equipment graphic.
- `scripts/ui/recovered_scope.gd` mirrors the two recovered scope quadrants into four 320×320 quads around the source frame center, sampling UVs 0.01–0.99. `combat_overlay.gd` draws this instead of the procedural lens/cross. The third-person reticle hides while scoped, eliminated or in a modal. The zoom caption sits bottom-center to avoid the current weapon strip.

## Evidence and remaining differences

Source PNGs: `previous/recovery/converted/textures/shared/M51/HUD2_TXR-feef96d255-55de0527/`, originally `archives/M51/RUN/COMMON/HUD2_TXR.ZED` and `HUD2_PAL.ZED`. Additional HUD configuration is in `previous/recovery/native/scripts/disc/READERC.ZAR-1b7df1c973/00013-hud.rdr.json`; weapon tuning is in `native/scripts/disc/ZWEAPON.ZAR-496d80a9db/00000-zweapon.rdr.json` under the same recovery root.

The local format research `previous/recovery/research/socom-unzipped/web/redotcom/docs/research/84-accuracy-and-recoil.md`, sections 2, 3, 9 and 16, identifies the HUD coordinate frame, bitmap families, color constants, third-person halving, scope quadrants and sidearm dimensions. Its cited original functions include `BitmapReticule_Init` (0x2178c0), `BitmapReticule_UpdateAccuracy` (0x215250), `ChangeReticule` (0x213e20), and the color update at 0x215c10. The runtime was implemented independently; no decoder/viewer implementation was copied.

This is a source-art pass, **not yet an exact original ballistics simulation**. Weapon profiles still use our angular spread, stance/focus multipliers, recoil recovery and camera kick. Outward/inward display easing remains 35/9 per second; the original per-weapon `TargetMin/Max`, linear dilation/constriction, turn-rate bloom, square shot distribution and unscoped reticle-only recoil have not been ported. The half-displacement is an original-style indicator, not a literal screen-space boundary containing all bullets. Grenade fill mapping and shotgun quarter placement are adaptations to the current gameplay values. Original identification timers, launchers, range text, NVG/binocular views and threat indicators remain future work; their textures are catalogued. Scope zoom levels and ballistic drop remain those of the current marksman weapon.

## Checking it

Run the game and compare **1 / 2** for rifle/pistol, then choose **Breacher** and **Marksman** through the class menu. Run, fire, stop, focus aim and change stance. The arms should open and settle while the disc stays fixed; recoil should lift the complete aim point. Hold a grenade throw to fill its meter. Aim at a living enemy/teammate for red/green, and aim past close cover with the muzzle blocked to see the accuracy pip. Scope in/out and open menus: there should never be two crosshairs.

`recovered_hud_regression` exercises these loadout, shooting, throw, target-team, obstruction and visibility paths (16 checks). Existing camera tests verify recoil/shot projection and fixed-resolution centering; weapon tests cover scope behavior. PNG hashes are also verified directly against the recovery manifest. See [the rendered comparison](../../docs/recovered-crosshairs.png) for the installed sprites.

Validated 2026-10-05: `tools/dev import`; `tools/dev check` (95 files); `tools/dev test` (20 suites, 600 checks); all 174 texture hashes; live 640×480 rifle, pistol, shotgun, scope, grenade-charge and running-burst frames. The final hidden renderer session stopped with no runtime errors. Concurrent movement work updated its own legacy expectations during this pass; the final full run includes those updates.
