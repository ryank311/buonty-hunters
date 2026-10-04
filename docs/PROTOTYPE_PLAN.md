# Godot first playable implementation plan

This plan implements the [design](DESIGN.md) in small, testable stages. Its immediate goal is **M0: a soldier that can reliably navigate a readable town graybox**. Everything below is proposed work unless identified as an observed repository fact.

**Implementation update — October 3, 2026:** the first runnable traversal prototype now exists, with both levels, stances, camera clearance, live tuning, and limited practice shooting. The October 2 inventory below records the starting state. Read [PLAYTEST.md](PLAYTEST.md) and the repository README for the current build. Automated physics checks cover the implemented fundamentals; visual and device checks are still required to complete M0.

## Current project

Inspected October 2, 2026:

- `project.godot` names the application SOCOM and declares Godot 4.7 with the Mobile renderer.
- Jolt Physics is selected; the Windows rendering driver is D3D12.
- Display stretching uses `canvas_items` with an expanding aspect policy.
- The installed `/Applications/Godot.app/Contents/MacOS/Godot` reports `4.7.stable.official.5b4e0cb0f`.
- There are no `.tscn` gameplay scenes, `.gd` scripts, Input Map entries, or assigned main scene in the project inspected.
- There is no `.codegraph/` index. No existing controller or multiplayer implementation needs migration.

Keep this engine and renderer configuration for the graybox. Verify any feature against the installed editor before adding it. The documentation links below use Godot's moving stable channel; pin the project to the inspected version while comparing results. No gameplay test has been run as part of this documentation task because no game exists yet.

## Scene and code organization

Create only the M0 files initially. Later directories are an architectural destination, not a requirement to scaffold unused systems.

```text
scenes/
  main.tscn                    # Local test entry point
  actors/player.tscn           # Body, visual proxy, aim and camera rig
  levels/movement_lab.tscn     # Rulers, ramps, stairs, clearance fixtures
  levels/old_quarter.tscn      # Authored graybox and named positions
  ui/prototype_hud.tscn
scripts/
  player/player_controller.gd
  player/player_input.gd
  player/stance_controller.gd
  player/camera_controller.gd
  levels/test_session.gd
  ui/prototype_hud.gd
resources/
  movement/default_movement.tres
  camera/default_camera.tres
```

Use typed GDScript. Define resource classes for movement and camera values so experiment variants do not require editing controller code. Author the map as an inspectable scene with reusable geometry pieces. Avoid hiding the whole layout in one procedural generation script.

Proposed player hierarchy:

```text
Player (CharacterBody3D)
  BodyCollision (CollisionShape3D)
  VisualRoot (Node3D)
    SoldierProxy
    WeaponPivot
      Muzzle (Marker3D)
  CameraYaw (Node3D)
    CameraPitch (Node3D)
      SpringArm3D
        Camera3D
```

Lean and stance offsets are controller-managed transforms, with clearance checks. Put `Camera3D` directly under `SpringArm3D` so the camera shape can participate in the arm's collision test; exclude the owner's body and test thin walls. Godot documents shape sweeps and the difference between a camera child and a fallback ray. [Godot third-person camera documentation](https://docs.godotengine.org/en/stable/tutorials/3d/spring_arm.html).

Movement runs in `_physics_process` through `CharacterBody3D.velocity` and `move_and_slide()`. Apply gravity and acceleration with delta; do not multiply velocity by delta again when calling `move_and_slide()`. Configure slope and floor-snap behavior, then test it on authored ramps. [Godot CharacterBody3D reference](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html).

### Responsibility boundaries

| Component | Owns | Must not own |
| --- | --- | --- |
| PlayerInput | Mouse, keyboard, pad mapping into a command | Health, scoring, hits |
| PlayerController | Movement execution and facing | Local HUD or round decisions |
| StanceController | Allowed transitions and collision clearance | Arbitrary animation-only hitbox changes |
| CameraController | Local view, FOV, obstruction, lean framing | Damage or objective authority |
| TestSession, later MatchSession | Spawn, reset, player roster, world lifecycle | Raw device input |
| WeaponController, M1 | Fire eligibility, cadence, ammunition | Trusting a visual effect as proof of a hit |
| RoundController, M2 | Phase, timer, mode outcome, scores | Player-specific camera behavior |
| ModeRule, M3 | Objective state and mode-specific outcome | Scene reload or direct UI manipulation |

A command records movement axes, look intent, requested stance, jump/lean, and later fire/interact actions. Simulation produces state; presentation observes it. Local play remains simple, without RPCs in M0. This separation allows a future bot or remote player to supply the same kind of command.

Use meters, Y-up, and a consistent forward convention. Name collision layers: World, Actors, Hitboxes, Interactables. Camera casts inspect World; movement inspects World and appropriate Actors; weapon queries inspect World and damage Hitboxes while excluding their owner. Do not let both an actor capsule and its hitboxes award damage for one shot. Add dedicated camera blockers only when a tested geometry problem requires them.

## M0 ordered work

| Order | Work | Reviewable result |
| --- | --- | --- |
| 1 | Main scene, environment, a floor, directional light, spawn, Input Map. | F6/F5 enters a simple local scene; Escape releases the mouse; click resumes capture. |
| 2 | Movement resource and standing body; normalized movement, strafe, backpedal, gravity. | A 10 m lane produces repeatable travel times; diagonal movement gives no bonus. |
| 3 | Trailing camera, pitch limits, self-exclusion, obstruction handling. | Corners and walls do not reveal the opposite side by clipping. |
| 4 | Crouch and prone with visual proxy, clearance checks, and stance-relative camera. | A blocked stand request stays crouched; prone rotation respects body length. |
| 5 | Small jump, ramps beneath stairs, lean clearance, basic footsteps. | The movement course is traversable in both directions without sticking or camera popping. |
| 6 | HUD stance, location and help; optional debug speed, state, camera distance, aim rays. | A tester can explain the active stance and controls; debug panels can be hidden. |
| 7 | Old Quarter geometry, spawn markers, named landmarks and cross-links. | All three routes are walkable; Market and Balcony are recognizable. |
| 8 | Controller support, sensitivity options, restart, checkpoint/route timing controls. | Repeatable comparisons on mouse and pad; reset returns the player to a known state. |
| 9 | Run the M0 acceptance session and fix failures. | A short capture and recorded measurements support the first gameplay review. |

Keep the movement laboratory available separately from the town. Include 10 m and 25 m lanes; 15°, 30°, and 45° ramps; 1.2 m and 1.8 m door fixtures; a low ceiling; waist-high cover; interior/exterior corners; an exterior stair; and a ledge with a recovery zone. Place clear height labels in the development course only.

Use neutral ground and walls, dark solid blockers, pale low cover, a muted teal west spawn, and muted ochre east spawn. Development route labels are useful; replace them with believable landmark cues during art production. Fall-out recovery is a debug reset in free roam, and later an explicit elimination or objective recovery rule during matches.

### M0 acceptance checks

| Check | Pass condition |
| --- | --- |
| Basic control | Forward, backward, strafing, diagonal input, and looking work independently; no stuck input after pause/focus loss. |
| Frame-rate comparison | The same straight traversal at capped 30, 60, and 120 FPS differs by less than 5%; physics rate held constant. |
| Stance clearance | Twenty repetitions under each ceiling fixture cause no penetration, forced standing, or ground-height drift. |
| Prone | Near-wall turns and stance exits cannot rotate the body through a wall or into a stair. |
| Camera | Twenty traversals of each corner/stair fixture show no view through solid geometry; camera recovers smoothly after obstruction. |
| Lean | Both sides stop at obstructing geometry; neither introduces a camera origin outside the legal space. |
| Navigation | Every intended route, cross-link, and two-way balcony approach is traversable without jumping over accidental collision defects. |
| Timing | Record ten runs from each spawn on each route; adjust geometry toward the design's timing targets. |
| Readability | A new tester can find Market, Arch, and Balcony after one guided lap, then repeat the lap unaided. |
| Performance | Target steady 60 FPS in the graybox on the development machine; record hardware, resolution, renderer, and frame-time distribution. |
| Restart | Ten resets restore position, velocity, stance, camera, and UI without accumulating nodes or errors. |

The targets are acceptance criteria to test, not results already achieved. If camera or collision failures remain, hold the scope at M0 rather than compensating with decoration.

## Subsequent playable increments

**M1: make shooting trustworthy.** Add the rifle resource, camera-to-aim and muzzle-to-hit queries, one static target and one moving target, non-overlapping damage regions, ammunition, reload, death, and feedback. Test firing beside walls, through a doorway, above low cover, while leaned, and while prone. Add a debug view of both rays. Compare spread at 10/25/50 m and record actual hit distributions. Assert cadence and ammunition invariants. Automated checks are useful here for duplicate hits and reload cancellation; visual checks establish feel.

**M2: complete an offline round.** Begin with one allied bot and two enemies, expanding toward 5v5 only after the lifecycle works. Use simple state-based bots with a few authored patrol/engagement goals, line-of-sight sensing, bounded reaction delay, and no knowledge of unseen player position. A separate sensor emits observations to decision logic. Navigation follows authored ground and stair paths. Bots validate shooting, deaths, rounds, and spectator flow; they do not certify human map balance. Add an explicit debug elimination trigger to test spectating without relying on bot skill.

Test one survivor, mutual elimination, timeout with equal/unequal survivors, friendly fire, a teammate dying while being spectated, and every round-reset field. Confirm that an already resolved round cannot award a second point.

**M3: add objective pressure.** Implement shared-bomb Demolition as a mode component, then the Extraction variant and hostage pathing. Cover pickup contention, cancellation, carrier death, out-of-bounds recovery, planted overtime, all-planters dead, all-defenders dead, same-tick defuse/detonation, hostage loss, and escort death. These edge cases warrant automated state-machine tests because an incorrect result invalidates a match.

**M4: validate networking before expanding content.** First use two local processes and one dedicated server process, then real LAN/WAN clients and eventually ten player slots. Godot's high-level API supplies multiplayer peers and RPC mechanisms; ENet is one supported transport. [Godot high-level multiplayer documentation](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html).

Proposed network model: server owns player eligibility, health, ammunition, hits, objectives, round time, and scoring. Clients send sequenced input, not awarded damage. Locally predict movement and reconcile against acknowledged server state; interpolate other players. Replicate entity IDs, stance, aim and action state, not local cameras. Validate movement bounds, fire rate, and interactions on the server. Assess bounded server rewind for hitscan after basic authority works. Jolt physics and a shared controller do not by themselves guarantee deterministic prediction.

Start with a proposed 60 Hz simulation and 20–30 Hz snapshots, then measure bandwidth and correction quality. Test 50/100/150 ms latency, jitter and packet loss, dropped objective carriers, late joins, and a full-team disconnect. Use reliable events for round transitions and idempotent objective changes; use sequenced transient input/state where appropriate. Spawner/synchronizer helpers do not replace ownership rules, prediction, or validation. In an active round, a disconnect removes that living player and drops carried objectives; future rejoining waits until the next round. If an entire team disconnects, award a forfeit after a configured grace period.

Do not add several polished maps before this network milestone. That would make changes to collision dimensions, movement or camera fairness expensive. A small networking feasibility spike can precede M3 once M1 is stable if architecture risk appears, without turning M0 into an online project.

## Rendering integration

Keep the existing Mobile renderer for M0. Render the entire game at 640×480 using `viewport` stretch mode and `keep` aspect. Scale the completed frame to the window, with equal black bars where needed. The framebuffer, field of view, HUD proportions, and visible world stay identical across monitor sizes and aspect ratios. [Godot multiple resolutions documentation](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html).

HUD controls retain their authored 1024×768 coordinate layout, uniformly scaled into the 640×480 render target before the final image is enlarged. This keeps the existing composition and menu hitboxes intact. The old half-resolution comparison toggle and its saved preference are retired. Verify native framebuffer dimensions, menu bounds, mouse sensitivity, and reticle-to-hitscan projection when changing presentation.

## Review procedure and decision log

For each playable increment, capture a repeatable 90-second route: spawn, Arch approach, Market low cover, Courtyard, Balcony, Stair House, Service Passage, and reset. Check the same 4:3 composition in a native 4:3 window and a wider window with side bars. Record version, movement/camera resource values, route times, and known issues beside the capture. Change one major variable per comparison.

Initial decisions are provisional: SOCOM II-led mechanics; 5v5; original town; near-centered camera; no separate sprint; first-to-six; shared-bomb Demolition; no regeneration; modern remappable inputs. The first play review should decide camera distance/offset, movement responsiveness, and whether the map feels too empty at five players per side. Slow prone crawling and a running dive are now implemented for feel testing, including collision and a committed landing recovery. Later reviews can settle first-person views, magazine persistence, equipment quantities, and team weapon differences.

The next review is to play the graybox, tune movement and camera values, and complete the outstanding M0 visual and device checks before expanding combat or producing finished art. Completion requires a runnable traversal prototype that passes the relevant checks, not merely a set of scripts that imports successfully.
