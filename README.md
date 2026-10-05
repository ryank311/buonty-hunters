# SOCOM inspired Godot prototype

An original tactical third-person shooter focused on the feel of PS2-era SOCOM, with an eventual 5v5, single-life multiplayer format.

The playable graybox has an original town, a measured movement lab, a controllable soldier, four soldier classes with their own weapons and equipment, and an in-game tuning menu. It runs locally with one player. The soldier uses a forward combat posture, a shoulder-seated rifle, articulated arms, and a low-poly field uniform with a boonie hat. Directional locomotion turns the hips and waist toward travel while the shoulders keep the weapon on target. Fixed-length limbs, planted feet, weighted acceleration, and landing compression support the movement.

## Play

Open `project.godot` in **Godot 4.7** and click the **Play ▶** button (or press **F5**). You start in **Old Quarter**. Press **F2** to switch to the **Movement Lab**, **F1** to tune the feel, and **Esc** to release the mouse and open the menu. On Mac, **Command + the matching number** also works for every in-game function-key shortcut: **Cmd+1** opens options, **Cmd+2** switches levels, **Cmd+3** toggles diagnostics, and **Cmd+4** opens class selection.

**Cmd+1 / F1 → Recovery Lab**, then **Tab**, opens a searchable collection of **202 recovered character models and 402 motion clips**. The selected character and our player model play the same clip side by side. The browser has category filters, pause, scrubbing and frame stepping. **Try recovered leg motion on player** enables an optional standing/crouching locomotion trial; close the browser to walk. **Cmd+6 / F6** changes the clip, **Cmd+7 / F7** pauses, **Cmd+9 / F9** steps one animation frame, and **Cmd+8 / F8** shows recovered collision. **N** cycles three inspection spawns. See the [character and animation guide](tools/recovery/CHARACTERS.md) and [map/weapon pilot guide](tools/recovery/PILOT.md) for sources, rebuilding and current limits.

The entire game renders at a fixed **640×480 (4:3)**, including the HUD and menus. Resizing only enlarges that finished image; every monitor shows the same framing, detail, and HUD proportions. Black bars fill unused space without cropping or stretching. The camera sits above and slightly right of the soldier, framing him just left of the reticle with the aiming area clear. The window opens at twice the render size (in screen points, so Retina displays are not halved), stepping down only to fit the screen. **F1/Start → Camera → Camera height above stance** and **Camera side offset** adjust that framing; ceiling and wall probes keep it within the level.

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
| Equip primary / pistol | 1 / 2 |
| Equip equipment (grenades, claymores) | 3 / 4 |
| Throw a grenade / set a claymore | Left mouse button with it equipped |
| Scope zoom (sniper rifle, while aiming) | Mouse wheel, or = / - |
| Search a body | F |
| Choose class | F4 / Cmd+4 |
| Switch view while eliminated | Q / E |
| Tuning / pause | F1 / Cmd+1 / Esc |
| Switch level | F2 / Cmd+2 |
| Diagnostic display | F3 / Cmd+3 |
| Reset position | Backspace |
| Next spawn | N |
| Start / stop route timer | T |

Gamepad bindings use left/right sticks for movement/look, A for jump, B tap for crouch or hold for prone, LB/RB for lean, LT/RT for aim/fire, and X for reload. **D-pad left equips the primary; right equips the pistol, and pressed again steps through the equipment.** D-pad up cycles spawns; down resets/refills; while looking through the scope they zoom instead. Y searches a body within reach and otherwise controls the timer, LB/RB switch view while eliminated, **Choose class** is in the Start menu, L3 holds slow walk, and R3 toggles diagnostics. Labels use Xbox names; the corresponding positions on PlayStation controllers work through Godot's mappings.

**Hold C/B for 0.35 seconds** to lie prone; hold while running forward to dive. The dive uses swept collision and lands prone, with a brief settling period before firing or changing stance. Prone crawls at **0.38 m/s**. Sideways movement follows a **reach → pull → settle** cycle: the leading hand and leg move first, then the body catches up, averaging about 0.23 m/s. This uses an authored movement curve and animation; the character is not driven by simulated limb forces. Tap C/B to rise to crouch, or Space/A to stand. Walking keeps low steps; jogging has a distinct recovery step, push-off, and body bounce.

**Start** or **Back/Select** opens tuning. **LB/RB** changes pages; **up/down** selects a control; **left/right** adjusts a slider; **A** confirms; **B/Start** resumes. Level switching and every tuning setting are available through this menu without a mouse. Bindings are currently fixed; look speed, focused aim sensitivity, dead zone, inversion, and vibration are adjustable. Actual hardware feel still needs a playtest.

**Old Quarter** has three traversable routes, ten spawn markers, cover, an arch, market, courtyard, balconies, and a covered service passage. **Movement Lab** has distance markers, ramps, stairs, narrow doorways, stance-clearance fixtures, camera corners, and static/moving practice targets.

The rifle starts with **30 loaded / 90 reserve** rounds; the semi-auto pistol has **12 / 36**. Each keeps its own ammunition across swaps. A swap cancels an unfinished reload without transferring rounds. Reset refills both. Recoil combines aim climb, sideways kick, recovery, expanding shot spread, weapon movement, and optional controller vibration. Those are the rifleman's weapons; the other classes are described under [Classes, weapons, and round rules](#classes-weapons-and-round-rules). Bots, objectives, round flow, and online multiplayer are future work.

Every firearm except the sniper rifle uses **instant hitscan**; the sniper rifle fires a bullet that takes time to arrive and drops on the way. Bullet-hole decals stay on the struck walls, floors, cover, and targets, including moving targets. The latest 128 marks remain until replaced or until you reset/change levels. Swapping or reloading preserves them. Impact sizes are adjustable through `impact_diameter` in each weapon resource (metres).

The reticle has a **translucent charcoal circle** and four separate pale marks. Its aim point stays exactly at screen center during movement and looking; firing recoil lifts the circle and marks together, then returns them to center. The hitscan ray follows this raised aim point. Movement and firing spread the marks outward independently of recoil climb; the circle's size stays fixed. The rifle's cone starts at 0.25° stationary, 1.1° walking, and 5.75° running, reaching 9.25° during sustained running fire. Crouch reduces recoil and total spread by 20%; prone reduces both by 50%. Focus aim adds a further stability benefit.

F1 exposes movement, body weight, camera, controller, separate **Rifle recoil / Pistol recoil** pages, and **Accuracy** for walking/running spread and maximum shot bloom. Changes save when you resume. Use **Restore all defaults** to return to the baseline. See [playtest notes](docs/PLAYTEST.md) for the comparison sequence and validation limits.

The HUD uses compact, borderless translucent strips with a 5% screen margin. Bottom left shows the equipped weapon, AUTO/SEMI mode, ammunition, reserve-magazine equivalents, and health. Bottom right shows your stance/health and your squad: teammates, marked OK or DOWN, then open slots. With a grenade or claymore equipped the weapon strip shows how many you carry instead of magazines. The circular map at top right follows your position and facing over the level's real building footprints: yellow is you, cyan is the selected spawn, and N indicates north. **F1/Start → Camera → HUD backing opacity** adjusts the strip opacity (18% by default). This solo build starts at 100 health. The only incoming damage is from your own explosives, and the other soldiers are stand-ins that do not think or shoot.

## Classes, weapons, and round rules

You choose a soldier class, not individual weapons. **F4**, or **Choose class** in the Start menu, opens the list; choosing one respawns you with its loadout.

| Class | Primary | Pistol | Equipment |
| --- | --- | --- | --- |
| Rifleman | Field rifle: automatic, 600 rpm, 30 rounds | Service pistol: 9 mm, 12 rounds | 2 frag grenades, 1 smoke grenade |
| Marksman | Sniper rifle: scoped, 5 rounds | Machine pistol: automatic, 1000 rpm, 18 rounds | 2 claymores, 1 smoke grenade |
| Breacher | Combat shotgun: 6 shells of 9 pellets | Heavy pistol: 7 rounds, 55 damage each | 2 flashbangs, 2 frag grenades |
| Pointman | Submachine gun: automatic, 800 rpm, 30 rounds | Service pistol | 2 flashbangs, 2 claymores |

Soldiers have 100 health. A hit to the head does about three times a weapon's damage and a hit to the legs about three quarters. Damage also falls with distance, at a different rate for each weapon:

| Weapon | Damage up close | Falls to | Between |
| --- | --- | --- | --- |
| Field rifle | 34 | 70% | 60 and 150 m |
| Submachine gun | 22 | 45% | 15 and 45 m |
| Combat shotgun | 9 × 14, spread over 4.5° | 20% | 6 and 25 m |
| Sniper rifle | 95 | 80% | 250 and 400 m |
| Service pistol | 26 | 50% | 20 and 50 m |
| Heavy pistol | 55 | 50% | 20 and 60 m |
| Machine pistol | 16 | 40% | 10 and 35 m |

- **Sniper rifle.** Hold the right mouse button (LT) to look through the scope; the wheel, **=** / **-**, or D-pad up/down steps through ×3, ×6, and ×12. The bullet leaves at 380 m/s and falls under gravity, so a distant or moving target needs lead and hold-over; the ticks under the scope's centre are for that. Fired without the scope it is inaccurate.
- **Frag grenade.** Thrown where you aim, bounces, and explodes 3.5 seconds later. It kills at the centre and does nothing beyond 8 m or behind cover. It hurts you and teammates too.
- **Smoke grenade.** Bursts after 2 seconds into a cloud about 9 m across that lasts 18 seconds.
- **Flashbang.** Goes off after 1.8 seconds and whites out the view of anyone within 14 m who can see it, for up to 4.5 seconds: less with distance and when facing away, and not at all behind cover.
- **Claymore.** Set on the ground a pace ahead, facing the way you face, and armed a second later. You cannot set it off yourself: it fires when an **enemy** walks within 4.5 m of its front. The blast is a cone to the front that hurts anyone in it, including you.

**Elimination.** At zero health you are out for the round and your body stays where it fell. Your view moves to a living teammate; **Q / E** (LB/RB) switch between the remaining teammates and your own body, and the mouse or right stick looks around whichever you are watching. Enemies are never shown. **Backspace** (D-pad down) starts the next round with everyone back up.

**Searching bodies.** Stand at any fallen soldier, enemy or teammate, and press **F** (Y) for a menu offering their primary and their pistol, with the ammunition left in each. Taking one leaves your own weapon of that kind with the body.

**Stand-in soldiers.** Each level starts with two teammates (ALPHA, BRAVO) and four enemies, one of them walking a short patrol to try claymores on. They take damage, fall, and can be searched, but they do not think or shoot, so the quickest way to see the eliminated view is a frag at your own feet. Friendly fire is on. Their places are listed in `scripts/combat/roster.gd`.

## Editing and checks

- `scenes/main.tscn` is the entry point.
- `scenes/levels/old_quarter.tscn` and `movement_lab.tscn` contain ordinary editable geometry, collisions, markers, and targets.
- `resources/movement/default_movement.tres` and `resources/camera/default_camera.tres` hold default tuning.
- `resources/weapons/` holds one resource per weapon and piece of equipment (damage, falloff, recoil, fuse, radius); `resources/classes/` says what each class carries.
- `scripts/combat/` contains the weapon handling, bullets, grenades, claymores, smoke, elimination and spectating, and the level rosters; `scripts/actors/combat_dummy.gd` is the stand-in soldier.
- `scripts/player/` contains the controller, camera, stance clearance, input, and visual proxy.
- `tools/build_graybox.py` is the original scene/audio authoring recipe. Running it overwrites generated level scenes and audio, so preserve any manual edits first. Python is not needed to play.

Use the project wrapper for validation and hidden screenshots:

```sh
tools/dev check
tools/dev test
tools/dev shot town_market lab_range --full
```

On this Mac the executable is `/Applications/Godot.app/Contents/MacOS/Godot`. The suites exercise character motion/collision, all three town routes, visible limb endpoints and posture, controller input events and menu navigation, ammunition conservation, recoil/recovery, persistent surface impacts, and the class loadouts, weapon damage, bullet flight, grenades, claymores, elimination, and body searches. QA mode ignores saved tuning; headless runs skip audio playback and vibration. The project retains Mobile rendering and Jolt Physics.

## Design and research

- [Game design](docs/DESIGN.md) — experience, controls, movement, camera, combat, round rules, level design, and visual direction.
- [Research findings and sources](docs/RESEARCH.md) — documented mechanics, map studies, source confidence, and questions requiring playtesting.
- [Implementation plan](docs/PROTOTYPE_PLAN.md) — Godot structure, ordered work, and acceptance checks.
- [Map and HUD wireframes](docs/wireframes.svg) — conceptual layout for the first original level, Old Quarter.

The design uses SOCOM II as the provisional gameplay reference and treats numerical tuning as starting values to assess through play, not recovered values from the original game.
