# Lessons from the earlier attempts

Distilled from the written record of ten project folders. Statements about what happened come from those projects' own documents. The section "The pattern" is a reading of that record, written on 2026-11-10 at the start of v5.

## The lineage

| Project | When | Stack | Got to | Stalled on |
|---|---|---|---|---|
| zigcraft-ai-1, zigcraft-new, zigcraft | Oct 2024 to Feb 2025 | Zig, OpenGL, raylib | A basic chunked block world | No record |
| zigcraft-neo | Mar to Apr 2026 | Zig, OpenGL 4.1, GLFW | 25 gated phases, fast near field, far LOD, 10 biomes | Terrain was "a taxonomy of hand-shaped noise fields"; rivers were decoration; far LOD seams |
| zigcraft-neo-v2 | 2 Jun 2026 | Zig, SDL2, OpenGL | Regional terrain product with real drainage, headless | Previewer built before the game; the playable build was slower than v1 |
| zigcraft-neo-v3 | Jun to Jul 2026 | Zig, OpenGL 4.1, GLFW | 110k lines; 8.45 km views at 62 to 68 FPS; tectonic landforms the owner approved in a 43-minute flyover; full menu and save flow | Rivers never passed the owner's review |
| odincraft-v1 | 13 to 14 Jul 2026 | Odin, SDL3, Metal | Menu, music, diffusion-model atlas, voxel view | A "parity" port that ended uncertified; terrain was one sample per 250 m |
| odincraft-v2, v3 | 12 Aug 2026 | Odin, SDL3, Metal | Menus, saves, streaming, test apparatus, in hours | Never reached real terrain; gates were green on toy worlds |
| odincraft-v4 | 5 to 27 Sep 2026 | Odin, SDL3 GPU | A 1,000 km world with tectonics, erosion, climate, geology, ecology; atlas; streaming; block breaking | Walking-scale terrain was uninteresting; crafted places read as excavations; 120 FPS pacing never passed |

## The pattern

1. **The ground under the player was always built last.** Every plan ran from the outside in: engine first, or continent first, with the place you stand in as the final refinement. The record shows walking-scale terrain accepted once, on one seed, as "restrained natural ground detail".
2. **Rivers failed the same way every time.** Water was fitted to a finished heightfield: carve fields in Neo, clamped ribbons in Neo v3, compiled channels and place "transactions" in v4. The result read as a ribbon on the land or a canal dug into it. A river has to be formed together with its valley.
3. **Measurements passed while the owner's eyes rejected.** v4's one waterfall closed its sediment ledger to the cubic metre and was rejected on sight. Agents certified their own terrain. Gates measured what was easy to measure.
4. **Scale was fixed before anything was worth scaling.** A 1,000 km world made every look at a change cost minutes, and left a gap between a 1 km simulation mesh and 1 m blocks that only generic noise could fill. That gap is exactly where the player lives.
5. **Each restart threw away what worked along with what failed.** Neo v3 had a working engine and approved large landforms. v4 revision 15 had realistic large-scale relief. Neither carried forward, because the knowledge lived in code that the next attempt was told not to read.
6. **The projects accreted.** v4 ended with 15 world revisions, four other version schemes, up to seven companion files per world, ten command-line modes, and compatibility loaders for the saves of a game with no players.
7. **The evidence rivalled the game.** v4 has 17,000 lines of game, 13,700 lines of experiments and 5.3 GB of reports. Neo v3's status document reached 75 KB while its one open phase stayed open.

## What has been shown to work

These are worth knowing because they bound the risk: the unsolved problem is the look of the land at walking scale, and most of the rest has been done at least once.

- Smooth rendering of 8.45 km of block terrain with near/far levels built from one source of truth (Neo v3).
- Background generation and meshing with no work on the frame thread, and streaming that never blocks movement (Neo v3; v4 over a 7.5 km flight).
- Large-scale relief from tectonic uplift plus stream-power erosion that matches real mountain statistics; a toy run on 250,000 cells produced real branching valley networks in about six seconds (v4, `reference/odincraft-v4/relief-compare-findings.md`).
- Whole-world creation in about 100 seconds for 1,000 km (v4 revision 13 onward).
- Habitat-restricted plant communities that audit clean (v4).
- Block breaking with persistence, and the slice camera (v4).
- Immutable world plus layered save, written atomically (OdinCraft v2 to v4).

## Process lessons the documents agree on

- The running game is the test harness. A previewer or a benchmark can justify work; only the game, moving, on real terrain, can accept it.
- The owner is the only judge of how the world looks. Automated checks can reject a change and can never accept one.
- One feature at a time, each one finished or reverted.
- Plans heavier than the change they describe are a warning sign, as are thresholds set before anything was measured and modules named before they were needed.
- A missing measurement is a failure. One benchmark reported 1,254 FPS from a 40-frame window; the steady figure was 319.
- Prefer deleting a special case to adding a compensation for it.
- Commit accepted work. v4's last two weeks, including its best terrain result, were never committed.

## Technical pitfalls to design against

**Water**
- Water levels stored as whole metres per column: every shallow is exactly one metre deep, lakes become flat sheets, and rounding makes floating sheets and four-metre steps.
- Clamping water per column drapes it over slopes.
- Lakes stored as coarse ownership cells produce water walls and ravines through hillsides.
- A river reconstructed after the terrain floats over gullies, raises its own banks or rises downstream.
- A waterfall drawn as a column of water from bed to surface looks like a wall of water. Falling water needs its own representation.

**Terrain**
- One height per column cannot express an overhang, an undercut wall or a cave mouth, which rules out the gorge references.
- Shapes stamped on a lattice or carved into a finished surface read as diagrams or excavations. A feature needs a host: a reason in the rock and the drainage for being where it is.
- Independent fine patches disagree at their edges, by hundreds of metres at divides.
- Cliffs need bare rock, or soil and trees hide them. Soil decided on a coarse grid leaves rock plains.
- Recorded dead ends: soft broad uplift, isotropic fractal noise, one mountain strike direction per world.

**Engine**
- Far from the origin, 32-bit floats blur the camera and crack edges. World coordinates want 64 bits with camera-relative rendering.
- Near/far seams: water edges, fog and draw order must agree across the boundary, and the far level must sample the same terrain as the near one.
- Streaming: rebuilding whole windows, tying what is shown to how fast it builds, and discarding stale results so that slow builds never finish.
- A 68-byte vertex cost about 800 MiB of arena; later versions used 4 to 20 bytes.
- Odin: `matrix4_perspective` produces OpenGL depth range; the default optimisation level is minimal; size worker pools to the 12 performance cores.
- macOS stalls presentation for unfocused windows, which pollutes timings.
- v4's frame pacing failed even with no world on screen, and the cause was never found because SDL GPU exposes no GPU timings.

**Measurement**
- Lakes counted as sea, four-connectivity inventing tiny lakes, and windows too short to be past warm-up all produced confident wrong conclusions.

## Lessons from v5's first steps

Added 2026-11-11, after rock beds, cliffs in blocks and four island kinds were built and compared with real islands. The detail is in `foundations.md` section 11 and `interesting-world/notes/real-islands.md`.

**Judging the world**
- "Realistic but dull" meant not realistic enough. Real islands of the same size are steeper, cliffed at the sea and sharper at the crest. Compare with real elevation on the game's own grid before deciding what the land lacks; the plan was ordered from a diagnosis that the real data only partly supported.
- A real island loaded into the game tests the dressing separately from the land. If it does not look like its photographs, the fault is in what is bare, the soil, the plants or the rock, since the land is known to be right.
- Read a real island's figures before calling it unlivable. Mikurajima looked uninhabitable on the map and has a village, on ground of about 17° (the median under its mapped buildings).
- Only the cliff is bare. The older lesson that cliffs need bare rock still holds for the face; real flanks of 30 to 45° carry forest.
- A design's constants are starting points. Three sets of numbers argued from sources failed the first time they were run.

**Working**
- A diagnosis read from a screenshot can be wrong. Paint the thing in question in one loud colour before fixing it: the "scree sheet" was bare sandstone.
- Ask the owner about catalogue rows and the order of work, never about one island's content. The seed draws the content, and a question framed as a hand choice confused the owner.
- Do not hold the default island fixed while the generator is changing. Keeping seed 7 identical through one step cost a hand-picked key and a row without ranges, both removed the next day.
- Steeper land exposes old bugs. A tree at a cliff's foot wrote outside the chunk above it, which had been possible since the first build and needed a cliff taller than a tree. After any change to the land, fly fast across the steepest ground of each kind.
- Frame interval is unreliable when the window is not in front (the pitfall above). Build the last commit in a separate checkout, run both in the same minutes, and judge by the line for the game's own work.
- An agent's report is a claim: rebuild, rerun the benches and look at the pictures before passing it on. Brief the agent to test the findings it is handed as well; it was an agent that showed the "scree sheet" in its brief was something else.

**Speed** (2026-11-14, after frames fell to 30 a second at full screen)
- GPU time can be seen. Instruments' Metal System Trace (`xcrun xctrace record --template 'Metal System Trace' --launch -- build/odincraft --bench=...`, then `xctrace export`) gives each pass's vertex and fragment time and the driver's own events, with no change to the game. It also shows what other programs take of the GPU: a browser and the window server took a tenth of it.
- The paced bench cannot show headroom: it floors at 8.33 ms, and the GPU slows its clock when it idles between frames, so a frame that costs 5.6 ms flat out shows as 8.3 to 8.6 ms. Compare two builds by trace, run one after the other.
- SDL's `cycle` on a target drawn whole on the GPU every frame keeps spare copies, and a copy that has stood idle is wired again by the driver when it comes back: at full screen that held the scene back 10 to 30 ms about once a second. Cycle only what the CPU writes.
- The faces were the cost, not their shading: two million instanced quads a frame plus the shadows'. Faces turned from the eye or the sun are dropped by facing before they are drawn (`by_face`, `mesh.odin`), which took out two fifths of them without changing a pixel.

**Forming's speed** (2026-11-15, step 31)
- A timing that is fast in some runs and twice as slow in others, the same build at the same time, can be the cache's sets. Large arrays made alone begin at the same place in a page, so the same cell of a dozen of them fell into one set of a cache that holds eight; `erode` took 100 or 205 ms by chance, and 65 every run once the grid's arrays were staggered in one block.
- Sharing a pass among cores pays less than the cores suggest when the next pass runs in order on one thread: the lines the helpers wrote are read back from their caches. Share what costs arithmetic (noise, rays, races), not passes that only move memory.
- Where the result depends on the order of ties, as the flood's on its binary heap, a faster structure changes the land; keep the structure and make its steps cheaper, and check a hash of everything forming leaves, not only the maps.
