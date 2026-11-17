# WorldState character & clothing pipeline

One Blender build (`tools/blender/build_character.py`, headless) produces
`assets/models/character.glb`: the 17-bone gameplay skeleton, the five faces,
every hairstyle, every garment and every fitted accessory, skinned with at most
four influences. The game shows the worn variants (`CharacterRig._show_variants`)
and tints them through one shared shader family (`src/player/shaders/hero_*`).

```
tools/character_review/rebuild.sh       # Blender build -> Godot import -> texture import policy -> reimport (~1.5 min)
python3 tools/character_review/review.py capture <milestone> --quick   # Godot + Blender review renders, before/after, dashboard
```

## Conventions

**Skeleton.** Never changes: bone names `b_<name>` = `CharacterRig.BONES`, bind
pose with arms 42 degrees out (`ARM_A`), legs 5 degrees (`LEG_A`). Animation,
ragdoll and IK are untouched by anything here.

**Body.** MakeHuman hm08 (CC0), lean young-adult morph, retargeted onto the rig
(`torso()` maps the anatomy's heights onto the rig's joints). Weights: MakeHuman's,
with two corrections everything inherits - the shoulder (chest keeps the acromion;
no clavicle bone) and the base of the neck (follows the chest).

**Garments** (`tools/blender/garment_kit.py`, used by `empire_wardrobe.py`):
1. Cut the garment's region from the body (same vertices, same weights: it
   deforms exactly with the skin), subdivide once.
2. `tailor(ob, layer)`: fit, don't push. Per height slice the cloth spans the
   body's convex hull + the layer's ease and hangs under gravity (limited taper:
   darts at the sides); sleeves are tubes round the arm axis.
   Layers (`EASE_LAYER`): skin 0.4 cm, shirt 1.0, knit 1.3, jacket 2.0.
3. Necklines: measured on the real neck (`neck_ring_fit`, `STAND_R`), cut with
   `iso_cut` along a smooth curve, snapped onto the collar/rib's base ring.
4. Layering against the garment underneath: `clear_layer` (clearance),
   `follow_layer` (weights blend toward the under-layer's own, so both move
   together), `tuck_into` (inside the waistband).
5. Construction pieces (`shirt_collar`, `shirt_placket`, `button_mesh`,
   `shirt_cuff`, `rib_band`, lapels) are parametric, low-passed and mirrored,
   UV into the shared trim atlas, wound outward (`face_out`), crisp-edged
   (`crisp`), and take their weights from the garment they are sewn to
   (`weights_from`). One mesh per garment's trims (`Topx_<Cut>_Trim`).
6. `pack_uvs` then `bake_detail`: seams, topstitching and fine folds baked into
   the garment's own normal map from 3D seam definitions (`seam_height`,
   `seams_fn`); albedo near-white (the game tints it).
7. `finish` (edge thickness), `add()`.

**Names the rig keys on.** `Top_<cut>` (the garment), `Topx_<cut>_*` (its extra
pieces), `Skin_Arms_<cut>` (bare skin it needs), `Acc_<model>_<face>` (fitted
accessories: shades, cap, beanie, headphones), `Skin_Hands`, `Courier_*` (always
shown), materials `hero_*` (tint regions in `CharacterRig._install_hero_materials`).

**Accessories** (`tools/blender/accessories.py`): built per face from measured
landmarks (nose bridge, corneas, pupils, temples, ear roots, scalp, the actual
hair mesh the hat is worn over), skinned 100% to the head. Hats imply the hair
worn under them (`CharacterRig.HAT_HAIR`).

**Materials and price.** Every garment, budget or luxury, goes through the same
fit, construction, bake and shader. Price changes the design (cut, trims,
fabric colour and weave strength), never the rendering quality.

**Textures** (iPhone budget, enforced by `tools/character_review/fix_imports.py`
after every build): VRAM-compressed with mipmaps; normals 1024, ORM 512,
near-flat garment/face/hair albedos 512; one shared 256 weave and one shared
256 pore detail tile (`FABRIC_DETAIL` in the rig).

**Adding a garment.** Write it in `empire_wardrobe.py` with `everyday_top` (or
`tailored_top` + kit steps for a new construction), give it a `Top_<cut>` name,
add its id to `HeroLook`/`Wardrobe`/`Shop` like the existing tops, add its
material name to the rig's tint table and `FABRIC_DETAIL`, rebuild, capture.

## Review

`tools/character_lab.gd` renders the hero through the real look path under the
game's atmosphere from fixed cameras (and a neutral studio light with
`neutral`); `tools/blender/render_character_review.py` renders Cycles material
and clay passes; `review.py` builds before/after pairs and the dashboard at
`art/character_review/index.html`.
