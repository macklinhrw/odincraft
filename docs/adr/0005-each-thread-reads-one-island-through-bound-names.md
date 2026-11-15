# Each thread reads one island through names it binds

The world holds every island of the archipelago at once, each region formed from its own record and seed. What forming makes for an island (its land, rock, rivers, features, trails, animals, named places) is held in one record per island, `Formed`, and every system reads its part under the name it had when there was one island: `land`, `region`, `rivers`, `seed` and the rest are thread-local pointers that a thread points at the island in hand (`bind`) before it reads. Forming an island binds it on the thread that forms it; building a chunk binds column by column; posing creatures and drawing rivers bind each island in turn; the frame thread otherwise keeps the start island bound. We chose this over passing the island to every procedure, which would have touched several hundred lines and every field reader in the catalogues, and over one island's state swapped in and out of plain globals, which cannot form two islands at once or build a chunk while an island forms.

## Consequences

- A package-level variable that forming writes is a race between islands formed side by side. A system keeps its state in `Formed`, with its pointer set in `bind`; a table filled from the catalogues alone is filled once at start (`crowns`). The thread sanitizer found no race when this was built (2026-11-15).
- A procedure that forgets to bind reads whatever island its thread last bound, silently. Every entry point that takes a point in the world binds first (`bind_at`, `height_in_world`), and a scope that reads another island uses `bound`, which restores the binding at its end.
- An island comes out the same formed alone or beside others: three islands' maps, alone and side by side, were identical bit for bit on two seeds.
- Reading through a pointer costs: forming takes 3 to 8% longer than with plain globals. Thread-local pointers cost the same as plain ones (measured), since the compiler hoists their address out of loops.
- Each formed island is held whole, about 40 MB. The world-frame design's summaries of a few kilobytes for distant islands, formed again on approach, are not built.
- Standard output drops what a thread forming quietly writes (`quiet_init`), so the forming code prints as it always has and an island formed beside play or beside another says one line.
