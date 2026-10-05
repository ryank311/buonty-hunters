# Recovered maps

The project includes only the disc's multiplayer maps: original geometry, collision, sky dome, lighting and fog, at the native 0.1 m per source unit. Open **Esc / Start → Maps** in the game and pick one; **Next spawn** cycles its spawns. Campaign maps remain in the offline recovery archive and must not be reinstalled into the main project.

## Pipeline

| Step | Command | Output |
| --- | --- | --- |
| Prepare | `previous/recovery/.venv/bin/python tools/recovery/prepare_level.py MP72` (or `--all`) | `previous/recovery/staging/levels/<ID>/` OBJ/MTL inputs; textures in `art/blender/textures/recovered_map_<id>/`; committed `resources/recovered/levels/<id>.json` |
| Local lights | `previous/recovery/.venv/bin/python tools/recovery/prepare_lights.py --verify` | `resources/recovered/lighting.json`; all installed MP maps, no Blender rebuild |
| Build | `prepare_level.py --batch MP72 MP1 ...`, then submit `staging/levels/batch_call.py` to the Blender MCP `execute_blender_code` tool | `art/blender/recovered_map_<id>.blend` |
| Export | `tools/dev blender export recovered_map_mp72 ...` then `tools/dev import` | `art/models/recovered_map_<id>.glb` |
| Verify | `tools/dev test recovered_maps_regression`, `tools/dev shot level=map:MP72 spawn=1` | |

The Blender MCP runs in safe mode, so the recipe imports the prepared OBJ files with Blender's own importer instead of reading data itself; a call carries only map ids, and eight to thirteen maps fit in one call. A multiplayer map appears in the menu as soon as its description and GLB exist. `--all` selects only `MP<number>` maps; named preparation and Blender batches reject campaign IDs before writing files.

## Installed — 2026-10-05

All 22 multiplayer maps: 958,189 world triangles (16,410 Frostfire to 83,308 Shadow Falls), every map with a sky dome and at least three spawns. Storage: 124.4 MiB of GLB, 38.0 MiB of `.blend`, 12.0 MiB of source textures, plus the textures Godot extracts beside each GLB.

The 12 campaign maps (`M51–M53`, `M61–M63`, `M71–M73`, `M81–M83`) were removed from `art/` and `resources/recovered/levels/`. Their 3,468 installed files (227.0 MiB, including Blender sources, GLBs, textures, import sidecars and level JSON) were moved to the ignored `previous/recovery/retired/campaign-project-20261005/`, preserving relative paths and a SHA-256 `manifest.json`. Twelve concurrently generated campaign action manifests and the original action catalogue were also archived (1.4 MiB); the active action catalogue retains only multiplayer entries. The original ISO and all decoded campaign data remain untouched. Back up this local archive separately; it is not shipped or committed. Shared characters, animations, guns, props and HUD assets remain available even where their provenance names a campaign archive.

## What the preparation selects

- **Geometry:** intact states only. Object paths matching destroyed/debris branches (`destroyed`, `whats_left`, `*_parts`, `part<n>`, `bad_parts`), `_shadow` and `_pulse` helpers, camera-following rain/dust and the night-vision mask are omitted; `good_parts` is kept. Exact duplicate and degenerate triangles are removed. Surfaces are merged per texture, so a map is about 80–250 draw surfaces.
- **Sky:** objects named `sky`, `skydome`, `cyl_sky`, `cloudlayer` and similar, and any surface with a sky, cloud, star or moon texture (not `skylight` windows or the water's `moonreflect`), become a separate `Sky` group. MP72 and MP53 keep their dome in the zone library and use that model (`mp72_sky`, `sky`). In game the dome follows the camera and the sky shader projects it to the far distance, unlit and unfogged, so it never clips and shows no parallax; the original 82 m draw distance did not contain these domes either. A dome built into the level follows only horizontally and keeps its authored height, so its mountain or skyline band sits where the designers put it; a separate model puts the eye just above its rim.
- **Collision:** the level's original collision polygons, minus the same omitted branches and camera/trigger volumes (`cameratype & 1`), grouped by original surface (`<asset>_<surface>-colonly`; material id = SOILS index + 2, 0 = the map's DefaultMaterial) so bullet impacts play the right effect. Water (`material 11`) is its own group, which the game keeps off every movement and bullet layer and probes for splashes. Godot uses it two-sided, as in the Crossroads pilot.
- **Ambience** (`<map>.rdr` `world_params` and `camera`): ambient colour and up to three directional lights (PS2 128 = full intensity, so colours are scaled by 255/128), standard fog colour and range, and draw distance. The game swaps in this environment and sun while the map is loaded and restores the defaults afterwards.
- **Materials:** each texture's original blend mode from the map's `*_lib.rdr` (`ALPHACLIP`, `ADDITIVE`); textures with sub-128 alpha are treated as cutouts when no mode is recorded.
- **Spawns:** multiplayer maps use the mission's named `Scenic_Views` (base views first), dropped onto the highest walkable collision below each camera and kept only with clear headroom. Any map with fewer than three usable views is topped up with clear walkable spots near the centre of the walkable area, at least 15 m apart (`Map centre`). Each spawn faces the direction with the longest clear line of sight at eye height (16 directions tested against the collision, leaning toward the map centre); spawn names drive the HUD location.

## Known limits

- Lighting is per-pixel with the original directional and local light records, not the PS2 vertex lighting; baked vertex colours are not recovered yet. See local-light recovery below for fallback sources and rendering limits.
- Rain/dust followers, animated and scrolling materials (`whispy_scroller`), lens flares, water surfaces and destructible state changes are not reconstructed. All 43 native doors across nine multiplayer maps now swing with moving collision; see [ACTIONS.md](ACTIONS.md) for the action HUD, source ownership and remaining interaction limits.
- Alternate light states (`light_off`, `bulboff`) are separate models in the source and all remain.
- No AI navigation, team spawns or objectives. The default stand-in roster is not placed on recovered maps.
- The geometry is the extraction's assembly. Spot-check unfamiliar maps for leftover state branches and add patterns to `DROP` in `prepare_level.py` rather than editing a GLB.

## Local-light recovery — 2026-10-05

`prepare_lights.py` audits all 22 installed multiplayer maps. It reads the native `<MAP>_GEO.ZED` archive through `native/indexes/`, expands only instances reachable from `worldmodel`, and recovers **248 placed CLight nodes** (native node type 8). The mesh extractor omitted these nonvisual nodes. An additional **103 fixture-based approximations** supply the clearly lit lamps and fires whose models have no CLight record. The committed catalogue has 351 emitters across 14 maps; the other eight maps were audited and have no confirmed active local emitters in this pass. Campaign maps remain excluded.

| Map | Native | Fixture approximation |
| --- | ---: | ---: |
| Blizzard (MP1) | 37 | 0 |
| Death Trap (MP11) | 16 | 0 |
| Frostfire (MP2) | 35 | 1 |
| Desert Glory (MP6) | 1 | 21 |
| Sujo (MP61) | 27 | 0 |
| Enowapi (MP62) | 6 | 0 |
| Shadow Falls (MP64) | 27 | 0 |
| Night Stalker (MP7) | 23 | 1 |
| Crossroads (MP72) | 0 | 16 |
| Sandstorm (MP73) | 5 | 0 |
| Rat's Nest (MP8) | 20 | 0 |
| Chain Reaction (MP81) | 0 | 30 |
| Guidance (MP82) | 2 | 34 |
| Requiem (MP83) | 49 | 0 |

Native evidence is preserved per emitter: archive path, scene path, payload-relative `nparams_offset`, position, normalized RGB, inner range, outer range and `evidence: native`. The 96-byte `nparams` contains a row-vector transform, six-float bounds, type and flags. `diffuse` is three normalized floats (do **not** apply the global PS2 255/128 multiplier); `min_range` is a source-unit radius and `max_range_sq` is the squared outer radius. Child transforms compose as `local @ parent`, including the referenced prototype root. Positions use the installed map's `source_origin` and `scale`; radii use its scale. `--verify` checks these composed transforms against recovered mesh placements before writing (7,604 matched placements, maximum discrepancy 0.0001221 source units on the current archive).

Fallback profiles are explicit in `FIXTURES`, never a broad name search. They cover Crossroads bright/dim bulbs, Chain Reaction fluorescents, Guidance hanging lamps/posts, Desert Glory lamps and burning rubble/barrel, Night Stalker's firepit and Frostfire's tower-flame marker. Crossroads and Chain Reaction retain spherical light-influence bounds that guide their positions/ranges; other offsets and all fallback colors/energies are estimates. Each entry is labeled `evidence: fixture`. Off/no-source fixtures, inactive branches, unplaced library prototypes, destroyed branches and generic `fire_effects` attached to demolition objectives do not gain fallback lights. Baked bright patches, skylights and pale textures alone are insufficient evidence for an emitter.

`scripts/levels/recovered_lighting.gd`, installed by `RecoveredMap`, owns six reusable shadowed OmniLights. This is deliberate: the [Mobile renderer limits each mesh to eight omni lights](https://docs.godotengine.org/en/latest/tutorials/3d/lights_and_shadows.html), and the recovered world meshes span the map because they are merged per texture. The pool favors nearby influence volumes, reserves two slots for combat effects, fades replacements and uses selection hysteresis. Walls block the local lights. All catalogue sources become eligible as the camera approaches, but only six contribute at once; distant illuminated rooms can therefore lose local illumination. Do not instantiate every light permanently without first splitting the map meshes or changing the rendering approach.

The original inner plateau is approximated by Godot's smooth attenuation curve. Fire/torch sources get subtle deterministic energy variation; flame particles, destructible switching and emissive-surface reconstruction are separate work. Source light positions are preserved even when the original emitter is placed well below its bulb. The runtime needs only the committed JSON; Linux exports already include and audit it. Reload the map after regenerating the catalogue.

Validated with `tools/dev check`, the three core suites and `recovered_maps_regression` (all 22 maps and their spawns), plus hidden in-game captures in Frostfire, Requiem, Shadow Falls, Chain Reaction, Crossroads and Desert Glory. Identical-camera comparisons with the light controller hidden confirmed the tunnel, warehouse, torch and rubble illumination. SteamOS has not been rebuilt for this pass.
