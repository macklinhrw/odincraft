# OdinCraft v5

A small first-person block game used to test directions for world generation, look and gameplay. The owner decides direction and judges everything visual by looking; record each decision in `docs/open-decisions.md` the moment it is made.

- `docs/ideas.md`: read before proposing a feature.
- `docs/lessons.md`: read before proposing architecture, a plan or a way of working.
- `docs/foundations.md`: the plan for the wider world and the order of work on the island; one design per system in `docs/foundations/`. Read its sections 3 and 8 before adding to the land, rock, water, plants or living things. A plan, not decisions.
- `docs/interesting-world.md`: the research under that plan. Its note `interesting-world/notes/real-islands.md` compares the generated islands with real Japanese ones, which are the owner's north star for the land; `foundations.md` section 11 has the target figures. Judge a change to the land against them.
- `docs/adr/`: why the engine is shaped as it is. Read before changing level of detail or lighting.
- `reference/README.md`: index of the earlier projects' idea documents, kept verbatim.

The sibling folders `../odincraft-v1` to `v4` and `../zigcraft*` hold the earlier attempts. Read their code only to learn what a feature did for the player. Design every implementation fresh.

## Working on the code

- Keep it small. The whole game is about 3,400 lines; prefer changing a rule to adding a system.
- What the world is lives in four files: `rock.odin` draws the rock under the island from the seed, `land.odin` forms the island in that rock, `rivers.odin` traces and cuts the rivers, `gen.odin` answers the engine's questions from all three. `water.odin` then moves the water near the player.
- What kind of island it is lives in one record, `region` in `land.odin`: size, origin, outline, uplift pattern, rock story and history as a list of phases, drawn from the seed within the ranges of a row in `KINDS` (ridge, cone, worn, raised). Change a kind by editing its row, never by adding a constant. `--seed=N` picks the world and the seed picks the kind; `--kind=<name>` shows any kind on any seed. Seed 7, the default, draws the cone island. `--map` with `--overlay=<field>` paints one field (the names are in `OVERLAYS`, `land.odin`).
- Everything in the region is stored relative to its middle, and `--origin=x,z` places that middle in the world (default 0,0); the generator's entry points (`gen_columns`, `gen_volume`) and the start convert. Positions given to `--above`, `--pos` and the bench's printed end point are in the world.
- Judge a change to the land from the map first: `build/odincraft --map=out.png` forms the island, writes a 1024-pixel relief map with rivers and exits, in about a second.
- `./build.sh` builds with unused-code checks on. `./build.sh run` plays.
- Look at every visual change yourself before showing it: `build/odincraft --shot=out.png` waits for the world to load, writes one 2560 × 1440 frame and exits. Add `--fly`, and place the camera with `--above=x,height,z` (height over the ground) or `--pos=x,y,z`, `--look=yaw,pitch` in degrees and `--hour=`. The region is 8,192 m square around its origin, and the default cone island spans about -2,300 to 2,500 in x and -2,400 to 2,600 in z of it; the map shows the whole region at 8 m a pixel with -z at the top, and yaw 0 looks toward -z. Other kinds and seeds put the land elsewhere: read the map first. The PNG is uncompressed; shrink it with `sips -Z 1600 -s format jpeg` before reading it.
- Check frame pacing after any change to drawing or streaming: `build/odincraft --bench=15 --fly --speed=120 --above=-900,60,1700 --look=90,0`, which crosses the default island's south flank over forest. The target is no frame over 12.5 ms. Without `--fly` the same option runs along the ground, which exercises collision, and prints how far it got.
- After any change to the land, the rock or trees, fly fast across the steepest ground of each kind, since steep land finds bugs gentle land hides: `build/odincraft --bench=20 --fly --speed=200 --above=0,80,-2000 --look=180,0` crosses the default island's summit, and `--kind=` with a path read off the map covers the others.
- After any change to the player, trees or the start, run `build/odincraft --bench=8` with no position: that is how the owner starts, on a river bank, and about 60 m is the expected distance.
- The start-up lines print the island's kind and history, its rock, how long it took to form (keep it near one second) and how long a step cut at the coast takes to climb to the farthest stream head; the length of the last phase against that says how finished the land is.
- A dark or odd patch in a screenshot is usually real geometry lit truthfully. Move the camera to it before changing the mesher.
- Place cameras with `--above`, not `--pos`, near the ground. A camera inside the ground sees sky through the terrain and looks like missing water or missing land.
- Water takes time to move, and its animation drifts over time. Test it late and with numbers: `--after=45` delays a screenshot, `--dig=x0,y0,z0,x1,y1,z1` clears a box of blocks once the world has loaded (repeatable; `--after` then counts from the dig), and `--probe=x0,z0,x1,z1` prints ground, water depth and whether each column is supplied when the game exits. Probe across a river first to find its banks.
