# Agent notes

Odincraft is a block game in Odin, SDL3 GPU and Metal (macOS, Apple Silicon): a generated world that feels like a real place, with a history, in which the player founds and keeps a hold of dwarves, after the ideas of Dwarf Fortress first and RimWorld second. The natural world is the foundation and is never traded away for play. The owner sets direction and judges every visual result by looking. Record each decision in `docs/open-decisions.md` as soon as it is made.

## Read first

- `ARCHITECTURE.md`: module map, data flow, where to start.
- `docs/plan.md`: the plan from 2026-11-16 on, in two tracks, the natural world (N) and play (P), with the stories it is for and its rules.
- `docs/foundations.md`: the foundations, and the steps built so far with what each taught. Read sections 3 and 8 before adding to land, rock, water, plants or living things.
- `docs/foundations/interface.md`: where everything on the screen goes and why. Read it before adding anything the player sees or clicks.
- `docs/adr/`: read before changing level of detail, lighting, threading, water, the view from above and its cut, the clock, or the dwarves' world.
- `docs/interesting-world/notes/real-islands.md`: the real islands the land is measured against. Judge a change to the land by those figures.
- `docs/lessons.md`: why earlier attempts stalled. Read it before proposing architecture or a way of working.

The longer working notes this file replaced are in the history of `CLAUDE.md` (now a link to this file).

## Rules of the code

- `gen.odin` is the only way the engine learns about the world. Every query takes a cell size (ADR 0001).
- Forming must stay deterministic. An island comes out bit for bit the same whether formed alone or beside others. Keep per-island state in `Formed` and read it through the bound names (`regions.odin`, ADR 0005). A package-level variable that forming writes is a race.
- Rules are rows on named fields (`FIELDS` in `fields.odin`). A new kind of condition becomes a new field, not code in a row.
- A block is a `Mat`, 16 bits wherever it is kept. A rule asks what a material is through its traits (`TRAITS` in `gen.odin`, `is(m, LEAVES)`); never write a `bit_set[Mat]`, which holds no more than 128 materials.
- What lives on an island is never a preference: a plant or animal is there because it could reach the island, the island can keep it, and the seed drew it. Give it a row that decides, and print why not.
- The dwarves' world must stay deterministic (ADR 0009). Only the thread running it touches `Hold`. The frame sends it orders and reads `Shown`. It learns the ground from `gen.odin` and its own list of edits, never from the frame's `World`, the simulated water or a clock. Nothing in it may count on seven dwarves: the hold grows. A dwarf takes up its floor: whatever moves a dwarf to another floor does it through `take`, and whatever changes a block settles the dwarves in its column (`settle`).
- Keep it small. Prefer changing a rule to adding a system.

## Checking work

```sh
odin check src -vet-unused             # what CI runs
./build.sh                             # build/odincraft
./build.sh test                        # forming is deterministic (src/forming_test.odin)
build/odincraft --map=out/a.png        # forming changes: compare maps byte for byte against the parent
build/odincraft --shot=out/v.png --above=x,h,z --look=yaw,pitch --hour=h   # a picture in first person, for the owner
build/odincraft --shot=out/v.png --over=x,z --span=metres --tilt=degrees --turn=degrees --cut=level   # a picture from above
build/odincraft --dwarves=600 --orders=out/orders.txt   # the dwarves' world with no window: its log, the log's hash, what it cost
build/odincraft --shot=out/v.png --over=x,z --select=x,y --say   # a picture of the interface with a thing in the hand, and what the screen says
build/odincraft --shot=out/v.png --above=x,h,z --plain   # a picture of the world alone, with no interface
```

The game starts in the view from above (`src/above.odin`); `--over` puts it somewhere, and any of `--pos`, `--above`, `--look`, `--fly`, `--place` and `--first` give first person. `--cut=ground` holds the cut over the ground under the view's middle, `--bare` leaves out the leaves, `--cursor=x,y` puts the pointer at a pixel of the picture and says the block under it (with `--why`, why), and `--cursor=x,y,x,y` marks the box between two. `--pace=0`, `2` or `4` pauses or hurries the world's clock, and a bench says how far it ran.

**Every picture has the interface on it** (`src/play.odin`). A picture meant to show the land takes `--plain`. A picture of the interface puts it in a state: `--select=x,y` takes the thing under that pixel in the hand (`--tab=rock`, `ground`, `plants`, `near` or `world` chooses the card's depth); `--list=places` opens the list and `--row=N` chooses its Nth named place, which takes the view there; `--lens=rock`, `water-table`, `rain`, `livable`, `plants`, `soil` or `leaves` puts a lens on and `--lenses` opens their choices; `--cut=level --drag` shows the cut's mark as it is while dragged; `--menu`; `--lessons`; `--tell=words` and `--alert=words`; `--scale=75` to `200`. `--say` with `--shot` prints what the screen says, area by area, each part with the key written on it and its name, which is how to check a screen without looking and how `src/play_test.odin` presses a button. Every colour, typeface, size and spacing is in `LOOK` (`src/ui.odin`); a key is a row of `BINDS` (`src/play.odin`).

The three benches, after any change to drawing, streaming, trees or the start (target: no frame over 12.5 ms):

```sh
build/odincraft --bench=15 --fly --speed=120 --above=-2500,60,-600 --look=90,0   # forest flank
build/odincraft --bench=10 --fly --speed=60 --pos=500,700,-1000 --look=200,-35  # down through cloud
build/odincraft --bench=15 --over=-2500,-600 --turn=90 --speed=120 --span=200 --cut=ground   # from above, the cut following the ground
```

The first run of a world's seed runs the plates' history (about 2 s) and keeps the known world in `build/worlds/`, keyed by `plates.odin` and `known.odin`; later runs read it back.

`--dwarves=seconds` runs the dwarves' world that long and exits. The same seed and orders must print the same hash twice. An orders file has a time and an order on each line: `120 go 2620 -1720` (the ground at a column), `6:40.0 go 2300 76 -1380` (a block to stand on), `300 block 2700 3 -1750 Air` (a block changed). The log prints an order it obeyed in this form, so a played game's log can be played again. Add `--shot` for a picture of that moment, `--why=x,z` to ask a dwarf standing there who it is, `--cursor=x,y --send` with `--bench` and `--over` to send the party to the block under the pointer as a right click does, or `--party=N` to measure a larger hold. Start-up says where the party lands. A bench with the dwarves on screen: `--bench=40 --over=2696,-1760 --span=80 --speed=0 --cut=ground --dwarves=115 --orders=file`.

`./build.sh test` hashes what forming leaves, then plays the dwarves' world, plays its orders again from `build/hold_test_orders.txt` alone and beside a reader, and compares the three logs. It then makes the play screen with no window, presses its buttons and asks what it says (`src/play_test.odin`). A change that alters the land on purpose updates `GOLDEN` in `src/forming_test.odin` and says so in its commit message.

Never open a window unless asked to. Use `--shot` or `--bench`, which draw unseen; the binary refuses to open a window without a terminal. Place cameras with `--above` near the ground, since a camera inside the ground sees sky through it. Put outputs in `out/`, which is ignored.

## Commits

One step per branch, merged with a message that says what changed for the player and how it was checked. Commit as the repository's configured git identity, with no co-author trailers.
