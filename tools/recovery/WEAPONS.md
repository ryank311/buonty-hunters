# Recovered guns

The complete set of 43 named gun designs from `WEAP_MDL` is installed as 73 distinct textured geometry variants. All 1,462 source occurrences are recorded in `resources/recovered/weapons.json`. The source variants include small geometry/UV differences between archive contexts; the most common variant gets the plain ID and other versions carry a hash suffix. Ten designs are pistols, four are launchers. Ammunition, mines, explosives and the laser designator are outside this gun collection.

**Recovery Lab → Tab → Guns** opens the searchable collection. Filter by type or name, step through models, rotate the preview, and equip firearms. Equipping uses the existing prototype tuning for the corresponding weapon family and fills that slot. It does not reproduce the original game's weapon statistics. Launchers can be inspected; rocket/grenade-launcher firing is not implemented. The M16/M4 underbarrel variants use their rifle firing behavior only.

The seven standard firearm profiles now select recovered models: M4, M9, Glock 18, Desert Eagle, MP5, Remington 870 and Remington 700. Both carried firearm models remain loaded for the native swap animations. Selected guns survive level changes and respawns; choosing a class restores its loadout. Every model is also directly loadable as its catalogue `path` (`PackedScene`). No offline recovery files are required at runtime.

## Fidelity and selection

- Scale stays **0.1 metres/source unit**. Source +X becomes Blender +Y and Godot -Z. Geometry keeps the native attachment origin. No individual resizing or centering is applied to held models; only the Lab display places a centered instance above its stand.
- `prepare_weapon_meshes.ts` decodes original packets using the pinned recovery decoder and selects placements by their actual scene paths. `_low`/`_lo` LOD branches are excluded. Snipers use their standard scope, excluding the alternate thermal scope. The optional SIG suppressor is excluded from the base model. RPG7 retains its loaded projectile. Optional accessory configurations are not separate gun designs in this pass.
- Original `firepoint` markers supply each model's muzzle, including the source spelling `firepont` on RPG7. Markers are retained as `Muzzle` nodes in Blender/GLB and as canonical Godot coordinates in the manifest. Both muzzle flashes and shot origins follow these markers through the native hand attachment.
- Triangle signatures include positions, UVs and texture hashes. Packet padding/order, degenerate triangles and duplicate faces are removed. Geometry differences are preserved as variants, even when visually subtle. The 73 exports contain 60–550 triangles apiece.
- Shared, content-addressed PNGs live in `art/blender/textures/recovered_weapons/`. Blender image links are relative. Materials approximate original base colour and alpha; the original PS2 lighting/material system is not reproduced.

Each source is `art/blender/recovered_gun_<id>.blend`, exported to `art/models/recovered_gun_<id>.glb`. Export notes about geometry below zero and missing collision are intentional: these are hand attachments, not standing world props. The original inspection M4 remains available as the pilot asset; gameplay uses the correctly selected high-detail collection model.

## Rebuild

Requires the existing offline tree and pinned decoder from [README.md](README.md). This does not rerun extraction or overwrite its reports.

```sh
TSX_TSCONFIG_PATH=previous/recovery/reports/decoder-tsconfig.json node --import ./previous/recovery/research/socom-unzipped/web/node_modules/tsx/dist/loader.mjs tools/recovery/prepare_weapon_meshes.ts
previous/recovery/.venv/bin/python tools/recovery/prepare_weapons.py
```

Submit each generated `previous/recovery/staging/weapons/calls/*.py` through Blender MCP `execute_blender_code`. Calls import the staged OBJ, bind copied textures, add the native muzzle and save a distinct editable source. Do not execute the recipes with shell Blender. Then export the names listed by the catalogue with `tools/dev blender export <names...>` and run `tools/dev import`.

Runtime integration: `scripts/combat/recovered_weapons.gd`, `WeaponProfile.recovered_model`, `SoldierSkin.set_weapon_model`, `PracticeWeapon._show_weapon`, and the gun page in `recovery_browser.gd` / `recovery_lab.gd`.

`recovered_weapons_regression` loads every export and checks textures, triangle counts, native dimensions and original muzzle markers; it exercises search, equip, slot selection, stance attachments, ammunition retention and level changes. Keep the collection, native gunplay, swap, combat and full regression checks passing when updating models. Inspect the game renderer as well as the Blender previews.
