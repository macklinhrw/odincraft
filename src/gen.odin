package main

import "core:math"
import "core:sync"
import "core:time"

// The world generator. Everything the engine knows about the world comes through
// gen_columns and gen_volume, which read the land formed in land.odin and the rivers
// traced in rivers.odin. Those two take a chunk in the world; everything below them works
// relative to the region's middle (region.origin), so the island is the same wherever it lies.
//
// One block is one metre, y is up and sea level is y = 0. The generator is asked for the
// ground at a cell size: 1 m beside the player, up to 64 m at the horizon. Detail finer
// than the cell fades out, so a coarse answer is the average of the fine one and distant
// terrain shows the same hills as near terrain.

// A block is an index into one table of materials, 16 bits wide wherever it is kept, meshed and
// drawn, so the table can grow to many kinds of rock in their forms and the bark and leaf of many
// species. The atlas of tiles is written from it (tools/blocks.py). Each kind of rock has four forms
// (geology.md, D5): the solid rock; its scree, fallen from a face; the rock broken in place under the
// soil; and its gravel, rounded by a river. Each form's rows follow the solid ones in their order.
Mat :: enum u16 {
	Air, Grass, Dirt, Stone, Sand, Snow, Wood, Leaves, Gravel,
	Shii_Bark, Shii_Leaves, Grey_Bark, Camellia_Leaves, Hisakaki_Leaves, Pine_Bark, Pine_Needles, Scrub_Leaves,   // each species' bark and leaf (SPECIES); the tabu's are Wood and Leaves
	Wood_End, Shii_End, Grey_End, Pine_End,               // a trunk cut across: its rings. Only faces are these, never blocks (grain, mesh.odin)
	Wood_Across, Shii_Across, Grey_Across, Pine_Across,   // and the bark of a lying trunk, turned to run along it
	Litter, Susuki, Dune,             // what covers the ground between the trees (COMMUNITIES)
	Black_Sand,                       // a beach ground from dark lava
	Shingle, Black_Shingle,           // the stones the waves round and throw up where they leave no sand
	Loam, Silt, Red_Clay, Ash,        // the soils under it (SOILS)
	Mudstone, Siltstone, Sandstone, Grit, Limestone, Basalt, Scoria, Rhyolite, Tuff, Reef,
	Red_Sandstone, Chalk, Coal, Breccia, Dolerite, Granite, Slate, Schist, Gneiss, Quartzite, Hornfels, Marble,
	Mudstone_Scree, Siltstone_Scree, Sandstone_Scree, Grit_Scree, Limestone_Scree, Basalt_Scree, Scoria_Scree, Rhyolite_Scree, Tuff_Scree, Reef_Scree,
	Red_Sandstone_Scree, Chalk_Scree, Coal_Scree, Breccia_Scree, Dolerite_Scree, Granite_Scree, Slate_Scree, Schist_Scree, Gneiss_Scree, Quartzite_Scree, Hornfels_Scree, Marble_Scree,
	Mudstone_Broken, Siltstone_Broken, Sandstone_Broken, Grit_Broken, Limestone_Broken, Basalt_Broken, Scoria_Broken, Rhyolite_Broken, Tuff_Broken, Reef_Broken,
	Red_Sandstone_Broken, Chalk_Broken, Coal_Broken, Breccia_Broken, Dolerite_Broken, Granite_Broken, Slate_Broken, Schist_Broken, Gneiss_Broken, Quartzite_Broken, Hornfels_Broken, Marble_Broken,
	Mudstone_Gravel, Siltstone_Gravel, Sandstone_Gravel, Grit_Gravel, Limestone_Gravel, Basalt_Gravel, Scoria_Gravel, Rhyolite_Gravel, Tuff_Gravel, Reef_Gravel,
	Red_Sandstone_Gravel, Chalk_Gravel, Coal_Gravel, Breccia_Gravel, Dolerite_Gravel, Granite_Gravel, Slate_Gravel, Schist_Gravel, Gneiss_Gravel, Quartzite_Gravel, Hornfels_Gravel, Marble_Gravel,
}

Material :: struct {
	colour:   [3]f32,   // albedo, linear
	strength: f32,      // of a rock, 0..1 (rock.odin); zero for anything else
	crack:    f32,      // metres between the cracks that break a face of it, along the strike
	loose:    Mat,      // what it is once fallen from a face
}

MATERIALS := [Mat]Material{
	.Air       = {{1.0, 0.0, 1.0}, 0, 0, .Air},
	.Grass     = {{0.070, 0.135, 0.032}, 0, 0, .Air},
	.Dirt      = {{0.130, 0.085, 0.048}, 0, 0, .Air},
	.Stone     = {{0.165, 0.155, 0.140}, 0, 0, .Air},
	.Sand      = {{0.330, 0.285, 0.180}, 0, 0, .Air},
	.Snow      = {{0.780, 0.800, 0.840}, 0, 0, .Air},
	.Wood      = {{0.105, 0.068, 0.036}, 0, 0, .Air},
	.Leaves    = {{0.021, 0.074, 0.017}, 0, 0, .Air},   // tabu: dark and glossy
	.Gravel    = {{0.105, 0.097, 0.085}, 0, 0, .Air},
	.Shii_Bark       = {{0.087, 0.070, 0.055}, 0, 0, .Air},   // dark grey-brown, furrowed
	.Shii_Leaves     = {{0.074, 0.139, 0.021}, 0, 0, .Air},  // olive with a yellow cast
	.Grey_Bark       = {{0.184, 0.177, 0.151}, 0, 0, .Air},   // smooth and pale, on camellia and hisakaki
	.Camellia_Leaves = {{0.010, 0.048, 0.013}, 0, 0, .Air},   // the darkest, with red flowers
	.Hisakaki_Leaves = {{0.045, 0.087, 0.023}, 0, 0, .Air},   // small, dull
	.Pine_Bark       = {{0.106, 0.087, 0.074}, 0, 0, .Air},   // black pine: dark plates
	.Pine_Needles    = {{0.015, 0.058, 0.028}, 0, 0, .Air},
	.Scrub_Leaves    = {{0.058, 0.128, 0.030}, 0, 0, .Air},  // tobira and its like: glossy mid green
	.Wood_End        = {{0.300, 0.190, 0.105}, 0, 0, .Air},   // the wood inside: tabu's is reddish
	.Shii_End        = {{0.330, 0.240, 0.140}, 0, 0, .Air},
	.Grey_End        = {{0.400, 0.320, 0.210}, 0, 0, .Air},   // camellia's pale and fine
	.Pine_End        = {{0.380, 0.260, 0.120}, 0, 0, .Air},   // pine's yellow with resin
	.Wood_Across     = {{0.105, 0.068, 0.036}, 0, 0, .Air},
	.Shii_Across     = {{0.087, 0.070, 0.055}, 0, 0, .Air},
	.Grey_Across     = {{0.184, 0.177, 0.151}, 0, 0, .Air},
	.Pine_Across     = {{0.106, 0.087, 0.074}, 0, 0, .Air},
	.Litter    = {{0.096, 0.058, 0.025}, 0, 0, .Air},      // fallen evergreen leaves
	.Susuki    = {{0.096, 0.157, 0.038}, 0, 0, .Air},    // susuki grass and dwarf bamboo
	.Dune      = {{0.128, 0.139, 0.062}, 0, 0, .Air},   // dune grass, straw
	.Black_Sand = {{0.060, 0.057, 0.054}, 0, 0, .Air},   // basalt and cinder sand, dark grey
	.Shingle       = {{0.128, 0.120, 0.108}, 0, 0, .Air},   // sea-worn pebbles, paler than the rock they came from
	.Black_Shingle = {{0.075, 0.072, 0.070}, 0, 0, .Air},
	.Loam      = {{0.058, 0.040, 0.026}, 0, 0, .Air},   // dark topsoil
	.Silt      = {{0.050, 0.046, 0.038}, 0, 0, .Air},   // grey river silt
	.Red_Clay  = {{0.184, 0.062, 0.030}, 0, 0, .Air},     // the red clay long rain leaves on old ground
	.Ash       = {{0.019, 0.013, 0.010}, 0, 0, .Air},      // black soil weathered from ash and cinders
	.Mudstone  = {{0.062, 0.064, 0.074}, 0.25, 0.1, .Mudstone_Scree},   // dark blue-grey, crumbles into flakes; never holds a face
	.Siltstone = {{0.098, 0.082, 0.062}, 0.4, 0.3, .Siltstone_Scree},   // grey-brown flags, thin ledges
	.Sandstone = {{0.136, 0.108, 0.074}, 0.6, 1.5, .Sandstone_Scree},   // warm buff rectangular blocks
	.Grit      = {{0.150, 0.134, 0.128}, 0.8, 4, .Grit_Scree},          // pinkish grey pebbly rock that caps the hills, in huge blocks
	.Limestone = {{0.178, 0.180, 0.178}, 0.65, 1, .Limestone_Scree},    // pale grey
	.Basalt    = {{0.050, 0.047, 0.045}, 0.75, 1, .Basalt_Scree},       // black-grey lava flows, jointed into columns
	.Scoria    = {{0.085, 0.043, 0.033}, 0.25, 0.1, .Scoria_Scree},     // red-brown cinders and ash between the flows; crumbles
	.Rhyolite  = {{0.200, 0.186, 0.172}, 0.7, 2, .Rhyolite_Scree},      // pale grey-pink stiff lava, in sheeted crags
	.Tuff      = {{0.215, 0.200, 0.160}, 0.3, 0.1, .Tuff_Scree},        // cream pumice and ash
	.Reef      = {{0.235, 0.225, 0.190}, 0.8, 2, .Reef_Scree},          // coral, shells and their sand, raised from the sea: pale cream, rough and full of holes
	.Red_Sandstone = {{0.150, 0.068, 0.045}, 0.55, 2, .Red_Sandstone_Scree},   // laid in a dry past: red faces of rectangular blocks, red gravel and sand
	.Chalk     = {{0.330, 0.325, 0.300}, 0.35, 0.5, .Chalk_Scree},     // white and crumbly: rounded downs, cliffs that fall as they are cut
	.Coal      = {{0.018, 0.017, 0.016}, 0.15, 0.1, .Coal_Scree},     // a black seam a metre or two thick in a cut
	.Breccia   = {{0.062, 0.068, 0.055}, 0.35, 0.5, .Breccia_Scree},       // lava shattered as it met the sea, set in its own ash: green-grey and lumpy, between the pillow lavas of an old arc
	.Dolerite  = {{0.042, 0.047, 0.045}, 0.9, 1, .Dolerite_Scree},      // the dark rock of dikes and plugs, in blocks and rough columns
	.Granite   = {{0.190, 0.160, 0.150}, 0.65, 5, .Granite_Scree},        // pink-grey and coarse, its cracks wide apart: stacked blocks, domes, boulders
	.Slate     = {{0.058, 0.064, 0.078}, 0.6, 0.3, .Slate_Scree},   // mudstone squeezed in a fold belt: blue-grey, split into sheets standing on edge
	.Schist    = {{0.112, 0.106, 0.094}, 0.5, 0.3, .Schist_Scree},          // glittering wavy bands, slabby
	.Gneiss    = {{0.150, 0.128, 0.118}, 0.7, 3, .Gneiss_Scree},          // banded grey and pink, in knobs
	.Quartzite = {{0.250, 0.245, 0.230}, 0.95, 1, .Quartzite_Scree},  // sandstone baked or squeezed hard: white, sharp-edged
	.Hornfels  = {{0.055, 0.051, 0.049}, 0.85, 1, .Hornfels_Scree},    // mudstone baked beside a pluton: dark, hard and splintery
	.Marble    = {{0.290, 0.286, 0.272}, 0.6, 1.5, .Marble_Scree},        // limestone baked beside a pluton: white and crystalline
	.Mudstone_Scree  = {{0.066, 0.068, 0.079}, 0, 0, .Air},   // fresh broken rock is a little paler than the weathered face
	.Siltstone_Scree = {{0.105, 0.088, 0.066}, 0, 0, .Air},
	.Sandstone_Scree = {{0.146, 0.116, 0.079}, 0, 0, .Air},
	.Grit_Scree      = {{0.160, 0.143, 0.137}, 0, 0, .Air},
	.Limestone_Scree = {{0.190, 0.193, 0.190}, 0, 0, .Air},
	.Basalt_Scree    = {{0.058, 0.054, 0.051}, 0, 0, .Air},
	.Scoria_Scree    = {{0.093, 0.047, 0.036}, 0, 0, .Air},
	.Rhyolite_Scree  = {{0.214, 0.200, 0.185}, 0, 0, .Air},
	.Tuff_Scree      = {{0.228, 0.212, 0.170}, 0, 0, .Air},
	.Reef_Scree      = {{0.250, 0.240, 0.205}, 0, 0, .Air},
	.Red_Sandstone_Scree   = {{0.161, 0.073, 0.048}, 0, 0, .Air},
	.Chalk_Scree           = {{0.353, 0.348, 0.321}, 0, 0, .Air},
	.Coal_Scree            = {{0.019, 0.018, 0.017}, 0, 0, .Air},
	.Breccia_Scree         = {{0.066, 0.073, 0.059}, 0, 0, .Air},
	.Dolerite_Scree        = {{0.045, 0.050, 0.048}, 0, 0, .Air},
	.Granite_Scree         = {{0.203, 0.171, 0.161}, 0, 0, .Air},
	.Slate_Scree           = {{0.062, 0.068, 0.083}, 0, 0, .Air},
	.Schist_Scree          = {{0.120, 0.113, 0.101}, 0, 0, .Air},
	.Gneiss_Scree          = {{0.161, 0.137, 0.126}, 0, 0, .Air},
	.Quartzite_Scree       = {{0.268, 0.262, 0.246}, 0, 0, .Air},
	.Hornfels_Scree        = {{0.059, 0.055, 0.052}, 0, 0, .Air},
	.Marble_Scree          = {{0.310, 0.306, 0.291}, 0, 0, .Air},
	// broken in place, weathered a little browner than the face
	.Mudstone_Broken       = {{0.073, 0.071, 0.078}, 0, 0, .Air},
	.Siltstone_Broken      = {{0.111, 0.090, 0.065}, 0, 0, .Air},
	.Sandstone_Broken      = {{0.151, 0.117, 0.078}, 0, 0, .Air},
	.Grit_Broken           = {{0.166, 0.145, 0.134}, 0, 0, .Air},
	.Limestone_Broken      = {{0.195, 0.193, 0.187}, 0, 0, .Air},
	.Basalt_Broken         = {{0.061, 0.053, 0.047}, 0, 0, .Air},
	.Scoria_Broken         = {{0.097, 0.049, 0.035}, 0, 0, .Air},
	.Rhyolite_Broken       = {{0.218, 0.199, 0.181}, 0, 0, .Air},
	.Tuff_Broken           = {{0.234, 0.214, 0.168}, 0, 0, .Air},
	.Reef_Broken           = {{0.255, 0.240, 0.200}, 0, 0, .Air},
	.Red_Sandstone_Broken  = {{0.166, 0.075, 0.047}, 0, 0, .Air},
	.Chalk_Broken          = {{0.355, 0.345, 0.315}, 0, 0, .Air},
	.Coal_Broken           = {{0.027, 0.022, 0.017}, 0, 0, .Air},
	.Breccia_Broken        = {{0.073, 0.075, 0.058}, 0, 0, .Air},
	.Dolerite_Broken       = {{0.052, 0.053, 0.047}, 0, 0, .Air},
	.Granite_Broken        = {{0.208, 0.172, 0.158}, 0, 0, .Air},
	.Slate_Broken          = {{0.069, 0.071, 0.082}, 0, 0, .Air},
	.Schist_Broken         = {{0.126, 0.115, 0.099}, 0, 0, .Air},
	.Gneiss_Broken         = {{0.166, 0.138, 0.124}, 0, 0, .Air},
	.Quartzite_Broken      = {{0.271, 0.261, 0.242}, 0, 0, .Air},
	.Hornfels_Broken       = {{0.066, 0.058, 0.051}, 0, 0, .Air},
	.Marble_Broken         = {{0.312, 0.304, 0.286}, 0, 0, .Air},
	// river gravel, washed paler
	.Mudstone_Gravel       = {{0.075, 0.078, 0.089}, 0, 0, .Air},
	.Siltstone_Gravel      = {{0.117, 0.098, 0.075}, 0, 0, .Air},
	.Sandstone_Gravel      = {{0.160, 0.128, 0.089}, 0, 0, .Air},
	.Grit_Gravel           = {{0.176, 0.158, 0.151}, 0, 0, .Air},
	.Limestone_Gravel      = {{0.209, 0.211, 0.209}, 0, 0, .Air},
	.Basalt_Gravel         = {{0.061, 0.058, 0.056}, 0, 0, .Air},
	.Scoria_Gravel         = {{0.102, 0.053, 0.042}, 0, 0, .Air},
	.Rhyolite_Gravel       = {{0.234, 0.218, 0.202}, 0, 0, .Air},
	.Tuff_Gravel           = {{0.251, 0.234, 0.188}, 0, 0, .Air},
	.Reef_Gravel           = {{0.274, 0.263, 0.222}, 0, 0, .Air},
	.Red_Sandstone_Gravel  = {{0.176, 0.082, 0.056}, 0, 0, .Air},
	.Chalk_Gravel          = {{0.384, 0.378, 0.349}, 0, 0, .Air},
	.Coal_Gravel           = {{0.025, 0.024, 0.022}, 0, 0, .Air},
	.Breccia_Gravel        = {{0.075, 0.082, 0.067}, 0, 0, .Air},
	.Dolerite_Gravel       = {{0.052, 0.058, 0.056}, 0, 0, .Air},
	.Granite_Gravel        = {{0.222, 0.188, 0.176}, 0, 0, .Air},
	.Slate_Gravel          = {{0.071, 0.078, 0.094}, 0, 0, .Air},
	.Schist_Gravel         = {{0.133, 0.126, 0.112}, 0, 0, .Air},
	.Gneiss_Gravel         = {{0.176, 0.151, 0.140}, 0, 0, .Air},
	.Quartzite_Gravel      = {{0.291, 0.286, 0.269}, 0, 0, .Air},
	.Hornfels_Gravel       = {{0.067, 0.063, 0.060}, 0, 0, .Air},
	.Marble_Gravel         = {{0.337, 0.333, 0.317}, 0, 0, .Air},
}

// A rock's broken and gravel forms (its scree is its `loose` in MATERIALS), and the rock it becomes
// where a pluton baked it (AUREOLE, rock.odin): mudstone to hornfels, sandstone to quartzite,
// limestone to marble. A rock not baked into another keeps its own.
Rock_Forms :: struct { broken, gravel, baked: Mat }
FORMS := #partial [Mat]Rock_Forms{
	.Mudstone = {.Mudstone_Broken, .Mudstone_Gravel, .Hornfels}, .Siltstone = {.Siltstone_Broken, .Siltstone_Gravel, .Hornfels},
	.Sandstone = {.Sandstone_Broken, .Sandstone_Gravel, .Quartzite}, .Grit = {.Grit_Broken, .Grit_Gravel, .Quartzite},
	.Limestone = {.Limestone_Broken, .Limestone_Gravel, .Marble}, .Basalt = {.Basalt_Broken, .Basalt_Gravel, .Air}, .Scoria = {.Scoria_Broken, .Scoria_Gravel, .Air},
	.Rhyolite = {.Rhyolite_Broken, .Rhyolite_Gravel, .Air}, .Tuff = {.Tuff_Broken, .Tuff_Gravel, .Air}, .Reef = {.Reef_Broken, .Reef_Gravel, .Air},
	.Red_Sandstone = {.Red_Sandstone_Broken, .Red_Sandstone_Gravel, .Quartzite}, .Chalk = {.Chalk_Broken, .Chalk_Gravel, .Marble},
	.Coal = {.Coal_Broken, .Coal_Gravel, .Hornfels}, .Breccia = {.Breccia_Broken, .Breccia_Gravel, .Air}, .Dolerite = {.Dolerite_Broken, .Dolerite_Gravel, .Air},
	.Granite = {.Granite_Broken, .Granite_Gravel, .Air}, .Slate = {.Slate_Broken, .Slate_Gravel, .Hornfels}, .Schist = {.Schist_Broken, .Schist_Gravel, .Air},
	.Gneiss = {.Gneiss_Broken, .Gneiss_Gravel, .Air}, .Quartzite = {.Quartzite_Broken, .Quartzite_Gravel, .Air}, .Hornfels = {.Hornfels_Broken, .Hornfels_Gravel, .Air},
	.Marble = {.Marble_Broken, .Marble_Gravel, .Air},
}

// What the rules ask of a material besides its row, a set of traits for each: a bit_set of
// materials holds no more than 128 of them. A rule asks `is(m, LEAVES)`, true if the material
// has any trait of the set.
Trait :: enum u8 {
	Leaf,     // seen through, near by: the gaps in its tile are clear
	Bark,     // a stem or limb. Bark and leaf are a plant's, which the sky, the water and a column's ground see past
	Cover,    // covers the ground over a soil (block_below)
	Passes,   // a rock water passes through, so a spring rises where it lies on one that holds it (rivers.odin)
	Sinks,    // a rock the rain sinks into rather than running off it, so few streams cut it (SOAKS, rock.odin)
	Pebbles,  // a river's gravel, which lies two blocks deep on its bed (block_below)
	Grass, Litter, Susuki, Dune, Silt, Sand, Rubble,   // the grounds a ground plant grows on (GROUND_PLANTS.on)
}
@(rodata) TRAITS := #partial [Mat]bit_set[Trait]{
	.Grass = {.Cover, .Grass}, .Litter = {.Cover, .Litter}, .Susuki = {.Cover, .Susuki}, .Dune = {.Cover, .Dune}, .Dirt = {.Cover},   // the dirt is the earth of a trail
	.Sand = {.Sand}, .Silt = {.Silt},
	.Wood = {.Bark}, .Shii_Bark = {.Bark}, .Grey_Bark = {.Bark}, .Pine_Bark = {.Bark},
	.Leaves = {.Leaf}, .Shii_Leaves = {.Leaf}, .Camellia_Leaves = {.Leaf}, .Hisakaki_Leaves = {.Leaf}, .Pine_Needles = {.Leaf}, .Scrub_Leaves = {.Leaf},
	.Sandstone = {.Passes}, .Grit = {.Passes}, .Limestone = {.Passes}, .Basalt = {.Passes}, .Scoria = {.Passes}, .Tuff = {.Passes}, .Reef = {.Passes, .Sinks},
	.Red_Sandstone = {.Passes}, .Chalk = {.Passes}, .Granite = {.Passes}, .Gneiss = {.Passes}, .Quartzite = {.Passes}, .Marble = {.Passes},   // through their pores, or the cracks of the hard ones
	.Mudstone_Scree = {.Rubble}, .Siltstone_Scree = {.Rubble}, .Sandstone_Scree = {.Rubble}, .Grit_Scree = {.Rubble}, .Limestone_Scree = {.Rubble},
	.Basalt_Scree = {.Rubble}, .Scoria_Scree = {.Rubble}, .Rhyolite_Scree = {.Rubble}, .Tuff_Scree = {.Rubble}, .Reef_Scree = {.Rubble},
	.Red_Sandstone_Scree = {.Rubble}, .Chalk_Scree = {.Rubble}, .Coal_Scree = {.Rubble}, .Breccia_Scree = {.Rubble}, .Dolerite_Scree = {.Rubble}, .Granite_Scree = {.Rubble},
	.Slate_Scree = {.Rubble}, .Schist_Scree = {.Rubble}, .Gneiss_Scree = {.Rubble}, .Quartzite_Scree = {.Rubble}, .Hornfels_Scree = {.Rubble}, .Marble_Scree = {.Rubble},
	.Mudstone_Broken = {.Rubble}, .Siltstone_Broken = {.Rubble}, .Sandstone_Broken = {.Rubble}, .Grit_Broken = {.Rubble}, .Limestone_Broken = {.Rubble}, .Basalt_Broken = {.Rubble},
	.Scoria_Broken = {.Rubble}, .Rhyolite_Broken = {.Rubble}, .Tuff_Broken = {.Rubble}, .Reef_Broken = {.Rubble}, .Red_Sandstone_Broken = {.Rubble}, .Chalk_Broken = {.Rubble},
	.Coal_Broken = {.Rubble}, .Breccia_Broken = {.Rubble}, .Dolerite_Broken = {.Rubble}, .Granite_Broken = {.Rubble}, .Slate_Broken = {.Rubble}, .Schist_Broken = {.Rubble},
	.Gneiss_Broken = {.Rubble}, .Quartzite_Broken = {.Rubble}, .Hornfels_Broken = {.Rubble}, .Marble_Broken = {.Rubble},
	.Gravel = {.Pebbles},
	.Mudstone_Gravel = {.Pebbles}, .Siltstone_Gravel = {.Pebbles}, .Sandstone_Gravel = {.Pebbles}, .Grit_Gravel = {.Pebbles}, .Limestone_Gravel = {.Pebbles}, .Basalt_Gravel = {.Pebbles},
	.Scoria_Gravel = {.Pebbles}, .Rhyolite_Gravel = {.Pebbles}, .Tuff_Gravel = {.Pebbles}, .Reef_Gravel = {.Pebbles}, .Red_Sandstone_Gravel = {.Pebbles}, .Chalk_Gravel = {.Pebbles},
	.Coal_Gravel = {.Pebbles}, .Breccia_Gravel = {.Pebbles}, .Dolerite_Gravel = {.Pebbles}, .Granite_Gravel = {.Pebbles}, .Slate_Gravel = {.Pebbles}, .Schist_Gravel = {.Pebbles},
	.Gneiss_Gravel = {.Pebbles}, .Quartzite_Gravel = {.Pebbles}, .Hornfels_Gravel = {.Pebbles}, .Marble_Gravel = {.Pebbles},
}
is :: #force_inline proc "contextless" (m: Mat, traits: bit_set[Trait]) -> bool { return TRAITS[m] & traits != {} }
LEAVES       :: bit_set[Trait]{.Leaf}
PLANT_BLOCKS :: bit_set[Trait]{.Bark, .Leaf}
COVERS       :: bit_set[Trait]{.Cover}
PEBBLES      :: bit_set[Trait]{.Pebbles}

CHUNK       :: 32               // cells along a chunk side
CHUNK_SHIFT :: 5
P           :: CHUNK + 2        // a chunk plus a one-cell border, which meshing needs
SEA_LEVEL   :: 0
SEA_SURFACE :: SEA_LEVEL - 0.15   // where the sea stands, a little under the block tops at the shore
COARSE      :: 64               // metres: a column wider than this, 16 km off and more, is the mean of the land, with no stream cut or stack in it
NO_WATER    :: -1e6
@(thread_local) seed: u32   // every random choice in a region is keyed from this: its island's seed (bind)

// The ground under one chunk and its border.
Columns :: struct {
	top:    [P*P]i32,   // elevation of the top face, metres
	ground: [P*P]i32,   // elevation of the ground, which is lower than the top under a canopy
	crown:  [P*P][2]i32, // the underside and top of a single tree's crown over the ground, where one hangs here
	stem:   [P*P]u8,    // where a trunk stands in the cell: 1 + its x + 4 times its z in metres from the cell's corner, or 0
	kind:   [P*P]Tree_Kind, // the species of that crown and trunk
	water:  [P*P]f32,   // level of the river or sea standing here, or NO_WATER
	mat:    [P*P]Mat,   // what the surface is made of
	under:  [P*P]Under, // what lies under the ground: the rock stack's base, which places the beds, and any cover or body (rock.odin)
	slope:  [P*P][2]u8, // the smooth ground normal's x and z, packed; zero in the border
	hollow: [P*P][2]i32, // the floor and roof of a hollow carved under the top here (events.odin); far off, of its mouth
	plant:  [P*P]u8,    // at the nearest level, 1 + the ground plant standing here (plants.odin), or 0
	lo, hi: i32,        // lowest ground and highest top
}

hash :: proc(x, y: i32, seed: u32) -> u32 {
	h := u32(x)*0x9E3779B1 ~ u32(y)*0x85EBCA77 ~ seed*0xC2B2AE3D
	h ~= h >> 15; h *= 0x2C1B3C6D
	h ~= h >> 12; h *= 0x297A2D39
	h ~= h >> 15
	return h
}

hash01 :: proc(x, y: i32, seed: u32) -> f32 {
	return f32(hash(x, y, seed) >> 8)*(1.0/16777216.0)
}

// Smooth noise in 0..1 with its gradient.
noise :: proc(x, y: f64, seed: u32) -> (v, dx, dy: f32) {
	fx, fy := math.floor(x), math.floor(y)
	ix, iy := i32(fx), i32(fy)
	tx, ty := f32(x - fx), f32(y - fy)
	ux := tx*tx*tx*(tx*(tx*6 - 15) + 10)
	uy := ty*ty*ty*(ty*(ty*6 - 15) + 10)
	a, b := hash01(ix, iy, seed), hash01(ix + 1, iy, seed)
	c, d := hash01(ix, iy + 1, seed), hash01(ix + 1, iy + 1, seed)
	k1, k2, k4 := b - a, c - a, a - b - c + d
	v = a + k1*ux + k2*uy + k4*ux*uy
	dx = 30*tx*tx*(tx*(tx - 2) + 1)*(k1 + k4*uy)
	dy = 30*ty*ty*(ty*(ty - 2) + 1)*(k2 + k4*ux)
	return
}

// How much of a wave survives at a cell size: all of it at four cells per wavelength,
// none at two.
band :: proc(wavelength, cell: f64) -> f32 {
	return f32(clamp(wavelength/cell*0.5 - 1, 0, 1))
}

// Layered noise in -1..1.
fbm :: proc(x, z, wavelength, cell: f64, octaves: int, seed: u32) -> f32 {
	sum, amp, total: f32 = 0, 1, 0
	px, pz, wl := x, z, wavelength
	for i in 0..<octaves {
		total += amp
		if w := band(wl, cell); w > 0 {
			v, _, _ := noise(px/wl, pz/wl, seed + u32(i))
			sum += w*amp*(v*2 - 1)
		}
		amp *= 0.5
		wl *= 0.5
		px, pz = 0.8*px - 0.6*pz, 0.6*px + 0.8*pz
	}
	return sum/total
}

smoothstep :: proc(a, b, x: f32) -> f32 {
	t := clamp((x - a)/(b - a), 0, 1)
	return t*t*(3 - 2*t)
}

// Form an island's land and its rivers, and all that lies and lives on them, from its record and
// seed alone (regions.odin), on whichever thread calls. Nothing asks about the island before.
gen_init :: proc(f: ^Formed) {
	bound(f)
	started := time.now()
	f.region.origin, f.region.size, f.landslide = f.island.origin, f.island.size, {box = {1e9, 1e9, -1e9, -1e9}}
	record := record_of(f.island)   // the start island keeps its seed's record (open-decisions.md, 2026-11-15)
	region_init(KINDS[f.island.kind].name, f.island.size, &record if f.island.id != 0 else nil)
	region.shape.swell = world_frame.wind   // every island's swell comes from the one wind (archipelago.odin); the start island's is the one it drew
	story, read := story_for(f.island)
	region.story = story
	rock_init(read)
	land_form()
	rivers_trace()
	plants_init()
	hollows_make()
	arrivals_say()
	trails_make()
	places_make()
	creatures_make()
	f.seconds = time.duration_seconds(time.since(started))
	sync.atomic_store_explicit(&f.ready, true, .Release)
}

Ground :: struct {
	h, steep: f32,   // elevation, and how steep the ground is there, rise over run
	under:    Under, // what lies under it: the rock stack's base and any cover or body (rock.odin)
	water:    f32,   // level of the river or sea standing here, or NO_WATER
	cover:    Mat,   // river gravel, the loose rock lying under a face, or the stones of a shore; Air for none
	fallen:   f32,   // depth of the loose rock fallen from a face, under any gravel
	laid:     f32,   // depth of the sand or stones the waves have laid on a shore
}

REPOSE     :: 0.67   // loose rock comes to rest at about 34°
SOIL_HOLDS :: 1.3    // and soil holds on ground up to about 52°, rise over run: forest to 45° and scrub clinging above it

// How strongly a bed of `lo` under a bed of `hi` stands as a ledge on a hillside this steep:
// a riser at the foot of `lo` and a tread on its top. Only a stronger bed under a weaker one,
// and only where the land forming left the stronger near the steepest slope it holds.
ledge :: proc(lo, hi: Mat, steep: f32) -> f32 {
	return smoothstep(0.05, 0.3, MATERIALS[lo].strength - MATERIALS[hi].strength)*smoothstep(0.5, 0.9, steep/rocks.law[lo].limit)
}

Ledge :: struct {
	h, rise: f32,   // height, and how many times steeper than the smooth hillside the ground is
	lift:    f32,   // depth of the loose rock lying there
	face:    Mat,   // the rock of the face above, if this bed lies under one
}

// The beds in a hillside (docs/foundations/ground-and-underground.md, §5). The land forming
// leaves a face as a smooth slope through its beds. Here the height within each bed is pushed
// toward its contact with a weaker bed above, from both sides, so a strong bed stands as a
// riser with a tread on its top and the weak bed above begins on that tread. The contacts
// stay where the rock has them; only the ground between them moves, and the change fades
// once a cell is too coarse to hold a riser. Under a riser, rock fallen from it lies at its
// angle of rest.
ledges :: proc(h, steep: f32, u: Under, x, z, cell: f64) -> (l: Ledge) {
	l.h, l.rise = h, 1
	if h < u.roof do return   // a dike, plug or pluton stands whole, with no beds to step
	y := h - stack_base(h, u) - STACK_LO
	n := int(rocks.bed[clamp(int(y), 0, STACK_LEN - 1)])
	if n == 0 || n + 2 >= len(rocks.beds) do return
	bed, floor := rocks.beds[n], rocks.floor[n]
	below := rocks.beds[n - 1].kind if n != rocks.cover_from else rock_in(h - (y - floor) - 0.5, u, 0)   // a cover's first bed lies on whatever bed the worn surface cut
	fade := band(2*f64(bed.thick/max(steep, 0.1)), cell)
	// A tread on this bed's top: under a weaker bed, or on a thick hard bed standing at the
	// steepest slope it holds, which breaks as a face whatever lies above it.
	massive := smoothstep(0.4, 0.6, MATERIALS[bed.kind].strength)*smoothstep(25, 40, bed.thick)*smoothstep(0.85, 1, steep/rocks.law[bed.kind].limit)
	// A bed is not equally strong all along: it stands as a face only in stretches, most of the
	// way along the strongest rocks and about a third of the way along the least of the strong, and
	// between them the hillside runs smooth through it under scrub. So a hill wears crags and
	// bluffs, not a wall round it at every strong bed.
	stands :: proc(n: int, x, z, cell: f64) -> f32 {
		return smoothstep(0, 0.15, fbm(x, z, 320, cell, 2, seed + 420 + u32(n)) - 0.25 + 2*(MATERIALS[rocks.beds[n].kind].strength - 0.6))
	}
	top := fade*max(ledge(bed.kind, rocks.beds[n + 1].kind, steep), massive)*stands(n, x, z, cell)
	foot := fade*ledge(below, bed.kind, steep)*stands(n - 1, x, z, cell)   // a tread at its foot, on the bed below's top
	if top + foot > 1 do top, foot = top/(top + foot), foot/(top + foot)   // so the ground never folds back over itself
	q := clamp((y - floor)/bed.thick, 0, 1)
	p := 1 - q
	SHARP :: 8   // how abruptly a riser turns into its tread
	g := q + top*(1 - math.pow(p, SHARP) - q) + foot*(math.pow(q, SHARP) - q)
	l.rise = 1 + top*(SHARP*math.pow(p, SHARP - 1) - 1) + foot*(SHARP*math.pow(q, SHARP - 1) - 1)
	l.h = h + bed.thick*(g - q)
	// Under the riser of the bed above: rock fallen from it, lying from the contact down at its
	// angle of rest, or where the hillside is steeper than that, no steeper than the hillside,
	// so it always comes to ground within this bed.
	above := rocks.beds[n + 1].kind
	if face := fade*max(ledge(above, rocks.beds[n + 2].kind, steep), smoothstep(0.9, 1.1, steep/max(rocks.law[above].limit, SOIL_HOLDS)))*stands(n + 1, x, z, cell); face > 0 {
		l.face = above
		fall := max(REPOSE/max(steep, 0.01), 1)   // its fall per metre of the smooth hillside's
		if lift := face*(h + bed.thick*p*(1 - fall) - l.h); lift > 0 {
			l.h, l.lift, l.rise = l.h + lift, lift, fall
		}
	}
	return
}

// The ground the land forming left at a point, shaped by its beds, read `back` metres up the
// hillside from where it stands.
shaped :: proc(x, z, cell: f64, back: f32 = 0) -> (l: Ledge, steep: f32, under: Under) {
	level := clamp(int(math.log2(cell)) - 4, 0, len(land.z) - 1)   // the land's grid as coarse as the cell, or its finest
	steep = max(land_at(land.slope, land.n, x, z), 0)
	under = rock_base(x, z, cell)
	l = ledges(land_at(land.z[level], land.n >> uint(level), x, z) - back*steep, steep, under, x, z, cell)
	return
}

// The ground at a point as seen at a cell size.
ground :: proc(x, z, cell: f64) -> (g: Ground) {
	l, steep, under := shaped(x, z, cell)
	g.under = under
	near := band(8, cell)   // cracks are gone by 4 m cells
	// A face that breaks along its cracks: each block between two cracks stands up to a metre
	// forward of the face or back from it, so the face breaks into prisms. One set of cracks
	// runs along the strike of the beds and the other across it, each bed with its own.
	n := bed_at(l.h - 0.5, under)
	kind := rocks.beds[n].kind if n >= 0 else under.body
	if gap := MATERIALS[kind].crack; near > 0 && l.lift == 0 && gap >= 1 {
		if bare := near*smoothstep(1, 1.5, steep*l.rise/rocks.law[kind].limit); bare > 0 {
			strike := rock_strike(x, z)
			u, v := (x*strike.x + z*strike.y)/f64(gap), (z*strike.x - x*strike.y)/f64(2.5*gap)
			across := i32(math.floor(v + f64(hash01(i32(n), 1, seed + 401))))
			along := i32(math.floor(u + f64(hash01(across, i32(n), seed + 402))))
			l, _, _ = shaped(x, z, cell, 2*bare*(hash01(along, across, seed + 403 + u32(n)) - 0.5))
		}
	}
	if l.lift > 0 do g.cover, g.fallen = MATERIALS[l.face].loose, l.lift
	// Small rises and hollows the simulation is too coarse to hold: more on slopes, none at
	// the shore, and none on a ledged face or loose rock, whose shapes have their own causes.
	h := l.h + fbm(x, z, 70, cell, 3, seed + 80)*(0.5 + 2.2*min(steep, 1))*smoothstep(0, 3, l.h)*min(l.rise, 1)*(1 - smoothstep(0, 1, l.lift))
	// A lake or pond stands at its level over the ground below it in its cells and the cells round
	// them, where its shore lies. Beyond them the ground stands as a bank that holds it, as at a
	// river; only its outlet stream is cut through. A river reaching it never raises its bed.
	// Blocks of the cap lie where the slide left them, as large as a room or a house: one in
	// about six of the 7 m squares of its debris, more where it lies thick.
	if t := slid_at(x, z); t > 2 && cell <= 2 {
		gx, gz := i32(math.floor(x/7)), i32(math.floor(z/7))
		if r := hash(gx, gz, seed + 710); f32(r & 0xFF)/255 < min(t/60, 0.3) {
			size := 2 + f64((r >> 8)%4)
			bx, bz := f64(gx)*7 + size/2 + f64((r >> 12)%u32(8 - size)), f64(gz)*7 + size/2 + f64((r >> 16)%u32(8 - size))
			// Its corners are worn and its top is humped, longer one way than the other: a box reads as built.
				u, v := (x - bx)/(size/2), (z - bz)/(size/2)*(1.5 if (r >> 28) & 1 == 0 else 0.7)
				if q := f32(u*u*u*u + v*v*v*v); q < 1 do h, g.cover, g.fallen = h + f32(1 + (r >> 20)%u32(size))*math.sqrt(1 - q) + 0.5, landslide.rock, 1
		}
	}
	h, g.laid = waters_edge(h, x, z, cell)
	lake, inside, bank := lake_near(x, z)
	h = max(h, bank)
	gravel: bool
	g.h, gravel, g.water = river_cut(h, x, z, cell)
	if inside {
		g.h, gravel = min(g.h, h), false
		if g.h < lake do g.h, g.water = max(g.h, lake - 1) if cell > 1 else g.h, lake   // far off, a lake's bed is drawn flat under it, so its cells do not show through
	}
	g.steep = steep*l.rise
	if g.laid > 0 do g.cover = MATERIALS[rock_in(g.h - g.laid - 0.5, under, rock_level(cell))].loose
	if gravel do g.cover = .Gravel
	if t, rubble := stack_at(x, z, cell, g.h, under); t > g.h {   // a stack is bare rock to its top
		if rubble do g.laid, g.cover = g.laid + t - g.h, MATERIALS[rock_in(g.h - 0.5, under, rock_level(cell))].loose
		else do g.steep = 3
		g.h, g.water = t, NO_WATER
	}
	if g.h < SEA_SURFACE do g.water = max(g.water, SEA_SURFACE)
	return
}

// ---- the shore -----------------------------------------------------------------------------

// What the waves leave at the water's edge (ground-and-underground.md §4, the beach and platform
// rows), from how open the shore is to the swell (`surf`) and how much of the sand its rivers bring
// they leave it (`sand-kept`). Where they leave sand, it lies as a beach: a flat berm as high as
// the waves run up, wider the more sand there is, and a face falling to the sea at the angle sand
// rests at under them. Where they leave none, they throw stones into a bank that is higher and
// steeper the more open the shore. Either is laid over the ground the forming left where that is
// steeper than its face, and neither stands under a sheer cliff or on a shore the swell breaks on.
// There the waves have cut the rock flat at the sea's level, with pools where it is worn deeper,
// and boulders too large for them to move lie along the foot of what stands over it.
CARRY :: 2.5 // the sand a shore loses to the swell, against the supply from a mouth (land_local)

sand_kept :: proc(x, z: f64) -> f32 {
	return land_at(land.supply, land.n, x, z) - CARRY*land_at(land.surf, land.n, x, z)
}

waters_edge :: proc(h: f32, x, z, cell: f64) -> (top, laid: f32) {
	top = h
	if h > 6 || h < -8 do return
	surf := land_at(land.surf, land.n, x, z)
	if surf < 0.01 do return
	slope := max(land_at(land.slope, land.n, x, z), 0.02)
	// A bench at the sea's level under steep ground, where the waves cut the foot of a cliff back,
	// with gullies and pools along the strike of the beds, where they found a weakness. A gentle
	// shore has none: the land runs down into the sea, and the rock the forming cut lies under it.
	if open := smoothstep(0.1, 0.2, surf)*smoothstep(0.45, 0.8, slope); open > 0 {
		along := rock_strike(x, z)
		u, v := x*along.x + z*along.y, z*along.x - x*along.y
		flat := 0.2 + 0.9*fbm(u/2, v, 10, cell, 3, seed + 740) - (1.3 if fbm(u/4, v, 5, cell, 2, seed + 741) < -0.2 else 0)
		top += open*smoothstep(-4.5, -2.5, h)*max(flat - h, 0)
	}
	sand := smoothstep(-0.05, 0.05, sand_kept(x, z))
	berm := 1.2 + 6*surf*(1 - sand) + 0.3*fbm(x, z, 60, cell, 2, seed + 742)
	face := math.lerp(f32(0.22), 0.06, sand)
	out := max(berm - top, 0)/slope - 30*sand*clamp(sand_kept(x, z), 0, 0.5)   // metres seaward of the berm's edge
	TOE :: -2.5   // the face reaches down to here, and the bank ends in a steep front under the water
	s := berm - face*max(out, 0)
	if s < TOE do s = TOE - 0.6*(TOE - s)/face
	if s > top do laid = (s - top)*(1 - smoothstep(0.8, 1.5, slope))*(1 - smoothstep(0.2, 0.3, surf))
	top += laid
	if cell <= 2 {
		// Boulders lie in heaps along the foot of what stands over the platform, larger under a cliff.
		chance := smoothstep(0.15, 0.3, surf)*smoothstep(0.6, 1.2, top)*(1 - smoothstep(3, 6, top))*smoothstep(-0.3, 0.1, fbm(x, z, 40, cell, 2, seed + 743))
		if b := stones(x, z, 0.45*chance, 1 + 0.6*smoothstep(0.4, 1.5, slope)); b > 0 do top, laid = top + b, laid + b
	}
	return
}

// Stones on a 3 m grid: in each square, with this chance, one of about this radius in metres,
// rounded, the tallest where two meet, so that they lie in heaps.
stones :: proc(x, z: f64, chance, size: f32) -> (h: f32) {
	if chance <= 0 do return
	gx, gz := i32(math.floor(x/3)), i32(math.floor(z/3))
	for j in gz - 1..=gz + 1 do for i in gx - 1..=gx + 1 {
		r := hash(i, j, seed + 730)
		if f32(r & 0xFF)/255 >= chance do continue
		rad := size*(1.3 + f32((r >> 8) & 0xFF)/255)   // none so small that it is one block, which reads as a box
		dx, dz := f32(x) - (f32(i)*3 + 3*f32((r >> 16) & 0xFF)/255), f32(z) - (f32(j)*3 + 3*f32(r >> 24)/255)
		if q := (dx*dx + dz*dz)/(rad*rad); q < 1 do h = max(h, rad*math.sqrt(1 - q))
	}
	return
}

height_at :: proc(x, z, cell: f64) -> f32 {
	return ground(x, z, cell).h
}

// What covers the ground, as an ordered catalogue: the first row whose host holds is the
// surface. Air brings the rock itself: what has fallen there, or else the bed.
// Forest holds on ground up to about 45° and scrub clings to about 52°, as on real flanks in a
// wet climate; only a face steeper than that is bare, which a weak rock makes only where the sea
// undercuts it or as the riser of a ledge.
Surface :: struct {
	name, why: string,
	brings:    Mat,
	host:      []Window,
}

SURFACES := [?]Surface{
	{"river gravel", "a river lays gravel on its bars and its bed", .Gravel, {{.Gravel, 0, ANY, 0}}},
	{"sand", "the waves keep the sand the rivers bring where the shore is sheltered enough", .Sand, {{.Beach, 0.3, ANY, 0}, {.Sand_Kept, 0, ANY, 0}}},
	{"boulders", "the swell breaks on this shore and leaves only stones too large for it to move", .Air, {{.Beach, 0.3, ANY, 0}, {.Surf, 0.25, ANY, 0}}},
	{"shingle", "the waves round the stones the shore gives them and throw them up in a bank", .Shingle, {{.Beach, 0.3, ANY, 0}}},
	{"washed rock", "the waves wash the rock bare to this height, and a little way under the sea, where sand cannot settle for them", .Air, {{.Surf, 0.1, ANY, 0}, {.Washed, 0, ANY, 0}, {.Height, -1.5, ANY, 0}}},
	{"lake bed", "silt settles out of the still water of a lake or pond", .Silt, {{.Under_Water, 0, ANY, 0}}},
	{"loose rock", "rock fallen from the face above lies at its angle of rest", .Air, {{.Fallen, 0, ANY, 0}}},
	{"bare rock", "soil cannot hold on ground this steep, so the beds show", .Air, {{.Too_Steep, 0, ANY, 0}}},
	{"sea floor", "sand settles under the sea where the waves do not stir it", .Sand, {{.Height, -ANY, 0.5, 0}}},
	{"bare scar", "a slide stripped the hillside to the rock, and no soil has yet weathered back", .Air, {{.Disturbed, -ANY, 1e4, 0}, {.Slid, -ANY, -0.5, 0}, {.Soil_Depth, -ANY, 0.15, 0}}},
	{"trail", "animals have trodden a path through the plants to the earth", .Dirt, {{.Trail, -ANY, 0.75, 0}}},
	{"soil", "soil holds, and the plants cover it", .Grass, {}},   // the plant community brings what covers it
}

// Sand and shingle are ground from the island's rock: black from basalt and scoria (Miyakejima,
// Ōshima), pale from every other (Kōzushima's rhyolite, Kikaijima's coral, sandstone).
shore_of :: proc(m, bed: Mat) -> Mat {
	if bed != .Basalt && bed != .Scoria do return m
	return .Black_Sand if m == .Sand else .Black_Shingle if m == .Shingle else m
}

surface_row :: proc(p: ^Point) -> int {
	for r, i in SURFACES do if host(r.host, p) > 0 do return i
	return len(SURFACES) - 1
}

// What the ground is at a point, what covers it, and the plant community growing there, if
// soil holds.
surface_at :: proc(x, z, cell: f64, at: ^Point = nil) -> (g: Ground, m: Mat, plants: Maybe(Community_Kind)) {
	p := point_at(x, z, cell)
	defer if at != nil do at^ = p
	row := surface_row(&p)
	m = SURFACES[row].brings
	if row == len(SURFACES) - 1 {
		k, _ := community_at(x, z, cell)
		m, plants = COMMUNITIES[k].cover, k
	}
	if m == .Air do m = p.cover if p.cover != .Air else crushed(rock_in(p.h - 0.5, p.under, rock_level(cell)), p.under)
	if m == .Sand || m == .Shingle do m = shore_of(m, rock_in(p.h - p.laid - 0.5, p.under, rock_level(cell)))
	if m == .Gravel && len(land.pebble) > 0 do if k := land.pebble[land_cell(x, z)]; k != .Air do m = FORMS[k].gravel   // of the rock upstream
	return p.g, m, plants
}

// ---- what the engine asks for -------------------------------------------------------------

// Whether a chunk of columns wider than COARSE lies wholly outside every island's region, in the open
// sea between them: under the sea such columns have no faces (mesh_columns), so nothing need be
// worked out for it.
open_sea :: proc(key: Key) -> bool {
	s := f64(i32(1) << u32(key.level))
	if s <= COARSE do return false
	lo := [2]f64{f64(key.x), f64(key.z)}*CHUNK*s
	for &f in formed {
		o, h := [2]f64{f64(f.island.origin.x), f64(f.island.origin.y)}, f.island.size/2
		if lo.x < o.x + h && lo.x + CHUNK*s > o.x - h && lo.y < o.y + h && lo.y + CHUNK*s > o.y - h do return false
	}
	return true
}

// The ground under a chunk at a level of detail. Beyond the nearest level, single trees are
// crowns hung over the ground on their trunks while cells are small enough to show them, then
// a canopy that is part of the columns. Each column is the island's whose region holds it, or
// the open sea's, whose floor lies level with every region's rim.
gen_columns :: proc(level, cx, cz: i32, c: ^Columns) {
	s := i32(1) << u32(level)
	cell := f64(s)
	heights: [P*P]f32
	for j in 0..<i32(P) {
		for i in 0..<i32(P) {
			ix, iz := cx*CHUNK + i - 1, cz*CHUNK + j - 1   // cell coordinates at this level, in the world
			k := j*P + i
			if !bind_at((f64(ix) + 0.5)*cell, (f64(iz) + 0.5)*cell) {
				heights[k], c.water[k], c.mat[k], c.top[k], c.ground[k] = SEA_BED, SEA_SURFACE, .Sand, SEA_BED, SEA_BED
				continue
			}
			x, z := (f64(ix) + 0.5)*cell - f64(region.origin.x), (f64(iz) + 0.5)*cell - f64(region.origin.y)
			p: Point
			g, m, plants := surface_at(x, z, cell, &p)
			heights[k], c.water[k], c.under[k], c.mat[k] = g.h, g.water, g.under, m
			if s == 1 do if kind, ok := plant_at(&p, m, plants); ok && g.water - g.h <= GROUND_PLANTS[kind].wet do c.plant[k] = u8(kind) + 1
			c.top[k] = i32(math.round(heights[k]))
			if heights[k] < SEA_SURFACE do c.top[k] = min(c.top[k], SEA_LEVEL - 1)   // what the land says is under the sea is drawn under it: a shoal is a shallow, not a raft of sand
			c.ground[k] = c.top[k]
			if s <= 8 do c.hollow[k] = hollow_at(x, z, cell)
			// The canopy: a cell is the leaf of a tree its community would grow, raised to about
			// the height of that tree's crown.
			if com, ok := plants.?; ok && s >= 8 {
				r := hash(i32(math.floor(x/cell)), i32(math.floor(z/cell)), seed + 160 + u32(level))
				spacing, tall, old := stand(land.age[dithered(x, z, r)])
				if gap, _, _ := gap_at(x, z, old); !gap && f32(r & 0xFFFF)/65536 < cover(com, spacing) {
					sp := SPECIES[pick_species(com, f32((r >> 16) & 0xFF)/256)]
					c.top[k] += i32(f32(sp.height[0] + i32((r >> 24) % u32(sp.height[1] - sp.height[0] + 1)))*tall) - 1
					c.mat[k] = sp.leaf
				}
			}
		}
	}
	// The slope of the ground before it was cut into blocks. Light uses it so that a
	// hillside shades as a hillside and not only as a staircase. Crowns keep zero.
	for j in 1..<P - 1 {
		for i in 1..<P - 1 {
			k := j*P + i
			if c.top[k] > c.ground[k] do continue
			gx := (heights[k + 1] - heights[k - 1])/f32(2*s)
			gz := (heights[k + P] - heights[k - P])/f32(2*s)
			inv := 127/math.sqrt(gx*gx + gz*gz + 1)
			c.slope[k] = {u8(128 - gx*inv), u8(128 - gz*inv)}
		}
	}
	if (level == 1 || level == 2) && bind_at(f64((cx*CHUNK + CHUNK/2)*s), f64((cz*CHUNK + CHUNK/2)*s)) {   // the trees of the island under the chunk's middle
		trees := make([dynamic]Tree, context.temp_allocator)
		x0, z0 := (cx*CHUNK - 1)*s - region.origin.x, (cz*CHUNK - 1)*s - region.origin.y
		trees_in(x0 - TREE_REACH, z0 - TREE_REACH, x0 + P*s + TREE_REACH, z0 + P*s + TREE_REACH, &trees)
		for t in trees {
			if t.form > (.Between if level == 1 else .Canopy) do continue   // past half a kilometre only the canopy trees: the ones between them are smaller than a cell there
			mid := crown_at(t)
			for j in max((t.z - TREE_REACH - z0)/s, 0)..=min((t.z + TREE_REACH - z0)/s, P - 1) {
				for i in max((t.x - TREE_REACH - x0)/s, 0)..=min((t.x + TREE_REACH - x0)/s, P - 1) {
					dx := f32(x0 + i*s) + f32(s)/2 - mid.x
					dz := f32(z0 + j*s) + f32(s)/2 - mid.y
					k := j*P + i
					lo, hi := envelope(t, math.sqrt(dx*dx + dz*dz))
					under, over := max(t.base + i32(math.round(lo)), c.ground[k]), t.base + i32(math.round(hi))
					if over <= under do continue
					if c.crown[k][1] > c.crown[k][0] do under, over = min(under, c.crown[k][0]), max(over, c.crown[k][1])
					c.crown[k], c.kind[k] = {under, over}, t.kind
				}
			}
			// The trunk's own cell always carries crown, so a small tree is never lost between cells.
			if i, j := (t.x - x0)/s, (t.z - z0)/s; t.x >= x0 && t.z >= z0 && i < P && j < P {
				k := j*P + i
				c.stem[k], c.kind[k] = u8(1 + (t.x - x0 - i*s) + 4*(t.z - z0 - j*s)), t.kind
				if lo, hi := envelope(t, 0); c.crown[k][1] <= c.crown[k][0] do c.crown[k] = {max(t.base + i32(math.round(lo)), c.ground[k]), t.base + i32(math.round(hi))}
			}
		}
	}
	c.lo, c.hi = max(i32), min(i32)
	for k in 0..<P*P {
		c.lo = min(c.lo, c.ground[k], c.hollow[k][0] if c.hollow[k][1] > c.hollow[k][0] else max(i32))
		c.hi = max(c.hi, c.top[k], c.crown[k][1] if c.crown[k][1] > c.crown[k][0] else c.top[k])   // a column with no crown has {0, 0}, which over the sea is no top
	}
}

// The block at a depth below the surface of a column, where `bed` is the rock at that
// height. Bare rock is rock all the way down, so a face and a hole show the same beds. Under a
// plant cover lie `deep` blocks of the soil, counting the cover, and some may be stones, then,
// where the rock was read from the island's setting, BROKEN blocks of the rock broken in place.
BROKEN :: 2

// The rock as a fault's crushed core has it at the nearest level: broken.
crushed :: #force_inline proc(m: Mat, u: Under) -> Mat {
	if u.crush do if b := FORMS[m].broken; b != .Air do return b
	return m
}

block_below :: proc(surface: Mat, depth: i32, bed: Mat, soil: ^Soil, deep: i32, stone: bool) -> Mat {
	if is(surface, COVERS) {
		if depth == 0 do return surface
		if depth >= deep + BROKEN || depth >= deep && !rocks.full do return bed
		if depth >= deep do return FORMS[bed].broken if FORMS[bed].broken != .Air else bed
		if stone && MATERIALS[bed].loose != .Air do return MATERIALS[bed].loose
		return soil.top if depth == 1 else soil.foot if depth == deep - 1 && deep > 2 else soil.sub
	}
	#partial switch surface {
	case .Sand, .Silt, .Black_Sand, .Shingle, .Black_Shingle: return surface if depth < 4 else bed
	case .Snow:  return .Snow if depth < 2 else bed
	}
	if is(surface, PEBBLES) do return surface if depth < 2 else bed
	if is(surface, RUBBLE) do return surface if depth < 5 else bed   // loose rock lies on the bed
	return bed
}

// The blocks of a nearest-level chunk and its border, in layers from y_base up. `lo` and
// `hi` widen the vertical range, for edits that reach outside the generated ground. They are
// the island's under the chunk's middle, which stays bound for meshing; a column of the open sea
// is sand to the bottom.
gen_volume :: proc(cx, cz: i32, c: ^Columns, lo, hi: i32) -> (blocks: []Mat, y_base, h: i32) {
	trees := make([dynamic]Tree, context.temp_allocator)
	sea := !bind_at(f64(cx*CHUNK + CHUNK/2), f64(cz*CHUNK + CHUNK/2))
	x0, z0 := cx*CHUNK - 1 - region.origin.x, cz*CHUNK - 1 - region.origin.y
	if !sea do trees_in(x0 - TREE_REACH, z0 - TREE_REACH, x0 + P + TREE_REACH, z0 + P + TREE_REACH, &trees, true)
	top := max(hi, c.hi)
	for t in trees do top = max(top, t.base + t.height + 1)

	y_base = min(lo, c.lo) - 4   // room below for the rim faces and corner light
	h = top - y_base + 1
	blocks = make([]Mat, P*P*int(h))
	for k in 0..<P*P {
		t := c.top[k]
		x, z := x0 + i32(k%P), z0 + i32(k/P)
		if sea || island_at(f64(x + region.origin.x) + 0.5, f64(z + region.origin.y) + 0.5) == nil {
			for y in y_base..<t do blocks[k + int(y - y_base)*P*P] = .Sand
			continue
		}
		soil, deep := &SOILS[0], i32(0)
		if is(c.mat[k], COVERS) {
			p := Point{x = f64(x) + 0.5, z = f64(z) + 0.5, cell = 1}
			row, depth := soil_at(&p)
			soil, deep = &SOILS[row], 1 + i32(math.ceil(depth))
		}
		debris := slid_at(f64(x) + 0.5, f64(z) + 0.5)   // a slide's broken rock lies over the beds
		for y in y_base..<t {
			stone := hash01(x + y*131, z, seed + 190) < soil.stones
			bed := (landslide.rock if c.mat[k] == landslide.rock && t - y <= 6 else MATERIALS[landslide.rock].loose) if f32(t - y) <= debris else crushed(rock_in(f32(y) + 0.5, c.under[k], 0), c.under[k])   // a block of the cap is whole
			b := block_below(c.mat[k], t - 1 - y, bed, soil, deep, stone)
			blocks[k + int(y - y_base)*P*P] = shore_of(b, bed)
		}
		for y in c.hollow[k][0]..<min(c.hollow[k][1], t) do blocks[k + int(y - y_base)*P*P] = .Air   // a hollow under a roof of the beds
	}
	for t in trees {
		put :: proc(blocks: []Mat, x, y, z: i32, m: Mat, replace: bool) {
			if x < 0 || x >= P || z < 0 || z >= P || y < 0 do return   // below y is this chunk's solid ground: a tree at a cliff's foot
			k := int(x) + int(z)*P + int(y)*P*P
			if replace || blocks[k] == .Air do blocks[k] = m
		}
		if t.form != .Fallen {
			grow(blocks, t, {x0, y_base, z0}, c)
			continue
		}
		// A stump, and the trunk lying beyond it (trees_in).
		bark := SPECIES[t.kind].bark
		put(blocks, t.x - x0, t.base - y_base, t.z - z0, bark, false)
		for d in 2..<2 + t.height do put(blocks, t.x - x0 + i32(t.fall.x)*d, t.base - y_base, t.z - z0 + i32(t.fall.y)*d, bark, false)
	}
	return
}
