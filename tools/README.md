# Tools

Two Python scripts that sit beside the game. Neither is needed to build or play it.

```sh
python3 -m venv .venv && .venv/bin/pip install -r tools/requirements.txt   # Python 3.12
```

`blocks.py` needs only Pillow; the other packages are for `plates_compare.py`. Run both from the repository root.

## `blocks.py`: the texture atlases

```sh
.venv/bin/python tools/blocks.py            # rewrites assets/blocks.png and assets/plants.png
.venv/bin/python tools/blocks.py out/sheet.jpg   # also writes an enlarged sheet to look at (mkdir -p out)
```

It takes the Pixel Perfection tiles in `assets/pixel-perfection/` (CC BY-SA 4.0, see [`assets/LICENSE.md`](../assets/LICENSE.md)), recolours each to a material's colour and lays them out in the order of `Mat` in `src/gen.odin` and `Plant_Kind` in `src/plants.odin`. The game embeds the atlases at compile time, so rebuild after running it. Run on an unchanged checkout, it reproduces both atlases byte for byte.

## `plates_compare.py`: the plate history against the real Earth

```sh
mkdir -p out && ./build.sh && build/odincraft --plates=out/plates   # the game's plate history, as raw grids
.venv/bin/python tools/plates_compare.py out/plates ~/plate-data out/compare
```

One seed's history is chaotic, so a figure is judged over many seeds: run the two lines above for each seed into its own folders, then

```sh
.venv/bin/python tools/plates_compare.py --summary out/compare-* [--before out/before-*]
```

prints the median and range over the seeds beside the real Earth, as a Markdown table, with the median of another set of runs as "ours before".

The second argument of the first form is a folder outside the repository where the reference data is downloaded on the first run (about 270 MB; it needs a network connection): the plate model and ocean-floor age grids of Müller et al. 2019, through `plate-model-manager`, and the PALEOMAP PaleoDEMs of Scotese & Wright 2018, from EarthByte. All are CC BY 4.0. The output folder gets `measures.csv`, a sheet per frame comparing the two Earths and `measures.png`, the figures through time. Speeds are measured in a frame with no net rotation of the whole surface, ours by construction and the real Earth's by taking out the net rotation of Müller's mantle frame. It draws its labels with macOS's Arial, so, like the game, it runs only on macOS as written. See [`docs/interesting-world/notes/real-plates.md`](../docs/interesting-world/notes/real-plates.md) for what the measures mean.
