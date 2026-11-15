# The world is drawn round and shaded flat

Every vertex of everything drawn in the world is lowered by d²/2R as it is drawn, d its distance across the ground from the eye and R 7,400 km, the Earth's radius lengthened for ordinary refraction (the surveyors' figure): 7 cm at 1 km, 15 m at 15 km, 108 m at 40 km, 280 m at 64 km. That gives the sea a horizon (12 km from an eye 10 m over it) and sinks far land under it, so a distant island shows its top and not its shore. The drop is applied in one place, `drawn` in `shaders.metal`, which every vertex shader of the view calls. Nothing else is lowered: the physics, the player, the generator and every shading computation stay on the flat world, so a fragment is lit, textured, shadowed, hazed and tinted by the water over it where it stands on the flat world, and the shadow maps are drawn flat.

We chose this over a world whose ground is generated or stored curved, which every system that reads heights would have to know about, and over lowering the shadow passes too, which with shading on the flat world would have moved each shadow by the drop at its caster's distance. Since the drop moves nothing near by more than a fraction of a pixel (7 cm at 1 km, 27 cm at 2 km), shading on the flat world cannot be seen to disagree with where things are drawn.

## Consequences

- A new vertex shader for the view must call `drawn`, or what it draws will float over the curve far off. A shadow pass must not.
- A surface drawn as a few large quads cannot bend: the sea is a grid of 64 × 64 quads round the eye, widening with distance to past the horizon (at least 80 km). Quads of the far rings and merged runs of tops are at most 4 km long, which bends to within 15 cm.
- The view's boxes for culling are widened down by the drop at their farthest corner, so nothing is culled that would have been drawn lower into view, and no face is left out by facing that the drop turns toward the eye.
- The cloud layer is round too: its rays rise off it by the same bend, so a ray along the horizon meets the cloud base at last instead of never.
- Haze and the cloud shadow on the ground are worked out along the straight flat ray, not the bent one: within 64 km the ray over a far summit runs at most a quarter of the drop lower in the middle than that, under 70 m, which changes the haze by a few hundredths.
- Every view the owner judges from now on is calibrated on the curve. Turning it off is one constant (`EARTH` in `shaders.metal` and `render.odin`), but a flat world shows a 300 m island whole at any range, so the far levels would then need to stop where land is still in view.
