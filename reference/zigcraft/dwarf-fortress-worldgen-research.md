# Dwarf Fortress world generation, ecology, resources, and history

**Research snapshot:** 2026-07-11

**Question:** what does Dwarf Fortress actually generate for climate, biomes,
plants, wildlife, creatures, geology, mineral resources, underground spaces,
civilizations, and history—and which ideas should become foundations for
Zigcraft's future colony-simulation world?

**Evidence rule:** this report distinguishes three confidence levels:

- **Primary / confirmed:** Bay 12 development logs, the official DF Talk
  transcript, official release notes, the official modding guide, and current
  game data distributed by Bay 12.
- **Primary / observed data contract:** a claim visible in the current vanilla
  raw files or procedural Lua scripts, but not an assertion about the
  closed-source placement algorithm that consumes those records.
- **Secondary / qualified:** the community-maintained Dwarf Fortress Wiki,
  used only where first-party material does not expose a current implementation
  detail. Its relevant pages themselves warn that some advanced-worldgen
  material was migrated from older versions.

Recommendations for Zigcraft are labeled **proposal** or **inference**. They are
not claims about Dwarf Fortress.

## Executive conclusion

Dwarf Fortress is not one uniformly detailed planet simulation. Its effective
shape is a hierarchy:

1. generate coarse environmental fields and terrain;
2. derive named regions and biome categories;
3. select data-defined plants, animals, rocks, and minerals that are eligible
   for those environments;
4. build caverns, sites, resource stocks, civilizations, and exceptional
   creatures;
5. simulate an abstract history in which populations, sites, rulers, wars,
   industries, trade, monsters, and artifacts interact; and
6. persist the resulting world so that fortress and adventure play encounter
   the same places, people, resources, ruins, and consequences.

The core dependency chain inside that reconstruction is described directly by Tarn Adams in the official DF Talk
world-generation episode: elevation, rainfall, and temperature are established
first; rivers and lakes follow; rainfall, temperature, drainage, and elevation
then determine biomes; creatures are imported from the raws; geography and
rocks constrain civilizations; and history advances until the configured stop
year ([official DF Talk combined transcript](https://www.bay12games.com/media/df_talk_combined_transcript.html)).

The major lesson for Zigcraft is therefore not “copy DF's biome table” or “copy
three cavern layers.” It is:

> Generate a compact, causal, persistent world truth early enough that ecology,
> resources, expedition choice, colony economics, discovery, history, and
> future modifications all refer to the same world.

Several actual DF mechanisms are deliberately simpler than the natural-world
standard requested for Zigcraft. First-party material acknowledges simplified
soil deposition, missing alluvium, and unsatisfying mineral shapes. Its fauna
has rich individual definitions, but public evidence does not establish a full
world-scale trophic ecosystem. Its categorical biome assignment is an
excellent content-routing device, but Zigcraft should preserve continuous
climate, soil, water, landform, and disturbance fields underneath any biome
label so that ecotones are gradual rather than hard borders.

## Scope and source limitations

Dwarf Fortress has changed continuously for two decades. The clearest
first-party pipeline explanation is an older DF Talk episode, while the current
vanilla data inspected for this report is from Classic 53.15, released June 25,
2026. The high-level dependency order has remained visible across official
logs, but individual algorithms and thresholds may have changed.

The current Linux release was retrieved from the
[official Bay 12 download](https://www.bay12games.com/dwarves/df_53_15_linux.tar.bz2)
and had SHA-256
`2eb7865c693c3e09abf0c937ed54f7534b4214e85129915d12c5c1ce626d378a`.
Relevant observed files include:

- `data/vanilla/vanilla_materials/objects/inorganic_stone_layer.txt`
- `data/vanilla/vanilla_materials/objects/inorganic_stone_mineral.txt`
- `data/vanilla/vanilla_plants/objects/*.txt`
- `data/vanilla/vanilla_creatures/objects/*.txt`
- `data/vanilla/vanilla_entities/objects/entity_default.txt`
- `data/vanilla/vanilla_procedural/scripts/generators/*.lua`

These are authoritative content definitions. They show which inputs the game
can express, not every hidden rule by which the executable places or updates
them. Where the distinction matters, it is called out below.

## The reconstructed Dwarf Fortress pipeline

| Layer | Primary-source finding | What it provides to play |
|---|---|---|
| Environmental fields | Elevation, temperature, rainfall, drainage, volcanism, and savagery are worldgen controls; temperature is also affected by pole choice and elevation, and orographic rain can create rain shadows. | Oceans, mountains, climate variation, wetlands, deserts, volcanic areas, and the environmental basis for regions. |
| Hydrology and terrain adjustment | Rivers are generated after elevation/oceans, through multiple passes; lakes and erosion follow. | Water, drainage basins, settlement corridors, valleys, and natural boundaries. |
| Regions and biomes | Rainfall, temperature, drainage, and elevation are combined to select biomes; contiguous regions are located and named. | A vocabulary for local appearance, plants, fauna, settlement suitability, and embark information. |
| Geology and resources | Geological regions, layer stones, inclusions, gems, ore veins, soil, aquifers, and volcanism-conditioned features are placed. | Mining, industry, construction materials, hazards, trade differences, and discovery. |
| Flora and fauna | Raw-defined species are filtered by biome and other eligibility rules; world populations/ranges are stored at aggregate scales. | Gatherable/cultivable materials, timber, food, wildlife encounters, livestock, and cultural access to animals/plants. |
| Underground | Tunable cavern layers, water/open-space proportions, vertical connections, underground lakes, volcano connections, populations, and depth-filtered creatures/plants are created. | A second ecological world, exploration progression, rare resources, hazards, and “dig deeper” stories. |
| Civilization seeding | Entity definitions express start biomes, biome support, site preferences, ethics, usable animals, technologies, and industries. Geography and available materials influence where civilizations begin and what they can do. | Distinct societies tied to place rather than interchangeable factions. |
| Historical simulation | Birth, death, succession, settlement, migration, industry, trade, war, beasts, religion, artifacts, and many other events advance for a configured number of years. | Ruins, relationships, political geography, famous people/items, resource flows, and a world that predates the player. |
| Embark and persistence | The player inspects the world, selects a local rectangle, and plays inside the same persistent world across forts/adventures. | Location is a strategic and narrative choice; later games inherit previous consequences. |

The environmental and early-history order is **primary / confirmed** by the
[DF Talk transcript](https://www.bay12games.com/media/df_talk_combined_transcript.html).
The 2007 log separately records the introduction of mid-level maps connecting
regional to local maps, geological regions and mineral distributions, biome
population tracking, and local river realization
([Bay 12 development log, 2007](https://www.bay12games.com/dwarves/dev_2007.html)).

## Climate, regions, and biomes

### Continuous inputs, categorical output

**Primary / confirmed:** Tarn's pipeline explanation says that DF establishes
elevation, rainfall, temperature, and drainage fields, adjusts temperature for
latitude/poles and elevation, applies rainfall, and later decides biome types
from rainfall, temperature, drainage, and elevation
([DF Talk](https://www.bay12games.com/media/df_talk_combined_transcript.html)).
The 2006 log also records wet/dry seasons, humidity-dependent temperature
variation, salinity derived from oceans, and plants/creatures respecting the
new biome system
([Bay 12 development log, 2006](https://www.bay12games.com/dwarves/dev_2006.html)).

**Primary / confirmed, historical parameter contract:** Bay 12 published a
June 2008 preview of its `world_gen.txt`. It exposed minima, maxima, spatial
variation, and weighted frequencies for elevation, rainfall, temperature,
drainage, volcanism, and savagery, plus good/evil area counts, region quotas,
erosion cycles, river minima, orographic precipitation, caves, civilization
counts, history end year, population limits, and explicit painted field grids
([official parameter/raw archive](https://www.bay12games.com/dwarves/spoilers/061208.zip),
[development context](https://www.bay12games.com/dwarves/dev_2008.html)). This
is valuable evidence of the generator's control surfaces, but it is a 2008
contract and must not be treated as a complete 53.15 specification.

**Secondary / qualified:** the current community
[advanced-world-generation page](https://dwarffortresswiki.org/index.php/Advanced_world_generation)
still describes terrain fields, weighted distributions, feature controls, and
world-rejection constraints, but warns that portions were migrated and may be
inaccurate for the current version. It is useful as an operator's map, not as a
source-code specification.

### Biomes are also content queries

**Primary / observed data contract:** current plants and creatures declare
eligibility against named biome tokens such as temperate broadleaf forest,
tropical savanna, mountain, tundra, freshwater/brackish rivers and lakes,
ocean, pool, subterranean water, and subterranean chasm. Definitions can also
carry `GOOD`, `EVIL`, or `SAVAGE` restrictions. This makes a DF biome more than
a surface color: it is a query key for a content catalog
([official 53.15 release archive](https://www.bay12games.com/dwarves/df_53_15_linux.tar.bz2)).

**Primary / confirmed historical behavior:** the 2010 log says animals and plants were changed from independent per-region
presence to more coherent ranges that respect biomes
([Bay 12 development log, 2010](https://www.bay12games.com/dwarves/dev_2010.html)).
This confirms the 2010 behavior, not the current closed-source placement
algorithm. The transferable point is that the species roster can be spatially
coherent rather than rerolled independently in every region.

### What Zigcraft should retain and improve

**Proposal:** make an ecoregion/biome a *derived view*, not the only ecological
truth. Persist continuous or ordinal fields for at least:

- seasonal temperature and frost;
- precipitation, aridity, snow persistence, and available water;
- soil depth, texture, drainage, fertility, salinity, and organic matter;
- landform position such as ridge, slope, valley floor, floodplain, wetland,
  coast, dune, and lake margin;
- elevation, exposure, and disturbance regime; and
- surface/subsurface connectivity.

Then derive human-readable biome and habitat labels from those fields. A tree
or animal should evaluate a multidimensional niche, with the biome label acting
as an index/cache/UI summary. This permits broad recognizable regions while
also producing ecotones, gallery forests, alpine transitions, riparian bands,
coastal zonation, and local refugia without categorical cliffs.

## Plants and vegetation

### What Dwarf Fortress expresses

**Primary / observed data contract:** current plant records can define:

- eligible biomes, wet/dry tolerance, seasons, frequency, and cluster size;
- underground depth and subterranean habitat;
- growth duration and timed growths such as leaves, flowers, fruit, seeds, and
  pollen;
- tree height, trunk diameter, branch/root structure, and mushroom caps;
- materials and uses including wood, food, drink, seed, thread, paper, oil,
  dye, extracts, and values; and
- good/evil associations.

Examples include pine restricted to forest families with explicit tree
architecture, tower-cap fungi tied to subterranean water and depth, and plump
helmets tied to subterranean water with all-season growth and edible/brewable
materials
([official 53.15 vanilla plant raws](https://www.bay12games.com/dwarves/df_53_15_linux.tar.bz2)).

**Primary / confirmed:** DF worldgen can track specific plant amounts at sites
through an annual crop cycle, while Tarn explicitly noted that a large mod
might require abstraction to a category such as an edible plant from a
location. Site populations consume food, farm, and participate in resource
flows
([Bay 12 development log, 2010](https://www.bay12games.com/dwarves/dev_2010.html)).
That is direct evidence for selective aggregation rather than globally
materializing every plant.

### What is not established

There is no primary public evidence that DF worldgen runs a complete dynamic
succession model, competition for light/water/nutrients among all species, or
a whole-world plant food web. Rich per-species definitions and annual site
stocks should not be mistaken for a process-complete ecology.

### Zigcraft lesson

**Proposal:** split vegetation into three scales:

1. a persisted potential-community record derived from climate, soil,
   hydrology, terrain, and disturbance;
2. aggregate biomass/cohort/resource stocks for world/history simulation; and
3. deterministic individual plants and local succession realized only for
   expedition regions and other active sites.

This supports a massive world and the four-minute mode without reducing the
surface to arbitrary decoration. The same potential community can drive atlas
color, site evaluation, animal carrying capacity, gathering, agriculture,
fire, logging, regrowth, and detailed local placement.

## Fauna, wildlife populations, and creatures

### Hand-authored natural species

**Primary / observed data contract:** current creature records can express
biomes, underground depth, frequency, population and cluster ranges, roaming,
activity period, lifespan, offspring, eggs, grazing/carnivory, aquatic and
climbing behavior, temperament, body parts, tissues, materials, size,
appearance, attacks, senses, trainability, products, and cultural use. This is
why a creature can be ecologically placed, anatomically simulated, butchered
into meaningful materials, domesticated, fought, described, and inherited by
a civilization from one definition
([official 53.15 vanilla creature raws](https://www.bay12games.com/dwarves/df_53_15_linux.tar.bz2)).

**Primary / confirmed:** the 2007 log says regions tracked some animal
population counts, local animal populations were transferred as maps moved,
and subterranean feature populations persisted across games
([Bay 12 development log, 2007](https://www.bay12games.com/dwarves/dev_2007.html)).
The 2009 log distinguishes renewable/depletable underground populations from
the then-more-complicated general wilderness case
([Bay 12 development log, 2009](https://www.bay12games.com/dwarves/dev_2009.html)).
In 2014, world activation brought population handling into ongoing play, and
animals used by invasions could come from actual populations
([Bay 12 development log, 2014](https://www.bay12games.com/dwarves/dev_2014.html)).

### Procedural exceptional creatures

DF uses a different strategy for exceptional fantasy content. Forgotten
beasts, titans, demons, curses, experiments, evil weather, and other procedural
objects are assembled from generators. Bay 12 exposed those algorithms as Lua
in 2025, with vanilla scripts under `data/vanilla/vanilla_procedural`
([official 2025 release notes](https://www.bay12games.com/dwarves/)). The
current creature generator visibly combines body bases, materials,
descriptors, capabilities, interactions, and difficulty rules
([official 53.15 release archive](https://www.bay12games.com/dwarves/df_53_15_linux.tar.bz2)).

**Inference/proposal:** this is a useful division of labor for Zigcraft:

- ordinary ecology benefits from curated, recognizable species with coherent
  niches and uses;
- rare mythic beings benefit from constrained procedural combinations because
  uniqueness is the point.

Generating every ordinary animal from arbitrary parts would weaken ecological
legibility and player knowledge. Generating a few singular monsters this way
creates memorable unknowns.

### Ecology limitation

DF's public data includes carnivore, grazer, vermin-eater, predator, and other
behavioral tags, but no primary source found for this report establishes a
complete world-scale predator–prey network or trophic population solver. Tarn
said in an official DF Talk discussion that wilderness creatures lacked the
larger population tracking needed for broad natural selection at that time
([DF Talk combined transcript](https://www.bay12games.com/media/df_talk_combined_transcript.html)).
Later population work expanded the system, but that does not prove a modern
food-web simulator.

### Zigcraft lesson

**Proposal:** maintain population *stocks* globally and instantiate
individuals locally:

- `SpeciesDefinition`: niche, life history, diet guild, body/material outputs,
  behavior, domestication, and game roles;
- `HabitatPatch`: connected suitable area and seasonal capacity;
- `PopulationStock`: abundance class or bounded quantity, age/sex summary only
  where it matters, migration links, pressure, harvest, and recovery;
- `LocalPopulationSeed`: deterministic realization recipe for active regions;
  and
- `ExceptionalCreatureRecord`: rare generated individuals with stable identity
  and history.

The four-minute profile should never simulate every animal. It should finish a
coherent habitat graph and bounded aggregate populations from which later
entities can be realized consistently.

## Geology, minerals, and natural resources

### The strong part of the DF model: contextual eligibility

**Primary / observed data contract:** current layer rocks are classified as
sedimentary, igneous intrusive, igneous extrusive, or metamorphic; some carry
aquifer or depositional-context flags. Mineral records declare eligible host
classes or exact host materials and an occurrence morphology such as vein,
cluster, small cluster, or single cluster. Examples in the vanilla data
include:

- hematite in several rock families with different occurrence forms;
- garnierite specifically in gabbro;
- bituminous coal and lignite in sedimentary hosts;
- native gold in igneous environments and small alluvial clusters;
- cassiterite in granite veins and alluvial clusters; and
- kimberlite in gabbro veins.

This is a compact and productive rule system: an ore is not independent noise;
host geology and deposit style constrain where it can appear
([official 53.15 inorganic raws](https://www.bay12games.com/dwarves/df_53_15_linux.tar.bz2)).
Bay 12's feature page summarizes the player-facing result as more than two
hundred rock and mineral types placed in their proper geological environments
([official features](https://bay12games.com/dwarves/features.html)).

**Primary / confirmed:** the 2007 development log records geological regions,
mineral distributions, layer-based local rock, specific inclusion patterns,
soil layers, rock-conditioned water tables, gems, and metal veins
([Bay 12 development log, 2007](https://www.bay12games.com/dwarves/dev_2007.html)).

### The limitation: placement shape is not geological process

Tarn has also been explicit about shortcomings. In DF Talk he described old
mineral layouts as small ovals and restricted veins concentrated in one
z-level, and later said the soil/stone model omitted important alluvial
deposition such as river sediment and stones
([official DF Talk transcript](https://www.bay12games.com/media/df_talk_combined_transcript.html)).
Those statements are old, so exact current geometry may differ, but they make
one point durable: DF's geology should not be assumed to be a full tectonic,
stratigraphic, hydrothermal, and sedimentary history simulation merely because
its mineral catalog and host rules are broad.

### Zigcraft lesson

**Proposal:** borrow host-conditioned deposits, but make the deposit envelope
three-dimensional and causal. A mineral occurrence should derive from one or
more events such as:

- magmatic differentiation or an intrusion;
- hydrothermal flow along a fault/fracture network;
- contact metamorphism;
- sedimentary basin deposition and diagenesis;
- weathering enrichment;
- placer/alluvial concentration along actual drainage history; or
- evaporite formation in closed basins.

The base world does not need globally voxelized ore. It does need a persisted
`GeologyAtlas` and sparse `DepositRecord` parents early enough that later
one-metre realization cannot contradict the world. A deposit envelope should
own genesis, host units, 3D bounds/shape controls, grade distribution,
alteration halo, erosion/exposure state, stable ID, and deterministic local
realization seed.

This is one of the foundations that should precede Phase 10 even if prospecting,
mining economics, and the full material catalog come later. Adding deposits
after worlds already exist would either rewrite immutable geology or make old
worlds resource-incomplete.

## Underground regions and biomes

### What Dwarf Fortress does

**Primary / confirmed:** the 2009 underground revision added worldgen controls
for removing underground features, changing openness, reducing layer count,
and varying cavern water. It created vertical connections among cavern layers,
surface caves, volcanic features, underground lakes, and deeper areas
([Bay 12 development log, 2009](https://www.bay12games.com/dwarves/dev_2009.html)).
The same log says underground creatures could specify which of the first three
layers or deeper areas they inhabit, and underground populations could be
depleted and recover.

**Primary / observed data contract:** current plants and creatures use
`SUBTERRANEAN_WATER`, `SUBTERRANEAN_CHASM`, and `UNDERGROUND_DEPTH` eligibility.
Tower caps, for example, are subterranean-water trees limited to shallow/mid
depths; many cavern animals are assigned to selected depths
([official 53.15 raws](https://www.bay12games.com/dwarves/df_53_15_linux.tar.bz2)).

**Inference from the confirmed feature/data contracts:** DF's underground
functions as both:

- a connected spatial feature system; and
- a deliberate progression space whose depth bands control ecology, hazards,
  civilizations, resources, and surprises.

### What Zigcraft should not copy literally

Repeated global cavern strata are a powerful game structure, not a universal
geological truth. **Proposal:** Zigcraft should derive underground habitat from
geology and water first, then tune its progression:

- karst and solution caves where soluble host units and groundwater permit;
- lava tubes and volcanic conduits in appropriate provinces;
- fracture/fault caves, talus voids, and tectonic openings;
- vadose, water-table, phreatic, flooded, geothermal, and deep isolated habitat
  states;
- aquifers and underground rivers connected to the same surface hydrology;
  and
- rare deep fantasy structures added as explicit exceptional world records.

A sparse global `SubsurfaceAtlas` can store volumes, connectivity, water,
temperature, chemistry, host geology, stability, habitat class, entrances, and
stable IDs. Detailed voxel walls, speleothems, sediments, organisms, and ore
exposures can be generated only near expeditions. This preserves the “whole
world exists” feeling without paying for every underground block during world
creation.

## Civilizations, resources, and history

### Geography is upstream of society

Tarn's worldgen explanation explicitly says geography and available rocks must
exist before civilizations are selected; he described this as a form of
geographical determinism
([DF Talk](https://www.bay12games.com/media/df_talk_combined_transcript.html)).

**Primary / observed data contract:** current entity definitions include
starting biomes, weighted biome support, preferred site types, available
animals, technologies/buildings, world constructions, ethics, religion,
positions, and permitted materials. The vanilla human entity, for example,
weights oceans, rivers, lakes, forests, and plains differently; dwarf entities
favor mountains and caves; elves begin in forests. These definitions do not
prove the full settlement-scoring algorithm, but they prove that environment
and society share a data contract
([official 53.15 entity raws](https://www.bay12games.com/dwarves/df_53_15_linux.tar.bz2)).

**Primary / confirmed:** official logs show humans spreading along accessible
surface water, villages supporting towns, industries producing differentiated
goods, trade moving surpluses, and settlement resource stocks being tracked.
They also show plants, animals, and minerals deliberately redistributed to
make resource geography more interesting
([Bay 12 development log, 2010](https://www.bay12games.com/dwarves/dev_2010.html)).

### History is simulation plus an event record

DF world history advances births, deaths, marriages, succession, migration,
site founding and reclaiming, settlement growth, industry, trade, war,
territory, monsters, religions, artifacts, and individual careers at differing
levels of abstraction. Events and relationships are recorded for later
legends, conversations, art, ruins, and gameplay. The official feature page
emphasizes that the world persists across multiple games and records changes
([official features](https://bay12games.com/dwarves/features.html)).

In 2014, Bay 12 moved many worldgen processes—birth, death, marriage,
succession, invasions, site foundations/reclaims, patrols, banditry, and animal
population handling—into continued world activity after play begins
([Bay 12 development log, 2014](https://www.bay12games.com/dwarves/dev_2014.html)).
That continuity is a major part of the north star: prehistory and gameplay are
not unrelated generators.

### Performance lesson

History is also expensive. As an illustrative first-party anecdote rather than
a portable benchmark, Bay 12 reported that a 1,000-year medium world still
took about 27–28 minutes on its test laptop in 2022 even after worldgen speed
work, and that optimizing overly frequent book-related behavior improved
worldgen by roughly 25%
([Bay 12 development log, 2022](https://www.bay12games.com/dwarves/)). Earlier
logs discuss culling dead historical figures/events to reduce memory
([Bay 12 development log, 2008](https://www.bay12games.com/dwarves/dev_2008.html)).

**Inference:** Zigcraft cannot put DF-scale centuries of detailed history into
the current four-minute promise without either displacing terrain/ecology work
or using much stronger abstraction. Deep history belongs to a later milestone
and perhaps higher world-detail profiles. The early foundation should make it
possible—not prematurely simulate it.

**Proposal:** when history arrives, use:

- aggregate population, production, consumption, and military stocks for most
  sites;
- explicit historical figures only when roles, relationships, achievements,
  or player contact make them narratively important;
- an append-only semantic `WorldEventLedger` rather than storing every
  transient simulation step;
- deterministic yearly/seasonal batches with fixed work caps;
- state snapshots/checkpoints for fast loading; and
- the same event types during prehistory and off-site runtime advancement.

## Embark-site information and discovery

DF makes the generated world actionable by letting the player choose a site.
The current graphical embark screen uses the whole world map and supports
scrolling large worlds
([Bay 12 development log, 2021](https://www.bay12games.com/dwarves/)). Earlier
logs record a site finder for metals, soil, and aquifers, later expanded to
specific metals and sand. The 2022 tutorial site selector deliberately searches
for a forested, fairly flat site with a brook and shallow metals
([Bay 12 development log, 2010](https://www.bay12games.com/dwarves/dev_2010.html),
[Bay 12 development log, 2022](https://www.bay12games.com/dwarves/)).

**Inference:** this reveals an essential design fact: “natural world
generation” alone does
not create a good colony game. Players need to understand the practical
consequences of place.

**Proposal:** Zigcraft's expedition map should eventually expose or filter:

- climate, seasons, growing period, snow, and weather hazards;
- freshwater reliability and flood/drought regime;
- terrain ruggedness, soils, forest/grassland cover, and arable potential;
- surface stone, construction materials, fuel, forage, and wildlife;
- known/probable mineral families, with exact deposits discoverable through
  prospecting rather than fully spoiled;
- aquifers, caves, geothermal/volcanic risk, and underground opportunity;
- travel access, nearby settlements, trade potential, political risk, and
  historical landmarks; and
- an explicit “why this site is interesting/difficult” explanation.

**Proposal:** store actual resource truth separately from the expedition's knowledge. The
root's `DepositRecord`/ecological endowment can be immutable world truth while
`ResourceKnowledge`
belongs to civilizations/expeditions and improves through maps, rumors,
surveys, and mining.

## Game design: where naturalism should yield

**Inference:** the requested direction—natural and expansive first, then intentionally good
game design—is compatible with DF's best decisions. DF repeatedly bends
literal realism when it improves comprehension, choice, pacing, or stories.

### First-party examples

- **Visual readability:** Bay 12 applies crown shyness to all tree species in
  the graphical presentation even though Tarn notes that not all real species
  exhibit it, because separated crowns make individual trees legible
  ([2020 development log](https://www.bay12games.com/dwarves/)).
- **Playable starting conditions:** the tutorial searches for water, forest,
  flatter ground, and accessible metal instead of placing new players at a
  uniformly random valid site
  ([2022 development log](https://www.bay12games.com/dwarves/)).
- **Interesting scarcity (inference from the change):** plants, animals, and minerals were redistributed,
  with metals made less ubiquitous and the site finder improved so scarcity
  became a choice rather than blind failure
  ([2010 development log](https://www.bay12games.com/dwarves/dev_2010.html)).
- **Discovery versus control:** Tarn discussed mineral surveying as a tension
  between letting players plan exact forts and making them adapt to what they
  discover
  ([DF Talk](https://www.bay12games.com/media/df_talk_combined_transcript.html)).
- **Player-selectable plausibility:** release 53.15 lets players keep newly
  added extinct animals absent, restrict them to isolated/untamed areas, spread
  them broadly, or even make them widely domesticated
  ([official 53.15 release notes](https://www.bay12games.com/dwarves/)).

### Recommended three-layer rule

**Proposal:** never hide a gameplay correction inside the physical generator.
Keep three explicit layers:

1. `NaturalPotential`: the causal physical/ecological result;
2. `PlayabilityPolicy`: bounded selection, repair, rarity, progression, and
   accessibility decisions; and
3. `PresentationPolicy`: what the map and rendered world exaggerate, simplify,
   or clarify.

Examples:

- A copper deposit may only occur in plausible host geology
  (`NaturalPotential`), but world-level quotas can ensure several reachable
  copper provinces (`PlayabilityPolicy`). The map can show a broad “copper
  potential” tint without exposing exact veins (`PresentationPolicy`).
- An expedition should not be guaranteed every strategic resource locally.
  It should usually have viable water, food/fuel, and construction options,
  while missing materials create exploration, adaptation, and trade.
- Rare resources should be meaningfully regional, not arbitrary speckles.
  Their absence should create another strategy rather than an unwinnable seed.
- Ecological diversity should include quiet, coherent landscapes. Filling every
  site with maximum species and terrain contrast makes the world noisy rather
  than beautiful.

This makes deviations reviewable. A designer can ask whether an intervention
improved play without corrupting geology, hydrology, or ecology.

## Transferable lessons and explicit non-lessons

| Dwarf Fortress idea | Zigcraft decision |
|---|---|
| Generate geography before ecology, society, and history. | **Adopt.** Preserve causal ordering and immutable upstream IDs. |
| Use environmental fields to derive named biomes. | **Adopt with improvement.** Keep continuous fields and ecotones underneath labels. |
| Species/content definitions declare habitat and useful products. | **Adopt.** A single data definition should serve distribution, rendering, harvesting, crafting, domestication, and history. |
| Give species coherent ranges rather than independent per-cell rolls. | **Adopt.** Build connected habitat patches and biogeographic provinces. |
| Track most remote ecology as aggregate populations. | **Adopt.** Realize individuals only in active/local contexts. |
| Use curated ordinary species and procedural singular monsters. | **Adopt.** These content types have different design goals. |
| Constrain minerals by host geology and deposit type. | **Adopt and deepen.** Generate causal 3D deposit envelopes rather than 2D blobs. |
| Use underground depth bands to create progression. | **Adopt as game design, not geology.** Derive caves from rock/water/heat, then tune risk/reward by depth. |
| Let civilizations inherit the resources, animals, and constraints of place. | **Adopt.** Geography should produce economic and cultural differences. |
| Simulate history before play and continue compatible processes afterward. | **Long-term adopt.** Build the persistence/event seams early; defer expensive history. |
| Show site consequences before embark. | **Adopt.** Expedition choice should be informed and strategically expressive. |
| Expose many advanced parameters and reject worlds until quotas pass. | **Do not copy as the main product UI/runtime strategy.** Keep 4/10/15-minute profiles simple and constructively bounded; retain an expert lab later. |
| Three broadly repeated cavern layers. | **Do not copy literally.** Use geology/hydrology-conditioned subsurface networks. |
| Categorical biome alone owns flora/fauna. | **Do not copy.** Use multidimensional niches, microhabitats, and gradients. |
| Rich animal definitions imply a complete ecosystem. | **Do not assume.** Design and test population/trophic behavior explicitly. |
| Large content count equals beauty or playability. | **Reject.** Coherence, composition, legibility, pacing, and meaningful differences matter more. |

## Foundation Zigcraft should establish early

The following is a **proposal** for durable world-root products. It is not a
request to implement every consumer before Phase 10.

```text
physical atlas
  geology + terrain + ocean + hydrology
              |
              v
climate, soil, groundwater, and disturbance potential
              |
              v
ecoregions + ecotones + connected habitat patches
              |
              +----> flora/fauna potential and population stocks
              |
              +----> resources and settlement carrying capacity
              |
              v
sites, civilizations, economy, and history (later)
              |
              v
expedition choice and persistent colony play
```

### Products needed before they become expensive to retrofit

The normative plan may group conceptual layers—for example climate,
ecoregions, soil, vegetation, and habitat/range records under `EcoAtlas`—as long
as ownership, versions, IDs, conservation, and query boundaries remain explicit.

| Product | Minimum early content | Why it must be early |
|---|---|---|
| `GeologyAtlas` | crust/province IDs, stratigraphic units, major structures/intrusions, age/provenance, physical properties, and stable hydrogeologic-parent IDs/classes later aquifer units refine | Terrain, caves, aquifers, soils, mineralization, construction stone, and mining all depend on it. |
| Tagged `DepositRecord` family | 6R2 primary `parent`: stable genesis/host/event, coarse 3D mineralization envelope and conserved grade/quantity bounds; 6R4 derived `parent`: stable source/process/trap, descendant envelope and conserved transferred bounds; 7C `body`: exact child partition/geometry/alteration/exposure/realization | Lets later voxel mineralization remain consistent across saves, profiles, and neighboring regions without a partial product. |
| `GroundwaterExchangeRecord` in `HydroGraph` | stable typed kind/endpoints/flow: `RechargeZoneId` to hydrogeologic parent, reach/lake loss to a parent, parent-to-parent transfer, or parent discharge to a real surface receiver with optional stable spring ID/location | Keeps Phase 6 discharge causes durable and expressible before Phase 7 cave/aquifer realization exists. |
| `SubsurfaceAtlas` | connected volumes/edges, entrances, host geology, water/heat/chemistry/stability classes | Prevents later underground biomes and resources from contradicting surface hydrology/geology. |
| `ClimateAtlas` | seasonal climate and water balance at the chosen global/adaptive resolution | Drives biome, agriculture, rivers, snow, hazards, and species capacity. |
| `EcoregionAtlas` | labels plus continuous memberships/ecotone weights and landform context | Gives maps and content a shared vocabulary without hard borders. |
| `HabitatPatchGraph` | connected patches, capacity inputs, seasonal connectivity, stable IDs | Supports aggregate wildlife, migration, local spawning, extinction/recovery, and history. |
| Root resource endowment | immutable natural availability and sparse resource IDs; separate knowledge state | Supports fair expedition choice, discovery, trade, and persistent extraction. |
| `WorldManifest` content contract | exact worldgen recipe/data versions and stable content IDs | Generated worlds must load after definitions evolve; saves cannot silently reinterpret geology/species. |

The exact schemas can remain narrow. Reserving causal ownership and stable
identity is more important than predicting every future field.

### Systems that can remain post-Phase 10

- a broad plant and animal catalog;
- detailed succession, food webs, disease, evolution, and seasonal migration;
- globally advancing population dynamics;
- procedural mythic species/creatures;
- civilizations, culture, religion, politics, and centuries of history;
- regional economies and trade;
- prospecting/mining progression beyond minimal material realization; and
- detailed underground ecosystems and fantasy depths.

Their upstream inputs, stable IDs, persistence/version boundaries, and local
refinement hooks should exist earlier. Their simulation does not need to.

## Scientific model upgrade for Zigcraft

DF demonstrates the product hierarchy, but it is not the scientific ceiling.
The following primary and authoritative sources identify compact state and
process seams Zigcraft can borrow. They are precedents for a bounded game
abstraction, not drop-in solvers or claims that the game predicts Earth.
Unless a sentence only summarizes a cited source, the architecture and phase
choices in this section are **proposals** for Zigcraft.

### Climate and ecological regions

**Proposal:** a cheap Holdridge-style life-zone map can be useful as a debug/
regression view because the system relates biotemperature, precipitation, and
potential-evapotranspiration ratio. The cited USDA Forest Service document is a
historical regional map/application, not a production-model specification;
annual means also omit seasonality, snow, soil, and competition
([USDA Forest Service Holdridge map/application](https://research.fs.usda.gov/download/treesearch/59191.pdf)).
Production truth should instead follow the reduced architecture shared by
BIOME-family and dynamic-global-vegetation models: seasonal climate and soil
state constrain plant functional types, water/carbon balance, productivity,
competition, and disturbance
([Prentice et al.](https://doi.org/10.2307/2845499),
[Sitch et al.](https://doi.org/10.1046/j.1365-2486.2003.00569.x),
[BIOME4](https://doi.org/10.1029/2002JD002559)). A compact Limited recipe can
use monthly normals or validated harmonics and a small authored PFT set rather
than transplanting those full research models. Potential evapotranspiration
should use a declared physically motivated approximation, with FAO
Penman–Monteith as the reference against which a cheaper implementation is
calibrated ([FAO Irrigation and Drainage Paper 56](https://www.fao.org/4/X0490E/x0490e05.htm)).

An ecoregion is consequently a coherent multivariate mosaic, not a new synonym
for biome paint. The US EPA treats geology, landform, soil, vegetation, climate,
wildlife, and hydrology as jointly relevant to ecological regions
([EPA ecoregions](https://www.epa.gov/eco-research/ecoregions)). Zigcraft should
keep distinct records for climate regime, potential PFT mixture, actual cover/
successional state, ecoregion, and habitat patch; the UI can summarize them
without collapsing their ownership.

### Soil and transported parent material

Soil follows the CLORPT organizing framework: climate, organisms, relief,
parent material, and time. Both USGS and NRCS emphasize those factors
([USGS soil formation](https://www.usgs.gov/publications/soil-formation-chapter-6),
[NRCS soil facts](https://www.nrcs.usda.gov/resources/education-and-teaching-materials/soil-facts)).
For Zigcraft this means a two-to-five-horizon parametric `SoilLandscape`, with
depth, texture, organic matter, drainage/water table, fertility/base status,
salinity, and horizon boundaries derived from causal inputs. Parent material
may be alluvium, colluvium, loess, till, or another transported deposit; using
the rock directly beneath every column would erase river, wind, ice, and slope
history. Empirical texture/organic-matter relations can provide water-capacity
priors, but they remain Earth-calibrated priors rather than universal laws
([Saxton and Rawls](https://doi.org/10.2136/sssaj2005.0117)).

### Stratigraphy and genetic mineral deposits

USGS mineral-deposit models classify mineralization by geological environment,
host, structure/process, identifying characteristics, and often grade/tonnage
distributions; they support generating permissive tracts and sparse genetic
bodies rather than independent ore noise
([USGS Bulletin 1693](https://doi.org/10.3133/b1693),
[USGS assessment method](https://pubs.usgs.gov/info/assessment/)). For example,
porphyry copper is tied to convergent-margin arc magmatism and intrusions, while
placers require a mineral source, transport, and hydraulic traps
([USGS porphyry copper model](https://doi.org/10.3133/sir20105070B),
[USGS placer model](https://pubs.usgs.gov/bul/b1693/html/bull3pke.htm)).

The resulting `DepositRecord` stores mineralization, grade/quality, body,
alteration, and quantity. Whether it is economically mineable ore is a later
technology, labor, access, price, and design decision. A chronological
`GeologyAtlas` with stratigraphic units, contacts/unconformities, structures,
intrusions, and provenance supports those deposits. A reduced source-to-sink
model such as pyBadlands demonstrates the useful dependency among erosion,
transport, deposition, and basin stratigraphy without requiring Zigcraft to run
its full scientific solver
([pyBadlands](https://doi.org/10.1371/journal.pone.0195557)).

### Groundwater, caves, and underground energy

Karst is a matrix plus interconnected fissure, fracture, and conduit system,
not an isotropic worm field
([USGS karst aquifers](https://www.usgs.gov/mission-areas/water-resources/science/karst-aquifers)).
Recharge pattern, soluble rock, structure, chemistry, hydraulic gradient, and
base level influence whether solution caves form branchwork or maze-like
networks and how conduits enlarge
([Palmer](https://doi.org/10.1130/0016-7606(1991)103%3C0001:OAMOLC%3E2.3.CO;2),
[Dreybrodt](https://doi.org/10.1029/96WR01332)). Zigcraft can reduce this to
coarse aquifer units and cave potential followed by a sparse anisotropic
conduit graph from recharge/sink nodes to springs/base-level outlets, then
locally realize passages/chambers. Carbonate karst findings do not generalize
to lava tubes, sea caves, fracture/talus voids, or mines; each needs its own
genesis model.

Underground habitat is normally energy-limited. Surface carbon arrives through
percolation, sinking streams, entrances, or animals; chemoautotrophic systems
are exceptional and need an explicit geochemical energy source
([Culver and Pipan synthesis](https://doi.org/10.1093/oso/9780198820765.003.0002),
[cave energy case study](https://doi.org/10.1007/s00442-014-3042-3)). A derived
habitat complex should therefore use entrance/light distance, water,
temperature, rock chemistry, connectivity, and energy flux. Fantasy can create
other energy sources, but those become causal world records rather than a free
“lush at depth three” lookup.

### Species ranges, populations, and disturbance

The US Fish and Wildlife Service HSI framework supports selecting key habitat
components/life requisites and expressing relative carrying-capacity indices;
it is useful constraint vocabulary, not proof of actual occupancy
([FWS habitat-suitability policy](https://www.fws.gov/policy-library/870fw1)).
**Proposal:** Zigcraft should make suitability season/life-stage aware where it
changes play. Actual range also depends on origins/refugia, dispersal, barriers,
history, interaction, and energy. Seed ranges from stable origins and
expand them through connected habitat patches, then store sparse aggregate
stocks. Primary production and trophic position constrain population priors,
but Lindeman's trophic-energy framework does not justify one universal transfer
percentage ([Lindeman](https://doi.org/10.2307/1930126)). Body-mass/density
relationships are also nonlinear and differ across trophic groups, so they are
priors rather than laws
([Silva and Downing](https://doi.org/10.1086/285764)).

Potential vegetation must remain separate from the actual disturbed landscape.
LANDIS-II demonstrates a useful large-landscape abstraction: species/age
cohorts and process-specific timesteps instead of every tree and every process
at the same global resolution
([LANDIS-II](https://doi.org/10.1016/j.ecolmodel.2006.10.009)). Phase 7 can use
fixed recurrence-derived disturbance/cohort state; post-Phase-10 simulation can
advance succession, fire, flood, harvesting, and populations in `WorldSave`.

### Scale split

The recommended bounded representation is:

- kilometre-scale global/adaptive fields for geologic provinces/columns,
  seasonal climate, broad soils/PFT mixtures, ecoregions, aquifers, and
  permissive resource tracts;
- roughly 100–500 m adaptive products where needed for regolith, ecotones,
  cover patches, wetland/flood recurrence, habitat connectivity, and surficial
  facies;
- sparse vectors and implicit volumes for faults, intrusions, deposits,
  aquifers, caves, ranges, and disturbances; and
- local one-metre evaluation of strata, soil, mineralization, cave geometry,
  plants, and entities from those persisted parents.

No profile globally rasterizes subsurface voxels or builds a species-by-cell
matrix. Higher profiles partition/refine parent truth and conserve quantities.

## Procedural game-design research beyond Dwarf Fortress

The design target is not maximum simulation. It is causal systems that create
perceivable choices, stories, and beauty. Experience-driven PCG explicitly
frames content generation around player experience, while quality-diversity
work treats quality and behavioral variety as separate goals rather than one
fitness score
([Experience-Driven PCG](https://yannakakis.net/wp-content/uploads/2019/02/EDPCG.pdf),
[PCG through Quality Diversity](https://arxiv.org/abs/1907.04053)). This supports
Zigcraft's non-dominated site portfolio: fertile/flood-prone, mineral-rich/thin-
soil, forested/fire-prone, coastal/storm-exposed, cave-accessible/dangerous—not
one globally “best” embark.

The Zigcraft policies in this section are **proposals/inferences** from the
cited design research, not empirical conclusions guaranteed by those sources.

Tarn Adams and Tanya Short likewise frame procedural generation as a change to
the whole design practice, including tools and live inspection, rather than a
black-box content step
([GDC: Practices in Procedural Generation](https://gdcvault.com/play/1023372/Practices-in-Procedural)).
For Zigcraft, maps, provenance inspectors, expressive-range plots, and recorded
repairs are therefore product-development tools, not optional debug polish.

**Inference/proposal:** unbounded or uncertified search-based generation is a
poor fit for the hard 4/10/15-minute contract. Fixed-budget search is possible,
but a generic metaheuristic does not by itself prove that every valid input
reaches an adequate solution within Zigcraft's declared work and quality caps.
Use broad search in offline generator development; a shipping search, if ever
selected, must use fixed candidates/iterations, deterministic order and ties,
predeclared overflow, and the same constructive viability guarantee as any
other recipe. The current default remains construction by invariant plus fixed
candidate sets and bounded deterministic repair
([search-based PCG survey](https://doi.org/10.1109/TCIAIG.2011.2148116)).
Expressive-range analysis provides the corresponding evaluation discipline:
sample many seeds and visualize outcome distributions so biases, holes, and
parameter effects cannot hide behind favorite screenshots
([Smith and Whitehead](https://www.pcgworkshop.com/archive/smith2010analyzing.pdf)).

Two first-party design precedents refine the history boundary. Caves of Qud
generates structured historical facts and then rationalizes/narrates them,
suggesting Zigcraft should simulate what affects terrain, resources,
populations, relationships, or play while generating viewpoint-dependent prose
around those facts later
([Qud history talk](https://www.gdcvault.com/play/1024990/Procedurally-Generating-History-in-Caves)).
RimWorld's designer argues for the minimum simulation players can perceive and
for repeated competing decisions with tangible consequences
([The Simulation Dream](https://tynansylvester.com/2013/06/the-simulation-dream/),
[Decision-Based Gameplay Design](https://tynansylvester.com/2005/01/4/)).
Worldgen detail that changes no observation, choice, consequence, or future
system is debt, not depth.

The synthesis is:

> Natural law creates the world's possibilities. Explicit game design ensures
> those possibilities are legible, beautiful, strategically varied, and never
> unknowable dead ends.

That rule permits deliberate simplification and exaggeration while forbidding
hidden contradictions. Natural truth, playability policy, presentation policy,
and player knowledge remain separately inspectable.

## Fit with Limited, Detailed, and Deep world creation

**Proposal:** all three profiles must create the same kinds of foundational
truth. Detail modes refine fidelity; they must not turn ecology or mineral
resources from absent into fundamentally different worlds without an explicit
child/refinement contract. The normative plan uses a strict ladder: Detailed
reproduces Limited byte for byte before one layer; Deep reproduces both before
its own layer.

### Limited (four-minute target)

- coarse/adaptive geology, climate, soil, groundwater, ecoregion, and habitat
  products;
- sparse major deposit envelopes and subsurface structures;
- enough resource indexing to evaluate expedition sites;
- no full history simulation and no global individual organisms;
- deterministic local realization recipes for plants, animals, caves, and ore;
  and
- the complete persisted root needed to load the world later.

### Detailed and Deep

Spend additional fixed work on finer climate/topography coupling, additional
deposit/cavern detail, smaller habitat patches, richer ecotones, better soils
and disturbance, more ecological stocks, and eventually longer or more
detailed history. The Limited causal backbone, stable IDs, major drainage,
protected geological identities, and world-level resource semantics should
remain intact, as should parent site identity, macro resource/cave/water access,
hazard/affordance class, and the viable-site portfolio. Higher layers may refine
local geometry and confidence without changing the seed's strategy.

Do not use wall-clock stopping to decide which species, deposits, or historical
events exist. Each profile needs declared resolutions, pass counts, feature
budgets, and overflow behavior.

## Research and acceptance gates implied by this direction

### Biome/ecology

- No categorical height, color, material, or vegetation cliff may occur solely
  because an ecoregion label changes.
- Riparian, wetland, alpine, coastal, rain-shadow, and soil-driven communities
  must respond to their causal fields.
- Species ranges must be spatially coherent and deterministic, while adjacent
  suitable habitat remains connected across atlas/product boundaries.
- Atlas, local terrain, vegetation, wildlife availability, and expedition
  information must agree.

### Geology/resources

- Layer contacts and deposit envelopes must be three-dimensional and cross
  local tile boundaries without seams.
- Mineral families must pass host-rock/genesis gates.
- Alluvial/placer resources must follow drainage and depositional context.
- Resource quotas may repair playability only within plausible geology and
  must be separately observable from the natural candidate.
- The same world/profile must reproduce identical resource IDs and voxels.

### Underground

- Cavern placement must cite a generating mechanism or explicit fantasy
  exception.
- Surface water, groundwater, caves, aquifers, springs, and underground flow
  must not contradict each other.
- Underground habitats must use water, heat, chemistry, connectivity, host
  geology, and depth—not depth alone.
- Loading/refining a region must not reveal or regenerate a different cavern or
  deposit.

### Colony-game value

- Every expedition site should have a legible resource/hazard profile and at
  least one viable strategy, not the same inventory.
- Strategic-resource geography must generate exploration, adaptation, or trade
  choices rather than arbitrary seed failure.
- Site scoring should measure diversity of viable play styles, not merely the
  count of resources present.
- Quiet/common landscapes, exceptional landmarks, and true rare regions need
  controlled frequencies so rarity retains meaning.

### Performance and persistence

- Global ecology uses bounded aggregate records; individual entity generation
  is local or historically important.
- Preflight caps cover habitat patches, deposit envelopes, cavern graph nodes,
  species-range assignments, population stocks, and history events.
- World creation persists and validates all canonical products before the
  atlas becomes selectable.
- A save pins its world root and content manifest; later block/entity changes
  layer over that root instead of regenerating nature from current code.

## Recommended immediate planning consequences

1. Treat geology, subsurface topology, climate/ecoregion inputs, habitat IDs,
   resource truth versus knowledge, and content versioning as foundation
   decisions—not post-Phase-10 cosmetic features.
2. Do not expand the current plan into full ecology or history now. Add narrow
   world-root products and stable seams, then prove terrain/hydrology first.
3. Add a dedicated post-terrain research/implementation sequence for climate
   → soils/ecoregions → geology/resources/subsurface → habitat/population
   potential before civilization history.
4. Reserve civilization and history simulation until the natural world can
   already answer: what grows here, what lives here, what can be mined here,
   how water moves here, and why a colony would choose this place.
5. Make “beautiful” an acceptance concern: broad composition, coherent
   ecotones, vertical and riparian structure, seasonality, local landmarks,
   restrained rarity, readable maps, and attractive local realization all need
   explicit visual surveys—not just data validity.

## Source register

### Primary / first-party

- [Official Dwarf Fortress features](https://bay12games.com/dwarves/features.html)
- [Official DF Talk combined transcript](https://www.bay12games.com/media/df_talk_combined_transcript.html)
- [Bay 12 development log, 2006](https://www.bay12games.com/dwarves/dev_2006.html)
- [Bay 12 development log, 2007](https://www.bay12games.com/dwarves/dev_2007.html)
- [Bay 12 development log, 2008](https://www.bay12games.com/dwarves/dev_2008.html)
- [Bay 12 development log, 2009](https://www.bay12games.com/dwarves/dev_2009.html)
- [Bay 12 development log, 2010](https://www.bay12games.com/dwarves/dev_2010.html)
- [Bay 12 development log, 2014](https://www.bay12games.com/dwarves/dev_2014.html)
- [Current Bay 12 development/release log](https://www.bay12games.com/dwarves/)
- [Official Dwarf Fortress modding guide](https://bay12games.com/dwarves/modding_guide.html)
- [Official Classic 53.15 Linux release](https://www.bay12games.com/dwarves/df_53_15_linux.tar.bz2)
- [Official June 2008 parameter/raw snapshot](https://www.bay12games.com/dwarves/spoilers/061208.zip)
- [GDC 2016: Practices in Procedural Generation](https://gdcvault.com/play/1023372/Practices-in-Procedural)

### Natural-systems primary/authoritative sources

- [USDA Forest Service Holdridge map/application](https://research.fs.usda.gov/download/treesearch/59191.pdf)
- [Prentice et al. biome model](https://doi.org/10.2307/2845499),
  [BIOME4](https://doi.org/10.1029/2002JD002559), and
  [LPJ](https://doi.org/10.1046/j.1365-2486.2003.00569.x)
- [FAO Penman–Monteith reference](https://www.fao.org/4/X0490E/x0490e05.htm)
- [EPA ecoregions](https://www.epa.gov/eco-research/ecoregions)
- [USGS soil formation](https://www.usgs.gov/publications/soil-formation-chapter-6)
  and [NRCS soil facts](https://www.nrcs.usda.gov/resources/education-and-teaching-materials/soil-facts),
  plus [Saxton and Rawls soil-water priors](https://doi.org/10.2136/sssaj2005.0117)
- [USGS mineral-deposit models](https://doi.org/10.3133/b1693) and
  [assessment method](https://pubs.usgs.gov/info/assessment/),
  [porphyry copper model](https://doi.org/10.3133/sir20105070B), and
  [placer model](https://pubs.usgs.gov/bul/b1693/html/bull3pke.htm)
- [pyBadlands source-to-sink model](https://doi.org/10.1371/journal.pone.0195557)
- [USGS karst aquifers](https://www.usgs.gov/mission-areas/water-resources/science/karst-aquifers),
  [Palmer cave morphology](https://doi.org/10.1130/0016-7606(1991)103%3C0001:OAMOLC%3E2.3.CO;2),
  and [Dreybrodt conduit enlargement](https://doi.org/10.1029/96WR01332)
- [Culver and Pipan cave-energy synthesis](https://doi.org/10.1093/oso/9780198820765.003.0002)
  and [cave energy case study](https://doi.org/10.1007/s00442-014-3042-3)
- [USFWS habitat-suitability policy](https://www.fws.gov/policy-library/870fw1)
  plus [Lindeman trophic dynamics](https://doi.org/10.2307/1930126),
  [Silva and Downing allometry](https://doi.org/10.1086/285764), and
  [LANDIS-II](https://doi.org/10.1016/j.ecolmodel.2006.10.009)

### Procedural-design scholarship and first-party practitioner sources

- [Experience-Driven PCG](https://yannakakis.net/wp-content/uploads/2019/02/EDPCG.pdf),
  [PCG through Quality Diversity](https://arxiv.org/abs/1907.04053),
  [search-based PCG](https://doi.org/10.1109/TCIAIG.2011.2148116), and
  [expressive-range analysis](https://www.pcgworkshop.com/archive/smith2010analyzing.pdf)
- [Caves of Qud history talk](https://www.gdcvault.com/play/1024990/Procedurally-Generating-History-in-Caves),
  [The Simulation Dream](https://tynansylvester.com/2013/06/the-simulation-dream/),
  and [Decision-Based Gameplay Design](https://tynansylvester.com/2005/01/4/)

### Secondary / qualified

- [Dwarf Fortress Wiki: advanced world generation](https://dwarffortresswiki.org/index.php/Advanced_world_generation)—useful
  current operator reference, but the page warns that some material was
  migrated from older versions.
- [Dwarf Fortress Wiki: biome](https://www.dwarffortresswiki.org/index.php/Biome)—useful
  terminology/embark reference; exact closed-source thresholds were not relied
  upon here.

## Bottom line

Dwarf Fortress's north-star value is not maximal simulation everywhere. It is
the integrity of a world whose geography, resources, inhabitants, history,
expeditions, and later player actions all point back to shared persistent
facts. Zigcraft should build that integrity earlier, use stronger natural
models for terrain, geology, hydrology, ecotones, deposits, and underground
systems, and then add deliberate game-design policies as visible layers.

The desired end state is a world that feels beautiful before it is useful,
useful before it is exploited, and still remembers what happened after the
colony changes it.
