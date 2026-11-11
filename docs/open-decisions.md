# Design decisions

What has been decided for v5 and what is still open. The owner decides direction; on 2026-11-10 the owner delegated the engineering choices for the first build to Claude, and those are marked "Claude's call" so the owner can overturn any of them. A decision that is hard to reverse, surprising, and a real trade-off also has a record in `docs/adr/`.

Background: `ideas.md` (the destination) and `lessons.md` (why earlier attempts stalled).

## Decided

**2026-11-10, by the owner**

- **Fresh repository, ideas only.** Earlier projects' idea documents are in `reference/`. Earlier code may be read to learn what a feature did; implementations are designed fresh.
- **Start with a small working game to test directions in.** A basic, minimal implementation with level of detail, lighting and anti-aliasing done properly, used to try directions for world generation, look and gameplay. This replaced the earlier plan of settling every decision on paper first.
- **Keep the code small.** Not too much code, not too long to write.
- **The world is a simulated island with designed rivers.** The owner chose this from the options below on the day the first build was playable. An island about 6 km across is formed before play by uplift and erosion on a grid, in about a second, and rivers are traced from its drainage and cut by design. See `adr/0003`. The noise generator the first build started with is gone.

**2026-11-10, Claude's call**

- **SDL3 with its GPU API, shaders written in Metal's language and compiled at start-up.** It is the least code and needs no shader build step. Measured: 120 FPS at 2560 × 1440 with about 2 ms of our own work per frame. If frame pacing cannot be held or diagnosed, the fallback is Metal directly.
- **The world is sampled at a cell size.** See `adr/0001`.
- **Volume near, columns far.** The nearest 256 m is a true block volume, so digging, building and overhangs work. Beyond that the ground is columns.
- **Water is its own smooth surface**, drawn over block terrain at its true level: a sheet for the sea, a ribbon for each river.
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

## Deferred on purpose

Saves and world formats, the atlas, menus and interface, final world size, the plant and biome catalogue, seasons and weather, underground structure, inventory, and everything in the living-world and colony horizons.
