# What makes a DF embark site and a RimWorld map distinct: inventory, counts, placement rules

Scope: complements `reference/zigcraft/dwarf-fortress-worldgen-research.md` (DF pipeline, history, design philosophy), which is not repeated here. Versions: Dwarf Fortress **53.17** raws (official Linux release, read directly); RimWorld **1.6 + Odyssey** Defs (third-party mirror of the shipped XML) and **1.5** decompiled map-generation code. Counts drift between versions; each is tied to its version below.

Source key (cited inline by short name):
- **DF raws**: `data/vanilla/*/objects/*.txt` in https://www.bay12games.com/dwarves/df_53_17_linux.tar.bz2 (primary; counts below are my own greps of these files).
- **DFwiki**: dwarffortresswiki.org, DF2014 namespace (secondary, community; often written for 0.40–0.47, may lag 50.x).
- **DF Talk**: https://www.bay12games.com/media/df_talk_combined_transcript.html (primary, Tarn "Toady One" Adams).
- **RW Defs**: https://github.com/GAarsin/Rimworld_Data (third-party mirror of the shipped 1.6 `Data/*/Defs`; data is first-party, host is not).
- **RW 1.5 code**: https://github.com/kasirii/RimWorld1.5.4409Decompiled (decompiled C#, third-party; 1.5, not 1.6).
- **RWwiki**: rimworldwiki.com (secondary).

## Key takeaways

1. **DF's local variety is catalogs filtered by tile fields, not landforms.** 53.17 ships 225 plants (72 trees), 25 layer stones, 21 soils, 58 minerals and 127 gems, each declaring where it may occur; biome, alignment, savagery, depth and the layer stack select them (DF raws).
2. **DF trees differ in name, not shape.** 51 of 72 species share one branch signature; height (1–8 tiles) is the main shape variable (DF raws).
3. **DF's surface landforms are thin.** Cliffs are eroded into ramps by default and volcanoes are one-tile pillars. Tarn says canyons, mesas, cliffs, alluvium and better waterfalls await a "map rewrite" (DFwiki Cliff; DF Talk).
4. **DF sites differ most underground:** soil depth, a sedimentary-or-extrusive / metamorphic / intrusive stack with host-specific ore, up to 3 aquifers, 3 cavern layers with their own life and water, then magma.
5. **RimWorld's base map is a few noise fields and thresholds:** elevation and fertility Perlin, rock above 0.7, gravel at 0.55–0.61, soil or rich soil by fertility, 1–3 patch-noise layers per biome, 2–3 stones per tile, weighted ore lumps (RW 1.5 code; RW Defs).
6. **RimWorld biomes are numbers more than shapes:** 0–4 tree species and 5–17 wild plants each, plus densities, disease and season (RW Defs).
7. **Odyssey (July 2025) is Ludeon's explicit fix for samey maps:** "over 85 dynamic map features" and "over 45 landmarks" so "every map is truly unique" ([Ludeon blog](https://ludeon.com/blog/2025/06/odyssey-preview-1-map-features-landmarks-and-biomes)).
8. **Odyssey's rule is: context gates a designed landform, then dice stack modifiers.** Each mutator has a biome whitelist, minimum hilliness, coast and river constraints; each landmark has a commonality and a table of follow-on chances (RW Defs). This is "simulate the why, design the what", shipped.
9. **Tynan Sylvester:** "anything in the Game Model that doesn't copy into the Player Model is worthless" ([The Simulation Dream](https://www.gamedeveloper.com/design/the-simulation-dream)).
10. **On foot (inference):** context-selected landform templates, mixed-biome edges, groves and habitats, strata in cut faces, caves from rock faces and a few distinct tree *shapes* transfer. Ore, fish, disease and species counts mostly do not.

---

## Part 1: Dwarf Fortress (53.17 unless noted)

### 1.1 Biomes

**Count.** 51 biome IDs: 27 land (mountain, glacier, tundra, 9 wetlands, 6 forests, 6 grassland/savanna/shrubland, 3 deserts), 21 water (3 oceans; lakes, murky pools and rivers, each temperate or tropical × fresh, brackish or salt) and 3 subterranean (water, chasm, lava) ([DFwiki Biome token](https://dwarffortresswiki.org/index.php/DF2014:Biome_token)). About 28 group tokens (`ANY_TEMPERATE_BROADLEAF`, `NOT_FREEZING`) let content target several at once.

**Mapping rule** ([DFwiki Biome](https://dwarffortresswiki.org/index.php/DF2014:Biome), secondary, from a 40d-era thread): elevation 0–99 is ocean, 300–400 mountain; between, a rainfall × drainage table picks the base biome (thresholds are in a wiki image I did not verify). Salinity picks fresh, brackish or salt. Temperature ≤ −5 gives tundra (drainage < 75) or glacier; −4 to 9 turns conifer forest into taiga; about 85+ gives tropical variants; tropical salt swamp with drainage ≤ 9 becomes mangrove. Noise applied after classification makes the local biome edges irregular.

**Overlays.** Savagery and good/evil ("surroundings") apply to any biome: savage land adds giant and animal-person variants; evil land has dead vegetation, undead and evil weather ([DFwiki Embark](https://dwarffortresswiki.org/index.php/DF2014:Embark)). Only 4 plants are GOOD, 4 EVIL, 1 SAVAGE (DF raws). The embark screen reports per biome: climate, tree and other vegetation density, surroundings, soil depth (four grades), clay, shallow and deep metal, flux, aquifer. A 2–16 × 2–16 embark (48 × 48 tiles each) usually straddles 3–4 biomes.

**For the player:** the biome picks the catalog and the climate; on the local map it is mostly a tint and a resource stock, not a different shape of land.

### 1.2 Plants

**Counts (DF raws):** 225 `[PLANT]` entries: 72 trees, 41 `[GRASS]` (including sedges, reeds, cattail, heather, 3 bamboos, 4 cavern floor plants), 34 field crops, 57 garden plants, 21 wild shrubs (plump helmet, rope reed, strawberry…). 17 are cavern-only (`UNDERGROUND_DEPTH`), 8 of them trees.

**Placement rule:** `[BIOME:x]` tokens (360 uses; `ANY_TROPICAL` 54, `ANY_TEMPERATE` 53), `[WET]`/`[DRY]` meaning near surface water or not (65 / 217), season tokens, `[FREQUENCY:n]` (97 × 50, 12 × 100) with `[CLUSTERSIZE:n]`, `[UNDERGROUND_DEPTH:a:b]`, and `[GOOD]/[EVIL]/[SAVAGE]`. Example: bilberry `[DRY][BIOME:ANY_TEMPERATE][BIOME:TUNDRA][BIOME:TAIGA]`, `FREQUENCY:50 CLUSTERSIZE:5`. Trees carry no `FREQUENCY` in 53.17, so an engine default applies, which I did not verify.

**Tree tokens (since 0.40):** `MAX_TRUNK_HEIGHT`, `MAX_TRUNK_DIAMETER` (1–3), `TRUNK_PERIOD` (growth rate), `TRUNK_BRANCHING`, heavy-branch and branch density and radius, `ROOT_RADIUS`, nine `TWIGS_*` flags, `TREE_HAS_MUSHROOM_CAP`/`CAP_RADIUS`, and seasonal `GROWTH` blocks (leaves, flowers, fruit) on named host tiles. How species actually differ (DF raws):

| Shape signature | Species | Examples |
|---|---|---|
| Broadleaf: heavy branches 25, branches 50, branching 2, 1-tile trunk | 51 | oak, maple, willow, apple, mango |
| Conifer or columnar: no heavy branches, branching 0 | 6 | pine, cedar, birch, alder |
| Bare pole: no branches | 4 | palm, banana, abaca, date palm |
| Saguaro: heavy branches only | 1 | saguaro |
| Mushroom cap | 4 | tower-cap (cap radius 3, trunk 3 wide), goblin-cap (height 1, trunk 3 wide), black-cap, nether-cap |
| Thick trunk | 3 | kapok (2), ginkgo (2), highwood (3) |

Height is the main variable: 28 species reach 8, 14 reach 5, 12 reach 3, 10 reach 2 (citrus), and bayberry reaches 1. Comments in the raws note the real heights the tiles cannot reach ("KAPOK … or much much taller 70m"). The wiki adds that all species get crown shyness in the graphical version, and that deciduous leaves colour and drop, patterning the ground ([DFwiki Tree](https://dwarffortresswiki.org/index.php/DF2014:Tree)).

**For the player:** trees are wood, fruit and a climbable canopy. The many species give products and names; silhouettes come in about six families.

### 1.3 Geology

**Counts (DF raws):** 25 layer stones: sedimentary 11 (sandstone, siltstone, mudstone, shale, claystone, rock salt, limestone, conglomerate, dolomite, chert, chalk), intrusive 3 (granite, diorite, gabbro), extrusive 5 (rhyolite, basalt, andesite, dacite, obsidian), metamorphic 6 (quartzite, slate, phyllite, schist, gneiss, marble). Also 21 soils (clays, loams, silts, peat, 5 coloured sands, ocean oozes; 16 carry `AQUIFER`, as do sandstone and conglomerate), 58 minerals and ores, 127 gems.

**Stacking** ([DFwiki Stone layers](https://dwarffortresswiki.org/index.php/DF2014:Stone_layers)): soil on top, absent to 10+ z thick and deeper at slope feet. Sedimentary is the first stone layer 80% of the time and never coexists with extrusive, which replaces it near volcanoes. Metamorphic never lies above sedimentary. Intrusive is never on top and is always the deepest, often thickest, layer. Layers are thick and sharp ("fifteen layers may be mostly quartzite, but the next thirty may be dominated by gabbro"); one biome has one stack.

**Ore rule:** `[ENVIRONMENT:<class>:<shape>:<freq>]` (class: sedimentary, intrusive, extrusive, igneous-all, metamorphic, all-stone, alluvial) or `[ENVIRONMENT_SPEC:<stone>:…]`; shape is vein, cluster, small cluster or single (DF raws). Hematite: sedimentary and extrusive veins, metamorphic small clusters. Galena: veins in extrusive, metamorphic, granite, limestone, yielding lead and 50% silver. Native gold: igneous veins plus alluvial small clusters. Kimberlite: gabbro veins only, with 5 gems nested in it. 155 of 205 environment lines are small clusters, so most deposits are pockets.

**Aquifers:** light or heavy, up to 3 per biome, in aquifer-capable soil or stone ([DFwiki Aquifer](https://dwarffortresswiki.org/index.php/DF2014:Aquifer)).

**Caverns:** 3 layers by default, the first usually 10–11 z down. Each is part-flooded, from pools to a sea (`CAVERN_LAYER_WATER_MIN/MAX`). Muddy floors grow cavern trees and shrubs (17 `SUBTERRANEAN_WATER` plants); a dry layer grows only floor fungus. Creatures are assigned per layer. Layers join by deep pits, passages and magma tubes ([DFwiki Cavern](https://dwarffortresswiki.org/index.php/DF2014:Cavern)).

**For the player:** digging down is a progression: soil, sediment with iron and flux, metamorphic, intrusive with the best gems, caverns, magma.

### 1.4 Local features

| Feature | Rule (source) | For the player |
|---|---|---|
| River / brook | Traced in world gen; small rivers become brooks walkable on their surface, with a fan-shaped headspring ([DFwiki Brook](https://dwarffortresswiki.org/index.php/DF2014:Brook)) | Unlimited water and power |
| Waterfall | Emerges where a river crosses a step ([DFwiki Waterfall](https://dwarffortresswiki.org/index.php/DF2014:Waterfall)) | Mist, happy thoughts |
| Murky pool | "Very common" outside deserts; its own tiny biome (6 types); evaporates and refills ([DFwiki Murky pool](https://dwarffortresswiki.org/index.php/DF2014:Murky_pool)) | Early, stagnant water |
| Volcano | "Only a few" per world, one embark tile, usually mountainous extrusive; a hollow obsidian magma pillar ([DFwiki Volcano](https://dwarffortresswiki.org/index.php/DF2014:Volcano)) | Surface magma |
| Cliffs | Default world gen "periodically erode[s] sharp cliffs" into ramps, except river cuts through mountains ([DFwiki Cliff](https://dwarffortresswiki.org/index.php/DF2014:Cliff)) | Mostly absent |
| Boulders | Random scatter of the substrate stone ([DFwiki Boulder](https://dwarffortresswiki.org/index.php/DF2014:Boulder)) | Shows the rock beneath |
| Sand, clay | Sand soils; sand is certain only in sand desert; clay shown at embark (DFwiki Embark) | Glass, pottery |

**Site finder** ([DFwiki Site finder](https://dwarffortresswiki.org/index.php/DF2014:Site_finder)) filters on savagery, evil, elevation, temperature, rain, drainage, flux, aquifer, river, shallow and deep metal, soil, clay: resources and hazards, not scenery.

### 1.5 Known weaknesses

- Tarn Adams on cliffs: removed because "they were everywhere and you didn't have a way to climb", so cave entrances "all look like these little pits"; "canyons and mesas and other interesting constructions aboveground" are future work (DF Talk).
- On soil and stone: "especially… the alluvial stuff, like all the river stones and how the rivers spill out sediment", to come after "canyons and cliffs" (DF Talk).
- On 3D: "We lost certain cool stuff… the map rewrite is our way of recreating that… better underground rivers and waterfalls" (DF Talk).
- Strata: "Three-dimensional variance is planned for the future" (DFwiki Stone layers).
- I found no citable community critique of samey embarks; that claim is **unverified**.

---

## Part 2: RimWorld (1.6 + Odyssey Defs; 1.5 code)

### 2.1 World tile → map

Land forms first, then rivers, then a shallow ancient-society simulation lays roads, then settlements ([RWwiki World generation](https://rimworldwiki.com/wiki/World_generation)). Each tile carries a biome, elevation, latitude, temperature, rainfall, one of 5 hilliness classes (flat to impassable), a river size (creek to huge), roads (5 types), coast direction, and 2–3 stone types: `Rand.RangeInclusive(2,3)` distinct rocks seeded by tile ID (RW 1.5 code `World.NaturalRockTypesIn`). Core has 5 stones: sandstone, granite, limestone, slate, marble ([RW Defs Various_Stone.xml](https://github.com/GAarsin/Rimworld_Data/blob/master/Core/Defs/ThingDefs_Misc/Various_Stone.xml)).

**Biome rule:** every biome's worker returns a score from tile temperature, rainfall and swampiness, and the highest score wins. The wiki quotes the code in page comments, for example temperate forest `15 + (T−7) + (rain−600)/180` and temperate swamp the same `+ swampiness×3`; tundra `−T`; boreal forest a constant 15 ([RWwiki Temperate forest](https://rimworldwiki.com/wiki/Temperate_forest) and sibling pages; secondary).

### 2.2 Biomes

**Count:** 12 core biomes, plus 5 Odyssey biomes (glowforest, scarlands, grassland, glacial plain, lava field) and an orbit "biome" ([RWwiki World generation](https://rimworldwiki.com/wiki/World_generation); [Odyssey (DLC)](https://rimworldwiki.com/wiki/Odyssey_(DLC))).

Per biome (RW Defs `BiomeDefs/*.xml`; plant and animal counts are `wildPlants` and `wildAnimals` entries including DLC; densities and disease from the wiki infoboxes):

| Biome | Plant density | Animal density | Disease MTB (days) | Wild plants | Trees | Animals | Base terrain by fertility | Patch noise layers |
|---|---|---|---|---|---|---|---|---|
| Temperate forest | 0.65 | 3.7 | 50 | 15 | oak, poplar | 36 | soil < 0.87 < rich soil | rich soil / mud / shallow water (ponds) |
| Temperate swamp | 0.8 | 4.3 | 40 | 12 | willow, cypress, maple | 33 | same | marshy soil; rich soil / mud / water |
| Tropical rainforest | 0.99 | 6.5 | 35 | 17 | cecropia, palm, bamboo, teak | 19 | same | marshy soil; marsh |
| Tropical swamp | 0.99 | 6.5 | 30 | 15 | willow, cypress, maple | 23 | same | 3 layers |
| Boreal forest | 0.4 | 2.8 | 60 | 14 | pine, birch, poplar, gray pine | 32 | same | lichen-covered / marsh / water |
| Tundra | 0.19 | 1.1 | 80 | 14 | pine, birch, gray pine | 19 | same | lichen-covered / marsh |
| Cold bog | 0.6 | 3.3 | 45 | 12 | willow, maple | 31 | same | 3 layers |
| Arid shrubland | 0.24 | 1.8 | 65 | 11 | drago | 25 | sand < 0.45 < soil < 0.90 < rich soil | none |
| Desert | 0.05 | 0.4 | 90 | 10 | drago | 13 | sand < 0.80 < soil | soft sand |
| Extreme desert | 0.002 | 0.1 | 90 | 5 | none | 6 | sand | soft sand |
| Ice sheet / sea ice | 0 | 0.2 / 0.1 | 90 | 0 | none | 7 / 5 | ice | shallow water |
| Grassland (Odyssey) | 1.0 | 3.7 | 50 | 11 | oak, poplar | 25 | grassland soil < 0.8 < rich soil | none |
| Glowforest (Odyssey) | 0.75 | 4.8 | 50 | 9 | none (fungi) | 18 | glowforest soil < 0.87 < rich soil | 3 layers |

Wild plants are weighted; temperate forest: grass 5, tall grass 2, brambles 1, bush 0.6, oak 0.5, poplar 0.5, berry 0.05, healroot 0.05 (RW Defs).

**For the player:** a biome is a difficulty and economy setting; visually, a ground palette and 0–4 tree types.

### 2.3 Map generation steps (1.6 `CommonMapGenerator.xml` and `BasePlayerMapGenerator.xml`, RW Defs)

| Order | Step | Rule (1.5 code unless noted) | For the player |
|---|---|---|---|
| 10 | ElevationFertility | Elevation Perlin (0.021, 6 octaves) × hilliness factor; mountainous tiles add a mountain along one non-coast side. Fertility: separate Perlin | Where rock, open ground, good soil fall |
| 20, 220, 500, 700 | Mutator steps (1.6) | Landmarks reshape fields and terrain and place structures. Mountain (−200), caves (−100), river (50, after lakes) and coast (100) are now mutators (Core `TileMutators.xml`) | Landforms, water, caves |
| 200 | RocksFromGrid | Rock above 0.7; each cell takes the stone whose own noise is highest (blotches); thin roof > 0.728, thick > 0.798; then ore lumps | Mountains, overhead-mountain bases |
| 210 | Terrain | 0.55–0.61 gravel; ≥ 0.61 rough stone; else patch noise, else terrain-by-fertility; rivers painted across the map | Ground mosaic; gravel apron round rock |
| 750 | Ruins, shrines | Ruins 0–3 / 10k cells; ancient shrines 0.12–0.25 / 10k | Loot and threats |
| 950 | Steam geysers | 0.7–1 / 10k cells, ≥ 25 apart | Power sites |
| 970 | Rock chunks | Below 0.55, p = 0.006 per cell × Perlin factor | Stone; shows rock types |
| 900–1200 | Plants, cave hives, snow, animals | Biome density and weights × fertility | Forage, wood, wildlife |

**Ore lumps** (RW Defs `Buildings_Natural.xml`, commonality and lump size): steel 1 (30–40), components 1 (3–6), uranium 0.12 (6–12), silver 0.10 (4–12), gold 0.07, jade 0.065, plasteel 0.05 (each 2–8). They are placed by weight with no host rock and no depth.

**Caves** (1.6 RWwiki Landmarks, "Caves"): 50% of mountainous tiles and 25% of large-hill tiles. Caves sealed from the outside stay hidden until opened. They hold dormant insect hives and light-averse cave plants ([RWwiki World generation](https://rimworldwiki.com/wiki/World_generation)).

### 2.4 Odyssey landmarks and map features ("mutators")

Ludeon's stated purpose: "For the gravship to be fun, you need new and exciting places to travel to!" The post promises "over 85 dynamic map features… Multiple features can be combined together on one map", and landmarks that are "marked with custom art on the world map" and "frequently combine with multiple map features" ([Ludeon blog, Tia Young, 19 Jun 2025](https://ludeon.com/blog/2025/06/odyssey-preview-1-map-features-landmarks-and-biomes)). Odyssey shipped on 11 July 2025 with update 1.6.

**Implementation** (RW Defs `Odyssey/Defs/TileMutators/`): 48 natural, 22 modifier and 1 special `TileMutatorDef`s, plus man-made ones in other files, and 41 `LandmarkDef`s. Each landmark has:
- a `commonality` (valley 1, ruins 1; archipelago, coastal island and peninsula 0.75; lake 0.5; cliffs, cavern, chasm, hollow, basin, fjord, wetland 0.5; plateau 0.4; oasis and hot springs 0.25; dunes, lava flow, dry lake 0.2; iceberg and toxic lake 0.15; terraforming scar 0.1; crevasse and frozen ruins 0.05);
- a required mutator (its landform);
- `mutatorChances` (follow-on modifiers);
- `comboLandmarkMutators` (a second landform).

Each mutator gates itself with a `biomeWhitelist`, `minHilliness`, `coastSidesRange` and `canSpawnOnRiver`. Hot springs, for example, need a mountainous tile in boreal forest, lava field, temperate forest, tundra or glacial plain, with no coast and no river. Landmark tiles are a separate class: landmark-defining features never occur on ordinary tiles ([RWwiki Landmarks](https://rimworldwiki.com/wiki/Landmarks)). I did not find the world-level rule for how many landmark tiles a world gets.

Landmark-defining features (41; RWwiki Landmarks, hilliness from the same table):
- **Mountain landforms (13):** basin, cavern, chasm, cliffs ("steep cliffs surround three sides"), hollow, plateau, valley, terraforming scar (mountainous or large hills); crevasse, dunes, ice dunes (flat); lava flow (small hills); lava lake (any).
- **Coastal (7):** archipelago, bay, coastal atoll, coastal island, fjord (mountainous only), peninsula, iceberg.
- **Inland water (8):** dry lake, hot springs, lake, lake with island, oasis, pond, toxic lake, wetland.
- **Man-made (13):** 4 ancient installations, 3 ancient vents (heat, smoke, toxic), ancient quarry (always comes with cavern and mineral-rich), harbor (always with bay), ruins, frozen ruins, abandoned colony, infested settlement.

Additional features (can stack on landmarks; some also on ordinary tiles; RWwiki Landmarks):
- **Terrain variants:** mountain, caves, coast, river (the only four in the base game); cave pools (15% on valley, chasm, plateau, cliff, hollow, basin); lava caves (10% on valley, plateau); ice caves (50% on crevasse); lakeshore (any tile beside a lake of 15 tiles or fewer); headwater; river confluence; river island (5% of plain river tiles); delta.
- **Biological:** fish ±, animal life ± (increased: 75% on oasis, 2% on ordinary tiles), animal habitat (one species ×10 likelihood), insect megahive, plant life ±, grove (one of 10 tree or fungus species en masse, in forest and swamp biomes), wild plants, wild cocoa tree, archean trees.
- **Weather:** foggy (30% on wetland), sunny, wet climate, windy.
- **Ground:** dry ground, fertile (more rich soil), high geothermal (2× geysers), marshy, muddy, sandy, increased pollution.
- **Ore and structures:** mineral rich (one ore; 100% on ancient quarry, 20% on terraforming scar), obsidian deposits; ancient uplink, junkyard, stockpile.
- **Mixed biome:** only on a tile bordering another eligible biome. The map is split into two zones, each with its own plants, animals and terrain. 20% of eligible tiles, plus up to 50% more on many landmarks (lake 0.5 in `BaseLake`).

**For the player:** landmarks make a site nameable and choosable ("the cliffs", "the hot springs"). Modifiers make two maps of the same landform differ in what you can eat, mine or fear.

### 2.5 Tynan Sylvester

- "In play, the Game Model is irrelevant… anything in the Game Model that doesn't copy into the Player Model is worthless"; his examples are Ultima Online's unnoticed ecology and DF's dwarf appearances, which "do nothing, but help players form mental images" ([The Simulation Dream, 2 Jun 2013](https://www.gamedeveloper.com/design/the-simulation-dream)).
- "Apophenia is seeing meaningful patterns in random or meaningless data" (same post). His GDC 2017 talk frames RimWorld as a story generator ([GDC Vault 1024232](https://gdcvault.com/play/1024232/); listing and secondary summaries only, no transcript).
- Inference: landmarks serve this. They give a site a name and shape people retell; hidden numbers matter only through visible effects.

---

## Part 3: What transfers to a first-person walking world (inference)

**Mostly top-down or colony-only:** ore lumps and host-rock ore catalogs (until mining matters), fish, animal and disease multipliers, weather weights, site-finder resource flags, and long species lists. On foot, 72 tree names with about 6 silhouettes read as 6 trees.

**Transfers, and fits "simulate the why, design the what":**
1. **Landform templates gated by simulated context** (Odyssey's model). The island's simulation already has slope, drainage, rock hardness, coast and elevation. Use them as the gates for a small designed set: cliff band, gorge, plateau, hollow, basin lake, waterfall step, hot spring, cove, river island, delta, dunes. Odyssey's mountain group alone has 13. Their absence is the weakness Tarn names in DF.
2. **Modifiers stacked on templates, keyed to causes:** a single-species grove on the deepest soil, fog on low wet ground, a muddy floodplain, an animal habitat. Cheap, and they make two valleys differ.
3. **Mixed-biome edges:** on one island, visible ecotones between dry ridge, wet valley floor and coast.
4. **Aprons at thresholds:** RimWorld's gravel band round every rock mass, 6–8-cell riverbanks and lakeshore terrain make edges readable; talus below cliffs is the 3D analogue.
5. **Strata in cut faces:** DF's thick, sharp layers suit gorges and cliffs walked past.
6. **Caves from rock faces:** RimWorld gates caves on relief (50% of mountainous tiles, 25% of large hills); mouths should open in sheer faces, not pits (Tarn's complaint).
7. **Few tree shapes chosen by site:** pole, conifer, broadleaf, scrub, one giant, selected by wet/dry and elevation and placed with a cluster-size rule.
8. **Named places:** landmarks carry names ("Alpine Lake", "<person>'s End"), adding the story layer Tynan argues for at almost no cost.

## Could not verify

- DF's rainfall × drainage thresholds (a wiki image derived from a 40d forum thread), the current tree spawn frequency default, and how aquifers are assigned to biomes.
- Which DF Talk episodes the quotes come from (the combined transcript has no clear episode markers at those lines).
- RimWorld 1.6 map-generation C#: the code cited is 1.5. In 1.6, rivers, caves, coast and mountains moved into mutator workers, whose code I did not read.
- How many landmark tiles a RimWorld world receives (a world setting is likely, but I did not confirm it). Ludeon's "85+ features" against my count of about 71 mutator defs in four files: the remainder are probably in other files and per-ore variants, unconfirmed.
- The RimWorld Defs come from a third-party mirror. They match wiki values where I checked (temperate forest plant density 0.65, animal density 3.7).
