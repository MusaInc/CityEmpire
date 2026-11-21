# Courier character source attribution

WorldState's characters adapt authored MakeHuman Community assets.
Original source files and attribution headers are retained in `sources/`.

* **Facial shape targets** (`sources/face_targets/`), **MakeHuman contributors** — CC0, fetched unmodified from the MakeHuman repository; they shape the five selectable faces. See `sources/face_targets/SOURCE.md`.
* **Hooded sweat jacket** (`elvs_hooded_sweat_jacket1`), **Elvaerwyn** — CC BY, as declared by its author and the community pack. [Source](http://www.makehumancommunity.org/node/1450), [official pack](https://static.makehumancommunity.org/assets/assetpacks/shirts02.html). CitySwing replaced it with skin-tight tops; City Empire uses it again as the hoodie in the Style screen (tools/blender/empire_wardrobe.py: recoloured texture, eased off the waist, subdivided). Attribution is shown in City Empire under Phone → More → Game → Credits.
* **Hair strand atlas** (`sources/hair_locks.png`) — generated for the WorldState texture pack on 2026-11-21. Blender derives an alpha-tested, dye-neutral game atlas from the refined source.
* **Running shoes 01**, **punkduck** — [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). [Official pack](https://static.makehumancommunity.org/assets/assetpacks/shoes02.html). Retargeted, resized and recoloured to white; original texture details adapted.
* **Cargo pants**, **Cortu Johnstone** — [CC0](https://creativecommons.org/publicdomain/zero/1.0/). [Official pack](https://static.makehumancommunity.org/assets/assetpacks/pants01.html). Adapted topology, fit, materials and pockets.
* **Gloves Hand**, distributed as `toigo_gloves_short`, source header credits **MRT** — CC0. [Official pack](https://static.makehumancommunity.org/assets/assetpacks/gloves01.html). Fitted and reskinned.
* **MakeHuman hm08 anatomy, morphology targets, rig and skin weights**, **MakeHuman contributors, Data Collection AB, Joel Palmius, Jonas Hauquier** — CC0 graphical assets, explicitly declared in original files / MakeHuman LICENSE.md. [Source repository](https://github.com/makehumancommunity/makehuman). Used for anatomical fitting, skin weights and opaque textile mask. No MakeHuman application code is included in the game.

CitySwing modifications: Musa Studios. Attribution is also available in the game's Settings → Character credits. Original pack metadata is retained alongside the assets. The jacket's upstream declaration does not specify a CC BY version; that declaration is preserved without assigning it a different licence.


### Fabric swatch atlas

`art/hero/sources/fabric-swatch-atlas.jpg` was generated with the built-in
ImageGen tool and is sampled into the Blender garment bakes. The GLBs carry
the baked garment textures.

> Generate a square PBR albedo source atlas for WorldState, a mobile game made in Blender. Exactly a two-by-two grid of four distinct seamless-looking flat photographic textile macro swatches. No margins, separators, borders, garments, stitching, folds, words, objects, or lighting gradients. Neutral desaturated mid gray values for all quadrants, uniform frontal cross-polarized studio light. Upper left authentic diagonal 3x1 denim twill with pale irregular slub yarn, upper right brushed jersey with extremely fine fibers and subtly heathered dye, lower left finely woven nylon ripstop with barely visible reinforced grid, lower right fine athletic shoe spacer mesh with open knit. Crop each quadrant edge to edge. Threads and interlacing should be identifiable at full resolution and stay finely scaled. True flat textile macro detail, no dramatic shadows or highlights.
