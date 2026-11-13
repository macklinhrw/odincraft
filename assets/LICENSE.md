# Block textures

`pixel-perfection/` holds block tiles taken from Mineclonia (<https://codeberg.org/mineclonia/mineclonia>),
an open-source game. Its `LEGAL.md` says its textures, unless noted otherwise, are from
**Pixel Perfection** by XSSheep (<https://www.planetminecraft.com/texture_pack/131pixel-perfection/>)
and **Pixel Perfection Legacy** by Nova Wostra, some of them changed or redrawn by Mineclonia's
contributors, under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Two tiles are
noted otherwise: `mcl_mud.png` and `mcl_mud_packed_mud.png` are by TheRandomLegoBrick, CC0 1.0.

The licence was read from Mineclonia's files on 2026-11-12, not from the packs' own pages. One of
Mineclonia's module notes (`mcl_core/README.md`) still names an older pack for its textures; the
tiles themselves are plainly Pixel Perfection's, and `LEGAL.md` is the project's statement. Check
both before distributing this game.

`blocks.png` is built from those tiles by `tools/blocks.py`, which recolours each to one of this
game's materials and adds flowers to one. It is an adaptation of them and is under the same
licence, CC BY-SA 4.0. The rest of this repository is not covered by that licence.

`plants.png` is built the same way from the plant pictures in `pixel-perfection/plants/`, also taken
from Mineclonia on 2026-11-12 and under the same `LEGAL.md` statement (Pixel Perfection, CC BY-SA
4.0): `mcl_flowers_fern`, `mcl_flowers_double_plant_fern_bottom` and `_top`, `mcl_flowers_tallgrass`,
`mcl_flowers_double_plant_grass_bottom` and `_top` and `flowers_dandelion_yellow` (module
`mcl_flowers`, whose README covers only its code); `mcl_farming_sweet_berry_bush_0`, `_1` and `_2`
(module `mcl_farming`, whose README states CC BY-SA 4 for its media); `mcl_core_papyrus` and
`default_dry_shrub` (module `mcl_core`, whose README names the older pack, as above); and
`mcl_bamboo_leaf_small` (module `mcl_bamboo`, with no notes of its own). `tools/blocks.py` recolours
some and keeps the others, and fills their clear pixels with their own mean colour. Not taken:
`flowers_waterlily.png`, which `mcl_flowers/CREDITS.md` credits to VanessaE, and the wildflowers,
credited to DragonWrangler1 under VoxelForge's licence. `plants.png` is likewise under CC BY-SA 4.0.
