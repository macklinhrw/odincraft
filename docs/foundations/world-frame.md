# The world frame

How a world resolved to 16 m and expressed in 1 m blocks grows from one 6 km island to an archipelago and then to about 1,000 km. Numbers are marked (measured), (sourced) or (guess).

**One measurement made for this design.** Scratch copies of the game with only `LAND_N` changed formed the land in 0.9 s at 512² (8 km square), 4.4 s at 1024² (16 km) and 20.2 s at 2048² (33 km), with peak memory of 40, 96 and 304 MB (measured; one thread, seed 7). That is 32 to 43 ms of one core per km² of land and about 72 bytes of working memory per 16 m cell. The 33 km island grew one thin range across a big lowland, because the uplift pattern in `land.odin` is written in absolute metres (measured, map viewed).

## 1. What it gives the player

From a high point on one island you see the next on the horizon, and when you cross to it the coast, rock and skyline are of another kind for a reason you can learn: a young arc volcano, an old granite island worn low, limestone with no rivers. Distant land sinks under the sea's curve and haze instead of ending at a draw distance. Land within reach is never a placeholder: it was formed at 16 m by the same simulation as today's island. For the colony game, the world is a finite map of named islands and regions, each with a known rock story, climate and sea-level history, so a site's character, neighbours and the cost of reaching them follow from geography.

## 2. Questions it answers

| Provides | To |
|---|---|
| Which region a point is in, with its kind, origin and outline | Everyone; the generator's dispatch |
| World fields on 2 km cells: plate setting, crust age, uplift rate and history, province (rock story), relative sea level, sea depth, sea-level temperature, rain, prevailing wind, wave exposure | Land forming, rock, climate, coast, plants |
| Each region's handoff record: outline, uplift pattern, rock story, climate values, sea-level curve, base level at each outlet, inflow at each inlet, seed | Land forming (`land.odin`) |
| The ground at 128 m to 1 km cells, and a stand-in for unformed regions | Engine far levels |
| Coordinate rules and the edit layer | Engine, rivers, water, player |

| Needs | From |
|---|---|
| Rock story rows: which rocks and what structure each province carries | Rock designer |
| How climate inside a region follows from the values handed down | Climate designer |
| A summary of each formed region: hypsometry, rivers and lakes with areas, highest point | Land and river forming |
| More levels of detail; a curvature drop in the vertex transform | Engine |

Added to the vocabulary. Fields: plate setting, crust age, uplift rate, relative sea level, province. Features: plate, plate boundary, hotspot, island, landmass, region, basin unit.

## 3. Foundational decisions

### D1. Seams go where little crosses: the sea, then drainage divides.

*Recommendation.* Each rung forms the land over its whole extent at its own cell size; the rung below refines it inside units whose edges carry almost no flux, with the values on those edges pinned from above. An island is a unit, and the sea is a free seam. A landmass larger than one region is cut along drainage divides, so water crosses a unit's edge only at its outlet (and, for a reach of a trunk river, its inlet), and both points take level and inflow from the rung above.

*Alternatives.* Square tiles cut across valleys: zigcraft found a halo "truncates upstream contributing area, changes basin spill decisions" and needed a reconciliation machinery to repair it (`future-phases-research.md`, "Lock: hydrology is larger than a RegionTile"). Overlapping windows blended at their edges are the recorded failure, disagreeing "by hundreds of metres at divides" (`lessons.md`). One 16 m simulation of a whole 300 km landmass is exact but costs about 45 minutes of one core (extrapolated, guess).

*Why expensive later.* Products, river records and streaming are all keyed by the unit.

*Changed by step 21 (2026-11-16, `interesting-world/notes/continents-forming.md`):* pinning failed (step 20), and so did every way of forming a landmass's long phases in pieces. What holds: **the landmass is formed whole through its 64 m phases (the coarse stage), and only the 32 and 16 m phases in pieces**, cut along its 64 m drainage and formed one after another, downstream first, each holding its formed neighbours' land through time at the cut and forming 6 km past it toward the rest (`continents.odin`). The seam is then not a divide pinned from above but the earlier piece's own land, which the later one adapts to.

### D2. A region is an island up to about 33 km across, or a basin unit of that size.

*Recommendation.* Cap a region at 2048² cells of 16 m: 33 km square, 20 s on one core (measured). An island that fits is one region, formed as today. A larger landmass is formed whole at 64 m, then cut by the Pfafstetter scheme, which splits a basin along its main stem into its four largest tributary basins and the five reaches between them, recursively, until each piece fits ([Verdin & Verdin 1999](https://doi.org/10.1016/S0022-1694(99)00011-6), sourced). Each piece is refined through 32 m and 16 m with its divides pinned to the 64 m solution, its outlet pinned to the trunk river's level, and a reach's upstream river entering as a point inflow. Today's schedule already spends most of its steps at 64 m, so a seam can disagree only by what the last two stages cut: tens of metres (guess, tested in Stage 2).

*Alternatives.* A 66 km cap costs about 90 s and 1.2 GB per region (extrapolated); worth it only with parallel routing ([Barnes 2016](https://doi.org/10.1016/j.cageo.2016.07.001)). Islands only: no river longer than about 30 km, no deltas.

*Why expensive later.* The cap sets the largest river and lake one simulation holds, the memory budget, and the shape of every record.

*Changed by step 21 (2026-11-16):* a piece of a landmass holds about 300 km² of land, on a square window of its lattice round it; the landmass pass has no cap but time and memory, since it cannot be cut. It is the one serial job: 37,555 km² took 251 to 260 s; the known world's largest landmasses, 317,000 to 380,000 km², about 35 to 42 min and 8 to 16 GB as a square grid, until the flood runs in parallel.

### D3. A region is a pure function of the seed and its record. Form near first, the rest in the background, and re-form rather than store.

*Recommendation.* Forming reads only the region's record and the seed hashed with its id, never another region's fine result, on one thread, so the result does not depend on order or core count. At creation: the world rung (about 1 s, guess), then every region within 64 km of the start, then enter. The rest form in the background on three low-priority threads and are kept as summaries of a few kilobytes, so every region is formed once at creation and the seed fixes the world. `--map` still forms one region in a second. A region the player comes within 64 km of is formed again, identically. No disk cache until saves exist.

*Alternatives.* Everything held in memory at 16 m: about 3.5 GB for 5% land at a slim 12 bytes a cell (guess).

*Why expensive later.* Once forming reads a neighbour's result or depends on order, determinism and parallel forming are both lost.

*Changed by step 21 (2026-11-16):* a piece of a landmass is a pure function of the seed, the landmass's coarse stage and the bands of its neighbours earlier in a fixed order, which are pure functions in turn. So it does depend on order, but the order is the world's, not the player's: forming any piece forms what it waits on first (a median of 4 pieces on seed 1's landmass), and it comes out the same whichever piece or site was reached first. The coarse stage is kept on disk beside the known world. The stages, against the owner's goal of 2026-11-16 of 10 minutes for the whole world: the plates (2.5 s); every landmass's coarse stage (today only where under 8 min; the rest needs the parallel flood); the pieces round the start or a chosen site before entering; the rest beside play or when visited.

### D4. The world rung is records plus a 2 km raster, from a cheap stand-in for plates.

*Recommendation.* Six to twelve plates as jittered Voronoi cells with velocities, each boundary classed as converging, spreading or sliding from the relative motion across it, as TerraFirmaCraft's region pipeline does on 12 km cells (`notes/minecraft-family.md`). From those: island arcs set back from converging edges, fold belts and fault blocks, rifts, one to three hotspot chains aging along the plate's motion, quiet platforms and old shield. Islands are records (centre, size, orientation, kind, age) with sizes from a power law (Korčák's law; exponent a guess). The raster is 500² cells, about 6 MB (guess). One relative sea-level curve serves all regions, shifted by each region's uplift. No erosion at this rung until a landmass exceeds one region.

*Alternatives.* A plate simulation (v4's crust model; [Cortial et al. 2019](https://doi.org/10.1111/cgf.13614)): much more code for causes a player meets as "this is an arc volcano". Hand-placed islands: nothing to inspect.

*Why expensive later.* Every region's kind, rock and uplift derive from it.

### D5. f64 metres in the world, i32 blocks, everything stored relative to its region, the GPU relative to the eye.

*Recommendation.* Most of this holds: the camera is f64 and chunks reach the GPU relative to the eye (`render.odin`). What does not: land and river grids assume the region is centred on the origin (`LAND_SIZE/2` in `land.odin` and `rivers.odin`), and the river ribbon is one strip of absolute f32 positions, which at 500 km step by 3 cm (arithmetic) and would shimmer against the banks. Each region stores positions relative to its origin (under 2 mm of error at 33 km) and the ribbon becomes a strip per region, positioned like a chunk. i32 blocks reach 2,147 km, so blocks, chunk keys and edits need no change.

*Why expensive later.* The recorded pitfall (`lessons.md`), and every new system copies whatever convention exists when it is written.

### D6. Edits are a sparse layer over a world that is never modified.

*Recommendation.* Make today's rule (`world.odin`) the law: an edit is (x, y, z, block) in absolute i32 coordinates, filed by chunk, later saved by region. Region products never change in play; water already restarts from the land's water (`adr/0004`).

*Why expensive later.* Anything written into the generated world is lost when a region is re-formed (D3).

### D7. The generator answers out to 1 km cells, the world is round, and far land is a stand-in until formed.

*Recommendation.* Add levels at 128, 256 and 512 m; with 17 chunks a side they reach about 32, 65 and 131 km. A formed region answers from its own averaged grids (`adr/0001`); an unformed one from its record: outline plus its kind's typical height against distance from the coast. Drop each vertex by d²/2R with R ≈ 7,400 km, the Earth's radius lengthened for ordinary refraction (sourced, standard surveying): 15 m at 15 km, 61 m at 30 km, about 280 m at 64 km. Within 64 km every region is formed (D3), so the stand-in is only seen as a coarse summit over the horizon, and swaps happen beyond 64 km.

*Alternative.* A flat world shows a 300 m island in full at 100 km, so the stand-in would need real detail. *Why expensive later.* Curvature decides what far levels show; every view the owner judges is calibrated on it.

## 4. The kinds

The kinds here are kinds of region. Two kinds differ when they differ in uplift pattern, rock story or coast history, and the owner can tell them apart in a grey relief map and, on foot, within ten minutes of landing. Climate is the climate designer's axis; the world rung only places each region in it.

| Axis | States | Seen on foot as |
|---|---|---|
| Size | islet, small island (today, 28 km²), island, large island, landmass: 5 | whether the sea is always in view; how big rivers get |
| Tectonic setting | arc, hotspot, fold belt, fault blocks, platform, old shield, accretionary wedge, sliding sliver: 8 | the skyline: cone, dome, parallel ridges, tilted blocks, flat tops, low knobs |
| Stage | young, mature, worn down: 3 | sharp or rounded; depth of valleys and soil |
| Sea-level story | drowned, steady, raised: 3 | branching inlets, beaches, or terraces above the shore |
| Ice history | none, mountain glaciers, ice cap: 3 | V or U valleys, cirque lakes, fjords |
| Exposure | open ocean, inner sea: 2 | cliffs and stacks, or beaches and calm shores |

Counts: today 1 kind; Stage 0 4; archipelago of 10 to 30 islands 10 to 14, no two neighbours alike; wide world 24 to 30. Against the benchmarks: Vintage Story has 6 geologic provinces; TerraFirmaCraft's region pipeline feeds 125 place-scale landforms; Dwarf Fortress has 51 biomes with climate folded in.

| Kind | Host (world fields) | Handed down | What the player sees |
|---|---|---|---|
| Young arc volcano | arc, crust age < 0.5 Myr | steep cone, hard young rock | one cone, radial gullies, black sand, lava lobes in low cliffs |
| Young hotspot shield | hotspot, < 1 Myr | broad dome, porous rock | 5° to 7° slopes, lava fields, almost no valleys |
| Eroded shield | hotspot, 1 to 5 Myr, wet windward | dome, uplift stopped | amphitheatre valleys, knife ridges, spring-fed falls; dry leeward |
| Raised-terrace island | forearc, uplifting fast | uplift pulses against the sea curve | flat terraces stepping up from the shore |
| Fold-belt ridges | fold belt, steep dip | ridge, tilted beds | parallel ridges, rivers on soft beds, headlands and bays |
| Scarp and vale | platform, gentle dip | broad tilt | one long scarp, a long back slope, slides under the cap |
| Flat-bedded plateau | platform, level beds | uniform uplift, then none | flat tops, stepped valley sides, cliffs round the coast |
| Basalt trap | flood basalt | level lava beds | stepped hillsides, column cliffs, sea caves |
| Cap-rock slide island | hard cap over weak beds | tilt plus slide events | slipped blocks, hummocks and ponds below a scarp |
| Granite domes | exhumed intrusion | dome, massive rock, wide joints | bare domes, tors, boulder shores |
| Worn glaciated shield | old shield, ice cap | almost none, many hollows | low rocky knobs, countless lakes, ragged coast |
| Limestone platform | platform, carbonate | low uplift, dissolving rock | sinkholes, no surface rivers, shore springs, cave mouths |
| Fault-block island | extending crust | one tilted block | a straight fault scarp on one side, a long slope on the other |
| Sliver island | sliding boundary | long narrow ridge | a straight fault valley, streams bent across it |
| Mélange hills | accretionary wedge | mixed hard and soft blocks | chaotic hills, landslides, odd hard knobs |
| Ria island | non-glacial, drowned | mature relief, sea rise | inlets up drowned valleys (today's island) |
| Fjord coast | glaciated, drowned | high relief, ice history | deep steep inlets, hanging valleys with falls |
| Barrier coast | platform, wide sandy shelf | almost none | barrier islands, lagoons, dunes |
| Collision range | fold belt, landmass, high uplift | strong ridge, glaciated tops | high peaks, deep valleys, cirque lakes |
| Delta lowland | landmass, big river mouth | subsiding, sediment | flat land, levees, side channels, marsh |
| Atoll | hotspot remnant in warm water | reef ring | sand and reef round a lagoon; only if the latitude allows coral |

## 5. How it works

**World rung.** Voronoi plates and boundary classes; island records along arcs, hotspot tracks and shelves; kind chosen by explicit rules from setting, age, latitude and sea-level story, the TerraFirmaCraft `ChooseBiomes` pattern (`notes/minecraft-family.md`). Climate values from latitude, a lapse rate and an upwind sweep for rain, as v4 did with results inside the real range (`relief-compare-findings.md`). Sea level: one post-glacial rise of about 120 m over 20,000 years (sourced, the standard eustatic figure), which drowns valley mouths unless a region rises faster. About a second (guess).

**Landmass pass**, only for a landmass larger than one region: `land.odin`'s stream-power forming at 64 m over the whole landmass from the world rung's surface and uplift (v4 revision 15 showed this matches real relief statistics), then the Pfafstetter cut. An 80,000 km² landmass at 64 m is about 3,900² cells, roughly 80 s on one thread (extrapolated, guess).

**Region rung.** Today's `land_form` with its constants replaced by the record: outline, uplift pattern scaled to the region, uplift history, rock story, sea-level curve as base level, pinned edges and point inflows for basin units. 0.9 s for today's island, 20 s at the cap (measured). Kept: elevation pyramid, slope, wetness, drainage, rivers and summary, region-relative, about 12 bytes a cell (guess; today keeps the working grid at about 70).

**Dispatch.** `ground(x, z, cell)` finds the region through the 2 km raster, which lists the region ids touching each cell. Island grids overlap only at sea: land wins, and two sea floors blend by distance. Basin units partition the land exactly; sampling across a divide reads the neighbour, so a chunk waits until every region under it is formed, which is rare with formation at 64 km and chunks at 256 m.

**Budget for the wide world** (32 to 43 ms per km² of land on one core, measured; ten threads; island counts guessed from the power law):

| | Land | Shape | Wall time to form all | In 4 minutes? |
|---|---|---|---|---|
| A | 2%, 20,000 km² | ~60 islands over 1 km², largest ~2,000 km² | ~1.2 min | yes |
| B | 5%, 50,000 km² | ~150 islands, largest ~10,000 km² in basin units | ~3.5 min | barely |
| C | 15%, 150,000 km² | an 80,000 km² landmass and islands | ~11 min | background only |
| D | 30%, Earth-like | a continent with 50,000 km² basins | ~20 min | background only |

## 6. Growth path

**Stage 0, on today's island.** Move the constants in `land.odin` that say what kind of island this is (uplift axis, width, rate and duration, `DROWN`, erodibility, shore shape) into a region record, with the uplift pattern relative to the region's size, and add four kind rows today's knobs can already make: today's ridge island; a young cone; a worn-down island whose uplift stopped two million years ago; a raised island where the sea fell and left steps. `--kind=` picks one. About 70 lines in `land.odin` and `main.odin` (guess). In the same change, store land and rivers relative to a region origin and add `--origin=` to move the island to 500 km (about 20 lines in `land.odin`, `rivers.odin`, `render.odin`). The owner looks at four `--map` images, then a `--shot` beside a river at 500 km that must match the same shot at the origin.

**Stage 1, the archipelago.** Ten to thirty islands in a sea about 150 km square, placed by a small stand-in (one arc, one hotspot chain, one platform); dispatch; levels at 128 and 256 m; curvature; background forming. The owner judges the next island on the horizon from a summit, and a change of kind on crossing. Bench frame pacing at one island's edge looking at another. Start only after rock, cliffs and the first plant communities are accepted on one island (`interesting-world.md`, steps 1 to 3): an archipelago of dull islands is v4's failure at a larger size.

**Stage 2, the wide world.** First the seam test on today's island: form it whole, then as two basin units cut on its 64 m solution with the divide pinned, and show both maps with the seam drawn and the largest height step along it. Only if the owner cannot find the seam: the landmass pass and Pfafstetter cut, then the 1,000 km world rung, summaries and the 512 m level.

**Not yet, with triggers.** ~~A plate simulation: the stand-in makes a contradiction the owner can see.~~ Withdrawn by the owner on 2026-11-15: a history of moving plates that makes the continents and islands is the goal (`foundations.md` section 8, step 22). Erosion at the world rung: a landmass larger than one region. A disk cache: saves exist, or a re-form is noticed. Parallel routing: a landmass pass over two minutes. Ice forming: a fjord or cirque kind is chosen. Levels beyond 512 m: curvature and haze shown to need them.

## 7. Risks and known failures

| Recorded failure | Avoided by |
|---|---|
| Ground under the player built last; scale fixed too early | Stage 0 touches only today's island; Stage 1 waits until one island is good on foot. |
| A coarse-to-fine gap filled with generic noise | Land within 64 km is always formed at 16 m; the stand-in is only a far silhouette. |
| Patches disagreeing at edges by hundreds of metres | Seams only at sea or along pinned divides, and the divide seam is tested on today's island first. |
| One mountain grain per world | Each region's structure comes from its own plate boundary. |
| f32 far from the origin | D5, checked with a shot at 500 km in Stage 0. |
| Oatmeal at archipelago scale | Kinds come from causes in coherent groups (an arc, a platform); neighbours must differ; the owner judges a grey map of the group. |
| Constants in absolute metres (measured: a 1 km range on a 33 km island) | Uplift patterns relative to region size from Stage 0. |
| Lazy forming eroding "made before you enter" | Every region formed once at creation; forming is pure and order-free. |

## 8. Decisions for the owner

1. **What "1,000 km wide" means.** *Recommendation: an ocean with islands, about 5% land (option B), and no landmass over about 10,000 km² until the seam test passes.* That is about 1,800 of today's island, and creation still fits four minutes. *Overruled by the owner on 2026-11-15:* one cohesive simulated world with continents and islands where the simulation makes them, never an ocean of islands.
2. **Where the world sits.** *Recommendation: about 36° to 45° north with a warm current along the south, after Japan from Kyushu to Tohoku:* beech in the north, evergreen laurel forest in the south, glaciers only on the highest northern peaks, no atolls. Choose a tropical south edge if atolls and coral limestone are wanted.
3. **A round world.** *Recommendation: yes, drawn to about 64 km.*
4. **Forming.** *Recommendation: the start and 64 km around it before entering, the rest in the background, the atlas waiting for every summary.*
5. **Sea-level history.** *Recommendation: one shared rise of about 120 m since the last ice age,* so most coasts are drowned valleys and terraces mark where land rose faster.
6. **When to start the archipelago.** *Recommendation: after rock, cliffs and the first plant communities are accepted on one island.*

## 9. Not verified

- Scaling beyond 2048², and on other seeds and kinds; only seed 7 was measured.
- That a divide pinned to a 64 m solution leaves no visible seam after the 32 m and 16 m stages. This is the design's largest open risk.
- The landmass pass time, 12 bytes a cell, the world rung's one second, and whether three background threads coexist with chunk building under the 12.5 ms frame target.
- Korčák's exponent and the island counts from it.
- That curvature and haze hide the stand-in well enough; the 64 km radius depends on it.
- The Pfafstetter, Barnes and Cortial papers were not re-read for this design; TerraFirmaCraft and v4 results are as recorded in the project's notes.
