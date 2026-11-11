---
name: OdinCraft v4
description: Native macOS foundation UI with experimental formation and atlas screens.
colors:
  ink: "rgb(6% 11% 13%)"
  panel: "rgb(9% 16% 19% / 97%)"
  text: "rgb(92% 95% 94%)"
  secondary: "rgb(65% 77% 79%)"
  brass: "rgb(90% 72% 36%)"
typography:
  display:
    fontFamily: Source Sans 3
    fontSize: 52px
    fontWeight: 400
  title:
    fontFamily: Source Sans 3
    fontSize: 24px
    fontWeight: 400
  body:
    fontFamily: Source Sans 3
    fontSize: 18px
    fontWeight: 400
rounded:
  square: 0px
components:
  button-primary:
    backgroundColor: "{colors.brass}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    height: 44px
  button-secondary:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.text}"
    rounded: "{rounded.square}"
    height: 44px
---

# Design System: OdinCraft v4

## Overview

A readable exploration instrument: restrained ink-blue surfaces, pale text and brass selection. This records the shipped foundation UI, whose survey scene is a rendering and movement fixture. Source: `src/main/ui.odin`; visual checks: `.impeccable/review/home.png` and `settings-small-115.png`.

## Colors

Brass identifies primary actions, keyboard focus and the inspection movement mode. Ink grounds menus; translucent panel surfaces hold controls and scene data. Text carries main content, with secondary blue-gray for instructions and context. Token percentages preserve the native renderer's normalized channel values.

## Typography

Bundled `assets/fonts/SourceSans3-Regular.ttf` supplies every label. Display is for Home and Settings headings, title for section headings, and body for controls and data. Token sizes are logical UI units, expressed as px for portability. Settings switches between 100% and 115%, scaling the whole interface; rendering still uses the full drawable resolution.

## Layout

The resizable macOS window has an 800 × 640 minimum in window units. Home and Settings use a 48-unit left inset and vertically stacked actions. Home shows its right-hand field controls only at logical widths of at least 1040. Exploration overlays sit 24 units from viewport edges; inspection appears on the right, measurements on the left. Pause centers a 396-unit-wide panel. At minimum size, the 115% Settings capture keeps every action visible.

## Elevation & Depth

Flat tonal layering, without shadows or blur. Exploration keeps the scene visible behind translucent data panels. Pause, Home and Settings use the ink background. Pausing stops terrain rendering and menus run at about 30 updates per second to reduce idle work.

## Shapes

Buttons, panels and focus borders are square rectangles. The operating system supplies the window frame. A small crosshair marks the exploration viewport center.

## Components

Buttons are 44 logical units high, with text inset 16 horizontally and 10 vertically. Home buttons are 285 units wide; Settings and Pause buttons are 340. Hover multiplies the fill's RGB channels by 1.12. Focus uses a brass rectangle extending 3 units beyond the control, separated from the fill by an ink inset; state changes are immediate.

Pointer clicks activate controls. Tab advances focus; Enter or Space activates it. Esc pauses exploration and releases the pointer, resumes from Pause, and returns Settings to its originating menu. Entering exploration captures the pointer for mouse look. Inspection (`I`) and measurements (`F3`) are optional scene overlays; the bottom strip retains movement and pause hints.

## Do's and Don'ts

- Do preserve readable scaled controls and visible brass keyboard focus.
- Do keep scene details in optional overlays and identify the current fixture honestly.
- Don't describe natural-world simulation or atlas screens as implemented in milestone 0.

## Milestone 1 extension (experimental)

Home now offers Create landscape and Open saved atlas. Formation shows a labelled progress bar and Cancel. The atlas uses a selectable map, an X-toggle cross-section, elevation/runoff/discharge/resistance readings, and explicit Explore/Continue/Home actions. Its current coarse physical fields are experimental, not finished geology or hydrology layers.

Exploration adds V/G/R survey shortcuts for aerial, ground and river views. Metre-scale blocks, experimental terrain and unavailable GPU/presentation timing must remain identified honestly. Rivers are translucent over their carved beds; depth comparison uses reversed floating-point depth. These rendering choices do not constitute landscape acceptance.


## Block material readability

The quick material pass uses stationary procedural texels at 16 samples per metre: olive grass, warm brown soil, gray fractured rock and pale sand. Grass edges cap the first metre of exposed soil; deeper faces read as rock. This is a visual altitude/surface convention, not simulated soil thickness or geological material identity. Fine grain fades with screen footprint to avoid distant texture aliasing. Explicit block-edge outlines were removed at the owner’s request; material grain and grass rims remain. The pass adds no mesh vertices, texture assets or uploads. Native close-up evidence: `.impeccable/review/block-textures.png`.
