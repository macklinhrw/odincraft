#!/usr/bin/env python3
"""Builds assets/blocks.png, the atlas of block faces the game reads.

One row per material in the order of `Mat` in src/gen.odin, two tiles a row: the face seen
from above or below, then the face seen from the side, 16 pixels square. The tiles are drawn
by an artist: they come from the Pixel Perfection pack in assets/pixel-perfection (CC BY-SA 4.0,
see assets/LICENSE.md). This script only says which tile each material takes and recolours it
to the material's colour in MATERIALS, so a face keeps the artist's pixels and the game's hue.

Run from the repository root with a Python that has Pillow:  python3 tools/blocks.py
With a file name it also writes an enlarged sheet to look at. A tile in the PNG can be painted
over by hand, and then this script would overwrite it.
"""
import re, sys
from PIL import Image

T, SOURCE = 16, "assets/pixel-perfection/"
LIFT, RICH = 1.12, 1.18   # the game's colours, a little brighter and richer on the face than on the map

# material: (top tile, side tile, turns of a quarter, contrast kept). A tile's name is its file.
OAK, DARK, GREY, SPRUCE = "default_tree", "mcl_core_log_big_oak", "default_acacia_tree", "mcl_core_log_spruce"
TILES = {
    "Grass": ("mcl_lush_caves_moss_block", None, 0, 1), "Susuki": ("mcl_core_grass_block_top", None, 0, 1), "Dune": ("mcl_pale_oak_moss", None, 0, 1),
    "Dirt": ("mcl_core_coarse_dirt", None, 0, 1), "Loam": ("mcl_lush_caves_rooted_dirt", None, 0, 1), "Litter": ("mcl_core_dirt_podzol_top", None, 0, 1),
    "Silt": ("mcl_mud_packed_mud", "mcl_mud", 0, 1), "Red_Clay": ("hardened_clay", None, 0, 1), "Ash": ("mcl_colorblocks_concrete_powder_grey", None, 0, 1),
    "Stone": ("default_stone", None, 0, 1), "Sand": ("default_sand", None, 0, 1), "Snow": ("default_snow", None, 0, 1), "Gravel": ("default_gravel", None, 0, 1),
    "Wood": (OAK + "_top", OAK, 0, 1), "Shii_Bark": (DARK + "_top", DARK, 0, 1), "Grey_Bark": (GREY + "_top", GREY, 0, 0.8), "Pine_Bark": (SPRUCE + "_top", SPRUCE, 0, 1),
    "Leaves": ("mcl_core_leaves_big_oak", None, 0, 1), "Shii_Leaves": ("default_leaves", None, 0, 1), "Camellia_Leaves": ("default_jungleleaves", None, 0, 1),
    "Hisakaki_Leaves": ("mcl_core_leaves_birch", None, 0, 1), "Pine_Needles": ("mcl_core_leaves_spruce", None, 0, 1), "Scrub_Leaves": ("default_acacia_leaves", None, 0, 1),
    # the rocks: a top, and a side that shows how each is built
    "Mudstone": ("mcl_deepslate_top", "mcl_deepslate", 0, 1),                     # thin dark layers
    "Siltstone": ("mcl_core_andesite", "mcl_mud", 0, 1),                          # flags
    "Sandstone": ("mcl_core_sandstone_top", "mcl_mud_packed_mud", 0, 1),          # thick soft beds; the pack's own sandstone side is masonry
    "Grit": ("mcl_end_end_stone", None, 0, 0.8),                                  # pebbly, in big blocks
    "Limestone": ("mcl_amethyst_calcite_block", None, 0, 1),
    "Basalt": ("mcl_blackstone_basalt_top", "mcl_blackstone_basalt_side", 0, 1),  # columns
    "Scoria": ("mcl_nether_netherrack", None, 0, 1),                              # cinder, full of holes
    "Rhyolite": ("dripstone_block", "mcl_deepslate_tuff", 0, 1),                  # bands where it flowed
    "Tuff": ("mcl_blackstone_basalt_smooth", None, 0, 1),                         # ash set hard
}
BEDDED = ("Mudstone", "Siltstone", "Sandstone")   # their scree is slabs, the others' lumps


def srgb(c):
    return tuple(255 * (max(v, 0) ** (1 / 2.2)) for v in c)


def face(tile, colour, turns, keep, flowers=False):
    """An artist's tile in a material's colour: each channel scaled so the tile's average is the
    colour, with the contrast between its pixels kept, or part of it. Gaps in leaves are filled
    with the leaf's own shade."""
    im = Image.open(SOURCE + tile + ".png").convert("RGBA").crop((0, 0, T, T)).rotate(90 * turns)
    px = [im.getpixel((x, y)) for y in range(T) for x in range(T)]
    solid = [p for p in px if p[3] > 127]
    mean = [sum(p[k] for p in solid) / len(solid) for k in range(3)]
    grey = sum(colour) / 3
    target = [min(max((grey + (colour[k] - grey) * RICH) * LIFT, 0), 255) for k in range(3)]
    out = Image.new("RGBA", (T, T))
    for i, p in enumerate(px):
        c = [target[k] * (1 + keep * (p[k] / mean[k] - 1)) if p[3] > 127 else target[k] * 0.42 for k in range(3)]
        out.putpixel((i % T, i // T), tuple(max(0, min(255, round(v))) for v in c) + (255,))
    if flowers:   # camellia: two blossoms, petals round a gold heart
        for x, y in ((4, 3), (11, 10)):
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if abs(dx) + abs(dy) < 2:
                        out.putpixel(((x + dx) % T, (y + dy) % T), (196, 54, 66, 255) if dx + dy <= 0 else (158, 40, 54, 255))
            out.putpixel((x, y), (228, 190, 84, 255))
    return out


def main():
    source = open("src/gen.odin").read()
    body = re.sub(r"//[^\n]*", "", re.search(r"Mat :: enum u8 \{(.*?)\n\}", source, re.S).group(1))
    names = [n.strip() for n in body.split(",") if n.strip()]
    colours = {m.group(1): srgb(tuple(float(v) for v in m.group(2).split(","))) for m in re.finditer(r"\t\.(\w+)\s*= \{\{([\d., ]+)\}", source)}
    atlas = Image.new("RGBA", (2 * T, len(names) * T), (255, 0, 255, 255))
    for row, name in enumerate(names):
        if name == "Air":
            continue
        top, side, turns, keep = TILES.get(name) or ("mcl_deepslate_cobbled" if name[:-6] in BEDDED else "default_cobble", None, row % 4, 0.9)   # anything else is broken rock: the rock's scree
        if name not in TILES and not name.endswith("_Scree"):
            raise SystemExit("no tile is named for " + name)
        atlas.paste(face(top, colours[name], turns, keep, name == "Camellia_Leaves"), (0, row * T))
        atlas.paste(face(side or top, colours[name], 0 if side else turns, keep, name == "Camellia_Leaves"), (T, row * T))
    atlas.save("assets/blocks.png")
    if len(sys.argv) > 1:   # a sheet for looking at: each tile enlarged and repeated, so its seams show
        K, cols = 6, 6
        sheet = Image.new("RGB", (cols * (2 * T * K + 8), ((len(names) + cols // 2 - 1) // (cols // 2)) * (2 * T * K + 8)), (40, 40, 40))
        for row in range(len(names)):
            for col in range(2):
                tile = atlas.crop((col * T, row * T, col * T + T, row * T + T)).convert("RGB")
                big = Image.new("RGB", (2 * T, 2 * T))
                for i in range(4):
                    big.paste(tile, (i % 2 * T, i // 2 * T))
                sheet.paste(big.resize((2 * T * K, 2 * T * K), Image.NEAREST), (((row % (cols // 2)) * 2 + col) * (2 * T * K + 8) + 4, (row // (cols // 2)) * (2 * T * K + 8) + 4))
        sheet.save(sys.argv[1], quality=92)
    print("built", len(names), "materials")


main()
