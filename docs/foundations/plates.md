# The plates: the world's history

How the world's continents and islands come out of one history of moving plates, and how each region's record is read from it. Written 2026-11-15 for step 22 (`foundations.md` section 8) after the owner's goal of the same day (`open-decisions.md`): no island formed on its own; every region's outline, uplift and sinking, vents, rock and sea read from the history at its place; a kind the name of a kind of history; the islands at least as varied and as close to the real ones as today's kinds; forming within its time budget; and the history measured against the real Earth's through time. The research is `interesting-world/notes/real-plates.md`. Numbers are marked (measured), (sourced) or (guess). The first half (the history, its frames, `--plates-why` and the comparison) is built; the second half (reading the regions) is built in part, as section 6 says.

## 1. What it gives the player

The coast on the horizon is a continent's because a continent drifted there; the chain of islands off it runs where a slab sinks under it, and its volcanoes are young at one end because the front moved; the flat-topped island far out is an old volcano the plate carried off its hotspot and the sea planed down; the strait between two islands is a basin that opened behind an arc. Every island can be asked why it is there (`--plates-why`), and the answer is a history: when its crust formed, which plate carried it, what rose or sank, which vents built it.

## 2. Foundational decisions

### D1. The history is a whole planet the size of the Earth; the known world is a window on it.

*Recommendation, and what is built.* Simulate the whole sphere of radius 6,371 km on about 36 km cells, and take the known world (1,000 km square) as a window at its end, placed where a continent's margin meets the sea over a sinking slab or a hotspot at 20–40° N.

Why: real plates are 18,000 km² to 100 million km² and move 20–100 mm/yr (sourced), so over 250 Myr a plate travels 5,000–25,000 km. A world of 1,000 km cannot hold one plate's motion for 10 Myr, so a flat 1,000 km world would either have plates as small as the world's own islands, moving a few km in all, or crust that leaves through the edges. A continent needs a supercontinent to break from, and the ocean beside it needs to be made and destroyed. The real Earth's figures (plate count, sizes, speeds, boundary lengths, ocean-floor ages, land) are figures of a whole planet, so only a whole planet can be measured against them, which the owner asked for. And the window can grow later: the planet already exists past its edges.

*Alternatives.* (a) A flat 1,000 km world of microplates: no continents, and no honest comparison; plates would have to be shrunk to the world, which `zigcraft-neo-v3`'s research warned against. (b) A small planet, about 1,500 km in radius, whose continents fit in the known world: comparable to the Earth only after rescaling every figure, and a horizon that drops ten times faster than the round world step 19 drew from the Earth's radius. (c) A coarse planet and a finer regional history run inside the window: the best of both, at roughly twice the code; deferred until reading the regions shows the window's cells are too coarse (section 6).

*What it means for the owner.* Within 1,000 km the continent is a margin, not a whole continent: the known world is a coast of one (or two) with its islands off it, as Japan, Korea and the Izu arc are within 1,000 km of each other. That is the plan's end shape (`foundations.md` section 5, item 1). It is set out as one question in `open-decisions.md`.

### D2. Rigid plates turning about poles, on a fixed grid, each step asking which crust moved onto each cell.

Each plate turns about its pole by its spin for a step; a cell takes the crust of every plate whose turned-back position lands on its own ground (`globe_step`). No plate: a gap, filled with new ocean floor (the ridge), or, a single cell away from a spreading boundary, the grid's own hole, filled from its neighbour. One: that crust. Two: they converge. Floating crust (continental, or ocean floor an arc or sediment has thickened past 18 km) is never subducted; between two sinking crusts the plate pair's polarity, settled from the first edges they meet along, decides which sinks, so a whole trench sinks one way; two floating crusts collide, and the one under is stacked onto the one over where the boundary converges. Floating crust that is not continent, carried into a trench on the plate going down (an arc, a plateau), is scraped off onto the plate over it (`accretes`, step 32): before, it could not sink and ploughed on through the plate over it as a stray piece of the plate going down, which was most of the boundary's stray cells. Each cell's crust keeps the turning it has had since it formed (a quaternion), so the place it formed is known exactly at any point inside it: relief read there moves with the crust, and `--plates-why` follows it.

*Why a grid and not Cortial et al.'s moving samples.* A fixed grid needs no remeshing, runs in parallel by cells with no sorting, and is the same at every step. Its cost is the grid's noise: holes and overlaps one cell wide wherever plates meet, which turned continent into ocean until a gap away from a spreading boundary was treated as a hole (measured: continental crust fell from 38% to 18% in 350 Myr before, 38% to 34% after).

### D3. A plate's motion comes from the forces on its edges, not from a drawn pole.

Slabs sinking under another plate pull it toward the trench (`SLAB` a km, more the older the slab), ridges push the plates apart (`RIDGE`), the plate over a trench is drawn toward it as the slab rolls back (`SUCTION`), colliding edges resist in proportion to their closing (`COLLIDE`, 500 since step 32, 400 before), and the mantle drags on each plate's base, 1 + `KEEL` times as hard under continent (1.5 since step 32, 2 before). A plate turns at the spin that balances them, reached with a lag of 8 Myr, the whole surface's net turning removed. So plates that pull slabs are fast and continents slow, as on the Earth (measured over eleven seeds since step 32: ocean plates 47–80 mm/yr, real 40–79; continental 15–20, real 19–36), and a plate's motion changes when a boundary changes: a ridge reaching a trench, a continent arriving at one. The first continent's plates are held still through the spin-up until 20 Myr before the history begins (`HOLD`), so they are moving when it does.

### D4. What happens to plates is rows of plain data.

- **`SPLITS`**: a continent rifts (the shortest of six lines through the continent's middle that leaves a quarter of it or more on each side, wandering up to about 380 km off a great circle over waves of 2,000 km, through a plate of 20 million km² or more, at least 30% continent; the continent is thinned within 300 km of the rift, so its margins sink to shelves); an arc rifts off the plate behind it (a back-arc basin opens behind 1,500 km of trench over slab older than 50 Myr: the Japan Sea, the Okinawa Trough, the Shikoku Basin); old ocean starts to sink under its continent (a passive margin turns active, on the side of the continent where its margin is oldest); old ocean floor founders under the younger (subduction begins inside an ocean, as the Izu-Bonin arc's did at 52 Ma; from 110 Myr old and about every 30 Myr since step 32, from 140 and every 60 before). Each has a host (size, continent's share, Myr since it last split, slab length and age, ocean age), a chance a Myr, and the speed its halves start apart at.
- **`PLATE_SETTINGS`**: trench, forearc, volcanic arc, back-arc, collision belt, rift, spreading ridge, hotspot, transform fault, passive margin, continental interior, ocean basin: ordered rows, each a range on one field (km to the nearest boundary of a kind on the same plate, or km past the volcanic front) and the crust's kind. These are the names step 17's world fields use.
- **Hotspots** (30 to 40, fixed in the mantle, each alive for 60–320 Myr), **arcs** (front 170–260 km from the trench, drawn per stretch; Syracuse et al. 2010 give 240 ± 62 km), **joins** (two plates colliding along 800 km, and along half or more of the boundary they share, for 40 Myr are sutured; two whose shared boundary has stopped moving for 20 Myr are one) and **wear** are constants with their sources beside them.

A condition of a new shape becomes a field, never a branch.

### D5. Volcanoes are features, carried by their plate.

An arc vent opens on the volcanic front wherever no active vent stands within about two cells; it builds 1.5 km a Myr to 1.5–3.5 km over the arc while the front stays under it, then dies as the plate carries it off. A hotspot builds a volcano each time its plate has carried the last one 60 km off, 2.5–6 km a Myr to 4–9 km over the sea floor. Every volcano rides the plate of the ground under it, sinks with its slab, sinks as its ocean floor cools and deepens, and is planed to the sea by the waves (30% of its height over the sea a Myr, at least 40 m a Myr). Each records when it began and last erupted, how much it built and its top over the sea: the vents a region's record will name.

### D6. The ground floats; the sea fills what a fixed volume of water fills.

Ocean floor stands at its age's depth (GDH1) raised by any crust thickened over 7 km; continental crust floats by Airy isostasy, 152 m of height a km of crust over 31 km above the sea and 217 m under it. A trench is pressed down 2,500 m before each overriding plate; a hotspot swells the ground 900 m. Land over the sea wears toward 300 m over it (a plain with no relief left hardly wears), high ground fast, and what wears off is laid on the sea floor beside it. Continental crust thicker than its neighbour on the same plate by more than 5 km spreads into it under its own weight, a fifth of the excess a step (`SLUMP`, `FLOW`, step 32), so a collision raises a belt and a plateau hundreds of km across where it raised a wall one cell wide and lost what passed 75 km. The sea's level is where the Earth's 1.335 billion km³ of water reaches (`sea_level`), so young ocean floor lifts the sea and floods the continents, as in the Cretaceous: the measured land falls with the ocean floor's age, on ours and in the PaleoDEMs.

## 3. Extent, cells, steps and span

| | Built | Why |
|---|---|---|
| Extent | The whole sphere, radius 6,371 km | D1 |
| Cells | A cube cut 256 cells to a face, stretched toward equal area: 393,216 cells, 36 km on average | Islands are features, not cells; at 24 km the history takes 2.4 times as long (measured 5.6 s) and its outcome changes |
| Step | 2 Myr | A plate at 100 mm/yr moves 200 km, under six cells; hotspot volcanoes between steps are placed along the path |
| Span | 350 Myr: 100 to spin up the first continent's ocean floor while the continent holds, then 250 recorded, the span of Müller et al. 2019 | Long enough for a supercontinent to break up and its pieces to collide; the real reference covers the same 250 Myr |
| Frames | Every 10 Myr, 26 of them | The age grids are kept every 10 Myr |

## 4. What the history leaves at each place

For any point on the planet at the end, and so for any point of the known world: its plate and that plate's serial and parent; its crust (continental or oceanic, its thickness, when it formed, where it formed); its height over the sea; its setting (D4); the volcanoes within reach with their dates and heights; the events (splits and joins) near it with their dates. Through time, `--plates-why` follows the crust now at the point back to where it formed and prints, every 10 Myr and whenever its setting changes, its plate, crust, height over the sea and setting: so the vertical motion it went through, the volcanism and when, and its setting through time are all there. The sea's level through time is in `history.csv` (`sea_m`) with the plates, continental crust, land, splits and joins at every frame.

## 5. How continents and islands emerge

Continents are the first continent's pieces: rifts break it, the seed choosing when and where; the pieces drift, collide (stacking into ranges), and grow at their margins where arcs mature past 28 km of crust. Land is the continental crust standing over the sea, less the margins stretched under it. Islands come from four causes, as the reference islands do: arc vents on the front (the Izu islands); arc crust grown past the sea (a mature arc); hotspot volcanoes, aging along their chain (measured: chains age at 16–82 km/Myr on seed 7, the plate's speed over the hotspot); and continental pieces and stretched margins standing just over the sea (a Tsushima). Forearc uplift (a Kikaijima) is not yet made: the forearc is a setting with no vertical motion of its own.

## 6. Reading a region's record (the second half)

Built 2026-11-15 in part (`foundations.md`, "Step 22, second half, as built"): items 1, 7 and 8 as planned; item 2 as each kind's own outline; items 3 to 6 not yet, each island's record within its kind's ranges still drawn from its seed. The plan as written, to be tested against today's kinds and the real islands' figures on many seeds:

1. **Where the regions are.** The known world's islands are found in the window at 1 km (`world_draw` does this coarsely today), each a candidate region with its middle and outline. Step 17's `Island` records are filled from them: middle, size, setting, age, seed.
2. **The outline** is where the window's ground at 1 km stands over the sea; for a volcanic island it is none, and the vents build it from the sea floor, as the cone and crater kinds do now.
3. **The history as `Phase` rows.** Follow the crust under the island's middle (as `--plates-why` does) and turn its height through time into phases: years and uplift from the change of height over each stretch, the sea from the sea's level, cut so the last few hundred thousand years, which decide the land at walking scale, keep today's phase lengths and cell sizes (64, 32, 16 m). The region's own vertical motion over the last million years is far below the history's 2 Myr step; it comes from the setting's row (a forearc rises 1.5–2.3 mm/yr, after Kikaijima; a hotspot island sinks as its plate cools, at the rate its ocean floor's age gives) rather than from the coarse heights.
4. **Vents** are the volcanoes within the region, with their dates mapped onto the phases and their heights and forms (arc: cone, `form` under 1; hotspot: a broad shield; a dome where the row says the lava is stiff).
5. **The rock story** from the setting: arc and hotspot volcanoes lava and ash; a continental piece layered rock, folded in a collision belt; the drowned shelf's islands its tilted beds.
6. **The sea** is the world's: the history's long-term level plus the last ice ages' fall and rise of about 120 m (sourced in `world-frame.md`), which is what drowns the inlets kind's valleys.
7. **Kinds become names.** A kind row keeps its name, its `after` (the real islands it is measured against) and gains a host on the record (setting, crust, age, sea's last rise); its ranges stay only for what the record cannot say yet. A cone is "a young arc vent on oceanic crust"; inlets "a continental piece the sea rose 120 m over"; raised "a forearc"; worn "an old island off its hotspot or a passive margin".
8. **The test.** Many seeds; every region formed; the figures start-up prints (`REAL`) by kind against the real islands and against today's kinds; forming time per region within today's (0.25–0.9 s).

## 7. Measured against the real Earth

`tools/plates_compare.py` (`interesting-world/notes/real-plates.md`, "Through time") measures our frames and the real Earth's on the same half-degree cells with one function, every 10 Myr from 250 Ma: plates and their sizes, speeds by kind of plate, boundary lengths by kind, the ocean floor's age distribution and depth from age, continental crust, land and its heights, land masses and islands. It draws a sheet per frame, ours beside the real, and a chart of the figures through time. It costs the game nothing: it is a script reading what `--plates` writes. Arc geometry (front distance, curvature) and the age progression of hotspot chains are measured on ours at the end (`--plates` prints the chains' rates) and quoted for the real (Syracuse et al.; O'Connor et al.); they are not yet in the script.

Since step 32 a figure is judged over eleven seeds (1 to 10 and 12), never one: the history is chaotic, and one change moves a seed's figures more than the change's own effect. `--summary` prints the median and range over the seeds' outputs beside the real Earth's, with the median of another set as "ours before"; a run of the eleven takes about 70 s on this machine. Speeds in both worlds are measured with the whole surface's net rotation taken out, as ours is made; Müller's mantle frame has little (its continental plates' speeds move by at most 6 mm/yr).

Where the comparison is blind, traces in a scratch build answered it (step 32, `foundations.md` section 8): which plates grow by joining and which by spreading, how much continent collisions consume and arcs make, where the old ocean floor lies, and how ragged each plate's outline is against a circle of its area. They are worth keeping as a habit, not as code.

## 8. Cost

| | Time | Measured on |
|---|---|---|
| The history, 175 steps on 393,216 cells, on 10 threads | 2.1–3.2 s, mean 2.37 (the history before step 32: 2.0–2.9, mean 2.20, alternating with it) | seeds 7, 1, 3, 12, three rounds; M3 Max, load 6 to 7.5 from other sessions |
| The same on one thread, before the crew | 7.5 s | seed 7 |
| At 24 km cells (884,736) | 5.6 s | seed 7, a scratch build, before step 32 |
| Drawing 26 frames and the known world at 1 km | 1.2–1.6 s | |
| `--plates-why` (the history twice, every field every step the second time) | 5.4 s | before step 32 |
| The comparison script, 26 frames both worlds | 13 s | after the first run, which fetches 270 MB of reference data |

The passes over cells run on a crew of 10 threads, each with a fixed share and its own sums, added in order, so the history is the same on any machine (checked: two runs give identical grids). Memory: two crust grids of 32 bytes a cell, about 25 MB, one more array of 1.6 MB for crust flowing (step 32), plus 61 MB of frames kept for drawing. The guess in `foundations.md` section 7 was about a second; the history is two to three times that, run once at world creation. Step 32's first half added about 0.17 s: twice as many splits, each of which scans the planet's cells several times on one thread, and twice as many plates for each cell to ask about.

## 9. Risks and what is weak

- **The known world's islands are the weakest part.** Its map at 1 km blends 36 km cells; coasts follow the cells despite a warp. The islands near the start are sites that rows put on the history's settings (section 6), not the history's own land. Since step 32, seed 7's start stands on a forearc of thinned continental crust 25 km thick, a shallow shelf, and 21 islands stand in the square round it. The reading's outer high (2,500 m of relief, a guess for oceanic forearcs) lifted that shelf to the sea's surface and let sika deer walk to the default island at the low sea; it now lifts the floor between islands no nearer the sea than 200 m (`OUTER_HIGH.crest`), and adds nothing where the history's floor is shallower.
- **Boundaries are two to three times the real length**: converging boundary 97 to 200 thousand km through time over eleven seeds against 51 to 70. Stray pieces are mostly gone (floating crust now accretes). What is left is the plates themselves: 39 of ours over a million km² today against the real 18, and outlines 2.0 to 2.2 times as long as a circle's of their area against the real 1.3 to 1.5. The real Earth's other 33 plates are microplates under a million km², which 36 km cells hardly hold. A boundary smoothed over two rings of cells did not shorten them; the lobes are hundreds of km across and come from the motions and the splits.
- **The first ocean floor still survives too long early**: 25% of the ocean floor older than 120 Myr at 250 Ma against 5, 13% at 200 against 2. The spin-up does not recycle it: the old floor lies in the middle of large plates and on continental plates' passive margins.
- **Continents hold level**, 37 to 38% throughout against the real 35 to 42%. Collisions consume about three times what arcs make, and the grid's filling of holes makes up part of the rest. Faster arcs drowned the land: the extra continent stood under the sea and took up its water.
- **The whole surface is slower than the real**: RMS speed 39 to 52 mm/yr against 44 to 73; continental plates 15 mm/yr at 250 Ma against 36.
- **Continents are low plains**: their interiors wear to about 300 m over the sea of the time, so a rise of 200 m drowns most of a continent at once (on one seed, land fell from 33% to 6% in 20 Myr while accretion was being tried). Too many small land masses: 233 of 10,000 km² to a million today against 107.
- **The outcome depends on the grid**: at 24 km the same seed ended (before step 32) with one plate of 204 million km². The history is chaotic; seeds differ more than any tuning, which is what a seed is for, but a figure from one seed is not a figure.
- **The plate count is the balance of rows' chances and joins**, tuned on eleven seeds by the comparison; seeds end today with 29 to 52 plates.
- **Forearcs do not rise and arcs do not migrate**: Kikaijima's setting exists but not its uplift; trench rollback is a force, not a moving trench.
- **Lines added**: 1,159 in `plates.odin` (45 by step 32), against the brief's "small". The frame drawing, the known world's map and `--plates-why` are a third of it.
