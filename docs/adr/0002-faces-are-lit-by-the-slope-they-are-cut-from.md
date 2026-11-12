# Faces are lit by the slope they are cut from

A block face takes sunlight and sky light as if it pointed halfway between its own direction and the smooth ground's, and a face turned away from the sun on a sunlit slope is shadowed as the slope is, sampled clear of its own block. Lighting by the face alone, which is the obvious way, made hillsides read as staircases from the air and left isolated near-black faces wherever a contour jogged by one block. Trees and anything else with no ground slope are lit by their faces alone.

A face under a roof of rock (2026-11-12, step 14) is lit by its own direction instead, since the slope it was cut from is the hillside above the roof, and takes only the share of the sky its block of air sees: thirteen rays cast at meshing, kept in four spare bits of the quad as 15 less the light. Without it a cave would be lit by the whole sky. Every face not under a roof keeps those bits at zero and is lit as before.
