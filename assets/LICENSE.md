# Block textures and typefaces

## Block textures

`pixel-perfection/` holds block tiles taken from Mineclonia (<https://codeberg.org/mineclonia/mineclonia>),
an open-source game. Its `LEGAL.md` says its textures, unless noted otherwise, are from
**Pixel Perfection** by XSSheep (<https://www.planetminecraft.com/texture_pack/131pixel-perfection/>)
and **Pixel Perfection Legacy** by Nova Wostra, some of them changed or redrawn by Mineclonia's
contributors, under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Two tiles are
noted otherwise: `mcl_mud.png` and `mcl_mud_packed_mud.png` are by TheRandomLegoBrick, CC0 1.0.

The licence was read from Mineclonia's files on 2026-11-12, not from the packs' own pages. One of
Mineclonia's module notes (`mcl_core/README.md`) still names an older pack for its textures,
"Faithful 1.11" under the MIT licence. That note is taken to be a stale leftover from MineClone2,
for two reasons checked on 2026-11-15: Mineclonia's top-level `LEGAL.md` says every texture not
noted otherwise is Pixel Perfection under CC BY-SA 4.0 and that no non-free licences are used
anywhere, and Faithful 1.11 is a 32×32 pack while every tile here is 16×16, Pixel Perfection's
resolution.

`blocks.png` is built from those tiles by `tools/blocks.py`, which recolours each to one of this
game's materials and adds flowers to one. It is an adaptation of them and is under the same
licence, CC BY-SA 4.0. The rest of this repository is licensed under the AGPL-3.0-or-later; see `LICENSE`.

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

## Typefaces

`fonts/` holds the interface's two typefaces (`docs/foundations/interface.md`, I10), three files as
their makers released them, unchanged. Each is under the [SIL Open Font License, Version 1.1](https://openfontlicense.org),
whose text and copyright notice stand beside it:

- `Marcellus-Regular.ttf`, version 1.000: Copyright (c) 2012, Brian J. Bonislawsky DBA Astigmatic
  (AOETI), with Reserved Font Name "Marcellus". Licence: `fonts/OFL-Marcellus.txt`. It sets names.
- `AtkinsonHyperlegible-Regular.ttf` and `AtkinsonHyperlegible-Bold.ttf`, version 1.006: Copyright
  2020 Braille Institute of America, Inc. Licence: `fonts/OFL-AtkinsonHyperlegible.txt`. It sets
  everything else.

All were taken on 2026-11-16 from Google Fonts' repository (<https://github.com/google/fonts>,
`ofl/marcellus` and `ofl/atkinsonhyperlegible`), with the `OFL.txt` that stands beside each there.
The licence was read three ways that day and they agree: those two `OFL.txt` files; the repository's
`METADATA.pb` for each family (`license: "OFL"`); and the licence field inside each font file, which
says "This Font Software is licensed under the SIL Open Font License, Version 1.1". The Braille
Institute's own page for Atkinson Hyperlegible was not read; it once gave the face under a licence
of its own, and the files here are the ones Google Fonts gives under the OFL.

The OFL lets a font be bundled and embedded with any software, the AGPL's included, as long as the
copyright notice and the licence go with it and the font is not sold by itself (conditions 1 and
2). The fonts stay under the OFL; they do not become AGPL, and the rest of the repository does not
become OFL (condition 5 covers the fonts alone). They are embedded in the game binary with `#load`
and drawn by the game's own reader (`src/type.odin`); none is changed, so the reserved name is not
in question. A changed copy would have to drop the name "Marcellus".

SHA-256: `1cf0cd10b17d35e852729962cc1ffaffed94514895972458345e2df34abb2f81` Marcellus-Regular;
`7fb917c89019896d0b52ee84b7cbb3304c18cb90b19a62f5e32712bd23e97669` AtkinsonHyperlegible-Regular;
`5a3b0c8cc8ca545155150b4512a1fa248298df121c50d6557e651e61fbdab92f` AtkinsonHyperlegible-Bold.
