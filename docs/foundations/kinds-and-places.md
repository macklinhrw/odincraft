# Kinds, places, inspection and judging variety

Design for the shared machinery: how every system declares its kinds, how any kind is gated on any field, what the formed world is found to contain, which spots become named places, how the game answers "why is this here", and the tools that help the owner judge variety. Numbers are marked *(measured)*, *(sourced)* or *(guess)*.

## 1. What it gives the player

On foot, the player can aim at a block, a tree, a stream or a slope and get one plain sentence back: what it is, and which rock, slope, water or event put it there. Asking again goes one step further back, to what made that slope or that water, and stops at an event or at the shape of the island. A handful of spots on each island carry names that come from their causes ("Grey Step Falls", "the Thirty Ponds"). They are few enough to remember and they sit where something unusual happened. In the colony game the same sentences explain a site's resources and hazards, the survey becomes the site finder and the atlas, and named places become what people refer to and tell stories about.

## 2. Questions it answers

| Provides | To | Needs | From |
|---|---|---|---|
| `Site`: every registered field at a point and cell size, in natural units | every system that chooses a kind | each field registered once, with a sampler, a unit and words for its ranges | owners of fields (all eight) |
| Kind maps on the region grid (rock at surface, landscape type, plant community, landform piece) as fields | everyone, through `Site` | catalogue rows with hosts and weights | catalogue owners |
| Distance-to-feature-kind fields (to lake, cliff band, waterfall, landslide…) | any host condition | features with a position and extent | water, landform, geology, living world |
| Place features with names | atlas, start, the living world | the feature list, plus viewsheds from elevation | survey (this system) |
| `why_at`: a sentence and its chain of causes | player, owner | a `why` phrase on each row, a cause record on each feature | all |
| Survey, overlays, seed sheets, simulated walks | owner, developers | a seed that can be set at run time | world frame |

## 3. Foundational decisions

**D1. Kinds are rows of plain data in Odin source, not data files.** Each catalogue is a constant array of structs. Every row starts with the same header (name, host, weight, patch size, what it brings, a `why` phrase), followed by the catalogue's own numbers (a tree's dozen shape numbers, a rock's strength and colour). A row holds no procedures and no formulas, only literals and names of other rows.
*Alternatives:* text "raws" read at start (Dwarf Fortress), JSON (TerraFirmaCraft, Vintage Story), XML Defs (RimWorld), or kinds written as code.
*Why:* a full optimised build takes 2.0 s *(measured)* and forming the land about 1 s, so editing a row and looking costs about as much as reloading a file would. A loader with error messages would add a few hundred lines *(guess)* and give the game a format nobody asked for yet. Keeping rows pure data means a text loader can be written later without touching a single row. *Expensive later:* if kinds start as code (`if wet > 0.6 do tree = .Alder`), they can no longer be surveyed, explained or edited as data, and turning them back into data means rewriting every kind.

**D2. A host is a set of windows over named fields, nothing more.** A window is `{field, lo, hi, edge}`: a score of 1 inside `lo..hi`, falling to 0 over `edge` outside it. The windows of one host multiply (AND). A kind may list up to three hosts and takes the best of them (OR), which covers Dwarf Fortress's repeated `[BIOME:]` tokens. Every other kind of condition becomes a field:
- "near a lake" is a window on the field *distance to lake*, which is derived automatically for any feature kind that a host refers to;
- "on limestone" is a window on *rock at surface*, whose value is a row index tested against a set;
- "sun-facing and steep" becomes a derived field *dryness*, written in code by the owner of that field.
*The rule:* a condition of a new shape is a new field and never a new operator.
*Alternatives:* a scoring procedure per kind (RimWorld's biome workers), tags and tokens (Dwarf Fortress), a small expression language. *Expensive later:* the inspector, the survey and the "nearest miss" explanation all depend on hosts being windows. Once a host is an opaque procedure, none of them can say why it failed.

**D3. One vocabulary of fields, in natural units, read through one `Site`.** `Field` is an enum. A table gives each field a name, a unit, the words for its ranges (slope: flat, gentle, steep, cliff), a phrase for where it comes from ("land draining through here"), its native cell size, and a sampler. Fields that live on the 16 m region grid are stored interleaved, one cell holding all of them, so one bilinear lookup fills them all. Fine fields (rock at a depth, distance to a river at 1 m) are sampled only when a catalogue's rows refer to them, using a `bit_set[Field]` computed once at start.
*Alternatives:* each system exposes its own procedures, as `forest_at` and `surface_at` do today. *Expensive later:* every row in every catalogue is written in these names and units, so renaming or rescaling one means editing every row that uses it.

**D4. Exclusive kinds are chosen by a stable weighted race on the region grid. Detail kinds are decided point by point.**
- *Exclusive* catalogues give one answer per point: rock at the surface, landscape type, plant community, landform piece. Each kind's score is `weight × host`. Each kind also draws its own key at each point, `u^(1/score)`, where `u` comes from smooth noise on the scale of that kind's `patch` and is seeded by the kind's name. The highest key wins. This is weighted sampling by keys ([Efraimidis & Spirakis 2006](https://doi.org/10.1016/j.ipl.2005.11.003)). Adding a kind changes only the points it wins, and the noise gives each kind patches of its own size with ragged edges. The race runs once on the 512² grid after forming: 262k cells × about 15 kinds × 5 windows ≈ 20M window tests, roughly 20 to 50 ms *(guess)*. The result is stored as a `u8` kind map plus the runner-up and the margin between them. At block scale the race is rerun only where the margin is small, so edges blend over 10 to 50 m (`interesting-world.md` 4.4). A majority filter removes patches smaller than a kind's `patch`, after Mojang's "microbiome" fixes (`minecraft-family.md`).
- *Detail* catalogues stack: ground detail, small plants, stacked modifiers. Each row is tested on its own at each point: present where `hash(point, name) < density × host`.
*Alternatives:* plain argmax, which gives hard straight edges; a cumulative weighted draw, which reshuffles the whole world when a row is added; evaluating every kind per block, which is costly and disagrees between levels of detail. *Expensive later:* this rule draws every boundary in every world. Changing it moves all of them.

**D5. Randomness is keyed by name, and the seed becomes a run-time value.** Today `SEED :: 7` is a constant with fixed offsets added (`SEED + 140`; 20 uses *(measured)*). Proposed: `stream(#hash("trees", "fnv32a"))` mixed with a run-time `seed`, so each kind's stream is the hash of its name. Odin computes `#hash` at compile time *(measured)*. Adding, removing or reordering rows never moves another row's dice. *Expensive later:* once worlds are kept, every stream is frozen, and seed sheets need a run-time seed.

**D6. Features carry identity, extent and cause from the moment they are made.** One list per region: `{kind, id, position, bounding box, size, cause}`. The cause is the event that made the feature (a parent feature's id) plus up to three `(field, value)` pairs measured at creation. Ids are the region, the kind and an ordinal in position order, so they stay stable when unrelated features change. Systems create the features they cause (a landslide, a lake). The survey creates the features that are only found afterwards (viewpoint, waterfall, cliff band, community patch). *Expensive later:* a cause cannot be recovered after the fact, and names, saves and colony references will all attach to ids.

**D7. The tools for judging variety live in the game binary, on a budget, and can reject but never accept.** They are a survey, overlays, seed sheets and simulated walks. All of it goes in one file, at most about 400 lines *(guess)*. It prints to stdout or writes the one PNG named on the command line, and no report directory exists. Automatic checks reject only failures of mechanism (section 5). Taste is left to the owner. *Expensive later:* this is the process that let v4 reach 13,700 lines of experiments.

## 4. The kinds

This system owns one axis of its own, **places**, plus the shape of every catalogue. The catalogues the whole game needs:

| Catalogue | Owner | Pick | Today | Archipelago | Wide world | Benchmark *(sourced)* |
|---|---|---|---|---|---|---|
| Rock | geology | exclusive per bed | 2–3 | 8–12 | 20–25 | DF 25, TFC 20, RW 5 |
| Mineral, deposit | geology | detail | 0 | 5–10 | 30–60 | DF 58 + 127 gems |
| Soil | ground in blocks | exclusive | 3 | 6–8 | 12–20 | DF 21, TFC 8 |
| Landform piece | landform processes | exclusive per slot | 3 | 15–25 | 60–125 | TFC 125, RW 41 landmarks |
| Landscape type (district) | landform + world frame | exclusive, coarse | 1–2 | 6–10 | 20–40 | ReTerraForged 16, RW 17 biomes |
| Water body | water | features | 2 | 8–12 | 20+ | DF 21 water biomes |
| Climate zone | climate | exclusive, world cells | 1 | 2–4 | 10–20 | DF 27 land biomes |
| Plant community | vegetation | exclusive | 3–4 | 11 | 40–60 | MC 57 biomes, RW 17 |
| Plant species and tree form | vegetation | brought by communities | 1–3 | 8 forms, ~25 species | 60–120 | DF 225 (72 trees, ~6 shapes), MC 10 trees in 19 shapes, TFC 20 + ~158 |
| Ground detail | ground in blocks | detail | 2–4 | 15–25 | 60–100 | MC 299 placed features, RW ~70 map features |
| Event, disturbance *(added)* | landform processes | chosen sites | 0–1 | 4–6 | 15 | RW landmarks such as the terraforming scar |
| Modifier *(added)* | owner of the target | detail, on patches | 0 | 5–10 | 30+ | RW Odyssey ~70 stacking features |
| Animal | living world | detail | 0 | 5–10 | 50–150 | RW 13–36 per biome |
| Human mark | living world | features | 0 | 0–3 | 20–40 | RW 13 man-made landmarks |
| Weather | climate | per region and time | 0 | 2–4 | 10–15 | RW weather features |
| Place type | this system | from features | 1 | 8–12 | 40+ | RW 41 landmarks |

All counts above are guesses except the benchmarks. **Two rows count as different** only if a player on foot can tell them apart at 30 m in a grey screenshot, by shape, edge, size or what they bring. A row that differs only in name, colour shade or noise seed does not count toward any target. This was v4's rule, and it was right. A lint lists pairs of rows whose own numbers are all within 15% of each other *(guess)*, as pairs for the owner to look at.

**The same three kinds in the proposed form:**

```odin
// rock (geology)
{head = {name = "grey sandstone", weight = 1, patch = 0,
         hosts = {{{.Bed_Depth, 0, 400, 0}}},   // any depth: chosen bed by bed, not by surface
         brings = {{"boulder scatter", 0.3}, {"thin stony soil", 1}},
         why = "a hard bed of sand laid in the sea and raised"},
 strength = 0.8, crack = 2.5, permeable = true, dissolves = false, color = {150, 148, 140}},

// plant community (vegetation)
{head = {name = "beech slope forest", weight = 1, patch = 300,
         hosts = {{{.Slope, 8, 32, 6}, {.Wetness, 0.25, 0.7, 0.1}, {.Soil_Depth, 0.6, 9, 0.3}, {.Exposure, 0, 0.5, 0.15}}},
         brings = {{"beech", 0.85}, {"dwarf bamboo", 0.6}, {"mossy log", 0.05}, {"windthrow mound", 0.02}},
         why = "beech holds deep soil on sheltered slopes"},
 stems_old = 75, gap = 0.14},

// landform piece (landform processes)
{head = {name = "fallen-rock apron", weight = 2, patch = 0,
         hosts = {{{.Dist_Cliff_Band, 0, 40, 10}, {.Slope, 20, 38, 4}, {.Hollow_Humped, -1, 0.2, 0.1}}},
         brings = {{"scree", 1}, {"fallen block", 0.1}, {"young birch and alder", 0.3}},
         why = "rock falls from the face above and lies at its resting angle"},
 form = .Apron, rest_angle = 34, block_size = {1, 4}},
```

`brings` names rows in any catalogue, with a share. A brought kind is placed inside the bringer's extent whether or not its own host holds there, and the inspector says "brought by …". This is TerraFirmaCraft's forest floor ([`oak_entry.json`](https://raw.githubusercontent.com/TerraFirmaCraft/TerraFirmaCraft/1.21.x/src/main/resources/data/tfc/worldgen/configured_feature/tree/oak_entry.json)) and RimWorld's `mutatorChances`. Names are resolved to indices at start, and a missing name stops the game.

**Stacked modifiers** are rows that change another catalogue's numbers inside a patch, for example `{name = "single-species grove", host = deepest soil, target = community, set = {canopy share of the brought tree ×1.6}}`. They are Odyssey's stacking features, gated by cause.

**What must be code:** field samplers, the forming processes, the drawing routines (tree grower, face breaker, scree, lake fill) chosen by a row's `form`, the race, the survey and the naming grammar. **What must never be code:** which kind appears where, any number that tells one kind from another, names, and `why` phrases. **What must never be data:** formulas.

**Example rows across catalogues** (host conditions over the shared fields):

| Catalogue | Row | Host | Seen on foot |
|---|---|---|---|
| Rock | dark shale | bed index odd, strength < 0.3 | crumbling grey bands under ledges |
| Rock | limestone (if chosen) | one named bed | pale faces, sinks where streams vanish |
| Soil | river silt | distance to river < 30 m, slope < 4° | dark flat ground, no stones |
| Landform piece | bench | slope < 8°, directly above a hard bed's top | a level shelf in a stepped valley side |
| Landform piece | rock shelter | cliff band over weak bed, wetness > 0.4 | a dry hollow under an overhang |
| Landform piece | sea stack | distance to sea < 60 m, hard rock, exposure > 0.7 | a pillar off a headland |
| Event | landslide | hard cap over weak bed, slope > 25°, valley below | scar, hummocks, ponds |
| Water body | debris pond | inside a landslide, hollow | small pools among beech |
| Community | valley-floor forest | wetness > 0.7, slope < 6°, distance to river < 60 m | big trees leaning over water |
| Community | wind scrub | exposure > 0.7, humped | leaning crowns 2–4 blocks tall |
| Community | heath | exposure > 0.85 or soil depth < 0.3 m | open purple-brown ground |
| Ground detail | mossy log | community brings it; slope < 20° | trunks lying under the canopy |
| Ground detail | driftwood | distance to sea < 15 m, sand | grey wood on the beach |
| Modifier | fog hollow | hollow, wetness > 0.8, elevation < 50 m | mist sitting in the low ground (with weather) |
| Place type | waterfall amphitheatre | waterfall + cliff band within 60 m + pool | a curved wall with a fall into a pool |
| Place type | pond cluster | ≥ 5 water bodies within 400 m + one event | the Jūniko piece |
| Place type | gorge | river reach with cliff bands on both sides < 40 m apart | walls closing in over the water |
| Place type | high viewpoint | viewshed > 4 km² that takes in another place | a summit that pays |
| Place type | headland | coast stretch, hard rock, a stack or cave within 200 m | a point to walk out to |
| Place type | confluence meadow | two reaches meeting, open community | a clearing where streams join |
| Place type | tor | humped summit, massive rock, rock stacks | a pile of blocks on a hilltop |

## 5. How it works

**Each rung.**
- *World* (km cells): climate zone and province fields fill the same `Site`, and coarse catalogues such as climate zone run the race on world cells. Rows are written the same way at every rung.
- *Region* (16 m): after forming, (1) derive distance fields for the feature kinds that hosts refer to (a two-pass chamfer transform, [Borgefors 1986](https://doi.org/10.1016/S0734-189X(86)80047-0); about 1 ms each on 512² *(guess)*); (2) run the race for each exclusive catalogue into its kind map; (3) run the survey.
- *Place* (1 m): fill `Site` from the interleaved grid with one bilinear lookup plus the fine fields that are referenced. Read the kind map, rerunning the race at edges. Test the detail rows. The cost per column is one grid lookup plus about 10 detail rows *(guess)*. That is small next to meshing, and it runs on the worker threads.

**Survey.** For each kind map, connected patches (cells, patch count, largest, how many of the 1 km squares it appears in). It also finds features: a cliff band is a connected run of slope > 45° on hard rock; a waterfall is a river drop > 3 m across a hard bed; a viewpoint is a local high point whose viewshed exceeds 4 km². Viewsheds are rays over the 16 m grid from about 300 candidates, 360 rays × 250 steps ≈ 27M steps, about 50–100 ms *(guess)*. Then places. Its uses are a dead-and-wallpaper table (dead: never occurs; wallpaper: in more than 90% of 1 km squares *(guess)*), the start, and later the atlas and the site finder. The site finder filters on scenery as well as resources, which Dwarf Fortress's does not (`df-rimworld.md` 1.4).

**Places.** A place is a cluster of features that is rare for its region. Candidates are gathered around anchor features (waterfall, lake, event, summit, coast stretch). A place-type row matches by the features it requires within its radius. The score is the sum of `−log(frequency in region)` over the matched features, plus a bonus for viewshed. Places are chosen best first with a minimum spacing. The budget is about one named place per 3 km² of land, so 8 to 12 on today's 28 km² island, and at most three may be one-offs whose defining kind occurs nowhere else in the region *(guess, set against Compton's "few characterful artifacts")*. Names come from a grammar per place type: a word drawn from the defining cause (rock colour, the community's tree, a count, a size), then the place type's generic word. The word is picked by the place's name stream. About 40 lines and one word table *(guess)*. That table can later be swapped for a fantasy language.

**Inspection.** `why_at(x, y, z)` reruns the hosts at that one point and builds the sentence from four things:
1. the winning row's name and `why`;
2. the two windows nearest their edges, in words ("steep, deep soil");
3. the runner-up and the window that ruled it out ("alder would grow if it were wetter: 0.41, needs 0.6");
4. the feature the point lies in, with its cause ("in the scar of landslide 2, where shale gave way under sandstone").

Asking again follows the field's "comes from" phrase or the feature's parent. Nothing is stored per point. The costs are one phrase per row, three words per field range and about 32 bytes of cause per feature *(guess)*.

**Judging variety.**
- `--map --overlay=<field or catalogue>`: a ramp for a field, a palette for a catalogue.
- `--sheet=out.png --seeds=1-16`: 16 maps in a 4 × 4 grid, about 20 s *(guess, from 1.0–1.5 s per island, measured)*.
- `--survey --seeds=1-20`: one tab-separated line per seed (land area, share of each kind, patches, places, walk counts) for expressive-range plots ([Smith & Whitehead 2010](https://www.pcgworkshop.com/archive/smith2010analyzing.pdf)).
- Simulated walks: random pairs of points, the cheapest route on the grid, a sample every 16 m. Counts per kilometre: edges crossed (community change, rock to soil, shore, slope break over 20°), kinds within 150 m, places coming into view, and quiet stretches. These are checklist items 1–4, 7, 8 and 13 of `interesting-world.md` section 7.

*Rejects automatically:* a name that does not resolve, a field nobody samples, a row without `why`, different output from the same seed twice, a kind absent on all 8 seeds of a sheet, and forming plus survey time over 2 s *(guess)*. *Informs only:* wallpaper, distributions, walk counts, every checklist number. None of these can accept a change.

## 6. Growth path

**Stage 0, on today's island.** New `kinds.odin`, about 200 lines *(guess)*: the `Field` table with today's fields (elevation, slope, wetness, distance to river, distance to sea, rock hardness), `Site`, windows, the race, `brings`, `why_at`. Then:
- `surface_at`'s `switch` becomes four rows (gravel, sand, stone, grass) and `forest_at` becomes one community row. The owner's check: `--shot` from three cameras is pixel-identical to before, and `--bench=8` still reaches about 57 m.
- `--seed=` replaces `SEED`, about 20 lines changed *(measured: 20 uses)*.
- `--overlay=` and `--why=x,z` (prints the sentence) go into `survey.odin`, about 120 lines *(guess)*.

The owner looks at a wetness overlay and reads three `--why` answers. The first rows that change the world come from the vegetation and geology designers' stage 0.

**Stage 1, archipelago.** Kind maps and feature lists per island. Feature ids carry the island. World-rung fields enter `Site` as one value per island. The survey adds places and walks. The sheet runs across islands as well as seeds. The survey's output is the atlas's data.

**Stage 2, wide world.** World cells run the coarse catalogues. Each region is surveyed when it is formed. A world summary (counts per region) chooses the start and backs the site finder.

**Not yet:**

| Deferred | Trigger |
|---|---|
| Text loader for rows | The owner asks to edit rows without building, or modding begins |
| Expression language in rows | Never |
| Places with names | The first one-off place exists (landslide) |
| Simulated walks | Three communities and cliffs exist, so there is something to count |
| An interface for inspection | Settled under open decision 4 (what the player does) |
| Player knowledge separate from world truth | The colony game or expeditions |
| Quality-diversity search | Never in the game; maybe a throwaway experiment |

## 7. Risks and known failures

- **Measurements passing while the eye rejects** (`lessons.md` 3). Tools can only reject, and the owner's look is the only acceptance.
- **Evidence rivalling the game** (v4: 5.3 GB of reports). One file, about 400 lines, stdout and one PNG, no report directory.
- **Ledgers of intended kinds that accepted none** (v4 `landscape-crafting.md`, 200 types targeted). Targets are perceptible differences, rows are added one at a time with their host, and the survey proves where each occurs.
- **Data files becoming a language.** No formulas. A new condition is a new field.
- **Fragmented microbiomes** (Minecraft 1.18). Patch size per kind and a majority filter.
- **Stamped shapes reading as diagrams.** Every row needs a host, and the shared code refuses rows without one.
- **Thresholds set before measuring.** Every number here is a guess to be read off the first survey.
- **Moving the owner's start.** The start finder is not touched until a place-based start is proposed and walked.

## 8. Decisions for the owner

1. **Rows in source for now, data files later?** *Recommend yes.*
2. **How many named places?** *Recommend 8–12 on this island, at most 3 one-offs.*
3. **Names, and in what voice?** *Recommend plain descriptive English drawn from causes, starting with the first one-off place.*
4. **Inspection now as `--why` plus a key that prints the sentence; real interface later?** *Recommend yes.*
5. **Show changes to kinds with one seed walked plus a 16-seed sheet?** *Recommend yes for any change to the land or the catalogues.*
6. **Should rarity emerge, or be capped?** *Recommend it emerges from hosts, with hard caps only on events (one to three landslides).*

## 9. Not verified

- All cost estimates (the race, viewsheds, the per-column cost, the chamfer transform). Only the 2.0 s build, `#hash` and the 20 uses of `SEED` were measured.
- Whether race noise gives edges the owner accepts, and whether bilinear lookup is smooth enough for edges at block scale.
- The place budget, the wallpaper threshold, the 15% lint and every count in section 4.
- That the stage 0 refactor can be pixel-identical: `surface_at`'s noise must then be read through `Site` in the same order.
- That three hosts per kind and six windows per host are enough. RimWorld and TerraFirmaCraft suggest it, but I have not counted.
