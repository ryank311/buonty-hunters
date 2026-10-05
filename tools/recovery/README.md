# SOCOM II disc recovery

This is an offline extraction/staging pipeline. It preserves the ISO, extracts its filesystem and ZDB archives, indexes every ZAR/ZED key, and converts supported assets to PNG, OBJ/MTL and JSON. It does not modify gameplay or install assets into the running game.

The recovered collection is at `previous/recovery/`. Open `previous/recovery/index.html` for the searchable catalogue. `previous/` is already git-ignored; `.gdignore` keeps the recovery tree out of Godot's importer. Back up this folder separately from Git.

A first Blender/Godot integration now lives in **Cmd+1 / F1 → Recovery Lab**. Its M4, animated SEAL and Crossroads plaza sources, controls and rebuild steps are documented in [PILOT.md](PILOT.md). The extraction commands below still only produce the offline collection. The main project now installs all 22 multiplayer maps through [LEVELS.md](LEVELS.md); campaign maps remain offline and must not be reinstalled.

## Recovery result — 2026-10-05

The USA disc yielded 349 filesystem files, 35 ZDB archives, 2,170 archive members and 1,894 distinct ZAR/ZED libraries. All extracted filesystem bytes were compared with their ISO extents; all archive member hashes passed verification.

| Converted output | Count |
| --- | ---: |
| PNG texture entries | 15,270 (3,398 distinct PNG hashes) |
| Static model entries, including weapons, props and level pieces | 4,813 |
| Character variants and LODs, with skin data | 560 |
| Assembled levels | 34 (22 multiplayer, 12 campaign) |
| Skeletal animation clips | 1,178 |
| Decoded reader/configuration records | 703 |

All 22,558 exports passed file validation, with zero conversion errors or failed geometry chunks. One unused `cratelong` prototype in MP11 retains an unresolved `shadow_rect.tif` binding because that name has two different recovered textures. This warning is preserved in `reports/validation.json`; all native data remains available.

Textured previews of a soldier, an M4 and Crossroads were inspected. The recovery tree occupies about 8.1 GB in addition to the ISO. The five extractor tests, `tools/dev check`, `tools/dev import`, and all 11 Godot regression suites passed. The import pass also generated missing UID companions for the existing `throw_arc.gd` and `throw_regression.gd` scripts.

## Repeat the recovery

Requires Python 3.9+, Node 22+, npm, Git and `bsdtar` (included with macOS). The first run downloads a pinned decoder checkout and its local npm dependencies. Subsequent runs use the local checkout.

```sh
python3 tools/recovery/recover.py 'previous/SOCOM II - U.S. Navy SEALs (USA).iso'
```

Use `--out <fresh-folder>` for a different disc. Existing disc files are checked against the original ISO rather than overwritten. The extractor independently compares every ISO9660 file extent with the extracted bytes, then hashes the ISO, disc files and ZDB members. It rejects unsafe paths and invalid file bounds. Conversion errors are recorded individually so native data is never lost when a decoder cannot handle a record.

To rerun conversion after changing the adapter:

```sh
python3 tools/recovery/recover.py 'previous/SOCOM II - U.S. Navy SEALs (USA).iso' --convert-only
```

Verify the exports and regenerate the catalogue/contact sheet:

```sh
uv venv previous/recovery/.venv --python /usr/bin/python3
uv pip install --python previous/recovery/.venv/bin/python pillow==11.3.0 numpy==2.0.2
previous/recovery/.venv/bin/python tools/recovery/verify_assets.py previous/recovery
python3 -m unittest discover -s tools/recovery -p 'test_*.py'
```

Skip the `uv venv` command when that environment already exists. Verification checks all PNGs, OBJ face/UV indices and material file references, skeleton influence bounds and weight sums, animation JSON, and SHA-256 hashes of the unpacked archive members. Missing texture bindings and partial exports are listed separately from corrupt output files.

## Layout

| Directory | Contents |
| --- | --- |
| `disc/` | Every original disc file, including audio, movies, executable and engine data |
| `archives/<disc-archive>/` | All unpacked ZDB members with original internal paths; variants remain separate |
| `native/indexes/` | Full named key trees and exact offsets into the preserved ZAR/ZED files |
| `native/models/` | Individually named original PS2 mesh buffers and supporting records |
| `native/audio/` | Named sound banks and voice streams, preserved in original binary form |
| `native/animations/` | Original motion and zAnim records |
| `native/scripts/` | Compiled reader/configuration data, plus decoded `.rdr` JSON where applicable |
| `native/records/` | Other archive payloads |
| `converted/textures/` | RGBA PNGs by category, archive context and library; palette-dependent variants kept separate |
| `converted/models/` | Named OBJ/MTL files, decoded scene graph JSON and character skin sidecars |
| `converted/levels/<map-id>/` | Assembled level OBJ/MTL, collision OBJ/JSON and original placement matrices |
| `converted/animations/` | Decoded skeletal motion tracks as compressed JSON |
| `reports/` | Provenance, file hashes, conversion coverage, exceptions, validation and previews |
| `research/` | Local source checkouts used for decoding/research; outside the game code |

`reports/libraries.json` maps every library occurrence to its source archive. Identical library payloads are decoded once; all occurrences remain in the manifest. Counts include named LODs and variants across libraries, not only distinct characters or distinct weapons.

## What the exports preserve

- Textures: original stored pixel dimensions, palette colours and PS2 alpha conversion. Metadata retains the GS state and original palette/library references. A partial-height texture uses its original pixels; OBJ UVs account for the GS texture domain.
- Static models: triangle positions, UVs, material references, and lines. Hierarchy transforms are applied to assembled OBJ geometry. Full scene graphs and native packets preserve data beyond what OBJ can represent.
- Characters: a textured bind-pose OBJ plus `.skin.json.gz` containing bone hierarchy, local/bind matrices, all influences, weights, bone-local vertex positions and normals. No weights are truncated to four influences.
- Levels: world geometry, placed props, clutter, collision polygons and placement matrices. Alternate/destroyed states and LOD branches are retained together for extraction; these exports are not a final runtime scene.
- Animation: original motion clips plus decoded frame counts, durations, translations, quaternion keys and track flags. zAnim controllers remain indexed native records.
- Sounds/movies: all original files and named bank/stream records are preserved. Audio/video transcoding is not performed by this adapter.

OBJ uses the original right-handed Y-up game coordinates. One recovered soldier is about 19.4 source units tall and an M4 is about 8.86 units long; the established Blender/Godot conversion is 0.1 metres per source unit. Do not independently normalize every asset. OBJ V is flipped for its bottom-left texture convention. Surface normals should be recalculated on import; original normals and vertex colours remain in the native records (and character sidecars).

The MTL provides base-colour texture links. The PS2's blending, alpha test, vertex lighting, animated material effects, billboards and LOD/state selection need explicit handling in the next pipeline stage. A model with an unresolved texture is marked in the catalogue and validation report. A cross-context texture is used only when every recovered PNG of that exact name has identical bytes; ambiguous alternatives remain unresolved.

## Decoder provenance

The adapter calls the GPL-3.0 [redotcom packages in SOCOM Unzipped](https://github.com/Scotho/socom-unzipped/tree/a519c9bf0bdf94f5a7ba39037c942b970bfa1031/web/redotcom), pinned to commit `a519c9bf0bdf94f5a7ba39037c942b970bfa1031`. The checkout and its license stay under `previous/recovery/research/`; no decoder source is copied into gameplay code. The adapter adds recovery manifests, native payload organization, OBJ export, validation, and handling for cross-library palettes, partial-height uploads and the campaign wire's mixed packet layouts.

Archive layout was also cross-checked with [SOCOM Archives Manager](https://github.com/mbacker80/SOCOM-Archives-Manager) and [reCOM](https://github.com/NotEnoughPhotons/reCOM). These are format research sources, not recovered original game source code. The ISO contains compiled code and cooked assets, not the lost editable source project.

## Blender and Godot pilot

The [pilot](PILOT.md) imports an M4 and a Crossroads section with collision. The [character collection](CHARACTERS.md) extends it to all 202 distinct rigged character variants and 402 distinct motion clips, with the original 26-part rigs now used by the playable characters. In Recovery Lab, **Tab** opens the searchable comparison browser. Sources are saved in `art/blender/` and exported through `tools/dev blender` to `art/models/`. Start new integration work from the [agent asset handoff](../../docs/ASSET_RECOVERY_HANDOFF.md); it records the runtime architecture, validation requirements and remaining asset batches.

`preview_obj.py` is an optional software render for extraction QA. It needs Pillow and NumPy, and displays only source geometry/base-colour textures; it is not a Godot rendering comparison.
