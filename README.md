# OdinCraft v5

A block world that feels like a real place, explored on foot. This is a fresh start after ten earlier attempts in Zig and Odin.

**Status (2026-11-10): a playable island.** The game forms an island about 6 km across in a second: a mountain range, valleys cut by running water, and rivers that follow those valleys to the sea. You start on a river bank and can walk, fly, dig and build, with the land drawn to the horizon under sun shadows and haze. Water flows: dig a ditch from the river and it fills. It exists to try directions for world generation, look and gameplay; see `docs/open-decisions.md`.

## Run

```sh
./build.sh run
```

Needs Odin and SDL3 (`brew install odin sdl3`) on an Apple Silicon Mac.

| | |
|---|---|
| click | capture the mouse; Esc releases it, Esc again quits |
| W A S D | move; Shift runs, or flies fast |
| Space, Ctrl | jump; rise and sink when flying |
| F | switch between walking and flying |
| left, right button | break a block, place a block |
| 1 to 6 | choose the block to place |
| [ and ] | turn the clock back and forward |
| F2 | save a screenshot to `screenshots/` |

The window title shows frame rate, the slowest recent frame, quads drawn, chunks still loading, position and time of day.

Options are listed at the top of `src/main.odin`, including ones that dig and report water depths for testing. Three are for checking work without playing:

```sh
build/odincraft --map=island.png                                                # a map of the land and rivers
build/odincraft --shot=view.png --above=1114,30,1634 --look=158,-35 --hour=15   # one frame to a file
build/odincraft --bench=15 --fly --speed=120                                    # fly and report frame times
```

## Layout

- `src/land.odin`: forms the island before play, by uplift and erosion.
- `src/rivers.odin`: traces rivers from the land's drainage and cuts their channels.
- `src/gen.odin`: what the engine asks for: the ground, its cover, its water and the trees at any point.
- `src/water.odin`: water near the player, which flows, fills and settles.
- `src/world.odin`: chunks around the camera at seven levels of detail, built on worker threads; block edits.
- `src/mesh.odin`: turns blocks and columns into quads.
- `src/render.odin`, `src/shaders.metal`: drawing, lighting, shadows, sky, water.
- `src/player.odin`, `src/main.odin`: movement, collision, input, the main loop.
- `docs/`: what the game is meant to become, lessons from earlier attempts, decisions.
- `reference/`: idea documents from the earlier projects, copied unchanged.

## Known limits

- Edits, overhangs and caves show only within about 256 m; farther terrain is drawn from surface heights.
- Edits last for the session. There are no saves.
- Water flows within about 256 m of you. It cannot stand under a roof, so it does not fill caves, and it forgets what you did to it once you walk far enough away.
- There are no lakes, no swimming and no underwater view; you wade.
- Mountains are rounded and rock is only a surface colour: no cliffs or outcrops yet.
- The level of detail switches without blending, which can be seen as a small change in shape at about 256 m.
