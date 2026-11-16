#!/usr/bin/env python3
"""Builds assets/blocks.png, the atlas of block faces the game reads.

One row per material in the order of `Mat` in src/gen.odin, two tiles a row: the face seen
from above or below, then the face seen from the side, 16 pixels square. The tiles are drawn
by an artist: they come from the Pixel Perfection pack in assets/pixel-perfection (CC BY-SA 4.0,
see assets/LICENSE.md). This script only says which tile each material takes and recolours it
to the material's colour in MATERIALS, so a face keeps the artist's pixels and the game's hue.

It also builds assets/plants.png, the ground plants' pictures (src/plants.odin): a row for each
plant in the order of `Plant_Kind`, its lower picture then its upper one (clear for a plant one
picture high), from the same pack's plant pictures, recoloured or kept as the artist drew them.

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
    "Stone": ("default_stone", None, 0, 1), "Sand": ("default_sand", None, 0, 1), "Black_Sand": ("default_sand", None, 0, 1), "Snow": ("default_snow", None, 0, 1), "Gravel": ("default_gravel", None, 0, 1),
    "Shingle": ("default_gravel", None, 1, 0.8), "Black_Shingle": ("default_gravel", None, 1, 0.8),
    # bark on every face, as limbs run aslant and trunks lie fallen: a log's cut end would show on each step
    "Wood": (OAK, None, 0, 1), "Shii_Bark": (DARK, None, 0, 1), "Grey_Bark": (GREY, None, 0, 0.8), "Pine_Bark": (SPRUCE, None, 0, 1),
    # the faces the mesher gives a trunk by the way it runs (grain, src/mesh.odin): its rings where it is cut across, and its bark turned along a lying one
    "Wood_End": (OAK + "_top", None, 0, 1), "Shii_End": (DARK + "_top", None, 0, 1), "Grey_End": (GREY + "_top", None, 0, 1), "Pine_End": (SPRUCE + "_top", None, 0, 1),
    "Wood_Across": (OAK, None, 1, 1), "Shii_Across": (DARK, None, 1, 1), "Grey_Across": (GREY, None, 1, 0.8), "Pine_Across": (SPRUCE, None, 1, 1),
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
    "Reef": ("dripstone_block", "mcl_end_end_stone", 1, 1),                       # pitted where the rain dissolves it, lumpy with coral heads in a face
    "Red_Sandstone": ("mcl_core_sandstone_top", "mcl_mud_packed_mud", 0, 1),      # as the grey, in red
    "Chalk": ("mcl_amethyst_calcite_block", None, 0, 0.7),                        # soft and white
    "Coal": ("mcl_deepslate_top", "mcl_deepslate", 0, 0.8),                      # a black seam in thin layers
    "Breccia": ("mcl_nether_netherrack", "mcl_end_end_stone", 0, 0.9),           # broken lava set in ash, lumpy
    "Dolerite": ("mcl_blackstone_basalt_top", "mcl_blackstone_basalt_side", 1, 0.8),   # rough columns, turned across the wall it stands in
    "Granite": ("mcl_core_andesite", None, 0, 1.2),                               # coarse crystals
    "Slate": ("mcl_deepslate_top", "mcl_deepslate", 1, 1),                        # its sheets stand on edge
    "Schist": ("mcl_deepslate_tuff", "mcl_deepslate_tuff", 1, 1),                 # wavy glittering bands, on edge
    "Gneiss": ("mcl_deepslate_tuff", None, 0, 1.2),                               # banded
    "Quartzite": ("default_stone", None, 0, 0.8),                                 # hard, sharp, pale
    "Hornfels": ("default_stone", None, 0, 1),                                    # dark and splintery
    "Marble": ("mcl_amethyst_calcite_block", None, 1, 0.5),                       # white, crystalline and smooth
}
BEDDED = ("Mudstone", "Siltstone", "Sandstone", "Red_Sandstone", "Coal", "Slate", "Schist")   # their scree is slabs, the others' lumps

# plant: (lower picture, upper picture or None, colour (linear, as in MATERIALS) or None to keep the
# artist's). The grey pictures are drawn to be tinted; those already coloured keep their colours.
FERN, GRASS = "mcl_flowers_fern", "mcl_flowers_tallgrass"
PLANTS = {
    "Reed": ("mcl_core_papyrus", "mcl_flowers_double_plant_grass_top", (0.085, 0.125, 0.040)),
    "Sedge": (GRASS, None, (0.065, 0.120, 0.035)),
    "Susuki": ("mcl_flowers_double_plant_grass_bottom", "mcl_flowers_double_plant_grass_top", (0.105, 0.165, 0.040)),
    "Bamboo": ("mcl_bamboo_leaf_small", None, (0.075, 0.150, 0.030)),
    "Bracken": ("mcl_flowers_double_plant_fern_bottom", "mcl_flowers_double_plant_fern_top", (0.110, 0.170, 0.035)),
    "Fern": (FERN, None, (0.045, 0.105, 0.025)),
    "Shrub": ("mcl_farming_sweet_berry_bush_1", None, None),
    "Ardisia": ("mcl_farming_sweet_berry_bush_2", None, None),
    "Forest_Grass": (GRASS, None, (0.040, 0.090, 0.025)),
    "Grass": (GRASS, None, (0.090, 0.150, 0.040)),
    "Knotweed": ("mcl_farming_sweet_berry_bush_0", None, (0.085, 0.150, 0.040)),
    "Dead_Stems": ("default_dry_shrub", None, None),
    "Dune_Sedge": (GRASS, None, (0.120, 0.150, 0.055)),
    "Vitex": ("mcl_farming_sweet_berry_bush_0", None, (0.075, 0.110, 0.070)),
    "Flower": ("flowers_dandelion_yellow", None, None),
}


def srgb(c):
    return tuple(255 * (max(v, 0) ** (1 / 2.2)) for v in c)


def face(tile, colour, turns, keep, flowers=False):
    """An artist's tile in a material's colour: each channel scaled so the tile's average is the
    colour, with the contrast between its pixels kept, or part of it. Gaps in leaves are clear, and
    hold the leaf's own shade for where the game draws them whole."""
    im = Image.open(SOURCE + tile + ".png").convert("RGBA").crop((0, 0, T, T)).rotate(90 * turns)
    px = [im.getpixel((x, y)) for y in range(T) for x in range(T)]
    solid = [p for p in px if p[3] > 127]
    mean = [sum(p[k] for p in solid) / len(solid) for k in range(3)]
    grey = sum(colour) / 3
    target = [min(max((grey + (colour[k] - grey) * RICH) * LIFT, 0), 255) for k in range(3)]
    out = Image.new("RGBA", (T, T))
    for i, p in enumerate(px):
        c = [target[k] * (1 + keep * (p[k] / mean[k] - 1)) if p[3] > 127 else target[k] * 0.42 for k in range(3)]
        out.putpixel((i % T, i // T), tuple(max(0, min(255, round(v))) for v in c) + (255 if p[3] > 127 else 0,))   # a leaf's gaps are clear near by; far off the game draws them in this shade
    if flowers:   # camellia: two blossoms, petals round a gold heart
        for x, y in ((4, 3), (11, 10)):
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if abs(dx) + abs(dy) < 2:
                        out.putpixel(((x + dx) % T, (y + dy) % T), (196, 54, 66, 255) if dx + dy <= 0 else (158, 40, 54, 255))
            out.putpixel((x, y), (228, 190, 84, 255))
    return out


def picture(name, colour):
    """An artist's plant picture, recoloured to a colour as a face is, or kept. The clear pixels take
    the plant's mean colour, so the smaller copies the game makes for the distance stay its colour
    rather than darkening toward the black behind it."""
    if name is None:
        return Image.new("RGBA", (T, T), (0, 0, 0, 0))
    im = Image.open(SOURCE + "plants/" + name + ".png").convert("RGBA").crop((0, 0, T, T))
    px = [im.getpixel((x, y)) for y in range(T) for x in range(T)]
    solid = [p for p in px if p[3] > 127]
    mean = [sum(p[k] for p in solid) / len(solid) for k in range(3)]
    if colour:
        grey = sum(colour) / 3
        target = [min(max((grey + (colour[k] - grey) * RICH) * LIFT, 0), 255) for k in range(3)]
        px = [tuple(target[k] * p[k] / mean[k] for k in range(3)) + (p[3],) for p in px]
        mean = target
    out = Image.new("RGBA", (T, T))
    for i, p in enumerate(px):
        c = p[:3] if p[3] > 127 else mean
        out.putpixel((i % T, i // T), tuple(max(0, min(255, round(v))) for v in c) + (255 if p[3] > 127 else 0,))
    return out


def form(name, row, names):
    """A rock's other forms (src/gen.odin, Mat): its scree is broken rock, slabs for a bedded rock
    and lumps for the others, each turned a quarter more than the one before; the rock broken in
    place under the soil is its own face, cracked and faded; its gravel is rounded pebbles."""
    rock, kind = name.rsplit("_", 1)
    if kind == "Scree":
        return ("mcl_deepslate_cobbled" if rock in BEDDED else "default_cobble", None, (row - names.index("Mudstone_Scree")) % 4, 0.9)
    if kind == "Broken":
        top, side, turns, keep = TILES[rock]
        return ("mcl_deepslate_cobbled" if rock in BEDDED else "default_cobble", side or top, turns, 0.6 * keep)
    return ("default_gravel", None, (row - names.index("Mudstone_Gravel")) % 4, 0.9)


def main():
    source = open("src/gen.odin").read()
    body = re.sub(r"//[^\n]*", "", re.search(r"Mat :: enum u\d+ \{(.*?)\n\}", source, re.S).group(1))
    names = [n.strip() for n in body.split(",") if n.strip()]
    colours = {m.group(1): srgb(tuple(float(v) for v in m.group(2).split(","))) for m in re.finditer(r"\t\.(\w+)\s*= \{\{([\d., ]+)\}", source)}
    atlas = Image.new("RGBA", (2 * T, len(names) * T), (255, 0, 255, 255))
    for row, name in enumerate(names):
        if name == "Air":
            continue
        top, side, turns, keep = TILES.get(name) or form(name, row, names)
        if name not in TILES and not name.endswith(("_Scree", "_Broken", "_Gravel")):
            raise SystemExit("no tile is named for " + name)
        atlas.paste(face(top, colours[name], turns, keep, name == "Camellia_Leaves"), (0, row * T))
        atlas.paste(face(side or top, colours[name], 0 if side else turns, keep, name == "Camellia_Leaves"), (T, row * T))
    atlas.save("assets/blocks.png")
    plants = re.sub(r"//[^\n]*", "", re.search(r"Plant_Kind :: enum u8 \{(.*?)\}", open("src/plants.odin").read(), re.S).group(1))
    plants = [n.strip() for n in plants.split(",") if n.strip()]
    sheet = Image.new("RGBA", (2 * T, len(plants) * T))
    for row, name in enumerate(plants):
        if name not in PLANTS:
            raise SystemExit("no picture is named for the plant " + name)
        lower, upper, colour = PLANTS[name]
        sheet.paste(picture(lower, colour and srgb(colour)), (0, row * T))
        sheet.paste(picture(upper, colour and srgb(colour)), (T, row * T))
    sheet.save("assets/plants.png")
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
