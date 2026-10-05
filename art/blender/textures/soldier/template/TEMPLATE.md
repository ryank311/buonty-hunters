# Soldier textures: generation brief

Eight small textures dress the soldier model (`art/blender/soldier.blend`, exported to `art/models/soldier.glb`). This brief says what each one must show, where things sit inside it, and how to put the results into the game. The model is already UV-mapped to these eight files, and flat-colour placeholders with the same names are in place, so each finished image shows up in the game as soon as it replaces its placeholder.

`overview.png` shows the model in the game with the placeholders (front, left side, back right). The look to match is the desert soldier in `concept-art/` at the repo root: `nb54vlq60yd91.jpg`, `3985481aaa.jpg`, and `the-best-online-gaming-experience-...webp` are the clearest views. Use those for mood, colour, and level of detail only. Everything painted must be original: no real flags, unit patches, name tapes, brand logos, or text of any kind.

## The eight textures

| File | Final size | Tiles? | Guide | Used on |
|---|---|---|---|---|
| `camo.png` | 128 × 128 | yes | none | Shirt, trousers, boonie hat |
| `nylon.png` | 32 × 32 | yes | none | Shoulder and side straps, chest panel, belt, thigh straps, holster |
| `hair.png` | 32 × 32 | yes | none | Back, sides, and top of the head |
| `face.png` | 64 × 64 | no | `guides/face.png` | Front of the head and the neck |
| `vest_back.png` | 128 × 128 | no | `guides/vest_back.png` | The striped panel on the back of the vest |
| `pouch.png` | 64 × 64 | no | `guides/pouch.png` | All nine pouches |
| `boot.png` | 64 × 64 | no | `guides/boot.png` | Both boots |
| `glove.png` | 32 × 32 | no | `guides/glove.png` | Both hands |

Together they come to about 48,000 texels, under one 256 × 256 sheet, which is the budget for a PlayStation 2 character here.

Generate every image as a **1024 × 1024 opaque PNG**. The final sizes above are produced by shrinking that master, so judge each image by how it reads when small.

## Style rules for every image

1. **PlayStation 2 era, 2002 to 2004.** Hand-painted over photo reference: soft, slightly blurred, muted, and simple. Not photoreal, not pixel art, not cel-shaded, not modern high-detail PBR.
2. **Flat and straight-on.** Orthographic, no perspective, no camera angle. The surface fills the whole frame, edge to edge.
3. **Light is baked in softly.** Gentle shading in folds, under flaps, and along seams is wanted. No direct light from one side, no cast shadows, no shine or highlights, no rim light, no gradient across the whole image.
4. **Nothing but the surface.** No border, frame, label, caption, watermark, text, background scene, or drop shadow. Where a guide shows grey background around a shape, paint the surrounding area in the surface's own main colour so nothing dark bleeds onto the model's edges.
5. **Bold enough to survive shrinking.** Features must still read at the final size. Avoid lines thinner than about 16 px on the 1024 px master, fine noise, film grain, and tiny stitching.
6. **Few colours.** Roughly 16 to 24 tones per image, taken from the palette below. Low contrast overall, low saturation.
7. **Tiling textures must repeat without a seam** on all four edges, with no feature that makes the repeat obvious (one distinct blotch, a stain, a crease).

### Palette

| Use | Colour |
|---|---|
| Uniform sand, the main camo colour | `#b5a883` |
| Camo pale khaki | `#cbbf9f` |
| Camo brown | `#8a7355` |
| Vest and strap nylon | `#8f8463` |
| Webbing rows, light | `#d0c6a4` |
| Webbing rows, dark | `#7b7054` |
| Pouch fabric | `#a09369` |
| Boot suede | `#7a6a4e` |
| Boot sole | `#3d3527` |
| Glove | `#3b3d33` |
| Skin | `#b48e6c` |
| Hair | `#2e261f` |

Shades may go a little darker or lighter than these for folds and wear. Keep each texture's average close to its listed colour: the soldier is seen from behind at a distance, and these values were chosen to read correctly in the game's lighting.

## Each texture

Positions are given as a percentage of the image, measured **from the left** and **from the bottom**.

### `camo.png` (tiles)

Three-colour desert camouflage cloth, as on a 1990s desert field uniform. Sand base over about 60% of the area, with broad pale khaki and brown blotches over the rest. Blotches are soft-edged, irregular, stretched horizontally, and between a sixth and a third of the image wide. A faint cloth weave and a few very soft fold shadows are welcome; pockets, seams, buttons, and zips are not. One tile covers half a metre of cloth, so the blotches come out 8 to 17 cm across on the soldier.

Prompt: *Seamless tileable texture of three-colour desert camouflage fabric, sand base with broad soft-edged pale khaki and brown blotches stretched horizontally, faint cloth weave, flat even lighting, straight-on, muted colours, early-2000s console game texture, hand-painted over photo reference, no seams, no pockets, no text.*

### `nylon.png` (tiles)

Plain khaki load-bearing nylon, colour `#8f8463`. A coarse, barely visible weave and nothing else. The belt and holster reuse this image darkened by the game, so keep it even and mid-toned.

Prompt: *Seamless tileable texture of plain khaki military nylon webbing fabric, coarse subtle weave, flat even lighting, straight-on, muted, early-2000s console game texture, no stitching, no buckles, no text.*

### `hair.png` (tiles)

Short, dark brown, cropped hair, colour `#2e261f`, with soft streaks running top to bottom. It wraps three times around the head, so keep it uniform.

Prompt: *Seamless tileable texture of short cropped dark brown hair, soft vertical strands, flat even lighting, straight-on, low contrast, early-2000s console game texture, no scalp, no parting, no highlights.*

### `face.png` (guide: `guides/face.png`)

A front view of the head and neck, as in the guide. The model's nose is on the centre line.

| Feature | From the bottom |
|---|---|
| Neck (plain skin, no collar, no clothing) | 0 to 22% |
| Chin | 27% |
| Mouth | 37% |
| Tip of the nose | 49% |
| Eyes | 61% |
| Eyebrows | 66% |
| Hat; the brim hides everything above and shades the brow below it | from 72% |

The head is 48% of the image wide at eye level, from 26% to 74% from the left, with the ears just inside those edges. Paint a man of about thirty: tanned, weathered skin, neutral expression, eyes open and looking straight ahead, light stubble, and a soft shadow under the hat line. Fill everything outside the head and neck with plain skin colour `#b48e6c`. The back of the neck takes its colour from the strip under the chin, so that strip must be clean skin.

Prompt: *Front-view orthographic face texture for a low-poly game soldier, laid out exactly as the guide image: tanned weathered male face, neutral expression, light stubble, eyes looking straight ahead, soft shadow across the forehead from a hat brim, plain skin neck below the chin, the area around the head filled with flat skin tone, flat even lighting, hand-painted early-2000s console game style, no hat, no collar, no background.*

### `vest_back.png` (guide: `guides/vest_back.png`)

The back panel of the vest, seen from behind: the single most recognisable part of the soldier. The panel is the large rectangle in the guide, from 5% to 95% across and from 5% to 88% up. It carries **eleven horizontal rows of webbing of equal height: six light (`#d0c6a4`) and five dark (`#7b7054`), alternating, light at the top and at the bottom.** Each row is about 7.5% of the image tall and runs the full width, off both side edges, because the panel's sides take their colour from the edge columns.

Welcome detail: a slightly darker stitched seam along the top and bottom of each row, soft shading where rows meet, and two faint vertical lines of stitching at about 30% and 70% across. Fill the strip above 88% and below 5% with the light webbing colour. Do not paint the shoulder straps that show at the top of the guide.

Prompt: *Straight-on texture of the back panel of a khaki tactical load-bearing vest, laid out as the guide image: eleven equal horizontal rows of nylon webbing alternating light sand and darker khaki-brown, light row at top and bottom, rows running the full width off both edges, stitched seams between rows, flat even lighting, muted, hand-painted early-2000s console game texture, no buckles, no patches, no text.*

### `pouch.png` (guide: `guides/pouch.png`)

One pouch, unfolded. The light square in the middle of the guide (14% to 86% both ways) is the front of the pouch. The darker border around it is the pouch's four sides, each folded outward from the edge it touches.

Front: a flap over the top 40% with a slightly darker lower edge and one small closure tab in the centre, and a plain body below it with one vertical strap down the middle. Border: plain pouch fabric a little darker than the front, with no detail. The same image is used on magazine pouches, large hip pouches, and a thigh pouch, so keep it generic.

Prompt: *Straight-on texture of a single khaki nylon military equipment pouch laid out as the guide image: central square is the pouch front with a top flap, a small closure tab and one vertical strap; the surrounding border is plain slightly darker fabric for the pouch sides; flat even lighting, muted, hand-painted early-2000s console game texture, no text, no logos.*

### `boot.png` (guide: `guides/boot.png`)

The right boot seen from its outer side, toe pointing right. The same image goes on both boots and on both sides of each.

| Part | Where |
|---|---|
| Sole, dark rubber `#3d3527` | 9% to 16% from the bottom, full length of the boot |
| Heel | 3% from the left |
| Toe | 96% from the left |
| Foot, tan suede | up to 52% from the bottom |
| Ankle shaft | 15% to 53% from the left, up to 89% from the bottom |

Tan desert suede with a darker toe cap and heel counter, a line of lace eyelets up the front edge of the shaft (its right side), and a padded collar at the top. Fill the grey background with suede colour `#7a6a4e`, and the strip below the sole with sole colour.

Prompt: *Side-view orthographic texture of a tan suede desert combat boot laid out exactly as the guide image, toe pointing right: dark rubber sole along the bottom, darker toe cap and heel, lace eyelets up the front of the ankle shaft, padded collar, background filled with flat suede colour, flat even lighting, muted, hand-painted early-2000s console game texture, no text, no logos.*

### `glove.png` (guide: `guides/glove.png`)

The back of the left hand in a loose fist, fingers up, thumb to the right, as in the guide. The wrist is at the bottom (4%), the knuckles at 85% to 93%, and the hand runs from 25% to 75% across with the thumb reaching 88%. Dark olive-grey tactical glove, colour `#3b3d33`: a wrist strap at 10% to 20%, a padded panel over the knuckles, and three faint lines between the fingers above it. Fill the background with glove colour. The palm reuses this image.

Prompt: *Straight-on texture of the back of a dark olive-grey tactical glove on a left fist, laid out as the guide image: wrist strap at the bottom, padded knuckle panel near the top, faint finger seams, thumb on the right, background filled with flat glove colour, flat even lighting, muted, hand-painted early-2000s console game texture, no text, no logos.*

## Putting the images into the game

Paths are from the repo root.

1. Save each 1024 × 1024 master as `art/blender/textures/soldier/masters/<name>.png` (create the `masters` folder).
2. Shrink each one over its placeholder, at the size in the table above:

   ```sh
   cd art/blender/textures/soldier
   for t in camo:128 vest_back:128 face:64 pouch:64 boot:64 nylon:32 hair:32 glove:32; do
     sips -z ${t#*:} ${t#*:} masters/${t%:*}.png --out ${t%:*}.png
   done
   ```

3. Export and import the model. The `.blend` links these files by path, so nothing has to be opened in Blender:

   ```sh
   tools/dev blender export soldier && tools/dev import
   ```

   The two `NOTE` lines the export prints (triangle count, no collision object) are meant for props and do not apply to the soldier.

4. Look at the result, from behind as played and then from three sides:

   ```sh
   tools/dev shot lab_start
   tools/dev shot lab_start stance=prone --spec='{"tuning":{"camera":{"field_of_view":30,"height_offset":0.75}},"actors":[{"team":3,"class":"rifleman","pos":[-1.3,0,22.6],"yaw":180,"name":"FRONT"},{"team":3,"class":"rifleman","pos":[0.1,0,22.6],"yaw":90,"name":"LEFT"},{"team":3,"class":"rifleman","pos":[1.5,0,22.6],"yaw":300,"name":"BACK"}]}'
   ```

   Each prints the path of a PNG to read. Teammates (ALPHA, BRAVO) are tinted by team; judge colour on the player and on the three soldiers in the second shot.

Check, at game size: the back panel's rows are crisp and level; the camo shows no visible repeat or seam on the trousers and sleeves; the face's eyes and mouth sit on the model's face rather than its forehead or chin; nothing dark rings the hands, boots, or neck. If a feature is offset, repaint to the guide rather than moving the model's UVs.

## How the model uses each image

For anyone adjusting the mapping later (it is set by script in `soldier.blend`, one UV layer named `UVMap` per object):

- **camo, hair, nylon** wrap or project at a fixed scale: one camo tile is 0.5 m, one nylon tile 0.2 m, one hair tile 0.1 m tall.
- **face** is a front projection of a 0.32 m square whose bottom edge is 1.42 m above the ground, centred on the model.
- **vest_back** is a projection from behind of a 0.38 m square whose bottom edge is at 1.13 m.
- **boot** is a side projection of a 0.315 m square starting 0.115 m behind the ankle and 0.03 m below the ground.
- **glove** is a projection onto the back of the hand of a 0.17 m square.
- **pouch**: each pouch's front face takes the central square and its sides the border.

The guides in `guides/` are renders of the model through exactly these projections.
