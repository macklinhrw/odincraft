# Water near the player is a depth in every column

Within the block volume, about 256 m, water is simulated: each column holds a depth of water standing on its ground, and thirty times a second water crosses each edge from the higher surface to the lower. It runs downhill, settles level, pours into anything dug beside it and is drawn as its own surface, in fractions of a metre. The land's water is the supply: a column that the land itself put under a river is topped up to the river's level, and the sea is held at sea level. Dry ground beside a river is not a source, however deep it is dug, until something lets the water in. Beyond the volume, rivers and sea are drawn from the generator and give way, chunk by chunk, to the simulated water.

We chose a depth per column over water blocks, which can only stand at whole metres and which earlier attempts could not make look right, and over drawn surfaces alone, which overlapped at river mouths and could not respond to digging. The owner asked for water that flows, fills, animates and reacts to broken blocks (2026-11-10).

## Consequences

- One depth per column means water cannot stand under a roof: it does not fill caves or flow beneath an overhang. Tree crowns are ignored, so water passes under trees.
- Water is not conserved. Rivers are endless sources and the sea an endless sink. Water with no supply behind it sinks away at about a metre in four minutes.
- The water's state lives only while its chunk is loaded. Walk away and come back, and a flooded pit starts again from the land's own water.
- The river's designed level and the simulation must agree at rest, so the generator cuts each channel with banks that stand clear of the level and a raised lip above each drop to hold the pool behind it.
- A sheet of falling water leans out from the block it falls past. Drawn flat against the block, the two share a plane and flicker.
- The step runs on the frame thread and costs about 2 ms when it runs. Chunks with no water in reach are skipped.
