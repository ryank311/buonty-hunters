# SOCOM inspired Godot prototype

An original tactical third-person shooter focused on the feel of PS2-era SOCOM, with an eventual 5v5, single-life multiplayer format.

The playable graybox has an original town, a measured movement lab, four soldier classes and a controllable recovered character. It runs locally with one player. The default SEAL and 201 switchable variants retain their original proportions and rigs; recovered full-body animations drive their basic locomotion. The existing controller supplies movement and collision. Original aim/fire poses, recoil and reloads are hooked up; weapon-specific visuals and remaining action events are still being integrated.

## Play

Open `project.godot` in **Godot 4.7** and click the **Play ▶** button (or press **F5**). You start in **Old Quarter**. Press **F2** to switch to the **Movement Lab**, **F1** to tune the feel, and **Esc** to release the mouse and open the menu. On Mac, **Command + the matching number** also works for every in-game function-key shortcut: **Cmd+1** opens options, **Cmd+2** switches levels, **Cmd+3** toggles diagnostics, and **Cmd+4** opens class selection. Alt-tabbing releases the mouse and leaves the game running; tuning/pause opens only through its shortcut or menu controls. Returning to the game restores mouse capture unless a menu is open.

**Cmd+1 / F1 → Recovery Lab**, then **Tab**, opens a searchable collection of **202 recovered character models and 402 motion clips**. The selected character and your playable character share a native clip and clock. Pause, scrub, step frames or turn the models. Click **Use selected character for player**, then close the browser to play; **[ / ]** switches characters anywhere. Selection survives respawn and level changes during the run. **Cmd+6 / F6** changes the clip, **Cmd+7 / F7** pauses, **Cmd+9 / F9** steps one animation frame, and **Cmd+8 / F8** shows recovered collision. **N** cycles inspection spawns. See the [character guide](tools/recovery/CHARACTERS.md), [map/weapon pilot](tools/recovery/PILOT.md), and [agent asset handoff](docs/ASSET_RECOVERY_HANDOFF.md).

**Recovery Lab → Tab → Guns** browses all **43 recovered gun designs (73 source variants)**. Search, filter, rotate and equip firearms; the standard loadouts also use their recovered models. Guns use recovered recoil, spread and firing modes; damage, ammunition and reloads retain prototype settings. Press **B / L3** to cycle supported modes. Shared-model records can be selected separately. Launchers are available for model inspection. See the [gun collection guide](tools/recovery/WEAPONS.md).

**F1/Start → Maps** loads all **22 recovered multiplayer maps**, at native scale with their original geometry, collision, sky dome, lighting and fog. **Next spawn** cycles grounded spawns from the original named views, supplemented with clear central positions where needed. Campaign maps are excluded from the project and builds; their sources remain in the offline recovery archive. There are no soldiers or objectives on these maps yet. See the [recovered maps guide](tools/recovery/LEVELS.md).

The entire game renders at a fixed **640×480 (4:3)**, including the HUD and menus. Resizing only enlarges that finished image; every monitor shows the same framing, detail, and HUD proportions. Black bars fill unused space without cropping or stretching. The camera sits above and slightly right of the soldier, framing him just left of the reticle with the aiming area clear. The window opens at twice the render size (in screen points, so Retina displays are not halved), stepping down only to fit the screen. **F1/Start → Camera → Camera height above stance** and **Camera side offset** adjust that framing; ceiling and wall probes keep it within the level.

| Action | Keyboard / mouse |
| --- | --- |
| Move / look | WASD / mouse |
| Slow walk | Hold Shift |
| Crouch / stand | Tap C |
| Prone / stand | Hold C, or Z |
| Dive forward into prone | Hold C while running forward |
| Jump / climb the ledge in front / rise from a lower stance | Space |
| Lean | Hold Q / E |
| Fire / focus aim | Left / right mouse button |
| Reload | R |
| Change firing mode | B |
| Equip primary / pistol | 1 / 2 |
| Equip equipment (grenades, claymores) | 3 / 4 |
| Throw a grenade / set a claymore | Left mouse button with it equipped: hold longer to throw further |
| Scope zoom (sniper rifle, while aiming) | Mouse wheel, or = / - |
| Search a body | F |
| Choose class | F4 / Cmd+4 |
| Previous / next recovered character | [ / ] |
| Switch view while eliminated | Q / E |
| Tuning / pause | F1 / Cmd+1 / Esc |
| Switch level | F2 / Cmd+2 |
| Diagnostic display | F3 / Cmd+3 |
| Reset position | Backspace |
| Next spawn | N |
| Start / stop route timer | T |

Gamepad bindings use left/right sticks for movement/look, A for jump, B tap for crouch or hold for prone, LB/RB for lean, LT/RT for aim/fire, and X for reload. **With a grenade in hand, how far you squeeze RT is how far it goes:** the arc follows the squeeze, easing off shortens it, and letting go throws. **D-pad left equips the primary; right equips the pistol, and pressed again steps through the equipment.** D-pad up cycles spawns; down resets/refills; while looking through the scope they zoom instead. F / Y performs the selected contextual action: open/close a door, climb a ledge, or search a body. Recovered icons appear at the bottom center; Tab or D-pad up/down selects between nearby actions. T controls the route timer. LB/RB switch view while eliminated, **Choose class** is in the Start menu, R3 toggles diagnostics, and **L3 changes firing mode**. Left-stick travel controls stop → walk → jog → sprint continuously; full sprint starts at 90% travel, without clicking L3. Shift still holds slow walk on keyboard. Footfalls follow the recovered leg contacts, with quiet walking, firmer jogging and heavier, louder sprinting. Labels use Xbox names; the corresponding positions on PlayStation controllers work through Godot's mappings.

**Hold C/B for 0.35 seconds** to lie prone; hold while running forward to dive. A prone soldier lies along the surface under them at its angle, on ramps and uneven ground as on the flat, and the stance changes only refuse when something stands where the body would go. The dive uses swept collision and lands prone, with a brief settling period before firing or changing stance. Prone crawls at **1.1 m/s**. Sideways prone travel averages about 0.55 m/s using the existing movement curve; the recovered strafe clip supplies the visible pose. Matching its foot/hand contacts to that curve remains follow-up work. Tap C/B to rise to crouch, or Space/A to stand. Walking and running use their original full-body clips. Jump and dive clips follow the controller’s flight phase and blend into recovered landing/prone poses.

Movement speeds are the original game's, read from its own motion table: **6.5 m/s** running forward or sideways, **3.7** backing up, **2.6** walking (Shift), **1.5** crouched, and **1.1** crawling. The legs turn by ground covered, not by a clock. Each recovered gait clip carries the distance its stride travels; the clip for the current speed comes from the original's speed bands, two clips share an overlap, and forward and strafe clips are mixed by direction. A planted foot therefore stays where it was put at any speed, including one you retune in F1. With the weapon raised, forward and backward movement takes the original's "Fire" variants, and strafes keep their own poses, which already hold the weapon on aim.

**Start** or **Back/Select** opens tuning. **LB/RB** changes pages; **up/down** selects a control; **left/right** adjusts a slider; **A** confirms; **B/Start** resumes. Level switching and every tuning setting are available through this menu without a mouse. Bindings are currently fixed; look speed, focused aim sensitivity, dead zone, inversion, and vibration are adjustable. Actual hardware feel still needs a playtest.

**Old Quarter** has three traversable routes, ten spawn markers, cover, an arch, market, courtyard, balconies, and a covered service passage. **Movement Lab** has distance markers, ramps, stairs, narrow doorways, stance-clearance fixtures, camera corners, and static/moving practice targets.

The rifle starts with **30 loaded / 90 reserve** rounds; the semi-auto pistol has **12 / 36**. Each keeps its own ammunition across swaps. A swap cancels an unfinished reload without transferring rounds. Reset refills both. Recovered recoil raises the unscoped reticle while leaving the camera still. Per-gun stance tables govern spread, movement/turn bloom and recovery. The M4 starts on three-round burst; B / L3 switches to automatic or semi. Releasing the trigger cuts a burst short. Weapon movement and optional controller vibration accompany shots. Those are the rifleman's weapons; the other classes are described under [Classes, weapons, and round rules](#classes-weapons-and-round-rules). Bots, objectives, round flow, and online multiplayer are future work.

Holding aim raises the recovered firing pose; firing also keeps the gun ready for five seconds. Rifle and pistol shots use their original recoil poses, and reload animations follow the ammunition timer while preserving movement. Idle breathing uses the original slower playback settings.

Every firearm except the sniper rifle uses **instant hitscan**; the sniper rifle fires a bullet that takes time to arrive and drops on the way. Bullet-hole decals stay on the struck walls, floors, cover, and targets, including moving targets. The latest 128 marks remain until replaced or until you reset/change levels. Swapping or reloading preserves them. Impact sizes are adjustable through `impact_diameter` in each weapon resource (metres).

Crosshairs use the **original recovered rifle, pistol, shotgun, grenade and scope textures**. The fixed disc and expanding arms follow actual spread and recoil; shotguns use their recovered square pellet distribution. Arms are yellow at rest, green over a living teammate and red over a living enemy within 32 m. A recovered accuracy pip marks a blocked muzzle. Grenade charge fills the original meter. Recoil, spread and firing modes come from the original weapon records; see the [profile recovery guide](tools/recovery/WEAPON_PROFILES.md) for source evidence and remaining adaptations. See the [HUD recovery guide](tools/recovery/HUD.md) and [browse all 174 recovered HUD textures](art/ui/recovered/index.html).

F1 exposes movement, body weight, camera, controller, separate **Rifle recoil / Pistol recoil** pages, and **Accuracy** for recovered spread strength. Recoil/spread multipliers of 1 use the source values. Changes save when you resume. Use **Restore all defaults** to return to the baseline. See [playtest notes](docs/PLAYTEST.md) for the comparison sequence and validation limits.

The HUD uses compact, borderless translucent strips with a 5% screen margin. Bottom left shows the equipped weapon, SEMI/BURST/AUTO mode, ammunition, reserve-magazine equivalents, and health. Bottom right shows your stance/health and your squad: teammates, marked OK or DOWN, then open slots. With a grenade or claymore equipped the weapon strip shows how many you carry instead of magazines. The circular map at top right follows your position and facing over the level's real building footprints: yellow is you, cyan is the selected spawn, and N indicates north. **F1/Start → Camera → HUD backing opacity** adjusts the strip opacity (18% by default). This solo build starts at 100 health. The only incoming damage is from your own explosives, and the other soldiers are stand-ins that do not think or shoot.

## Classes, weapons, and round rules

You choose a soldier class, not individual weapons. **F4**, or **Choose class** in the Start menu, opens the list; choosing one respawns you with its loadout.

| Class | Primary | Pistol | Equipment |
| --- | --- | --- | --- |
| Rifleman | Field rifle: semi/burst/auto, 625 rpm burst/auto, 30 rounds | Service pistol: 9 mm, 12 rounds | 2 frag grenades, 1 smoke grenade |
| Marksman | Sniper rifle: scoped, 5 rounds | Machine pistol: semi/auto, 1,250 rpm auto, 18 rounds | 2 claymores, 1 smoke grenade |
| Breacher | Combat shotgun: 6 shells of 9 pellets | Heavy pistol: 7 rounds, 55 damage each | 2 flashbangs, 2 frag grenades |
| Pointman | Submachine gun: semi/burst/auto, 750 rpm burst/auto, 30 rounds | Service pistol | 2 flashbangs, 2 claymores |

Soldiers have 100 health. A hit to the head does about three times a weapon's damage and a hit to the legs about three quarters. Damage also falls with distance, at a different rate for each weapon:

| Weapon | Damage up close | Falls to | Between |
| --- | --- | --- | --- |
| Field rifle | 34 | 70% | 60 and 150 m |
| Submachine gun | 22 | 45% | 15 and 45 m |
| Combat shotgun | 9 × 14, recovered stance-dependent spread | 20% | 6 and 25 m |
| Sniper rifle | 95 | 80% | 250 and 400 m |
| Service pistol | 26 | 50% | 20 and 50 m |
| Heavy pistol | 55 | 50% | 20 and 60 m |
| Machine pistol | 16 | 40% | 10 and 35 m |

- **Sniper rifle.** Hold the right mouse button (LT) to look through the scope; the wheel, **=** / **-**, or D-pad up/down steps through ×3, ×6, and ×12. The bullet leaves at 380 m/s and falls under gravity, so a distant or moving target needs lead and hold-over; the ticks under the scope's centre are for that. Fired without the scope it is inaccurate.
- **Frag grenade.** Thrown where you aim, bounces, and explodes 3.5 seconds later. It does not know who threw it: it kills anyone within about 4 m, you and your teammates included, wounds out to 8 m, and does nothing behind cover. The lightest toss on level ground comes down about 9 m away; aimed at the ground ahead it stops within 4 m.
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

## Linux and SteamOS builds

`tools/dev build linux` creates a native x86_64 release with the recovered runtime assets. It downloads matching verified templates on first use and audits the packaged data. `tools/dev deploy linux deck@STEAMOS_HOST` copies the latest build over SSH, tests the actual Linux executable, and installs **SOCOM Playtest** in KDE with a stable `~/Games/socom/play.sh` launcher for Steam. Quit and relaunch to pick up updates. See [Linux playtesting](docs/LINUX_PLAYTEST.md) for setup, logs, rollback and native development.

## Working on the game with an AI while it runs

While you play (F5 in the editor, or `tools/dev play`), the game serves an MCP endpoint on this machine, and the `game` MCP server registered for Claude Code and Codex connects an agent to it. Say what you feel ("walking is slow", "the jump is floaty", "that reload looks wrong") and the agent can:

- read what you just did: speed in each movement state, how long starts and stops took, jump height, turn rate;
- change movement, camera, and weapon values at once. A notice on the HUD names each change, and the F1 menu shows the new value;
- look at the soldier from any side, capture a filmstrip of a motion, slow time down, or freeze a moment (Esc releases a freeze);
- place you anywhere, change class, weapon, health, or the other soldiers, and read or set any variable;
- bring edited scripts into the running game without restarting it, or restart it in place and put you back where you were;
- write the values you settle on into the default resources.

The link runs only in the real game, never in a test run, so what an agent changes is the game in front of you. It listens on 127.0.0.1 only, needs a token only your user account can read (`.agent/live/`), and is absent from exported builds. `SOCOM_LIVE=0` turns it off. `tools/dev live status` shows what is running; `.agents/skills/live-game/SKILL.md` describes the tools.

## Design and research

- [Game design](docs/DESIGN.md) — experience, controls, movement, camera, combat, round rules, level design, and visual direction.
- [Research findings and sources](docs/RESEARCH.md) — documented mechanics, map studies, source confidence, and questions requiring playtesting.
- [Implementation plan](docs/PROTOTYPE_PLAN.md) — Godot structure, ordered work, and acceptance checks.
- [Map and HUD wireframes](docs/wireframes.svg) — conceptual layout for the first original level, Old Quarter.

The design uses SOCOM II as the provisional gameplay reference and treats numerical tuning as starting values to assess through play, not recovered values from the original game.
