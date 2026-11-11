# Soils and vegetation

Design for one system of the foundations plan. Numbers are marked **(measured)**, **(sourced)** with the note that carries the source, or **(guess)**.

## 1. What it gives the player

A walk from river to ridge crosses woods that differ for visible reasons: valley trees leaning over water, beech over dwarf bamboo, pines on thin soil over rock, wind-cut scrub and heath. Age shows: birch thicket on a landslide tongue, dark pole stand, old wood with gaps, logs, root mounds and saplings. A dug bank tells the same story: bleached sand under heath, black peat in the bog, brown loam under beech, silt on the floodplain. From a high point the canopy's colour and height follow the land. For the colony game: wood by species, food and fibre plants, and soils that differ in fertility, clay and peat, all inspectable ("ridge pine: dry, humped ground, 0.3 m of soil on hard rock").

## 2. Questions it answers

| Provides | Kind | Used by |
|---|---|---|
| soil depth, soil kind | fields, 16 m | blocks below the surface, bare rock, digging, fertility |
| plant community (best two and a weight) | field, 16 m | far canopy, animals, inspection, colony |
| canopy height and cover | fields, 16 m | far level of detail, sight lines |
| stand: a patch with community, age, origin | feature | placement, inspection, later logging and regrowth |
| tree, log, snag, root mound | derived per tile, never stored | blocks, collision, wood |

| Needs | From |
|---|---|
| elevation, slope, facing, hollow-or-humped, drainage area, wetness, distance to river and sea | land, rivers (facing, curvature, sea distance still to derive) |
| rock kind, strength; **added:** acid or base-rich, weathers to sand, loam or clay | rock |
| temperature, rain; **added:** warmest-month temperature, dry months per year | climate |
| exposure, sunlight, water table | climate, water |
| landslide, flood, fire features with an age; lake levels; channel width and height above it | the systems that record them |
| plant blocks passable to the player **and to water** | engine, `player.odin`, `water.odin` |

## 3. Foundational decisions

**1. A community is a flora crossed with a site slot; stand age is a third axis.**
Climate picks a **flora** (a regional species pool). Local drivers pick a **slot**, the same eleven everywhere: matrix, valley floor, wet woodland, water edge, mire, dry ridge and rock, sun slope, exposed, scree, coast strand, coast cliff. A community row is (flora, slot): species by layer, density, ground cover. Stand age (pioneer, dense young, mature, old with gaps) applies to all. Mangrove is then the tropical water-edge slot, gallery forest savanna's valley floor.
*Alternatives:* a flat biome list with its own communities (Dwarf Fortress, Minecraft); per-species tolerance at every point and no communities (Vintage Story).
*Expensive later because* content rows, far canopy, inspection and the colony's habitats key on it. Slot rules carry to every climate, so a new climate is only rows; per-species suitability gives no name to inspect and no stable far patches.

**2. Soil is two derived fields, depth and kind, on the 16 m grid.**
Depth is soil made minus soil removed: deep in hollows, floodplains and slope feet, thin on humped ground, none where the slope exceeds what the rock holds (soil-mantled slopes stop near 30°, sourced, `interesting-world.md` 4.1). Kind is a short rule table over parent material (the rock, or alluvium, colluvium, sand, peat), wetness, climate and age: the CLORPT factors (sourced, zigcraft research "Soil").
*Alternatives:* four blocks of dirt everywhere (today); soil carried through the erosion; DF's 21 soils by biome.
*Expensive later because* four systems read it; as one function it can later take a simulated regolith without changing readers.

**3. Stands are features; trees are recomputed, never stored.**
The 16 m rung cuts communities into stands of about 0.3 to 5 ha (guess) with an id, age and origin. Trees, logs and snags are a pure function of (seed, stand, 64 m tile, fields), cached per tile. Only player changes will be stored.
*Alternatives:* store every tree (about 420,000 on today's island at 150 a hectare, guess: fine for one island, not a world); scatter per chunk (today: one spacing, the orchard look).
*Expensive later because* the colony needs a unit that ages, is logged and regrows; (tile, index) becomes a tree's identity for edits.

**4. One tree grower, species as rows of about fourteen numbers; the crown envelope is the contract between near and far.**
The grown tree stays inside its species' envelope (cone, dome, oval, flat top, column, curtain, tuft) with a width-to-height ratio. Levels 1 and 2 draw the envelope as columns, as `crown_top` does now for a sphere; beyond 1 km the stand's canopy fields stand in (`adr/0001`).
*Alternatives:* stored templates (TerraFirmaCraft: 8 per oak); space colonisation (better crowns, more code and cost).
*Expensive later because* every species row, far view and the frame budget depend on it.

**5. A plant block is a row in a block table, one bark and one leaf block per species, coloured at draw time.**
Each row: colour per season, `solid`, `water_passes`, later a use. Trunks and leaves stay solid (decided 2026-11-10); ground plants are passable. Colour is looked up from (block, season) in the shader, so autumn and snow on crowns need no remesh. One byte covers island and archipelago (about 70 to 120 blocks, guess); the wide world needs 16 bits, cheap before saves exist.
*Expensive later because* wood types, inspection, seasons and saves hang off block identity.

**6. Vegetation reads disturbances; it records only its own.**
Landslides, floods, fire and lake changes are features of the systems that cause them; vegetation turns their age into stand age. It owns only treefall gaps and windthrow on exposed ground.
*Expensive later because* a pioneer tongue with no landslide above it is a diagram, and the colony game will burn and flood things.

**7. The world rung keeps only the potential community.**
Each world cell stores its flora and slot fractions: enough for an atlas colour, the canopy beyond 10 km and a region's boundary conditions. Soil, stands and trees exist only for regions formed on 16 m cells (zigcraft research, "Plants": potential, aggregate stocks, individuals near the player).
*Expensive later because* it fixes what a 1,000 km world holds in memory.

## 4. The kinds

| Axis | Island | Archipelago | World | Seen on foot |
|---|---|---|---|---|
| Flora | 1 | 3 to 4 | 13 | canopy form and palette, ground cover |
| Site slot | 11 | 11 | 11 | which wood, how open, what underfoot |
| Stand age | 4 | 4 | 4 | spacing, stem size, gaps, dead wood |
| Soil kind | 8 | 10 | 13 | bank colour, surface cover |
| Soil depth class | 4 | 4 | 4 | bare rock, stony, normal, deep |
| Tree species / silhouettes | 8 / 7 | ~20 / 10 | ~60 / 14 | shape, size, bark and leaf colour |
| Ground-layer forms | 6 | 8 | 10 | carpet, thicket, reeds, herbs, cushion |

Flora × slot × age gives 44 visible states on the island. Benchmarks: DF 72 trees in about 6 shapes and 27 land biomes; TerraFirmaCraft 20 trees, about 158 plants, 8 soils; RimWorld 0 to 4 trees a biome (sourced, `df-rimworld.md`, `minecraft-family.md`). The aim is to beat them in silhouettes per place and edges per kilometre, not in names.

**How many tree forms blocks can show (guess).** A crown 3 to 15 blocks wide has room for about 14 families: spire, tiered plates, broad dome, layered dome, narrow oval, umbrella, curtain, pole with tuft, multi-stem clump, swollen trunk, buttressed emergent, column, wind-cut wedge, candelabra. Each in four size classes (1 to 3, 4 to 10, 10 to 20, 20 to 40 m) plus colour. Two species stay separate rows only if they differ in family, size or colour at 30 m; otherwise one row, two names.

**Two communities differ** when a player sees a different canopy form or height, ground layer or openness, and each has its own host.

### Soils

| Soil | Host | In blocks; does |
|---|---|---|
| Bare rock | slope beyond what the rock holds, or under 0.2 m | stone and lichen; no roots |
| Stony colluvium | below scree or cliff | grey-brown with stones; quick drainage |
| Brown earth | moderate slope, neutral or base-rich rock | litter over brown loam; fertile, the default |
| Podzol | acid rock or sand, cool, wet | grey bleached band over rust; poor |
| Alluvium | under ~2 m above the channel on the valley floor | dark silt over gravel; most fertile, floods |
| Gley | water table at surface, clay parent | blue-grey mottled clay; pottery |
| Peat | waterlogged and cool | black-brown, deep; fuel, bog pools |
| Sand | coast strand | pale; dunes |
| Black earth, red tropical, desert, volcanic ash, tidal mud (world) | grassland; hot and wet; dry; young lava; intertidal | black; red clay; pale crust with salt band; dark; grey mud |

### Communities

| Flora / slot | Host | What the player sees |
|---|---|---|
| Cool-temperate / matrix | middle wetness, sheltered | beech domes 20 to 25 m, grey trunks, knee-high dwarf bamboo, gaps, mossy logs |
| Cool-temperate / valley floor | top-decile wetness, slope under 10°, within 2 to 3 channel widths, under 2 m above channel | fewer, bigger trees leaning over water; butterbur; bare gravel bars |
| Cool-temperate / wet woodland | 0.6 to 1.5 m above still water | many-stemmed alder and willow over wet ground |
| Cool-temperate / water edge | −0.5 to +0.6 m of still water | reeds two blocks tall in a band as wide as the shore is gentle |
| Cool-temperate / mire | flat, water table at surface, peat | treeless sphagnum, cotton-grass, pools |
| Cool-temperate / dry ridge | low wetness and humped, or thin soil on hard rock | flat-topped pines and hemlock spires on bare stone |
| Cool-temperate / sun slope | steep, sun-facing, drier third | crooked broad oaks over grass and bracken |
| Cool-temperate / exposed | exposure past a limit that falls toward the coast | wedges 2 to 4 m leaning downwind, then heather |
| Cool-temperate / coast strand | within ~300 m of the sea, low | sand, dune grass, rose scrub, pines taller inland |
| Any / pioneer age | stand under ~30 years old | dense thin birch, alder or willow among old fallen trunks |
| Boreal / matrix | cold, wet enough | spruce spires, moss carpet, birch patches |
| Warm-temperate / matrix | mild winters, wet | dark glossy laurel domes, ferns, deep shade |
| Mediterranean / sun slope | dry summers | grey-green shrubs 1 to 3 m, stony gaps |
| Tropical wet / matrix | hot, wet all year | buttressed emergents to 40 m, vines |
| Tropical / water edge on coast | intertidal mud | mangrove clumps on stilt roots |
| Savanna / matrix and valley floor | long dry season | scattered umbrella trees over grass; closed gallery forest along the river |
| Subalpine / exposed | warmest month near the tree limit | krummholz mats, alpine meadow, cushions |
| Tundra / matrix | below the tree limit | ankle-high shrubs, lichen, sedge in hollows |

### What a species row declares

- **Grower, 14 numbers:** mature height and spread; years to two-thirds height; clear bole fraction; apical control (1 keeps a leader, 0 forks); fork height and count; branch tier spacing and count; branch angle and gravity drag; envelope shape and width-to-height; leaf blob radius and fill; lean limit and what it leans toward (light, water, downwind); multi-stem chance and count; height where the trunk turns 2×2 (3×3 for giants); dead-top and snag rate. After Vintage Story's tree rows and DF's trunk tokens (sourced, `vegetation.md` section 4).
- **Tolerances** (shade, wet, salt, wind, frost) sort species within a community; **companions**: its litter, log and shrubs, after TerraFirmaCraft's forest entries (`minecraft-family.md`).
- **Season:** evergreen or deciduous, leaf timing, autumn and flower colour, whether the crown holds snow.
- **Uses:** wood hardness, colour and rot resistance; nut, fruit or sap; fibre, bark, resin, medicine, fodder. Columns reserved now, island values filled.

Island cast: beech (layered dome), wingnut or katsura (broad leaning dome), alder (narrow oval, multi-stem), willow (curtain), birch (white narrow oval), pine (umbrella on red bole), hemlock (spire), oak (crooked dome). Shrubs use the same grower at 1 to 3 m.

**Ground layer:** carpet (surface block only: moss, litter, heather, turf); passable 1 m thicket (dwarf bamboo, bracken); passable 2 to 3 m reeds; big-leaved herb; grown shrub; climber as a bark variant; floating leaves drawn by the water system.

## 5. How it works

**World rung (1 km cells or coarser).** Flora is a lookup on warmest-month and mean temperature, rain and dry months, after the Whittaker diagram and DF's rainfall × drainage table (`df-rimworld.md` 1.1). Temperature falls with height, so montane and alpine belts come from the same table; the tree limit sits near a growing-season mean of about 6 °C (Körner & Paulsen 2004, from memory) and is lowered by exposure on small islands (sourced, `vegetation.md` takeaway 4). Cost negligible.

**Region rung (16 m, once after the land forms).**
1. Derive facing, curvature (3 × 3 neighbourhood), distance to sea, exposure (height, humped, near sea, facing the wind) and sunlight (`vegetation.md` section 2).
2. Soil depth and kind (decision 2).
3. Slot scores: each slot is a smooth score over fields, in the community table (catena by wetness and curvature; shore bands by height above water; coast by distance). Keep the best two and a weight. Thresholds are set by looking at the map.
4. Stands: seeds on a jittered grid about 50 m apart (guess) claim cells as patches, split where the community changes. Age is the youngest disturbance covering it, else an exponential draw with the community's disturbance interval as mean.
5. Canopy height and cover per cell for the far view.

Cost: 262,000 cells (measured grid size) × a few dozen operations, under 30 ms (guess).

**Place rung (64 m tiles, with a 12 m margin so any chunk gets the same answer).**
1. Candidates on a dithered grid at the stand's spacing: about 3 m young, 6 m at fifty years, 10 to 12 m old (stems fall from ~1,480 to ~75 a hectare, sourced, `vegetation.md` takeaway 7), as Horizon Zero Dawn spaces each layer by footprint (sourced, `vegetation.md` section 5).
2. Species by weighted pick from the community, times the species' tolerance there, times a low-frequency noise per species so groves form.
3. One thinning pass after Deussen et al. 1998: of two overlapping crowns the taller wins; the loser becomes a sapling if lit, else a snag or a log with root mound and pit. Old stands get about 15 % gap (sourced) filled with saplings and thicket.
4. Each tree's open direction (away from taller neighbours, toward water or a gap, downwind when exposed) leans the trunk, lengthens branches that way, clips the crowded side and leaves a block between equal crowns. Slope tilts the base downhill.
5. Grow: trunk up with lean and wander; fork if apical control is low; branch tiers as lines of blocks with angle and drag, length from the envelope and space; leaf blobs at the outer ends; dead top by rate. One branch level plus forks should read at 1 m (guess). A mature beech is about 1,500 blocks (guess).
6. Ground layer per column, thinned under crowns; a 5 to 15 m shrub band at forest edges (sourced, `vegetation.md` section 2). Soil profile: cover, topsoil, subsoil to the soil depth, rock.

Level 0 uses all of it; levels 1 and 2 use steps 1 to 3 and draw envelopes as columns; beyond, the canopy fields. Crown reach grows from 4 m to about 10 m, with fewer trees. Placement is cached per tile on workers.

## 6. Growth path

**Stage 0, today's island, four slices.** `g.soft` stands in for rock hardness until the rock system exists.

- **0a. Soil and five communities** (valley floor, beech matrix, ridge pine, exposed scrub and heath, coast strand). `land.odin`: facing, curvature, sea distance, exposure (~50 lines). `gen.odin`: soil rule, community table, `forest_at` → community density, `trees_in` picks species, `crown_top` takes an envelope, `block_below` reads soil; new bark, leaf and soil blocks; `--map` tints communities (~220 lines, guess). Owner looks at the map, a walk from river to ridge, and a view from a high point.
- **0b. Stands and age:** patches, spacing by age, thinning, gaps, logs, snags, mounds (~130 lines). Look at ground level in old and young wood.
- **0c. The grower** within 256 m; envelopes stay far (~200 lines). Look under a beech, by birch, at pine on rock.
- **0d. Ground layer and water edges** once lakes exist; passable blocks in `player.odin` and `water.odin` (~80 lines).

About 630 lines in all (guess). After each: `--bench=8` from the start (about 57 m expected) and the flight bench (no frame over 12.5 ms).

**Stage 1, archipelago.** Flora per island from climate: cool-temperate, a boreal or subalpine belt on a high island, a warm-temperate island, an exposed treeless one. All eleven slots, about 20 species in 10 silhouettes, real lakes and disturbance features.

**Stage 2, wide world.** Thirteen floras, about 60 species; potential community per world cell; 16-bit blocks; aggregate stocks per stand for the colony, after LANDIS-II cohorts (sourced, zigcraft research).

**Not yet, with triggers.** Succession, logging, fire, farming: when colony time passes. Drawn seasons: when a calendar exists. Space colonisation: if the owner rejects the grower's crowns. Simulated soil: when the rule visibly contradicts the land. Fantasy floras: one more row gated on an authored field.

## 7. Risks and known failures

- **Orchard look.** Age sets spacing; thinning gives clumps, gaps and mixed sizes.
- **Edges that read as contour lines.** Dither the blend of the two best slots with noise over 10 to 50 m (sourced, `vegetation.md` section 2), and let stand edges carry boundaries.
- **Generic noise in the 16 m to 1 m gap** (`lessons.md`). Detail below a cell comes from things with hosts: logs from dead trees, mounds from logs, gaps from treefall.
- **Trees hiding the land** (`interesting-world.md` 2.6). Open slots on rock, exposure and coast; gaps; canopy that follows the ground.
- **Thresholds before measurement.** All are starting guesses; `--map` prints community fractions, and the owner judges.
- **Frame pacing.** Larger trees; per-tile cache; benches after each slice.

## 8. Decisions for the owner

1. **True tree heights** (beech 20 to 25 m, pine 12 to 18 m) against today's 8 to 14 m? *Recommendation: true*, for the enclosure in the woodland-lake photograph.
2. **Thin plants as passable cubes or crossed quads?** *Recommendation: cubes*, to stay blocky; crossed quads only if cubes read as hedges.
3. **Confirm the cool-temperate oceanic flora** (`open-decisions.md` question 7). It sets the eight forms.
4. **Species colour true or pushed apart?** *Recommendation: true hues pushed slightly apart* so community edges read from a ridge.
5. **Season until seasons exist?** *Recommendation: early summer.*
6. **How much wood?** *Recommendation: let the rules decide*, then check "does the forest open often enough to show the land?" on the first walk.

## 9. Not verified

- The tree-limit temperature (Körner & Paulsen) and the Whittaker diagram as a lookup, from memory; the soil production rule (Heimsath et al. 1997), from memory.
- That 14 silhouettes in four sizes are separable at 1 m, that one branch level plus forks reads as species, and that a mature tree is about 1,500 blocks.
- That a derived soil rule suffices before a simulated regolith.
- Stems and gap sizes for *Fagus crenata* old growth (`vegetation.md`).
- Whether `water.odin` and `player.odin` can treat passable plant blocks as air without further changes.
