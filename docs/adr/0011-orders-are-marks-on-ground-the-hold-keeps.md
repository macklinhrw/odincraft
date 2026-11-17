# Orders are marks on the ground, and the hold keeps the blocks it works

An order beyond "go" (`plan.md`, P3) marks blocks of the world: ground to dig, trees to fell, blocks to lay. The marks belong to the dwarves' world (`orders.odin`, ADR 0009): each is a block, the order it came from, the dwarf that has taken it if any, and why it is not being worked if it is not. An order arrives as every order does, with the tick it is obeyed at, from the frame or from an orders file, and the log prints it in the file's form. So the same orders give the same marks, the same work and the same blocks every time.

## Dwarves take the work

Nobody is assigned. A dwarf with nothing in hand looks at the dozen marks nearest it that nobody has taken, one of its own trade counting as half as far, and takes the first it can stand beside and has a way to (the way is found as any way is, `paths.odin`). It walks there, works for a time the material and its trade set, and the block changes. The dwarf that finished a block looks for the next before any idle dwarf does, so a face keeps its worker; a dwarf whose trade the work is not leaves a mark once for an idle dwarf whose trade it is. A few dwarves look in a tick, and one that found nothing rests three seconds, so the looking costs the same for seven dwarves and seven thousand marks as for a hundred and six thousand: tens of microseconds.

We chose marks the dwarves take over jobs handed out by a planner because the player is the will of the hold and not its foreman (`interesting-world/notes/df-rimworld-ideas.md`), and because a mark that waits can say why in its own words: the blocks in front are dug first, no dwarf has a way, the places to work from are taken, the rock is too hard, a tree stands on it, nothing is in store, nothing to lay it against, a dwarf stands in the way, the work would shut a dwarf in.

## What one-metre blocks make of it

A dwarf stands under a block and a half and steps one block, so a room is two blocks high and a stair a block to a step. An order to dig a box one block high is dug two high, down from the block marked, so that the cut which showed the mark shows the room. A stair is its own shape: dug, down a block a column with three blocks of room over each step; built, up a block a column. A wall is two high over the block the drag began on; a floor one layer at that level. A dwarf works what is beside it from a block under its feet to a block over its head, what is right over its head, and what is two down or two up in the next column where the block between is open.

## No dwarf is shut in by the work

Digging the last step out of a pit, or laying the last block of a wall, can leave a dwarf with no way out. Before a block is dug that a dwarf could stand on, and before any block is laid, the hold floods the floors joined to each floor beside it, up to 3,000 of them; where a flood runs out, that ground is a pocket, and the dwarves standing in pockets are counted. The change is made and they are counted again. If there are more, the change is taken back and the mark waits; an idle dwarf that was the cause is sent out. The count is local, 0.2 ms, and needs no notion of home.

We chose this over asking, before each block, whether every dwarf still has a way to some place called home: a way home is far, costs a search, and has no answer when the party has moved. We chose it over letting dwarves climb two blocks when trapped, which would be a second kind of walking kept for emergencies. The price is that a pit deeper than two blocks ends with its last blocks left as its stair and its order unfinished, and that closed ground of 3,000 floors or more is taken for open country.

A dwarf shut in by anything else (the player's own hand on the blocks) says so, in the log, on its card and as an alert, and is let out by any stair dug or built to it: an order like another.

## The hold's ground stays real

The hold reads the ground from the generator and its own edits and never from the frame's world (ADR 0009). Until now a changed block made it read the chunk from the generator again: 3 ms, and the chunk's old floors left behind for good. With dwarves changing thousands of blocks that would be seconds and hundreds of megabytes.

So a chunk the hold has changed, or asked a block of, keeps its blocks: about 155 KB (`Kept`, `paths.odin`). A changed block is one block written there, and the chunk's floors and rooms are read again from memory into the places they had among the walk's floors, with room to grow. The generator is asked again only when a change falls outside the layers kept, or a tree is felled.

Each change the dwarves make is passed to the frame through the queue that carried an orders file's blocks. The frame records it among the session's edits and rebuilds the chunk if it is loaded. When the camera is elsewhere the dwarves go on by their own blocks, and when it comes back the chunk is built with the edits over it.

A felled tree is not a block changed but a tree taken out: an edit at its foot, of a material that is only ever a face (a trunk's rings), tells the generator to leave the tree out of every chunk its crown reached.

## Consequences

- The hold's memory grows with the ground it works: 155 KB a chunk of kept blocks and 16 bytes a changed block, and as much again in the frame's session edits. A hold 320 m square of worked ground is about 16 MB. Kept blocks are never let go, and nothing is on disk until the world is kept (P6).
- Beyond the nearest 256 m the ground is drawn as columns, which show neither a pit nor a felled tree.
- What is dug goes to a store that is a count by kind, and building takes from the count: goods are nowhere in the world until they are carried (P5).
- A block laid needs a block beside it and nothing under it. Nothing falls.
- What the frame knows of the orders is in `Shown`: each order with work left, how many dwarves are at it and how many marks wait for each cause; the boxes of ground still to dig, which the terrain's shader tints, sixteen a picture; and the trees and cells marked, drawn as boxes.
- A dwarf at work is a dwarf standing, to one that walks: it is gone round, or squeezed past and set a floor back, and then walks to its place again. Where there are more hands than places to work from, that costs more than the hands give.
- `./build.sh test` hashes the blocks the hold changed and its store as well as the log, as played and as played again from the orders.
