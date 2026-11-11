# OdinCraft v5

A small first-person block game used to test directions for world generation, look and gameplay. The owner decides direction and judges everything visual by looking; record each decision in `docs/open-decisions.md` the moment it is made.

- `docs/ideas.md`: read before proposing a feature.
- `docs/lessons.md`: read before proposing architecture, a plan or a way of working.
- `docs/adr/`: why the engine is shaped as it is. Read before changing level of detail or lighting.
- `reference/README.md`: index of the earlier projects' idea documents, kept verbatim.

The sibling folders `../odincraft-v1` to `v4` and `../zigcraft*` hold the earlier attempts. Read their code only to learn what a feature did for the player. Design every implementation fresh.

## Working on the code

- Keep it small. The whole game is about 3,000 lines; prefer changing a rule to adding a system.
- What the world is lives in three files: `land.odin` forms the island, `rivers.odin` traces and cuts the rivers, `gen.odin` answers the engine's questions from both. `water.odin` then moves the water near the player.
- Judge a change to the land from the map first: `build/odincraft --map=out.png` forms the island, writes a 1024-pixel relief map with rivers and exits, in about a second.
- `./build.sh` builds with unused-code checks on. `./build.sh run` plays.
- Look at every visual change yourself before showing it: `build/odincraft --shot=out.png` waits for the world to load, writes one 2560 × 1440 frame and exits. Add `--fly`, and place the camera with `--above=x,height,z` (height over the ground) or `--pos=x,y,z`, `--look=yaw,pitch` in degrees and `--hour=`. The island spans about -3,400 to 3,500 in x and -2,600 to 2,900 in z; the map shows -4,096 to 4,096 at 8 m a pixel with -z at the top, and yaw 0 looks toward -z. The PNG is uncompressed; shrink it with `sips -Z 1600 -s format jpeg` before reading it.
- Check frame pacing after any change to drawing or streaming: `build/odincraft --bench=15 --fly --speed=120 --above=-2500,60,1500 --look=80,0`. The target is no frame over 12.5 ms. Without `--fly` the same option runs along the ground, which exercises collision, and prints how far it got.
- After any change to the player, trees or the start, run `build/odincraft --bench=8` with no position: that is how the owner starts, on a river bank, and about 57 m is the expected distance.
- A dark or odd patch in a screenshot is usually real geometry lit truthfully. Move the camera to it before changing the mesher.
- Place cameras with `--above`, not `--pos`, near the ground. A camera inside the ground sees sky through the terrain and looks like missing water or missing land.
- Water takes time to move, and its animation drifts over time. Test it late and with numbers: `--after=45` delays a screenshot, `--dig=x0,y0,z0,x1,y1,z1` clears a box of blocks once the world has loaded (repeatable; `--after` then counts from the dig), and `--probe=x0,z0,x1,z1` prints ground, water depth and whether each column is supplied when the game exits. Probe across a river first to find its banks.
