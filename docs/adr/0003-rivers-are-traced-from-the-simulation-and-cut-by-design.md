# Rivers are traced from the simulation and cut by design

The land simulation runs on 16 m cells, which is fine enough to form a valley and too coarse to hold a stream two metres wide. So the simulation supplies where water runs, how much of it, and a surface that only ever falls toward the sea. Channels are then designed along those lines: width from the land drained, a slight wander, a gravel bar and a cut bank at each bend, level pools with sheer drops on steep ground, and a strip of valley floor either side. The water is a ribbon drawn at its true level, in fractions of a metre, and is not made of blocks.

We chose this over simulating channels directly, which needs metre-scale cells across the whole island, and over carving rivers into finished terrain without regard to how the land drains, which every earlier attempt did and which produced rivers that floated or looked dug.

## Consequences

- Water exists only in the ribbon and the sea. Low ground beside a river does not flood, and there are no lakes yet. A lake needs a hollow the simulation keeps instead of filling.
- A pool sits at or below the simulated surface and never above it, so a river cannot end up perched above its own valley.
- At the coast the simulation's first sea cell is often only ankle deep, so each channel carries on along the sea bed, with its banks under the surface, until the water is about two metres deep.
- The ribbon is one mesh for the whole island, drawn at every distance. Far terrain columns that a stream crosses are lowered beneath it, which widens distant valley floors by up to a cell.
- The water's edge is a smooth line over square blocks, so in places it laps a little onto a bank block.
