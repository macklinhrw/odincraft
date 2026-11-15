# Third-party material

Odincraft's source code is licensed under the GNU Affero General Public License v3.0 or later (`AGPL-3.0-or-later`; see `LICENSE`). The material below is not the project's own and keeps its own licence.

## Block and plant textures

`assets/pixel-perfection/` and `assets/pixel-perfection/plants/` hold 16×16 tiles taken from [Mineclonia](https://codeberg.org/mineclonia/mineclonia). Per Mineclonia's `LEGAL.md`, they come from:

- **Pixel Perfection** by XSSheep: <https://www.planetminecraft.com/texture_pack/131pixel-perfection/>
- **Pixel Perfection Legacy** by Nova Wostra: <https://www.curseforge.com/minecraft/texture-packs/pixel-perfection-legacy>

Some were changed or redrawn by Mineclonia's contributors. They are licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

`mcl_mud.png` and `mcl_mud_packed_mud.png` are by TheRandomLegoBrick, [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

`assets/blocks.png` and `assets/plants.png` are adaptations of those tiles by Macklin Reeve-Wilson. `tools/blocks.py` builds them by recolouring each tile to a material's colour and arranging them into atlases. They are licensed under CC BY-SA 4.0. The atlases are embedded in the game binary. `docs/interesting-world/real/blocks-sheet.jpg` shows the atlas and is also CC BY-SA 4.0.

Per-file details are in [`assets/LICENSE.md`](assets/LICENSE.md).

## Data behind research figures

No third-party data is stored in this repository. Some figures in `docs/interesting-world/real/` were computed from:

- **Elevation tiles of the Geospatial Information Authority of Japan (国土地理院, GSI)**, DEM10B `dem_png`: <https://maps.gsi.go.jp/development/ichiran.html>. Used under the [GSI terms](https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html) (Public Data License 1.0). Source: 国土地理院. The tiles were resampled to 16 m, projected, and rebuilt as game terrain by this project, and the figures are processed from them. Files: `maps-real.jpg`, `crops-1.jpg`, `crops-2.jpg`, `charts.jpg`, `sections.jpg`, `game-from-sea.jpg`, `game-from-air.jpg`, `game-close.jpg`.
- **Müller, R.D. et al. 2019**, "A global plate model including lithospheric deformation along major rifts and orogens since the Triassic", *Tectonics* 38, 1884–1907, doi:10.1029/2018TC005462, with its ocean-floor age grids (EarthByte). [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- **Scotese, C.R. & Wright, N. 2018**, PALEOMAP Paleodigital Elevation Models for the Phanerozoic (EarthByte). CC BY 4.0.

Files: `plates-today.jpg`, `plates-measures.jpg`. `tools/plates_compare.py` downloads the data on first run, outside the repository.

All other images in `docs/` are renders and charts made by this project.
