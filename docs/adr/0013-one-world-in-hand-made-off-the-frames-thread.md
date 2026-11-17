# The game holds one world in hand, made in stages off the frame's thread

The game has a front door and a world's screen before play (`foundations/interface.md`, section 5). Both must be drawn at the screen's rate while a world is made, and say truly how far it has come. So the world is no longer made by start-up before a window exists: it is ordered (`world_open`, `making.odin`) and made on a thread of its own, in stages the frame reads each frame.

- **The plates' history** and **the region round the start**: `known_make`, as the command line calls it, then the islands' records and who reached each. The frame reads the planet's own clock for how far these have come, a word read without a lock and used for nothing but the figure shown.
- **The islands near the start**: the start island and those within `near` km, formed side by side by `gen_init`. When they are formed the world can be entered.
- **The far islands**: on three threads of low priority, beside whatever the player does.

Every stage is the procedure the command line runs, so a world made from the front door is the world `--seed=` makes: the start island's land hashes the same either way, and the same after another world was made first in the same run (measured on seeds 7 and 12).

There is one world in hand at a time. Its records are package-level (`known`, `archipelago`, `formed`), as they always were; ordering another world stops the forming threads, waits for the island each has in hand, puts the old world down and makes the new one. The frame's thread reads nothing of a world between the order and the moment its records are made (`making.records`, set under a mutex with the count of orders, so that a job an order has overtaken shows nothing).

We chose this over a process for each world, which would need no putting down and would close and reopen the window when the player chooses another world, a thing no run without a window can check. We chose it over giving each world its own record passed to every procedure, which is ADR 0005's choice again at the next scale and would touch every reader of the known world.

## Consequences

- **A world put down leaves its formed islands in memory.** An island's fields are carved from blocks (`carve`, `land.odin`) and its records hold slices into them, so nothing outside forming can free one safely. About 40 MB an island: a run that opens several worlds grows by what each had formed. It ends when islands are kept as summaries and formed again on approach (ADR 0005, consequences), or when forming allocates an island from one arena.
- **Forming cannot be stopped inside an island, nor the plates' history inside its run.** "Stop" begins no more islands; the one in hand is finished, and a history under way runs to its end and is kept.
- Forming threads for play and for the screens before it are the same pools (`forming_begin`), kept so that they can be waited for and stopped. Start-up's straight way in (`main`) uses them too, so that play can be left for the world's screen.
- Play is a procedure (`game`, `main.odin`) that can be entered and left more than once in a run. What a game held is let go when it is left (`game_end`), and the play screen is put back as it begins (`play_again`).
- The map's pictures are painted on one more thread of low priority, begun when a world's records are made and ended before they are put down (`chart.odin`).
- What the frame's thread keeps of islands on the GPU is let go by the frame's thread before the order is given (`world_gpu_drop`).
