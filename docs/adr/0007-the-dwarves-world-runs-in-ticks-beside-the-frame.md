# The dwarves' world runs in ticks beside the frame, from the seed and a list of orders

The dwarves' world is a simulation of its own (`hold.odin`). It advances in ticks of a tenth of a second. Everything it is lies in one record, `Hold`: the party, where each dwarf is in its step, the ground it has read, the orders and the log. One thread runs it and nothing else touches that record. The same seed and the same orders, each with the tick it is obeyed at, give the same log every time, with a window or without one (`plan.md`, section 6).

The frame thread and the hold pass three things, under one mutex the frame only tries:

- **Orders in.** The frame appends to an inbox (`hold_send`, `hold_block`). The hold takes them at the start of its next tick, stamps them with that tick and writes them in the log in the form an orders file is read in. So the log of a played game is itself an orders file, and playing it again gives the same events.
- **A picture out.** After each tick the hold lays out `Shown`: where the boat and every dwarf stood at that tick and at the one before, and what each was doing. The frame copies it and draws between the two.
- **The clock.** The frame says which tick its clock has reached. The hold runs up to it and waits. A hold busy finding a way falls behind, and the frame's clock is then held to two ticks past what was shown: the dwarves' time stretches, and they are never hurried after.

With no window (`--dwarves=seconds --orders=file`) the same thread runs flat out to the time asked and the log is printed. A picture (`--shot`) is of one moment: the hold is run to `--dwarves` and does not move while the frame is drawn.

We chose a thread of its own over stepping the hold on the frame thread, as the water is stepped (ADR 0004): finding a way across 500 m takes 0.2 to 0.5 s when the ground has not been read before, forty frames' worth. We chose ticks stamped on orders over a clock shared with the frame, which would make what happens depend on how fast frames come. We chose a record with one owner over state reached through names bound per thread (ADR 0005), which exists to let many threads read one island: here one thread writes.

## How it learns the ground

Through the generator, as everything does (ADR 0001): a chunk's blocks are made by `gen_columns` and `build_volume`, the calls the world's workers make, with the session's edits laid over them, and read once into a patch of floors and the steps between them (`paths.odin`). The hold never reads the world the frame streams, which holds only what is near the camera and loads in an order that depends on the machine. It keeps its own list of the session's edits, each of which came to it as an order with a tick.

It never reads the simulated water (ADR 0004) either: a dwarf wades by the level the land gives a column, not by the depth standing there in this frame.

## Consequences

- A change to a block reaches the hold as an order, `block x y z Material`, sent from `world_set`. Anything that changes blocks by another road is invisible to the dwarves.
- A dwarf can wade water the simulation has since drained, and walk dry through a pit the player has flooded. The two agree wherever nothing has been dug.
- Whatever the hold prints with a time in front is in the log and its hash. Timings are not: they are printed in brackets without a time, and are not the same twice.
- The hold's ground is read chunk by chunk and never let go: about 39 KB a chunk walked or searched, 8.2 MB for the 210 chunks of the run in `plan.md`. A changed block forgets the up to four patches that read it, and their floors are not given back.
- The frame draws a dwarf one tick late, a tenth of a second, so that it always has two ticks to draw between.
- `./build.sh test` runs the hold twice on the start island, once beside a thread that reads it and moves its clock in fits, and compares the logs. It keeps no golden hash: what the dwarves do follows the land, which changes on purpose. It runs inside the forming test, because the test runner frees what a test made when the test ends, so only one test can form the world.
- The frame may read `hold.party`, which is drawn once and not changed. When the party can change (a death, a migrant), it must go through `Shown`.
- The log is the hold's own and the frame cannot read it. An interface that shows what happened as messages (`foundations/interface.md`, I5) needs the new lines passed out as `Shown` is.
