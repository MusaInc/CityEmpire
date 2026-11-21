# WorldState character & clothing pipeline

Blender exports both WorldState builds from `tools/blender/build_character.py`.
Each build contains five faces, eight hairstyles, the wardrobe and fitted
accessories around the same 17-bone gameplay skeleton. The editable projects
are `art/hero/courier.blend` and `art/hero/courier_b.blend`, with the matching
GLBs in `assets/models/`. Godot shows the worn variants through `CharacterRig`
and shares shader parameters across surfaces using the same source material.

```
tools/character_review/rebuild.sh       # Both builds, both crowd LODs and Godot texture imports
python3 tools/character_review/review.py capture <milestone> --quick   # Godot + Blender review renders, before/after, dashboard
```

## Conventions

**Skeleton.** Never changes: bone names `b_<name>` = `CharacterRig.BONES`, bind
pose with arms 42 degrees out (`ARM_A`), legs 5 degrees (`LEG_A`). The
gameplay rig drives world-space foot contact. Its blend shapes close the
sculpted lids, flex the individual fingers, and restore fabric volume at the
elbows and knees from the active joint rotation. Fingers retain the source hand's joint weights in the
Blender bake and use the existing two hand blend shapes in Godot.

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
   together), `tuck_into` (inside the waistband). `fit_over_waist` applies
   the same rules to both cuts. Cargo, chinos, jeans, joggers and shorts share the same
   waist block and bend weights. The shorts use their own skinned legs. Trim transfers interpolate weights across the closest
   surface triangle to avoid switching to a different joint at each vertex.
5. Construction pieces (`shirt_collar`, `shirt_placket`, `button_mesh`,
   `shirt_cuff`, `rib_band`, lapels) are parametric, low-passed and mirrored,
   UV into the shared trim atlas, wound outward (`face_out`), crisp-edged
   (`crisp`), and take their weights from the garment they are sewn to
   (`weights_from`). One mesh per garment's trims (`Topx_<Cut>_Trim`).
6. `pack_uvs` then `bake_detail`: seams, topstitching and fine folds baked into
   the garment's own normal map from 3D seam definitions (`seam_height`,
   `seams_fn`); albedo near-white (the game tints it).
7. `finish` (edge thickness), `add()`. The fleece hoodie also uses this
   pipeline for its sleeve openings and rib cuffs. The bomber includes a zip, ribbed neck and cuffs, and fitted welt pockets.
   Trainers use fitted uppers and separate foam midsoles, rubber outsoles,
   tongues, eyestays and laces. Their tint regions keep the original shoe
   and sole choices. Cargo pockets have separate gusseted bodies and flaps.

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

**Textures and LODs.** Runtime maps are VRAM-compressed with mipmaps. The
import policy caps face and hair maps at 512, seam and panel normals at
1024, and preserves the 1024 hair-card atlas. Both GLBs use Godot mesh LODs.
The alpha-tested groom cards draw only up close and the opaque groom
retains the silhouette farther back. The same Blender files produce the
eight pedestrian outfits at 3,100 and 900 triangles per figure. Art sources
and intermediate bakes are excluded from exports.

**Adding a garment.** Write it in `empire_wardrobe.py` with `everyday_top` (or
`tailored_top` + kit steps for a new construction), give it a `Top_<cut>` name,
add its id to `HeroLook`/`Wardrobe`/`Shop` like the existing tops, add its
material name to the rig's tint table and `FABRIC_DETAIL`, rebuild, capture.

## Review

`tools/character_lab.tscn` renders the hero through the real look path under the
game's atmosphere from fixed cameras (and a neutral studio light with
`neutral`); `tools/blender/render_character_review.py` renders Cycles material
and clay passes; `review.py` builds before/after pairs and the dashboard at
`art/character_review/index.html`.

The stage opens the same look path as the game. Use `catalog` to review all
eight tops on both builds. The lab outfits a_denim through b_shorts cover
the three new lower cuts. City mode opens the live wardrobe, changes the
outfit through its normal controls and saves the portrait, outfit and rear
views. Set a temporary `XDG_DATA_HOME` and pass an isolated `--save` when
capturing the city.

```sh
godot --rendering-method mobile --fixed-fps 30 res://tools/character_lab.tscn -- screenshots/character-review catalog idle neutral three_quarter,collar
```
