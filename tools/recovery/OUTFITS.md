# Full-detail characters and worn equipment

**F1 / Cmd+1 / Start → Loadout** selects among 106 full-detail bodies. Recovery Lab and `[ / ]` use the same ordered list. The original 202-model catalogue and all source assets remain preserved; 96 distance LODs are excluded from selection. Native `character.rdr` LOD lists identify reduced meshes, with a triangle audit catching orphan variants: excluded meshes have 230–761 triangles; selectable bodies have 1,523–2,342. Some `_LO` names are full-detail bodies in the source character presets, so names alone are not sufficient. Godot's generated mesh LODs are disabled for every selectable body and imported accessory.

**Outfit** exposes separate headwear, goggles, vest gear, belts/pouches, holsters, packs and knives. Each slot offers Auto (the body's original gear), None, and recovered alternatives. Overrides persist across respawn, map changes and character changes for the current run. Restore original outfit clears overrides. Details built into a body's skinned mesh cannot be removed through these separate-gear controls. Loadout continues to own ammunition and weapons; outfit controls are visual only.

## Recovery evidence and placement

`previous/recovery/native/scripts/disc/READERC.ZAR-1b7df1c973/00005-character.rdr.json` supplies inherited character presets, `model_name`, `lods`, `default_gear`, and each piece's `ofs` (bone, translation, angles). `resources/recovered/outfits.json` records the selected source preset for every full-detail body and retains unavailable definitions. When several presets share a body, its source map's preset is preferred, then deterministic name order. Source-map texture variants are preserved.

The 38 available gear definitions include separate eyes, hats/helmets, goggles, belts, holsters, pouches, knives and satchels. There are 32 distinct textured assets including three carried grenade models. Preparation stages already decoded and assembled OBJ triangles as glTF at their original attachment origins, with the original PNGs. Blender MCP imports these into 32 editable `.blend` sources; `tools/dev blender export` produces the runtime GLBs. No geometry is remodelled or normalized. Original source triangles remain under `previous/recovery/`; the runtime only reads committed assets.

Export notes about an origin above/below the floor or missing collision are expected for these worn pieces: they retain their recovered bone attachment origins and do not need separate physics collision.

Local research `previous/recovery/research/socom-unzipped/web/redotcom/docs/research/78-character-mesh-and-skeleton.md`, §5, establishes offset order: fixed-axis X then Y then Z, yielding `Rz * Ry * Rx` for column vectors. Translation is scaled by the same 0.1 metres per native unit as the body. Runtime placement is the final native bone transform times that offset. This runs after locomotion, aim, lean, reload, swap and throw layers. The parent scene transform carries world movement, turning and terrain alignment. Ragdoll gear uses the final skeleton pose with its import-axis calibration removed. Recovery Lab previews also update worn gear when seeking a clip.

The `rifle`, `pistol` and `launcher` gear records use `NONAME.flt`: these are weapon sockets, not missing meshes. Inactive firearms reuse the actual equipped firearm model and the recovered rifle/spinelo or pistol/rthigh socket. Hand/stow visibility is complementary throughout the existing swap timing, so there is one visible copy of each firearm. Grenades use recovered frag, smoke and flashbang meshes, with fitted belt locations (an adaptation, not recovered belt slots). They follow current supply, with a maximum of two per equipment slot/four total; a grenade in hand is not also on the belt. Claymore is not displayed as a grenade.

## Remaining gaps

Eight named source pieces have no corresponding decoded equipment mesh: `seal_headset`, `seal_d_ch_back`, `al_terror_pack`, `upper_teeth`, `lower_teeth`, `vidonia_lower_teeth`, `valeska_upper_teeth`, `valeska_lower_teeth`. They are listed in the manifest and omitted, rather than replaced with invented geometry. Teeth also reference jaw attachments outside the installed 26-part rig. Some enemy hats/packs are already skinned into their body mesh; cross-character overrides can intersect that built-in clothing. The original weapon sockets are rigid attachments, with no added sling strap or cloth simulation. Gear does not alter armor statistics. Ragdolls retain worn character pieces; inventory display is driven on the living actor.

## Rebuild and check

```sh
previous/recovery/.venv/bin/python tools/recovery/prepare_outfits.py
# Submit staging/outfits/build_00.py through build_03.py to Blender MCP, then:
xargs tools/dev blender export < previous/recovery/staging/outfits/export_names.txt
tools/dev import
tools/dev check
tools/dev test debug_loadout_regression recovered_collection_regression hud_layout recovered_actions_regression ragdoll_regression
```

`debug_loadout_regression` checks selector filtering, grenade supply, held/stowed visibility, and gear staying fixed relative to the rendered bones through translation, turning, standing, crouching and prone. This guards the floating-gear failure caused by an invalid inventory field aborting attachment updates. The collection suite still audits all 202 preserved exports, while gameplay selection exercises the 106 full-detail bodies. Inspect rendered movement, swap states and the Outfit page as well as these checks.
