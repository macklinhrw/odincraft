# Agent notes

Odincraft is a block game in Odin, SDL3 GPU and Metal (macOS, Apple Silicon): a generated world that feels like a real place, with a history, in which the player founds and keeps a hold of dwarves, after the ideas of Dwarf Fortress first and RimWorld second. The natural world is the foundation and is never traded away for play. The owner sets direction and judges every visual result by looking. Record each decision in `docs/open-decisions.md` as soon as it is made.

## Read first

- `ARCHITECTURE.md`: module map, data flow, where to start.
- `docs/plan.md`: the plan from 2026-11-16 on, in two tracks, the natural world (N) and play (P), with the stories it is for and its rules.
- `docs/foundations.md`: the foundations, and the steps built so far with what each taught. Read sections 3 and 8 before adding to land, rock, water, plants or living things.
- `docs/adr/`: read before changing level of detail, lighting, threading or water.
- `docs/interesting-world/notes/real-islands.md`: the real islands the land is measured against. Judge a change to the land by those figures.
- `docs/lessons.md`: why earlier attempts stalled. Read it before proposing architecture or a way of working.

The longer working notes this file replaced are in the history of `CLAUDE.md` (now a link to this file).

## Rules of the code

- `gen.odin` is the only way the engine learns about the world. Every query takes a cell size (ADR 0001).
- Forming must stay deterministic. An island comes out bit for bit the same whether formed alone or beside others. Keep per-island state in `Formed` and read it through the bound names (`regions.odin`, ADR 0005). A package-level variable that forming writes is a race.
- Rules are rows on named fields (`FIELDS` in `fields.odin`). A new kind of condition becomes a new field, not code in a row.
- A block is a `Mat`, 16 bits wherever it is kept. A rule asks what a material is through its traits (`TRAITS` in `gen.odin`, `is(m, LEAVES)`); never write a `bit_set[Mat]`, which holds no more than 128 materials.
- What lives on an island is never a preference: a plant or animal is there because it could reach the island, the island can keep it, and the seed drew it. Give it a row that decides, and print why not.
- Keep it small. Prefer changing a rule to adding a system.

## Checking work

```sh
odin check src -vet-unused             # what CI runs
./build.sh                             # build/odincraft
./build.sh test                        # forming is deterministic (src/forming_test.odin)
build/odincraft --map=out/a.png        # forming changes: compare maps byte for byte against the parent
build/odincraft --shot=out/v.png --above=x,h,z --look=yaw,pitch --hour=h   # a picture for the owner
```

The two benches, after any change to drawing, streaming, trees or the start (target: no frame over 12.5 ms):

```sh
build/odincraft --bench=15 --fly --speed=120 --above=-2500,60,-600 --look=90,0   # forest flank
build/odincraft --bench=10 --fly --speed=60 --pos=500,700,-1000 --look=200,-35  # down through cloud
```

The first run of a world's seed runs the plates' history (about 2 s) and keeps the known world in `build/worlds/`, keyed by `plates.odin` and `known.odin`; later runs read it back.

`./build.sh test` hashes what forming leaves. A change that alters the land on purpose updates `GOLDEN` in `src/forming_test.odin` and says so in its commit message.

Never open a window unless asked to. Use `--shot` or `--bench`, which draw unseen; the binary refuses to open a window without a terminal. Place cameras with `--above` near the ground, since a camera inside the ground sees sky through it. Put outputs in `out/`, which is ignored.

## Commits

One step per branch, merged with a message that says what changed for the player and how it was checked. Commit as the repository's configured git identity, with no co-author trailers.
