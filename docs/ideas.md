# What OdinCraft is meant to become

Distilled from the idea documents of every earlier attempt (October 2024 to September 2026). The sources are in `reference/`. This is the destination as the owner has described it over two years. It is reference, and nothing here is a commitment until `open-decisions.md` says so.

## The idea

A block world that feels like a real place: formed by geology, water, climate and living things, explored on foot in first person, and understood through inspection as deep as Dwarf Fortress. Exploration comes first. The world is later the stage for a colony game, and later still an original Tolkien-like fantasy world.

The first note (2024-10-17) names the ingredients: Dwarf Fortress, Minecraft-style procedural worlds and RimWorld, with a top-down view of a voxel world that has real height, first person as a second view, and AI agents giving the world depth.

## Pillars that held across every attempt

1. **The landscape is the protagonist.** The game is worth playing when a walk through it is interesting: enclosed woodland, water, exposed rock, a valley that changes shape, a view from high ground, quiet stretches between landmarks.
2. **Realism comes from causes.** A river is a bed, banks, a valley, a discharge and a destination. Mountains belong to ranges. Plants grow where soil, water and climate allow. Names such as "biome" summarise that truth.
3. **Blocky surface, real geography.** One block is one metre. The surface stays recognisably voxel; the landforms are judged against real terrain.
4. **A finite world made before you enter it.** Generated once from a seed, kept, and never regenerated behind the player's back.
5. **Causes can be inspected.** Dwarf Fortress depth of information with modern readability: why is this rock here, where does this water go, why this forest.
6. **Long views and smooth movement.** Stand on a mountain, see the valley run to the coast, and walk there without a hitch.

## What the owner has asked for, in their words or as recorded

- "I like the real images, as well as the reterraforged ones by far the most ... goal is ultra realism." (2026-07-08, on the reference board described in `reference/README.md`)
- Rivers "looked completely terrible and unrealistic" (Zigcraft Neo), and later "blue ribbons that sit on the terrain" (Neo v3 review).
- "Incrementally add features (never multiple at once!)"
- "The benchmarks stopped being able to test actual gameplay."
- Reported failures to fix (v4 foundation plan, 2026-09-05): performance; generation and loading of new terrain; near/far transitions; horizontal and vertical world limits; terrible UI; terrain that looks insufficiently real and is boring.
- A place worth hiking through, with Jūniko in Japan as the reference for connected landscape experience: lakes in forest, waterfalls, distinctive rock, cliffs and valleys (2026-09-06).
- Forest with overlapping crowns, branching and leaning trunks, small trees under mature ones, dense waterside vegetation, irregular openings (the woodland-lake photograph on the reference board, `reference/README.md`).
- On 2026-09-11 the owner reported that nothing generated looked like a real mountain. On 2026-09-27 the owner called the v4 world uninteresting at walking scale.

Targets the owner accepted for v4, recorded here as the long-term scale: a world about 1,000 km wide, about 10 km of visible terrain, 120 FPS at 2560 × 1440 on an M3 Max, world creation within four minutes, deep underground and high mountains with no fixed height ceiling.

## Feature intentions

Grouped by how far they are from a first playable. The note after each says how far any earlier attempt got.

### A place worth walking

- Rivers formed with their valleys: bed, banks, floodplain, confluences, outlets. *Attempted in every version; never accepted.*
- Lakes as landforms, including clusters of small forest lakes and larger valley lakes, with real outlets. *v4: approximate, flat and shallow.*
- Waterfalls, cascades, gorges and rock structure where water crosses resistant rock. *v4: one fall passed every physical check and was rejected on sight as an excavated canal.*
- Connected three-dimensional places with several things to discover at different heights: a waterfall amphitheatre, a jointed gorge with a tributary fall, a woodland junction of rock and water. *v4: designed on paper in `reference/odincraft-v4/explorable-places-design.md`.*
- Overhangs, undercut walls and caves that open to the surface. *Never built; v4 stored one height per column.*
- Mountains that read as mountains from the ground, with wooded foothills, bare outcrops and high basins. *v4 revision 15 matched real relief statistics at large scale.*
- Forest structure: canopy, subcanopy, saplings, shrubs, ground plants, deadwood, reeds; trees as solid blocks with branching forms that vary by species, age and growing space. *v4: 14 species and 16 communities, simple forms.*
- Natural borders between habitats. *v4: experimental.*

### The game around it

- Walk, sprint, jump and fly with collision. *Built several times.*
- Aim at a block, identify it, break it; edits persist. Placing blocks. *v4: breaking built; placing never built.*
- Inspect the causes of what you are looking at. *v4: basic overlay.*
- A top-down elevation-slice view of the same world, which is also where the colony game would live. *v4: built.*
- Seasons, weather and a day cycle. *v4: seasonal foliage and snow only.*
- Front door: Home, New World with honest progress and cancel, an atlas of the finished world, choosing an expedition site, pause, save, Continue. *Built in Neo v3, OdinCraft v2 to v4.*
- Saves that keep the generated world immutable and store play on top of it, written atomically. *Built in OdinCraft v2 to v4.*
- Music in the menus. *OdinCraft v1.*

### The large world

- Tectonics and crust, uplift, erosion over geological time, sediment. *v4 revision 15: good against real California, Japan and Alps data.*
- Climate, a monthly water balance, groundwater. *v4: approximate.*
- Geology you can dig into: strata, minerals, deposits, aquifers, caves, ore bodies. *v4: declared priors, artificial banding.*
- Soils and plant succession. *v4: approximate.*
- Glacial landforms. *Researched only.*
- Terrain visible to about 10 km with stable near/far transitions, loaded without hitches. *Neo v3: 8.45 km at 62 to 68 FPS. v4: 10 km drawn, pacing never accepted.*

### The living world, the colony and the fantasy

- Animals, habitats and species ranges; resources that matter.
- Settlements, economy, transport; civilisations and history that arise from the geography.
- A colony game with Dwarf Fortress depth and RimWorld readability. v4 holds dwarf character concepts in its assets.
- AI agents and narration.
- An original fantasy world of convincing scale, with fantasy biomes and creatures, built on geography that stays understandable so authored influences can change it coherently.
- Multiplayer was mentioned once as a possibility.

## Visual targets

The board (described in `reference/README.md`, not redistributed) ranked them: real terrain first, then ReTerraForged, then Tectonic, with vanilla Minecraft as the floor. The single primary reference is `reterraforged-ridge-vista.jpg`. The woodland-lake photograph is the forest reference.
