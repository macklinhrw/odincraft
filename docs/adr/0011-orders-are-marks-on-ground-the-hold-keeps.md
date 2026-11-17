# Orders are marks on the ground, and the hold keeps the blocks it works

An order beyond "go" (`plan.md`, P3) marks blocks of the world: ground to dig, trees to fell, blocks to lay. The marks belong to the dwarves' world (`orders.odin`, ADR 0009): each is a block, the order it came from, the dwarf that has taken it if any, and why it is not being worked if it is not. An order arrives as every order does, with the tick it is obeyed at, from the frame or from an orders file, and the log prints it in the file's form. So the same orders give the same marks, the same work and the same blocks every time.

## Dwarves take the work

Nobody is assigned. A dwarf with nothing in hand looks at the two dozen marks nearest it that nobody has taken, one of its own trade counting as half as far, and takes the first it can stand beside and has a way to (the way is found as any way is, `paths.odin`). It walks there, works for a time the material and its trade set, and the block changes. The dwarf that finished a block looks for the next before any idle dwarf does, so a face keeps its worker; a dwarf whose trade the work is not leaves a mark once for an idle dwarf whose trade it is. Four dwarves may look in a tick, and one that found nothing looks again in a second.

We chose marks the dwarves take over jobs handed out by a planner because the player is the will of the hold and not its foreman (`interesting-world/notes/df-rimworld-ideas.md`), and because a mark that waits can say why in its own words: the blocks in front are dug first, no dwarf has a way, the places to work from are taken, the rock is too hard, a tree stands on it, nothing is in store, nothing to lay it against, a dwarf stands in the way, the work would shut a dwarf in.

**Why a mark waits is the mark's where it is true of every dwarf, and the dwarf's where it is not.** "No way" and "its places are taken" are found by one dwarf and hide the mark from that dwarf alone for two seconds; the others still try it. P3 kept them on the mark, so one dwarf that could not come at a block hid it from the six that could, again and again, and the screen said no dwarf could reach it (found by playing, 2026-11-16). An idle dwarf standing on the floor a block is worked from is woken to take the block; one standing on a marked block steps off it; and whether a block would shut a dwarf in is asked before the work on it is begun as well as at its end.

## What one-metre blocks make of it

A dwarf stands under a block and a half and steps one block. An order is named for what the player gets, as Dwarf Fortress's and Ingnomia's are (`interesting-world/notes/colony-sim-reference.md`, section 2), and marks by area on one level:

- **Dig out** marks every block of ground in a rectangle from the level the drag began on down as deep as the player set, two for a space to stand in. Into a hillside it is a room under the hill; on flat ground a pit.
- **Stair down** and **stair up** are a block down or up for each block along, three blocks of room over each step.
- **Wall** is one or two blocks high and stands on the ground along the line dragged, following it where it steps, so a mason on the ground reaches all of it; **floor** is one layer at that level; a built **stair** goes up a block a column.

A dwarf works what is beside it from a block under its feet to a block over its head, what is right over its head, and what is two down or two up in the next column where the block between is open. A mason lays from the lowest floor that reaches, so a wall is built from the ground beside it.

**Every dig is given its way in and out** (`way_in`, `orders.odin`). From the cells a dwarf will stand in once the order is dug, a passage is searched outward through the ground, level or a step up or down, to the nearest open ground a dwarf can stand on today, and its blocks are marked with the order: a notch of steps in a pit's rim, a passage to a room marked inside a hill. Open ground is a floor joined to 150 others, so a shelf of a sea cliff beside the dig does not count. The way does not pass under leaves, through rock too hard for the picks, or end in water deeper than a dwarf wades. We chose this over P3's rule, which left a pit's last blocks standing as its stair and its order unfinished, and over a bare pit, which no game of this kind leaves (Ingnomia's hole makes ramps; Dwarf Fortress pairs stairs).

**What an order marks is one rule asked of two worlds** (`cells_of`, through `Blocks`): the hold asks its own ground when the order is obeyed, and the frame asks the blocks it draws, every frame, for what is under the pointer and through the drag. So what the player is shown is what will be marked, where the frame's blocks and the hold's agree.

## No dwarf is shut in by the work

Digging a block out from under the only way, or laying the last block of a wall, can leave a dwarf with no way out. Before work is begun on a block a dwarf could stand on, before any is laid, and again when the work is done, the hold floods the floors joined to each floor beside it, up to 3,000 of them; where a flood runs out, that ground is a pocket, and the dwarves standing in pockets are counted. The change is made and they are counted again. If there are more, the change is taken back and the mark waits; an idle dwarf that was the cause is sent out. The count is local, 0.2 ms, and needs no notion of home.

We chose this over asking, before each block, whether every dwarf still has a way to some place called home: a way home is far, costs a search, and has no answer when the party has moved. With every dig given its way out, the count is a guard that seldom holds a block back.

A dwarf shut in by anything else (the player's own hand on the blocks) says so, in the log, on its card and as an alert, and is let out by any stair dug or built to it: an order like another.

## The hold's ground stays real

The hold reads the ground from the generator and its own edits and never from the frame's world (ADR 0009). Until now a changed block made it read the chunk from the generator again: 3 ms, and the chunk's old floors left behind for good. With dwarves changing thousands of blocks that would be seconds and hundreds of megabytes.

So a chunk the hold has changed, or asked a block of, keeps its blocks: about 155 KB (`Kept`, `paths.odin`). A changed block is one block written there, and the chunk's floors and rooms are read again from memory into the places they had among the walk's floors, with room to grow. The generator is asked again only when a change falls outside the layers kept, or a tree is felled.

Each change the dwarves make is passed to the frame through the queue that carried an orders file's blocks. The frame records it among the session's edits and rebuilds the chunk if it is loaded. When the camera is elsewhere the dwarves go on by their own blocks, and when it comes back the chunk is built with the edits over it.

A felled tree is not a block changed but a tree taken out: an edit in its trunk's column far under the world (`FELLED`), of a material that is only ever a face (a trunk's rings), tells the generator to leave the tree out of every chunk its crown reached. It is kept under the world and not at the tree's foot because a block laid or dug at the foot would take its place, and the tree would stand again.

## Consequences

- The hold's memory grows with the ground it works: 155 KB a chunk of kept blocks and 16 bytes a changed block, and as much again in the frame's session edits. A hold 320 m square of worked ground is about 16 MB. Kept blocks are never let go, and nothing is on disk until the world is kept (P6).
- Beyond the nearest 256 m the ground is drawn as columns, which show neither a pit nor a felled tree.
- What is dug lies where it was dug, a thing in a cell, and a block is laid of a thing brought to it (ADR 0012). P3 counted it into a store with no place.
- A block laid needs a block beside it and nothing under it. Nothing falls.
- What the frame knows of the orders is in `Shown`: each order with work left, how many dwarves are at it and how many marks wait for each cause; the ground still to dig as the fewest boxes a sweep of its marks finds (`boxes_of`), which the terrain's shader tints, forty-eight a picture, with the ground over each faintly; and the trees and cells marked, drawn as boxes.
- **Taking marks back is by column**: every mark in the columns dragged over, and no other. An order may be trimmed, and its end says what was done of it. Where no mark lies under it, Remove takes built blocks down, and with none of those takes ground out of a stockpile (ADR 0012).
- **A way in is searched every way at once through about ten blocks of ground, and beyond that as a straight stair or passage** up to 64 blocks long, rising, level or falling, the four ways from each cell stood in: under flat ground a room sixty blocks down gets a stair as long as it is deep. Where neither finds one, the order says so on its mark and its card: dig a stair or a passage to it first.
- **Timber is laid as `Mat.Timber`**, a block of sawn boards that is no tree's. A tree's bark block laid by hand is still drawn as a trunk by the mesher's rule.
- A dwarf at work keeps its place, and a walker goes by it (ADR 0012, "Friends do not block one another").
- `./build.sh test` hashes the blocks the hold changed and its store as well as the log, as played and as played again from the orders.
