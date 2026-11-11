# Design decisions

What has been decided for v5 and what is still open. The owner decides direction; on 2026-11-10 the owner delegated the engineering choices for the first build to Claude, and those are marked "Claude's call" so the owner can overturn any of them. A decision that is hard to reverse, surprising, and a real trade-off also has a record in `docs/adr/`.

Background: `ideas.md` (the destination) and `lessons.md` (why earlier attempts stalled).

## Decided

**2026-11-10, by the owner**

- **Fresh repository, ideas only.** Earlier projects' idea documents are in `reference/`. Earlier code may be read to learn what a feature did; implementations are designed fresh.
- **Start with a small working game to test directions in.** A basic, minimal implementation with level of detail, lighting and anti-aliasing done properly, used to try directions for world generation, look and gameplay. This replaced the earlier plan of settling every decision on paper first.
- **Keep the code small.** Not too much code, not too long to write.
- **The world is a simulated island with designed rivers.** The owner chose this from the options below on the day the first build was playable. An island about 6 km across is formed before play by uplift and erosion on a grid, in about a second, and rivers are traced from its drainage and cut by design. See `adr/0003`. The noise generator the first build started with is gone.

- **Water flows.** It runs downhill, fills what is dug, shows its movement and never lies in overlapping sheets. See `adr/0004`.

**2026-11-11, by the owner**

- **The end vision is a fantasy world grounded in realism, in the vein of The Lord of the Rings.** `ideas.md` lists the fantasy world as the last horizon; the owner has named it the destination. The natural world is what makes it believable, so foundations are judged by whether they can carry it. The world is original: nothing is taken from Middle-earth.
- **Plan the foundations for a wider world, beyond the island**, with variety that matches or exceeds Dwarf Fortress and RimWorld. The plan is `foundations.md`, with one design per system in `foundations/`; nothing in it is a commitment until recorded here.

- **Start Phase 1 of `foundations.md`**: the sixteen changes on one island, in its section 8, beginning with the seed and overlays (step 0) and rock beds in the land forming (step 1).

- **What a place is made of and what happened to it are drawn from the seed, never chosen by hand.** The rock story, the bed sequence, the tilt, the history and where an event such as a landslide falls all come from the seed, within the ranges of a catalogue row. The owner's choices are which rows exist and in what order they are built. This corrects `foundations.md` section 9, items 1 and 2, and question 7 below, which read as if the island's rock and history were picked once.

- **Steps 0 and 1 accepted on sight**: the seed, the overlays and the rock beds. The owner looked at the game and found the bare mountain faces fine as parts of the mountains. Step 2 (cliffs in blocks) follows, and with it the designed rule for what is bare: rock at its own slope limit stays bare, weak rock below it takes soil, and loose rock lies at the foot of a face.

- **Step 2 accepted**: ledges on hard beds, cracked faces, loose rock below a face, far faces coloured bed by bed. Fallen blocks were taken out on Claude's suggestion: single cubes, rare and never stacked, did not read as rockfall. They return when they can be done properly.

**2026-11-11, Claude's call**

- **The first rock story row to be written is "layered, gently tilted"**: five kinds (mudstone, siltstone, grey sandstone, grit, limestone), with the sequence, tilt and folds drawn from the seed. It is the row the experiment already showed working. More rows follow in Phase 2, and the seed then picks among them.
- **Rock is built before lakes.** This is an order of work: the first landslide waits for step 6, so it falls where a strong bed lies over a weak one.
- **The history rows wait for step 3.** Until then every seed has today's one history.

**2026-11-10, Claude's call**

- **SDL3 with its GPU API, shaders written in Metal's language and compiled at start-up.** It is the least code and needs no shader build step. Measured: 120 FPS at 2560 × 1440 with about 2 ms of our own work per frame. If frame pacing cannot be held or diagnosed, the fallback is Metal directly.
- **The world is sampled at a cell size.** See `adr/0001`.
- **Volume near, columns far.** The nearest 256 m is a true block volume, so digging, building and overhangs work. Beyond that the ground is columns.
- **Water is a depth in each column**, standing at its true level in fractions of a metre, not a block.
- **Faces are lit by the slope they are cut from.** See `adr/0002`.
- **Leaves and trunks are solid blocks.**

## Assumed unless the owner objects

- Odin, on Apple Silicon macOS.
- First person.
- One block is one metre, and the surface stays blocky.
- The same seed always makes the same world.

## Open

These are the directions the first build exists to test. Each is the owner's to decide after looking.

### 1. How real is "real"?

- **A. Natural truth first**: everything has a simulated cause.
- **B. Simulate the why, design the what**: simulation where it produces the look, designed landforms below that, chosen by the simulated context.
- **C. Designed throughout**, as ReTerraForged is.

The island as built is B: valleys, drainage, wetness and rock hardness are simulated; channels, bars, pools and trees are designed from them. *Recommendation: confirm B*, and use it for what comes next: rock outcrops and cliffs where the simulation says the slope is steep and the rock hard, lakes where it leaves a hollow.

### 2. What is missing from the land?

The simulation makes valleys and rivers. It does not yet make the other things in `ideas.md`:

- **Lakes.** Hollows are filled as the land forms, so every river runs to the sea.
- **Rock.** Steep ground is painted as stone, but there are no cliffs, ledges or outcrops, and ridges are rounded.
- **Waterfalls taller than a metre**, gorges, and anything with an overhang.
- **Forest structure.** One kind of tree, thick where the ground is wet.

*Recommendation: rock next.* It is what the mountains most lack, and cliffs along a river make the first gorge.

Research on 2026-11-11 (`interesting-world.md`) supports this and sharpens it: the land forming needs beds of hard and soft rock, which an experiment showed producing scarps, ridges and a varied coast; cliffs then have to be expressed in blocks, and the forest has to vary with the ground, or the change shows on the map and not on a walk. Its section 8 proposes an order of ten steps.

### 3. What should it look like?

The first build has a look: flat-coloured blocks with fine grain, hard sun shadows, soft corner shading, haze. Open choices include how saturated and how contrasty, drawn textures or none, softer shadows, clouds, and how trees are shaped. The owner's references are in `reference/visual/`.

### 4. What does the player do?

Walking, flying, breaking and placing blocks exist. Open: whether climbing a one-block step automatically feels right, swimming, what "inspecting causes" looks like, and when the top-down view arrives.

### 5. What status do the old scale targets have?

1,000 km world, 10 km views, 120 FPS at 2560 × 1440, creation within four minutes. The game draws to about 16 km and holds 120 FPS. The world is one island in an 8 km square, formed in about a second.

*Recommendation: treat 120 FPS and the long view as standing requirements now that they hold. Grow the world only when one island is good to walk across; the simulation's cost grows with area, so a 30 km island at this detail would take about fifteen seconds, and 1,000 km needs coarser cells far from the player.*

### 6. How do we work?

Proposed, each line answering a recorded failure:

- The owner judges everything visual by looking at the running game. Claude shows and asks.
- One change at a time, ending in something the owner can run in under a minute.
- Accepted work is committed the same day.
- Nothing is kept compatible until the owner declares a world worth keeping.
- An experiment is a separate program that is folded into the game or deleted. The game has one way of generating the world at any time.
- Tests cover logic that breaks silently, and never stand in for looking.

### 7. What is the island made of, and where is it?

Raised by `interesting-world.md`, section 9. The answers decide which landforms, caves and plants are honest.

- **Rock.** Layered rock with a hard cap over soft beds (scarps, benches, landslide lakes); two domains split by a fault; or lava flows (columns, sea caves, stepped hillsides). *Recommendation: layered rock first, a second domain later.*
- **Limestone.** It is the only honest route to long caves, sinkholes and springs. Without it, caves are sea caves, rock shelters and gaps among fallen blocks.
- **Climate.** *Recommendation: cool-temperate and oceanic, after Shirakami and Jūniko*: beech forest, about eight tree forms in eleven plant communities, no ice-age landforms.
- **Exaggeration.** Whether to steepen or compress the land beyond true proportions. *Recommendation: decide after rock, cliffs and the first plant communities have been walked.*

### 8. The wider world

Raised by `foundations.md`, section 9, which lists twelve decisions with a recommendation each. The ones that shape the most:

- **The fifteen foundational decisions** in its section 3 (kinds as rows of data, one rock function, a region's recipe as a record, features that record cause and age, fields as a base plus terms, and the rest). *Recommendation: adopt them as each first becomes real in a step, and record each here then.*
- **The end shape of the world.** An ocean of islands, or a mainland with islands off its coast inside known lands about 300 km across. *Recommendation: the mainland, which the fantasy vision needs, if an early test shows that regions can join along a drainage divide without a visible seam.*
- **Cold to hot.** A true slice of about nine degrees of latitude, or 1,000 km standing for about thirty. *Recommendation: thirty.*
- **Rock before lakes.** *Recommendation: yes*, so the first landslide sits on its real host.
- **People and the fantastic.** *Recommendation: the first island is wild; people arrive with the archipelago, first as ruins; the fantastic enters only as a cause with a source, a reach and an age, at most one marvel per region.*
- **The order of work.** Phase 1 is sixteen changes on one island (`foundations.md`, section 8). It replaces the ten steps in `interesting-world.md` section 8, which it contains.

## Deferred on purpose

Saves and world formats, the atlas, menus and interface, final world size, the plant and biome catalogue, seasons and weather, underground structure, inventory, and everything in the living-world and colony horizons.
