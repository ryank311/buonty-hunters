# Recovered maps

The project includes only the disc's multiplayer maps: original geometry, collision, sky dome, lighting and fog, at the native 0.1 m per source unit. Open **Esc / Start → Maps** in the game and pick one; **Next spawn** cycles its spawns. Campaign maps remain in the offline recovery archive and must not be reinstalled into the main project.

## Pipeline

| Step | Command | Output |
| --- | --- | --- |
| Prepare | `previous/recovery/.venv/bin/python tools/recovery/prepare_level.py MP72` (or `--all`) | `previous/recovery/staging/levels/<ID>/` OBJ/MTL inputs; textures in `art/blender/textures/recovered_map_<id>/`; committed `resources/recovered/levels/<id>.json` |
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
- **Collision:** the level's original collision polygons, minus the same omitted branches, camera/trigger volumes (`cameratype & 1`) and water (`material 11`). Godot uses it two-sided, as in the Crossroads pilot.
- **Ambience** (`<map>.rdr` `world_params` and `camera`): ambient colour and up to three directional lights (PS2 128 = full intensity, so colours are scaled by 255/128), standard fog colour and range, and draw distance. The game swaps in this environment and sun while the map is loaded and restores the defaults afterwards.
- **Materials:** each texture's original blend mode from the map's `*_lib.rdr` (`ALPHACLIP`, `ADDITIVE`); textures with sub-128 alpha are treated as cutouts when no mode is recorded.
- **Spawns:** multiplayer maps use the mission's named `Scenic_Views` (base views first), dropped onto the highest walkable collision below each camera and kept only with clear headroom. Any map with fewer than three usable views is topped up with clear walkable spots near the centre of the walkable area, at least 15 m apart (`Map centre`). Each spawn faces the direction with the longest clear line of sight at eye height (16 directions tested against the collision, leaning toward the map centre); spawn names drive the HUD location.

## Known limits

- Lighting is per-pixel with the original light directions, not the PS2 vertex lighting; baked vertex colours are not recovered yet.
- Rain/dust followers, animated and scrolling materials (`whispy_scroller`), lens flares, water surfaces, doors and destructible state changes are not reconstructed.
- Alternate light states (`light_off`, `bulboff`) are separate models in the source and all remain.
- No AI navigation, team spawns or objectives. The default stand-in roster is not placed on recovered maps.
- The geometry is the extraction's assembly. Spot-check unfamiliar maps for leftover state branches and add patterns to `DROP` in `prepare_level.py` rather than editing a GLB.
