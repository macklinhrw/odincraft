# A screen is a list of parts, drawn over the finished picture

The interface (`foundations/interface.md`) is drawn by the game itself, with no interface library. Each frame the play screen lists its parts from the game as it stands (`play_frame`, `play.odin`): a part is a rectangle of the picture with what kind of thing it is (a panel, a button, a row, a bed of the column), what it says, the key written on it, what a click on it does, and which of the screen's places it belongs to. Nothing is kept from one frame to the next but what the player has done: what is in the hand, which list is open, how far it is scrolled.

`ui.odin` does three things with that list, and knows nothing of the game:

- **Draws it.** Each part becomes a few rectangles, each a piece of one text atlas in one colour, a tile of a block as the world shows it, or one of the three signs. They go to the GPU as one buffer and one draw, over the resolved picture of the world and before it goes to the window or to a file. So `--shot` shows the interface exactly as the window does.
- **Says which part a point is on.** The parts lie in the order listed, later over earlier. The topmost that can be pressed or is solid decides (`screen_over`). `over_world` (ADR 0007) asks it, so the world and the panels share the pointer by one rule: a press belongs to what lies under it, and so does everything until the button is let go.
- **Says the screen in words** (`screen_says`, `--say`): each place's parts, a line each, with their keys. A test presses a part by its name and reads what the screen then says, with no window and no GPU (`play_test.odin`).

Every action is an `Act`. A key is a row of `BINDS` naming an act; a button names its act and shows that row's key. So the key written on a button is the key that presses it, and changing a key is changing a row.

## Why not a library

Odin's vendor folder has three candidates. `microui` lays out and draws in its own look, with a built-in bitmap font: the look here is the design's own (I10) and its text must be sharp at six scales. `fontstash` and `stb_truetype` draw text well, but both link a compiled C library, and the Odin that Homebrew installs keeps that library where the binding does not look for it, so `./build.sh` fails on the owner's machine with `Could not find the compiled STB libraries`. The game builds with Odin and SDL3 alone, and should go on doing so.

What the interface needs of TrueType is small: which glyph a character has, how far the pen moves, the outline, and the pair adjustments. `type.odin` reads those from the file (270 lines) and draws a glyph by exact coverage. The face's own instructions for fitting itself to pixels are not run.

## Text

The interface is laid out in modules: 4 pixels at the standard scale on a picture 1,440 pixels high, and a whole number of pixels at each of the six scales from 75% to 200% (3 to 8). When the scale changes, an atlas is made for it: every glyph of every text style, drawn at the pixel size the style has at that scale (`ui_bake`). A glyph is then copied to the screen one texel to one pixel, on whole pixels, never scaled. Body text is 6 modules: 24 pixels at the standard scale (I9).

We chose an atlas for each scale over one atlas of distance fields, which stays smooth at any size but rounds the corners of small text and cannot be as sharp as a glyph drawn at its own size.

## One table for the look

Every colour, typeface, size and spacing is a field of `LOOK` (`ui.odin`), and nothing else in the code names a colour or a size. The look is the design's second pass, which the owner has not yet judged: a different one is a different table.

## Consequences

- The interface's own work is listing the parts and making the rectangles: 0.05 ms a frame for the play screen at rest, 0.2 ms with a list, a card and a lens open (measured, `plan.md`, "I-1, as built"). The list is made again every frame, so nothing can show a stale state.
- A part has no memory. Anything that must last (a scroll, a drag, a tab) is a field of `Play`, and a part's name is for tests and `--say`, not for finding it again.
- A lens paints one of the land's fields over the ground in the terrain's own shader, from a texture of the field over the island, made on a thread of its own when the lens or the island changes (`lens_follow`). The land's fields are read at 10 m there: a lens shows where, not which block.
- Messages may be told from any thread (`tell`); the frame takes them. Alerts are the frame thread's.
- Text set in a face with no hinting is a little softer than a browser's at 18 pixels and under, which is the 75% scale's body text.
- Each new typeface or style costs atlas room: eight styles at 200% fill about a quarter of 2,048 pixels square.
- A list of a hundred rows lists only the rows in view, and a dwarf's picture is about twenty parts, a rectangle for each run of one colour: the play screen with a hundred dwarves, their list open and ten pictures at the top is about 600 parts (`plan.md`, "The dwarves on screen, as built").
- A screen that is not the play screen (the front door, expedition planning) is another procedure that lists parts. Nothing else is needed for it.
