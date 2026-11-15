package main

import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"

// The ground plants: what stands on the ground between the trees, drawn as two pictures crossed
// in an X on top of a column, as other block games draw grass and ferns. They exist only near the
// player, in the nearest ring of chunks, and fade out by distance; beyond them the ground's own tile
// carries their colour. They take no part in collision, cast no shadow, and are lit as the ground
// they stand on is lit. Each is a row hosted on the fields: what it grows on, in which plant
// communities, how many columns in a hundred it takes where its host holds, and how it clumps. The
// rows are tried in order and the first whose draw comes up at a column stands there. Its pictures
// are a row of assets/plants.png, built by tools/blocks.py. The flora is from
// docs/interesting-world/notes/real-vegetation.md, "The ground layer".
Plant_Kind :: enum u8 { Reed, Sedge, Susuki, Bamboo, Bracken, Fern, Shrub, Ardisia, Forest_Grass, Grass, Knotweed, Dead_Stems, Dune_Sedge, Vitex, Flower }
Ground_Plant :: struct {
	name, why: string,
	tall:      bool,      // two pictures high
	size:      [2]f32,    // metres a picture stands, the smallest and the largest
	share:     f32,       // of the columns where its host holds, the share it takes on average
	clump:     f32,       // metres across its clumps, with thin ground and bare patches between them
	wet:       f32,       // metres of water it can stand in
	on:        bit_set[Mat],
	within:    bit_set[Community_Kind],   // empty for any, or where no community grows, as a lake's bed
	host:      []Window,
}
SOIL_COVERS :: bit_set[Mat]{.Grass, .Litter, .Susuki, .Dune}
FORESTS :: bit_set[Community_Kind]{.Valley, .Slope, .Ridge, .Young}
RUBBLE :: bit_set[Mat]{.Mudstone_Scree, .Siltstone_Scree, .Sandstone_Scree, .Grit_Scree, .Limestone_Scree, .Basalt_Scree, .Scoria_Scree, .Rhyolite_Scree, .Tuff_Scree, .Reef_Scree}

GROUND_PLANTS := [Plant_Kind]Ground_Plant{
	.Reed = {"reeds", "common reed stands in a band in the shallows and on the wet margin of still or slow water, as wide as the shore is gentle", true, {1.3, 1.6}, 0.9, 5, 0.9, SOIL_COVERS + {.Silt}, {},
		{{.Over_Water, -0.8, 0.4, 0.3}}},
	.Sedge = {"sedges", "sedges and wild rice fill the wet ground above the reeds", false, {0.9, 1.1}, 0.6, 4, 0.1, SOIL_COVERS, {},
		{{.Over_Water, 0.3, 1.4, 0.4}}},
	.Susuki = {"susuki", "tall susuki grass stands where wind, salt or a slide keep the wood open", true, {0.65, 0.8}, 0.5, 9, 0, SOIL_COVERS, {.Windy, .Fresh, .Alder},
		{{.Canopy, -ANY, 0.5, 0.25}}},
	.Bamboo = {"dwarf bamboo", "dwarf bamboo spreads in dense patches through the grass of windy ground", false, {1, 1.3}, 0.45, 18, 0, SOIL_COVERS, {.Windy}, {}},
	.Bracken = {"bracken", "bracken takes the light of open grass and of gaps in the wood", true, {0.6, 0.8}, 0.3, 12, 0, SOIL_COVERS, FORESTS + {.Windy, .Alder},
		{{.Canopy, -ANY, 0.35, 0.2}}},
	.Fern = {"ferns", "evergreen ferns of the laurel forest's floor, thick in its half shade and thinning where the canopy closes", false, {0.8, 1}, 0.35, 7, 0, {.Litter, .Grass}, FORESTS + {.Alder},
		{{.Canopy, 0.2, 0.75, 0.35}}},
	.Shrub = {"evergreen shrubs", "aoki and other shrubs that keep their leaves grow up in the forest's shade", false, {0.9, 1.2}, 0.08, 10, 0, {.Litter, .Grass}, FORESTS,
		{{.Canopy, 0.4, ANY, 0.3}}},
	.Ardisia = {"manryō", "manryō, a knee-high shrub that holds red berries through the winter, in deep shade", false, {0.7, 0.9}, 0.05, 6, 0, {.Litter, .Grass}, FORESTS,
		{{.Canopy, 0.6, ANY, 0.3}}},
	.Forest_Grass = {"forest grass", "mondo grass, sedges and grasses on the moist floor of valley woods", false, {0.6, 0.8}, 0.3, 6, 0, {.Grass}, {.Valley}, {}},
	.Grass = {"grass", "short grasses and chigaya between the susuki", false, {0.7, 0.9}, 0.35, 5, 0, SOIL_COVERS, {.Windy, .Fresh, .Alder}, {}},
	.Knotweed = {"itadori", "itadori, a knotweed, is first onto the rubble and raw ground a slide laid bare, with the susuki", false, {0.9, 1.2}, 0.25, 8, 0, SOIL_COVERS + RUBBLE, {},
		{{.Disturbed, -ANY, 150, 150}}},
	.Dead_Stems = {"dead stems", "last year's stems of itadori stand dead among the new shoots", false, {0.8, 1}, 0.08, 6, 0, SOIL_COVERS + RUBBLE, {}, {{.Disturbed, -ANY, 60, 60}}},
	.Dune_Sedge = {"kōbōmugi", "kōbōmugi, a sedge whose runners bind the sand, grows nearest the sea, above the line the waves reach", false, {0.6, 0.8}, 0.4, 6, 0, {.Sand, .Dune}, {},
		{{.Beach, -ANY, -0.3, 0.3}, {.Inland, -ANY, 60, 30}}},
	.Vitex = {"hamagō", "hamagō, a low shrub that creeps over the dunes behind the sedge", false, {0.8, 1}, 0.15, 8, 0, {.Dune}, {.Coast}, {{.Inland, 20, ANY, 20}}},
	.Flower = {"nigana", "nigana and other yellow daisies flower in open grass in spring", false, {0.8, 1}, 0.03, 4, 0, {.Susuki, .Dune, .Grass}, {.Windy, .Coast, .Fresh}, {}},
}

// The plant standing on a column, if one does, and the chance each row had there. `m` is what
// covers the ground and `com` the community growing on it.
plant_at :: proc(p: ^Point, m: Mat, com: Maybe(Community_Kind), chances: ^[Plant_Kind]f32 = nil) -> (kind: Plant_Kind, ok: bool) {
	k, grows := com.?
	cx, cz := i32(math.floor(p.x)), i32(math.floor(p.z))
	for row, i in GROUND_PLANTS {
		if m not_in row.on || card(row.within) > 0 && (!grows || k not_in row.within) do continue
		u := hash01(cx, cz, seed + 800 + u32(i))
		if u >= 1.6*row.share && chances == nil do continue   // it could not come up here, however well it is hosted
		// Clumps: smooth noise on the scale of the row's clumps, so it stands thick in some
		// patches and is missing from others, as plants spreading by runners and seed do.
		clumps := 1.6*smoothstep(0.3, 0.7, 0.5 + fbm(p.x, p.z, f64(row.clump), 1, 2, seed + 820 + u32(i)))
		chance := min(row.share*clumps*host(row.host, p), 1)
		if chances != nil do chances[i] = chance
		if u < chance && chances == nil do return i, true
		if u < chance && !ok do kind, ok = i, true
	}
	return
}

// The share of the sky a stand's crowns hide from the ground: the cover of its community at its
// spacing, or in a gap as much as its young growth has closed it.
canopy_at :: proc(x, z: f64) -> f32 {
	k, c := community_at(x, z, 1)
	if land.community[c] == 255 do return 0
	spacing, _, old := stand(land.age[c])
	if gap, _, ago := gap_at(x, z, old); gap do return cover(k, spacing)*ago/STANDS.refill
	return cover(k, spacing)
}

// Metres of the ground over the still water it lies in or beside, or else over a slow stream
// within 8 m: one on ground gentler than 1 in 5, as a stream runs over a valley floor or a plain.
over_water :: proc(p: ^Point) -> f32 {
	level, inside, _ := lake_near(p.x, p.z)
	if !inside {
		r, ok := river_near(f32(p.x), f32(p.z))
		if !ok || r.d - r.half > 8 || land_at(land.slope, land.n, p.x, p.z) > 0.2 do return ANY
		level = r.bank - FREEBOARD
	}
	return p.h - level
}

// A plant as the renderer takes it, in the Quad's 16 bytes: the column's corner from the chunk's
// origin, the row (and 1 << 8 when two pictures high), a hash for its place, size and turn, its
// height in centimetres and the row again for the water, the ground's light, and the ground's slope.
plant_quad :: proc(x, y, z: i32, kind: Plant_Kind, wx, wz: i32, light: u16, slope: [2]u8) -> Quad {
	row := GROUND_PLANTS[kind]
	h := hash(wx, wz, seed + 830)
	size := math.lerp(row.size[0], row.size[1], f32(h >> 16)/65535)
	return {i16(x), i16(y), i16(z), i16(u16(kind) | u16(row.tall) << 8), u16(h), u16(size*100), light, slope}
}

// How many of a chunk's plants stand in more water than their row can.
plants_drowned :: proc(wt: ^Water, c: ^Chunk) -> (n: int) {
	for q in c.plants do n += int(wt.depth[water_cell(c.key.x*CHUNK + i32(q.x), c.key.z*CHUNK + i32(q.z))] > GROUND_PLANTS[Plant_Kind(q.a & 0xFF)].wet + 0.1)
	return
}

// Upload a chunk's plants, leaving out any standing in more water than its row can, so a plant
// the simulated water has flooded goes. Returns how many were left out.
plants_upload :: proc(dev: ^sdl.GPUDevice, c: ^Chunk, wt: ^Water) -> (drowned: int) {
	kept := make([dynamic]Quad, 0, len(c.plants), context.temp_allocator)
	for q in c.plants {
		if wt.depth[water_cell(c.key.x*CHUNK + i32(q.x), c.key.z*CHUNK + i32(q.z))] > GROUND_PLANTS[Plant_Kind(q.a & 0xFF)].wet + 0.1 do drowned += 1
		else do append(&kept, q)
	}
	if c.plant_buf != nil do sdl.ReleaseGPUBuffer(dev, c.plant_buf)
	c.plant_buf, c.plant_count = nil, u32(len(kept))
	if len(kept) == 0 do return
	n := u32(len(kept)*size_of(Quad))
	c.plant_buf = sdl.CreateGPUBuffer(dev, {usage = {.VERTEX}, size = n})
	staging := sdl.CreateGPUTransferBuffer(dev, {usage = .UPLOAD, size = n})
	copy((cast([^]u8)sdl.MapGPUTransferBuffer(dev, staging, false))[:n], (cast([^]u8)raw_data(kept))[:n])
	sdl.UnmapGPUTransferBuffer(dev, staging)
	cmd := sdl.AcquireGPUCommandBuffer(dev)
	pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUBuffer(pass, {staging, 0}, {c.plant_buf, 0, n}, false)
	sdl.EndGPUCopyPass(pass)
	_ = sdl.SubmitGPUCommandBuffer(cmd)
	sdl.ReleaseGPUTransferBuffer(dev, staging)
	return
}

// The ground plant at a point, in a sentence, as --why prints it.
plant_words :: proc(p: ^Point, m: Mat, com: Maybe(Community_Kind)) {
	chances: [Plant_Kind]f32
	kind, ok := plant_at(p, m, com, &chances)
	best := Plant_Kind.Reed
	for c, k in chances do if c > chances[best] do best = k
	if ok {
		row := GROUND_PLANTS[kind]
		fmt.printf("the ground plant is %s: %s; it takes %.0f in a hundred columns here", row.name, row.why, 100*chances[kind])
		if near, _ := edges(row.host, p); near[0] != "" do fmt.printf(". Here %s", near[0])
		fmt.println(".")
	} else if chances[best] > 0 {
		fmt.printfln("no ground plant stands on this spot; the likeliest here, %s, takes %.0f in a hundred columns", GROUND_PLANTS[best].name, 100*chances[best])
	} else {
		fmt.printfln("no ground plant grows on %v here", m)
	}
}
