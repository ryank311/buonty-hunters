# SOCOM inspired Godot prototype

An original tactical third-person shooter focused on the feel of PS2-era SOCOM, with an eventual 5v5, single-life multiplayer format.

The playable graybox has an original town, a measured movement lab, a controllable soldier, a rifle and pistol, and an in-game tuning menu. It runs locally with one player. The soldier uses a forward combat posture, a shoulder-seated rifle, articulated arms, and a low-poly field uniform with a boonie hat. Directional locomotion turns the hips and waist toward travel while the shoulders keep the weapon on target. Fixed-length limbs, planted feet, weighted acceleration, and landing compression support the movement.

## Play

Open `project.godot` in **Godot 4.7** and press **F5**. You start in **Old Quarter**. Press **F2** to switch to the **Movement Lab**, **F1** to tune the feel, and **Esc** to release the mouse and open the menu.

The entire game renders at a fixed **640×480 (4:3)**, including the HUD and menus. Resizing only enlarges that finished image; every monitor shows the same framing, detail, and HUD proportions. Black bars fill unused space without cropping or stretching. The centered camera sits above the soldier, leaving the aiming area clear. **F1/Start → Camera → Camera height above stance** adjusts that framing; ceiling and wall probes keep it within the level.

| Action | Keyboard / mouse |
| --- | --- |
| Move / look | WASD / mouse |
| Slow walk | Hold Shift |
| Crouch / stand | Tap C |
| Prone / stand | Hold C, or Z |
| Dive forward into prone | Hold C while running forward |
| Jump / rise from a lower stance | Space |
| Lean | Hold Q / E |
| Fire / focus aim | Left / right mouse button |
| Reload | R |
| Equip rifle / pistol | 1 / 2 |
| Tuning / pause | F1 / Esc |
| Switch level | F2 |
| Diagnostic display | F3 |
| Reset position | Backspace |
| Next spawn | N |
| Start / stop route timer | T |

Gamepad bindings use left/right sticks for movement/look, A for jump, B tap for crouch or hold for prone, LB/RB for lean, LT/RT for aim/fire, and X for reload. **D-pad left equips the rifle; right equips the pistol.** D-pad up cycles spawns; down resets/refills. Y controls the timer, L3 holds slow walk, and R3 toggles diagnostics. Labels use Xbox names; the corresponding positions on PlayStation controllers work through Godot's mappings.

**Hold C/B for 0.35 seconds** to lie prone; hold while running forward to dive. The dive uses swept collision and lands prone, with a brief settling period before firing or changing stance. Prone crawls at **0.38 m/s**. Sideways movement follows a **reach → pull → settle** cycle: the leading hand and leg move first, then the body catches up, averaging about 0.23 m/s. This uses an authored movement curve and animation; the character is not driven by simulated limb forces. Tap C/B to rise to crouch, or Space/A to stand. Walking keeps low steps; jogging has a distinct recovery step, push-off, and body bounce.

**Start** or **Back/Select** opens tuning. **LB/RB** changes pages; **up/down** selects a control; **left/right** adjusts a slider; **A** confirms; **B/Start** resumes. Level switching and every tuning setting are available through this menu without a mouse. Bindings are currently fixed; look speed, focused aim sensitivity, dead zone, inversion, and vibration are adjustable. Actual hardware feel still needs a playtest.

**Old Quarter** has three traversable routes, ten spawn markers, cover, an arch, market, courtyard, balconies, and a covered service passage. **Movement Lab** has distance markers, ramps, stairs, narrow doorways, stance-clearance fixtures, camera corners, and static/moving practice targets.

The rifle starts with **30 loaded / 90 reserve** rounds; the semi-auto pistol has **12 / 36**. Each keeps its own ammunition across swaps. A swap cancels an unfinished reload without transferring rounds. Reset refills both. Recoil combines aim climb, sideways kick, recovery, expanding shot spread, weapon movement, and optional controller vibration. Bots, combat damage, objectives, rounds, spectating, and online multiplayer are future work.

Both weapons use **instant hitscan**. Bullet-hole decals stay on the struck walls, floors, cover, and targets, including moving targets. The latest 128 marks remain until replaced or until you reset/change levels. Swapping or reloading preserves them. Impact sizes are adjustable through `impact_diameter` in each weapon resource (metres).

The reticle has a **translucent charcoal circle** and four separate pale marks. Its aim point stays exactly at screen center during movement and looking; firing recoil lifts the circle and marks together, then returns them to center. The hitscan ray follows this raised aim point. Movement and firing spread the marks outward independently of recoil climb; the circle's size stays fixed. The rifle's cone starts at 0.25° stationary, 1.1° walking, and 5.75° running, reaching 9.25° during sustained running fire. Crouch reduces recoil and total spread by 20%; prone reduces both by 50%. Focus aim adds a further stability benefit.

F1 exposes movement, body weight, camera, controller, separate **Rifle recoil / Pistol recoil** pages, and **Accuracy** for walking/running spread and maximum shot bloom. Changes save when you resume. Use **Restore all defaults** to return to the baseline. See [playtest notes](docs/PLAYTEST.md) for the comparison sequence and validation limits.

The HUD uses compact, borderless translucent strips with a 5% screen margin. Bottom left shows the equipped weapon, AUTO/SEMI mode, ammunition, reserve-magazine equivalents, and health. Bottom right shows your stance/health and four open squad slots. The circular map at top right follows your position and facing over the level's real building footprints: yellow is you, cyan is the selected spawn, and N indicates north. **F1/Start → Camera → HUD backing opacity** adjusts the strip opacity (18% by default). This solo build starts at 100 health and has no incoming damage or AI squad members yet.

## Editing and checks

- `scenes/main.tscn` is the entry point.
- `scenes/levels/old_quarter.tscn` and `movement_lab.tscn` contain ordinary editable geometry, collisions, markers, and targets.
- `resources/movement/default_movement.tres` and `resources/camera/default_camera.tres` hold default tuning.
- `resources/weapons/rifle.tres` and `pistol.tres` hold weapon and recoil defaults.
- `scripts/player/` contains the controller, camera, stance clearance, input, and visual proxy.
- `tools/build_graybox.py` is the original scene/audio authoring recipe. Running it overwrites generated level scenes and audio, so preserve any manual edits first. Python is not needed to play.

Use the project wrapper for validation and hidden screenshots:

```sh
tools/dev check
tools/dev test
tools/dev shot town_market lab_range --full
```

On this Mac the executable is `/Applications/Godot.app/Contents/MacOS/Godot`. The suites exercise character motion/collision, all three town routes, visible limb endpoints and posture, controller input events and menu navigation, ammunition conservation, recoil/recovery, and persistent surface impacts. QA mode ignores saved tuning; headless runs skip audio playback and vibration. The project retains Mobile rendering and Jolt Physics.

## Design and research

- [Game design](docs/DESIGN.md) — experience, controls, movement, camera, combat, round rules, level design, and visual direction.
- [Research findings and sources](docs/RESEARCH.md) — documented mechanics, map studies, source confidence, and questions requiring playtesting.
- [Implementation plan](docs/PROTOTYPE_PLAN.md) — Godot structure, ordered work, and acceptance checks.
- [Map and HUD wireframes](docs/wireframes.svg) — conceptual layout for the first original level, Old Quarter.

The design uses SOCOM II as the provisional gameplay reference and treats numerical tuning as starting values to assess through play, not recovered values from the original game.
