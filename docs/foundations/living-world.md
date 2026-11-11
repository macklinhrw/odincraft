# The living world: animals, peoples, history and the fantasy to come

Almost all of this is years away. What matters now is the few rules the natural world must follow so this layer can be added without rebuilding it, and one small first piece. Numbers are marked *(measured)*, *(sourced)* or *(guess)*.

## 1. What it gives the player

On foot, the land shows that something lives in it and has lived in it. A deer trail leaves the river at a gravel ford and climbs through the beech to a dry shoulder. Gulls work the sea cliff; a trout holds in the pool below a step. On a spur above a harbour sits a ring of tumbled stone where a fort was, and an old track runs from it through the pass. Each has a reason the player can inspect: water, shelter, a crossing, good stone, a date. In the colony game the same record becomes a site's trade-offs: the ford everyone used, fertile ground that floods, a ruin that says who failed here and why.

## 2. Questions it answers

What this system provides:

| Provides | To |
|---|---|
| **Field: crossing cost**, how hard a metre of ground is to cross on foot | Its own trails and history; later the colony's travel |
| **Features: trail, ford, road, settlement, mark** (ruin, wall, quarry, cairn, harbour), each dated | Place rung (expressed in blocks), inspector, plant system (trails and clearings open the canopy) |
| **Feature: event**, a dated record of what happened, where, from what cause, involving whom | Inspector, later narration and colony |
| **Kinds: animal, people, mark, influence**, and which animals are on which island | Place rung |

What the land must expose for it, who should provide each, and the cost of reserving it now:

| Needed | Provider | Cost to reserve now |
|---|---|---|
| Wood by species and age | Plant system: stand features with kind and age | None beyond its own plan |
| Stone by kind, at the surface and at depth | Rock system: the rock function it already proposes | Rock kinds carry a name and a building quality: one column in the table |
| Ore | Rock system, as deposits hosted by rock kind | Nothing now. Defer until digging has a purpose |
| Clay, fertile soil | Soil system: soil kind and depth | Floodplain fines and deep loam as two soil kinds |
| Fresh water and its reliability | Water system: river reach with drainage area; lake; spring | Stable identities on reaches and springs |
| Flood danger | Water system: height above the nearest channel | One derived field, cheap from the routing it does |
| Landslide danger | Rock system: strong rock over weak, slope | Landslide features with ages |
| Ease of crossing, natural routes | This system, from slope, wetness, plant density, cliff bands, water depth | One function |
| Passes | Land forming: saddles on drainage divides | Keep the divides it already finds |
| Harbours | Coast system: sheltered coast stretch with depth | A shelter value on each coast stretch |
| A record of time | Every system that forms a feature | An age on each feature and one event list (decision 3) |

Additions to the shared vocabulary: field **crossing cost**, field **height above channel**; features **trail**, **ford**, **mark**, **event**; kinds **animal**, **people**, **mark kind**, **influence**.

## 3. Foundational decisions

**1. Two doors only: causes enter before the land forms, marks after it.**
*Recommendation.* Anything living or fantastic changes the world in one of two ways. A *cause* adjusts a field before the region forms: extra uplift under a raised mountain, a rock no tectonics made, a climate colder than its latitude, a soil poisoned at a source. The simulation then makes the consequences: a raised mountain still erodes. A *mark* is a feature placed on the formed land and expressed at the place rung, as rivers are cut by design (`adr/0003`). Nothing edits the formed heightfield afterwards.
*Alternatives.* Stamping settlements and fantasy shapes on finished terrain; re-forming the land after each era.
*Why expensive later.* If land forming takes uplift, rock and climate from constants, each fantastic influence means surgery in `land.odin`. If it reads them as functions of position that a list of features (empty today) may adjust, the fantasy layer is rows.

**2. One crossing cost and one route tracer, shared by animals, people and colonists.**
*Recommendation.* Crossing cost rises with slope (sharply past about 25°, a wall past 45°, *guess*), wetness and standing water, plant density, and river depth and width; fords are where it dips. Trails, roads and long-distance colony travel all trace least-cost paths over it, and each use makes a line cheaper, so a road follows an old trail. Natural routes are what the tracer finds: valley floors, saddles, fords.
*Alternatives.* Separate pathing per system; paths placed by noise.
*Why expensive later.* If animals, history and colonists disagree about easy ground, the trail you follow will not lead to the ford the history used.

**3. Time is recorded: every formed feature carries an age, and the world keeps one list of dated events.**
*Recommendation.* A world has a present. Each feature that something formed (landslide, lake, stand, trail, ruin) carries its age in years and the event that made it. One append-only list holds natural and human events alike: kind, year, place, cause, actors. Disturbance age is read from it. The inspector, narration and the colony all read it.
*Alternatives.* Undated features; a history store added later.
*Why expensive later.* Dating features afterwards means re-deriving why each is where it is. Cost now: an integer per feature and a small array. The first landslide (interesting-world step 4) should be the first dated record.

**4. History is a short pass of decisions over the formed land that generates facts. It does not simulate people.**
*Recommendation.* For each era (three to five per island, *guess*), score sites by suitability, found settlements at the best unclaimed ones, trace routes between them, then end some by a cause the land supplies: the harbour silted, the slope slid, the soil wore out, a neighbour took it. Each step writes events and marks.
*Alternatives.* Dwarf Fortress's simulation of figures, wars and economies: a 1,000-year medium world took about 27 to 28 minutes in 2022 *(sourced, Bay 12 log via `dwarf-fortress-worldgen-research.md`)*, far over four minutes.
*Why expensive later.* The shape of the record (eras, sites, routes, causes of ending) is what narration and the colony will read. A pass of decisions can deepen later; a simulation cannot be made cheap.

**5. Animals are kinds with hosts. Populations are numbers, and individuals exist only near the player.**
*Recommendation.* An animal kind is a row: host conditions over fields and plant communities, a silhouette, a behaviour (herd, solitary, flock, perch, school), the signs it leaves, and how it reaches islands (flies, swims, walks, carried by people). Which kinds live on which island is decided once, at world creation. Abundance is a number per kind per island or habitat. Individuals are made near the player from (kind, place, time) and forgotten when the player leaves; only a later save layer remembers what was hunted.
*Alternatives.* Individuals simulated everywhere; animals spawned per chunk with no range, as on RimWorld maps.
*Why expensive later.* Presence per island is part of a world's identity. Rolled per chunk, an archipelago cannot have "no deer on the outer islands, but seals", the cheapest variety the world will ever get.

**6. Suitability is a set of functions over fields. It is never stored as a map.**
*Recommendation.* Fresh water, fertile soil, shelter, harbour, defensibility, flood and slide danger are each a function over shared fields; a people kind is a row of weights over them. A baked grid would freeze yesterday's fields; functions follow every improvement in rock, soil and water for free.

**7. Names attach to features, and come from the history.**
*Recommendation.* Any feature may carry a name drawn from the event that made it or the people who used it ("the Slip", "Harran's Ford"), generated in the history pass so the two agree. Names invented earlier would contradict it.

## 4. The kinds

**Axes owned:** which animals live here (by island and habitat); animal signs; the human past (era, people, use); route use; fantastic influence.

**Two kinds differ** when a player on foot sees a different place, silhouette or behaviour, or finds a different sign. Two deer with different names in the same wood with the same habits are one kind; DF's 72 trees in about six shapes *(sourced)* is the warning.

**Targets**, all *guess*, against DF's hundreds of creatures and RimWorld's 5 to 36 animals per biome *(sourced)*:

| | Today's island | Archipelago, 10–30 islands | Wide world |
|---|---|---|---|
| Animal kinds | 1 at Stage 0 (as trails); 8–12 later | 40–60, 6–25 on any island | 150–250 |
| Animal sign kinds | 1 | 8–12 | about 20 |
| Settlement and mark kinds | 0 | 12–18 | 40–60 |
| People kinds | 0 | 1–2 (one people in two eras reads as two) | 5–10 |
| Influence kinds | 0 | 0 | 6–15 |

**Example rows.** **[A]** archipelago stage, **[W]** wide world, **[F]** fantasy layer; unmarked rows suit today's island.

| Kind | Host conditions | What the player sees |
|---|---|---|
| Deer, as trails | Beds on dry, gentle, wooded, humped ground; drinks at a reach | Bare one-block paths converging downhill on fords and gravel bars |
| Gull and fulmar | Coast stretch with a cliff band, high exposure | Birds wheeling and settling on ledges; white streaks down the face |
| Heron | Lake or slow reach under 0.5 m deep | A grey shape in the shallows that lifts off as you near |
| Trout | Reach with pools; above a waterfall only if it got there first | Dark shapes holding in pools, gone when you step to the bank |
| Woodpecker | Old stand with dead wood | Drumming; holes in standing dead trunks |
| Grey seal **[A]** | Sheltered rock platform, remote island | Seals hauled out on a skerry |
| Puffin **[A]** | Turf over a sea cliff, island with no ground predator | Burrows riddling the clifftop; birds rafting below |
| Otter **[A]** | Coast or reach, island within swimming distance | Spraint on a rock at a confluence, tracks in the sand |
| Wild boar **[A]** | Broadleaf stand on deep soil, island once joined to land or reached by people | Rooted-up ground under oak and beech |
| Red deer herd **[A]** | Large island, open valley floor and moor | A herd grazing a far valley, moving off as one |
| Wolf **[W]** | Deer range on a large landmass | Tracks along a trail; a kill by a river |
| Path **[A]** | A trail people took over | The same line wider, with cut steps where steep |
| Ford **[A]** | Reach under 15 m wide and 0.6 m deep, on a route | Stepping stones across a riffle; trails meeting on both banks |
| Cairn **[A]** | Summit or pass on a route, rock at the surface | A pile of stones on the skyline |
| Shieling **[A]** | High gentle meadow with a spring, a day from a farm | A low stone hut and a turf-ringed fold |
| Farmstead **[A]** | Deep soil above flood height, sun-facing, water within 300 m | A long low house, a walled infield, clearance cairns |
| Field walls **[A]** | Fertile, stony ground near a farm | Walls of cleared stone, matching the rock below |
| Harbour hamlet **[A]** | Sheltered deep coast stretch at a stream mouth | A landing, a cluster of houses, a road inland |
| Hill fort **[A]** | Spur steep on three sides, near a route or harbour | A ring of tumbled stone and earth banks |
| Quarry **[A]** | Building stone exposed near a route | A square-edged cut face, a spoil heap, a track leading off |
| Abandoned village **[A]** | Settlement ended by a recorded cause | Roofless walls, nettles, overgrown fields, its route fading |
| Ashfall **[F]** | Cause: a source put ash into the soil field at a date | Grey soil under a young forest of one tree kind, region-wide |
| Raised spur **[F]** | Cause: uplift added under a named source before forming | A mountain the rock story cannot explain, eroded like any other |
| Blight **[F]** | Cause: soil changed outward from a source, communities dying by age | Dead stands near the source, sick ones beyond, healthy beyond that |
| Delvings **[F]** | People kind that cuts into strong rock with ore | Gates in cliff bands, spoil fans, roads to them, caves made by hands |

## 5. How it works

**World rung.** Which animal kinds reach each island: a kind arrives if its dispersal (flier, swimmer, walker, carried) covers the distance from a source, with a chance that falls with distance and rises with island area, after island biogeography ([MacArthur & Wilson 1967](https://press.princeton.edu/books/paperback/9780691088365/the-theory-of-island-biogeography); the rule is *inference*). Peoples and their arrival dates are world facts. Cost: negligible.

**Region rung (16 m cells).** After land, water and plant communities:

- *Trails.* Crossing cost per cell; one multi-source shortest-path pass from water gives every cell its cost-distance to drinking water. Trails are the downhill paths in that field from sampled bedding cells, merging where they meet, so they form networks converging on watering places as streams converge (*inference*). It is the least-cost road method of [Galin et al. 2010](https://doi.org/10.1111/j.1467-8659.2009.01612.x) applied to animals. Cost: one Dijkstra over about 260,000 cells, perhaps 30 ms *(guess)*.
- *History* **[A]**. Per era: score sites, found settlements, trace routes cheapened along earlier ones, end some by a cause the land offers; write events, marks and names. RimWorld lays roads with such a shallow pass (`df-rimworld.md`). Caves of Qud generates events and then rationalises them into narrative ([Grinblat & Bucklew 2017](https://dl.acm.org/doi/10.1145/3102071.3110574)). Cost: tens of sites per island, well under a second *(guess)*.
- *Abundance* **[A]**. Per kind per island, from the area its host rule accepts (the habitat-suitability approach of the US FWS framework cited in `dwarf-fortress-worldgen-research.md`). No food web.

**Place rung (metre blocks).**

- *Trails and roads* are designed like river channels: one or two blocks of trodden ground with a slight wander inside the traced line, steps where steep, trees kept off, water crossed at the ford the tracer chose. Far away a trail is just a material in a column (`adr/0001`).
- *Marks* are small designed pieces chosen by kind and made from what is under them: a wall from the stone cleared off its field, a ruin from local rock, decayed by its age.
- *Ambient animals* (Stage 0b) are animated from (kind, host feature, time) with no state: birds orbit a cliff band, fish hold in the pools the river design already makes. Drawn as small instanced shapes near the player only. A startled animal flees, then is forgotten.

**The colony game.** Dwarf Fortress's site finder filters on water, soil, clay, metal, aquifers and danger; RimWorld's site choice turns on biome, hilliness, rivers, roads and landmarks (`df-rimworld.md`). The natural world can honestly supply trade-offs of site (water against flood, soil against exposure, harbour against defence), resources at depth from the rock function, defensibility from slope, seasons from climate, and threats from floods and slides with their recorded history. Following Tynan Sylvester's rule, "anything in the Game Model that doesn't copy into the Player Model is worthless" ([The Simulation Dream](https://www.gamedeveloper.com/design/the-simulation-dream)), do not simulate food webs, off-screen individuals, animal genetics, prices before trade exists, or figures nobody meets. Do record what leaves a mark: where trails, fords, settlements and ruins are, and why each one ended.

**Narration.** Later narration, by AI agents or by templates, needs only the event list, the names and the features they point at. Nothing else has to be kept for it.

## 6. Growth path

**Stage 0: game trails on today's island.** The first living thing is its trace: a network of deer trails traced from the simulation and cut by design, the same pattern as the rivers. Trails need no new drawing, use today's fields, show on the map and from the ground, draw a walker on (`interest-design.md`), and build what every later part uses: crossing cost and the route tracer.

- `rivers.odin`: crossing cost, the shortest-path pass from water, trail tracing and merging, fords where trails meet a reach. About 80 lines *(guess)*.
- `gen.odin`: in `surface_at`, ground within a trail's width is trodden dirt; `trees_in` keeps trunks off trails. About 30 lines *(guess)*.
- `--map` draws trails as thin lines. About 10 lines.
- The owner looks at the map first (do trails converge on fords and bars, avoid the steepest ground, follow spurs?), then walks one down to the river from `--above`. `--bench=8` should still give about 57 m, since the start is on a bank.

When: best after rock and the first plant communities (interesting-world steps 1 to 3), so trails follow cover and avoid cliffs. It works on today's island regardless and can come sooner if the owner wants something alive.

**Stage 0b: birds at cliffs, fish in pools.** The first drawing of things that are not blocks, about 150 lines *(guess)*. Trigger: cliffs accepted (step 2) and pools in the river design.

**Stage 1: the archipelago.** Animal presence per island; the first history pass with one people in two eras, the ruins of the first among the farms of the second; routes reusing trails; names; the inspector shows each feature's age and cause. Trigger: a second island exists, and the owner wants evidence of people.

**Stage 2: the wide world.** More peoples and eras, regional abundance, mainland predators, colony site choice reading suitability and the event list. Trigger: the colony game becomes the next direction.

**Not yet, and what starts each:** behaviour beyond fleeing, when the player can do something with an animal; abundance numbers, when something consumes animals; individual historical figures, when narration or the colony needs them; ore and clay as stock, when digging has a purpose; fantasy, when one island's natural world is accepted and the owner names a first story, which then enters as a single cause; AI narration, when the event list holds a few dozen events worth telling.

## 7. Risks and known failures

- **Marks stamped on finished land read as diagrams** (`lessons.md`). Every mark has a host chosen by suitability and is built from the rock and soil beneath; nothing is placed by noise.
- **Trails fitted to the land, like the early rivers.** Trails come from a cost field the land produced and change the ground by a material, not a height. If they read as ruled lines, fix the wander and the merging rather than adding noise.
- **Scale before value.** No populations, peoples or history until something reads them. Stage 0 is one field and one tracer.
- **History breaking the creation budget.** DF's takes about half an hour *(sourced)*. This pass is decisions over a fixed number of eras.
- **Accretion.** Neo v3's research proposed nine named world products with versions before anything lived in them (`future-phases-research.md`). This design reserves one function, one integer per feature and one list. Trail statistics can reject a change and never accept one.
- **Fantasy as stamps.** A mountain pasted on is an excavation in reverse. Influences enter only as causes.

## 8. Decisions for the owner

1. **First living thing: its trace (deer trails) or the animals (birds and fish)?** *Recommendation: trails*, because they build the routes everything later uses and need no new drawing.
2. **Is the first island wild, with people arriving with the archipelago?** *Recommendation: yes.*
3. **History as a short pass of eras that generates facts, not a Dwarf Fortress simulation?** *Recommendation: yes.*
4. **Is the human past ruins only, at first, with nobody living there now?** *Recommendation: ruins first*; they reward walking without needing people to talk to.
5. **Should every formed feature carry an age from now on, starting with the landslide?** *Recommendation: yes.*
6. **Are fantastic influences admitted only as causes in fields before forming, or as dated events, never as shapes placed afterwards?** *Recommendation: yes.*

## 9. Not verified

- The Galin et al. 2010, Grinblat & Bucklew 2017 and MacArthur & Wilson 1967 citations are from memory; links and contents were not checked in this session.
- That real game trails converge from bedding cover on water in a branching network is an inference.
- Every cost, line count, slope threshold and kind count marked *guess*, especially the 30 ms pass and the number of eras.
- Whether a trail one or two blocks wide shows at all on the far rings, at one material per 16 to 64 m column. It may vanish past a few hundred metres, which may be right.
- DF's exact creature count in 53.17 was not counted; "hundreds" is the brief's figure.
