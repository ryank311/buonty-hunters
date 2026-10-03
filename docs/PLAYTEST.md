# First playable review

October 3, 2026. This is an offline movement and aiming graybox for testing the design's fundamentals. Open `project.godot` in Godot 4.7 and press F5. The original low-poly soldier and muted environment are placeholders for judging silhouette, scale, and camera position; final character animation and PS2-style environment art come later.

## Ten-minute first session

1. Start in **Old Quarter**. Walk out of the western spawn, explore the Market, then compare the northern Courtyard and southern Service Passage routes. Take both stairs to the Balcony. Look for useful cover, confusing turns, empty stretches, and spaces that feel too narrow or too wide.
2. Try **Shift** walking, **C** crouching, **Z** going prone, **Space** jumping/rising, and **Q/E** leaning. Back into walls and corners while turning the camera. Approach low cover while aiming with the right mouse button. The camera should recover when you leave an obstruction.
3. Press **F2** for the **Movement Lab**. Use the marked lane to judge speed and stopping distance. Try doors, all ramps, stairs, the low ceiling, and the prone tunnel. A blocked stance change should leave you in the current stance.
4. Press **N** to cycle lab starts, including the range position. Shoot the teal targets with the left mouse button; successful hits flash gold. Hold to fire and press **R** to reload. Compare the camera's view with the muzzle's actual clearance: an orange reticle and bar indicate an obstructed muzzle.
5. Press **F1** and change one setting at a time. Start with run speed, camera distance, and camera side offset. Resume and repeat the same route. Use **T** to time a route and **F3** for position, speed, frame rate, and camera-arm diagnostics. **Backspace** resets the player and practice state.

The menu includes **Restore all defaults**. Tuning saves when you resume and loads on the next normal launch. Focus loss or controller disconnection opens the menu and releases the mouse. Existing settings from the first build receive the new acceleration/braking defaults once; camera preferences remain intact.

## Movement and recoil comparison

The updated gait uses fixed-length thigh/shin segments and a knee bend toward each foot's facing direction. Strafe and diagonal movement turn the hips/feet toward travel, with a partial torso turn while the weapon stays aligned to aim. Rearward movement uses a backpedal. Acceleration is now 18 m/s² and braking 24 m/s²; at 4.5 m/s this gives roughly 0.25 seconds to full speed and 0.19 seconds to stop. The body compresses during loaded steps, changes of speed, and landings. **Movement → Body weight** changes that animation response independently of speed.

The leg revisions correct the standing proportions: approximately 12° of neutral knee flex replaces the previous forced 58° crouch. Both boots rest flat when idle. During travel the boot uses a restrained heel-contact/flat-support/toe-off cycle, with at most 4.5 cm swing clearance. Pelvis height adapts to leg reach rather than pulling a planted ankle upward. The latest pass also fixes a separate mesh-transform bug: limb length now scales on the limb's local axis before rotation. Previously, valid joint positions could still produce visibly stretched, misplaced arms and legs.

The latest supplied SOCOM screenshots guide the new ready stance: the upper back leans forward about 9° at rest and 13° during travel, the head sits forward over the rifle, and the support foot is slightly ahead. The rifle pitches around its shoulder contact rather than floating below it. Both arms have fixed lengths and hands attached to the grips; the support hand shifts along the handguard at extreme aim angles. Focus aim tucks the head closer to the sights. Hips and waist turn into a strafe while the shoulders counter-turn enough to keep the weapon reachable. Crouch and prone transitions blend instead of snapping. Prone visual gun pitch stays clear of the floor while the camera and muzzle rays still resolve the aimed surface.

The proxy now uses tapered, faceted cloth volumes, a boonie hat, webbing, and belt pouches to make the rear silhouette easier to compare with the references. Software projections of the actual meshes were inspected in idle, running, strafing, crouching, pistol, and prone poses. This is still an original procedural proxy, not finished character art or a claim of exact SOCOM animation timing. Judge full-speed movement in an interactive F5 session.

[Current pose sheet](posture-preview.png): top row shows rifle idle and running; middle row shows crouched poses; bottom row shows pistol, strafing, and prone. This is a software projection of the in-project meshes, not an in-engine gameplay screenshot.

At the range, compare a single rifle shot, a three-shot burst, and a full magazine at 10, 25, and 50 metres. Repeat while moving, crouched, prone, and focused with LT/right mouse. Switch to the pistol and repeat with distinct trigger pulls. The expanding reticle shows the shot cone; camera climb is separate from that spread.

Open **Start/F1 → Rifle recoil** or **Pistol recoil**. Use LB/RB to switch tuning pages, up/down to select, and left/right to change a value. These pages tune each gun independently:

| Setting | What to judge |
| --- | --- |
| Aim kick per shot | How far each shot lifts the view |
| Side kick per shot | How much a burst wanders horizontally |
| Recovery delay | Whether a continuing burst accumulates climb |
| Recovery speed | How quickly aim settles after releasing fire |
| Maximum aim climb | The limit during sustained fire |
| Spread growth per shot | How quickly continuous fire opens the shot cone |
| Visible weapon kick | The rifle/pistol's backward and upward movement |

The starting rifle uses 0.42° vertical kick, 0.16° side kick, 0.14 seconds recovery delay, 9°/second recovery, and 6° maximum climb. The pistol uses 0.95°, 0.22°, 0.12 seconds, 11°/second, and 7°. Crouch, prone, and focused aim improve stability. The values are our SOCOM-inspired playtest preset, not recovered original engine constants; compare the handling before calling it authentic. [Research basis](RESEARCH.md#recoil-and-sidearm-playtest-baseline).

To isolate camera recoil, set visible weapon kick and vibration to zero temporarily; to isolate burst accuracy, set spread growth to zero. Those controls affect different parts of the result. Restore defaults after experiments. Controller vibration is under the **Controller** page and can be disabled.

## Current boundaries

The rifle has automatic fire and 30 loaded / 90 reserve rounds. The semi-auto pistol has 12 loaded / 36 reserve, with one shot per trigger pull. **D-pad left/right** or **1/2** selects rifle/pistol, with a short draw time. Each gun keeps its own loaded/reserve counts. Switching cancels a reload; ammunition transfers only when a reload completes. An empty gun does not auto-switch. Release the trigger after switching before firing the pistol. D-pad down/Backspace resets and refills both.

Both guns use instant hitscan, with recoil, spread, synthesized sound, hit feedback, and camera/muzzle obstruction checks. A successful surface hit creates a persistent bullet-hole decal at the actual ray intersection. Marks follow moving targets, align to surface normals, and clip to the edges of box-shaped cover. Marks survive reloads and weapon swaps; the oldest retires after 128 active marks. Resetting, cycling spawns, or changing levels clears them. Rifle and pistol impact diameters default to 11 cm and 8 cm including chipped edges; edit `impact_diameter` in their weapon resources to tune this. Misses and inside-solid hits without a surface normal create no floating mark.

Try a tight burst on a wall, inspect it close up, then shoot the moving target and the edge of cover. Check that a blocked muzzle marks the cover instead of the target beyond it. The implementation uses small transparent surface meshes with one shared texture/material, avoiding the Mobile renderer's limit of eight projected `Decal` nodes per mesh. Box hits are clipped; complex future terrain meshes will need a separate conformity pass. [Godot decal documentation](https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html).

Armor, body-part damage, combat damage, and combat balance remain future work. Targets are test fixtures; there are no bots, deaths, rounds, objectives, or networking.

Gamepad input has adjustable look speed, focused aim sensitivity, dead zone, inversion, and vibration. Left/right sticks move/look; A jumps; B taps to crouch or holds to go prone; LB/RB lean; LT/RT aim/fire; X reloads; Start or Back/Select opens tuning. D-pad up cycles spawn; down resets; left/right equips weapons. Y starts/stops the timer, L3 holds slow walk, and R3 toggles diagnostics. Partial movement-stick deflection also controls speed. In menus, LB/RB changes page, up/down selects, left/right adjusts, A confirms, and B/Start resumes. Level selection is in the menu. Bindings are fixed in this build, and physical hardware still needs testing.

Following the supplied SOCOM screenshots, the HUD now uses compact floating text and thin translucent strips instead of large dark cards. The strips have no border and default to 18% opacity; change **Camera → HUD backing opacity** in the tuning menu. Location is at the top left. The circular navigation map is at the top right. Bottom left shows a rifle/pistol silhouette, AUTO/SEMI mode, loaded/reserve ammunition, magazine equivalents, a thin health bar, and reload/draw/empty status only when applicable. Magazine equivalents round reserve rounds upward to the next magazine; the exact reserve count remains visible. Bottom right shows your stance/health and four explicitly open squad slots. The route timer appears above it while timing or after a recorded lap. Health resets to 100; incoming damage and AI squad members remain future work. Diagnostic speed/hit counts and help are in the optional R3/F3 display.

The map is centered on the player and rotates with aim facing. It includes actual collision footprints from the current level, a view sector, and a north indicator. The yellow diamond is the player; the cyan diamond marks the currently selected reset spawn, clamped to the rim if outside the 38 m range. It does not invent teammates, enemies, or objectives. Switching test levels rebuilds its geometry.

Try resizing the window, swapping weapons, and reloading; the mode and ammo readout should remain visible throughout. Half-resolution 3D leaves the HUD at full layout resolution. It is an optional visual comparison, not the final retro rendering treatment.

## What to report

Record the **level/location, stance, input device, and tuning values** with each observation. Useful examples: “At the Arch, the camera moves too close when crouched against the left wall,” or “At 4.5 m/s, the Service Passage crossing takes too long.” Prioritize camera comfort, movement response, body/cover agreement, route readability, and aim visibility.

Decide movement and camera dimensions before investing in finished map art. The next increment should respond to this playtest; the initial numbers are hypotheses.

## Verification and remaining checks

The automated suite runs the real Godot/Jolt controller at a fixed 60 Hz. It checks spawn/floor stability, speed and diagonal normalization, braking, jump and landing, crouch/prone clearance, prone turning beside a wall, stairs, camera retraction/recovery, target hits, magazine/reload/cadence behavior, muzzle obstruction, menu bounds, movement/target suspension in menus, repeatable resets, both town balcony stairs, all ten town spawn clearances, and continuous traversal of each of the three town routes.

The additional `feel_regression.gd` suite checks knee direction and limb lengths over standing/crouched strides, torso/hip turns, landing compression, real injected controller input events, menu focus and controller-only level selection, no leaked menu actions, finite ammunition, reload cancellation, independent magazines, semi-auto fire, recoil accumulation/recovery/caps, stability modifiers, and settings serialization. Recoil recovery is also compared at 30/60/120 updates per second. These injected events exercise the actual InputMap and UI handlers; they do not certify a physical device's mapping or vibration driver.

**Latest result: 176 checks passed (35 traversal/session + 58 handling/controller + 35 HUD/map + 31 hitscan/decals + 17 posture).** With the weighted defaults, automated full spawn-to-spawn routes took 32.10 simulated seconds through Market, 41.57 through Courtyard, and 32.10 through Service Passage. These are scripted waypoint runs, not human playtest or first-contact measurements.

The impact suite checks immediate rifle/pistol hits, muzzle obstruction, wall/floor/ceiling alignment, rotated cover edges, moving-surface attachment, shot guards, misses, persistence, the 128-mark budget, destroyed surfaces, resets, and level changes. The posture suite checks the actual rendered limb transforms against their endpoints across standing/crouching/prone, all cardinal movement directions, the full aim range, recoil, and draw poses. It also checks shoulder contact, focus posture, anatomical limb lengths, foot connection during transitions, prone elbow clearance, and outward-facing mesh geometry.

The HUD/map suite checks safe margins, text bounds, and panel separation at 960×540, 1280×720, 1024×768, 1920×1080, and 2560×1080 output sizes; weapon/mode/ammo changes; persistent ammo during reload; health updates/reset; the five squad slots; retro resolution independence; and tuning-menu bounds. It also checks the compact translucent styling, actual minimap geometry, circular clipping, player centering, heading rotation, and map changes. Five added gait checks cover neutral knee flex, flat idle boots, grounded support, low swing clearance, and restrained foot roll.

Headless import and runtime checks execute with Godot 4.7. Graphical launches in this automation environment abort before engine initialization, including a fallback renderer attempt. Rendered appearance, audio balance, physical gamepad behavior, real frame pacing, and subjective feel therefore still need an interactive F5 session. Headless runs also emit a macOS certificate-store diagnostic unrelated to these offline gameplay checks.

Passing the automated checks does not complete every M0 acceptance item in [the implementation plan](PROTOTYPE_PLAN.md). In particular, inspect thin-wall/near-camera clipping visually, compare different frame rates and aspect ratios, and test all controller bindings on hardware.
