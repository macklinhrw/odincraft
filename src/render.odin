package main

import "core:encoding/endian"
import "core:fmt"
import "core:bytes"
import "core:hash"
import "core:image/png"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"

// Drawing. A frame is: four sun shadow maps, the cloud layer at half size, then terrain, sky (where no terrain is) and water
// into a 4x multisampled target that resolves to the scene texture, then the scene to the
// window. Lighting, clouds, fog and tone mapping live in shaders.metal.

SHADERS    :: #load("shaders.metal", string)
BLOCKS     :: #load("../assets/blocks.png")   // the faces of every block, drawn by tools/blocks.py: a row for each material, its top then its side
PLANTS     :: #load("../assets/plants.png")   // the ground plants' pictures, by tools/blocks.py: a row for each, its lower picture then any upper one
TILE       :: 16
SHADOW_RES :: 2048
BOX_MAX    :: 8192   // creatures' boxes drawn a frame at most
FOV        :: 70.0   // vertical, degrees
NEAR       :: 0.1

// Shadow cascades: how far each reaches from the camera, the finest level of detail drawn
// into it, and how many frames pass between redraws. A far cascade cannot resolve single
// blocks, so it does not draw them, and it covers so much ground that the camera barely
// moves across it in a few frames. The second and third take turns, a frame each: between them
// they draw every tree in a kilometre, which is most of what a wooded view costs. Each draws
// only the chunks that can shade ground in view (see the shadow pass in `render`).
CASCADE_RADIUS    :: [4]f32{64, 256, 1024, 4096}
CASCADE_MIN_LEVEL :: [4]i32{0, 0, 1, 3}
CASCADE_INTERVAL  :: [4]int{1, 2, 2, 4}

Gpu :: struct {
	dev:            ^sdl.GPUDevice,
	window:         ^sdl.Window,
	format:         sdl.GPUTextureFormat,
	source:         cstring,
	w, h:           u32,
	color, depth:   ^sdl.GPUTexture,   // multisampled
	scene:          ^sdl.GPUTexture,   // resolved frame
	clouds:         ^sdl.GPUTexture,   // the cloud layer along each line of sight, at half size
	shadow:         ^sdl.GPUTexture,   // one layer per cascade
	shadow_sampler: ^sdl.GPUSampler,
	blocks:         ^sdl.GPUTexture,   // one layer per tile of the atlas
	plant_pics:     ^sdl.GPUTexture,   // the same for the ground plants
	plant_sampler:  ^sdl.GPUSampler,
	lifted:         ^sdl.GPUTexture,   // the field `lifted`, for the cloud cap
	block_sampler:  ^sdl.GPUSampler,
	linear:         ^sdl.GPUSampler,
	terrain, shadow_pipe, sky, water, river, pool, present, plant, cloud_pipe, box: ^sdl.GPUGraphicsPipeline,
	ribbon:         ^sdl.GPUBuffer,    // the rivers' water surface
	ribbon_count:   u32,
	falls:          ^sdl.GPUBuffer,    // the falling water, as quads of simulated water
	falls_count:    u32,
	boxes:          ^sdl.GPUBuffer,    // the creatures' boxes, written each frame
	box_staging:    ^sdl.GPUTransferBuffer,
	boxes_drawn:    int,
	quads_drawn:    int,
	plants_drawn:   int,
	frame:          int,
	cascade_vp:     [4]matrix[4, 4]f32,   // each shadow map's view as it was last drawn
	cascade_eye:    [4][3]f64,            // and the eye it was drawn round
	waited:         f64,   // seconds the last frame spent waiting for the display
	unseen:         bool,  // no window is shown: frames are drawn in full and paced as a 120 Hz display would
	shown_at:       u64,   // when the last unseen frame was done
}

// What to draw.
View :: struct {
	eye:        [3]f64,
	yaw, pitch: f32,
	hour:       f32,    // time of day, 0..24, by the sun
	day:        f32,    // of the year, 0 on 1 January
	weather:    [2]f32, // cover and cloud base forced by --weather, where they are 0 or more
	seconds:    f32,
	target:     [3]i32, // block being aimed at
	has_target: bool,
	crosshair:  bool,
	boxes:      []Box,  // the creatures near enough to see (creatures.odin)
}

// Mirrors `Frame` in shaders.metal.
Frame :: struct {
	view_proj: matrix[4, 4]f32,
	shadow_vp: [4]matrix[4, 4]f32,
	cascade_r, sun, cam, target, cam_r, cam_u, cam_f, screen, cloud, weather: [4]f32,
}

// The sky through the year, from the 1991-2020 normals at Tanegashima (30.7° N, 25 m high, the
// nearest low island to this latitude): each month's mean cover is the share of its daylight
// without sunshine. Each spell draws a cover around the month's mean and a cloud base, and the
// weather passes from one spell to the next; the clouds drift on the wind at `wind` m/s.
Sky :: struct {
	cover:       [12]f32,
	spell, deck: f32,      // days a spell lasts; metres from the cloud base to the deck's top
	base:        [2]f32,   // metres, the lowest and highest cloud base
	wind:        f32,
}
SKY := Sky{cover = {0.66, 0.62, 0.62, 0.57, 0.62, 0.73, 0.48, 0.45, 0.54, 0.55, 0.59, 0.62}, spell = 2, deck = 300, base = {250, 1000}, wind = 8}

// The cover (0 clear to 1 overcast) and cloud base at a time, the same for the same seed.
FAIR :: 0.3   // cloud cover under which a day counts as fair
weather_at :: proc(day, hour: f32) -> (cover, base: f32) {
	t := (day + hour/24)/SKY.spell
	k, w := i32(math.floor(t)), smoothstep(0, 1, t - math.floor(t))
	for i in i32(0)..=1 {
		mean := SKY.cover[int((f32(k + i) + 0.5)*SKY.spell/365*12) %% 12]
		c := math.pow(hash01(k + i, 0, seed + 700), 1/mean - 1)   // a draw whose mean is `mean`
		b := SKY.base[0] + (SKY.base[1] - SKY.base[0])*hash01(k + i, 1, seed + 700)*(1 - 0.5*c)   // lower under a heavier cover
		cover, base = cover + c*(w if i == 1 else 1 - w), base + b*(w if i == 1 else 1 - w)
	}
	return
}

Item :: struct {
	chunk:  ^Chunk,
	origin: [4]f32,   // chunk origin relative to the camera, and its cell size
	lo, hi: [3]f32,   // bounds relative to the camera
	level:  i32,
	mask:   u8,       // quarters not covered by a finer chunk
	seen:   bool,     // inside the view this frame
}

fatal :: proc(what: string) -> ! {
	fmt.eprintln(what, "failed:", sdl.GetError())
	os.exit(1)
}

Pipeline :: struct {
	vs, fs:                               cstring,
	vs_uniforms, fs_uniforms, fs_samplers: u32,
	quads:                                bool,   // takes Quad instances
	ribbon:                               bool,   // takes plain positions
	pool:                                 bool,   // takes Water_Quad instances
	boxes:                                bool,   // takes Box instances
	cull:                                 sdl.GPUCullMode,
	color:                                sdl.GPUTextureFormat,   // .INVALID for depth only
	samples:                              sdl.GPUSampleCount,
	depth, depth_write:                   bool,
	compare:                              sdl.GPUCompareOp,       // .INVALID for no depth test
	blend, clamp_depth:                   bool,
	coverage:                             bool,   // alpha to coverage, for cut-out pictures
}

make_pipeline :: proc(g: ^Gpu, p: Pipeline) -> ^sdl.GPUGraphicsPipeline {
	shader :: proc(g: ^Gpu, entry: cstring, stage: sdl.GPUShaderStage, uniforms, samplers: u32) -> ^sdl.GPUShader {
		s := sdl.CreateGPUShader(g.dev, {
			code_size = len(g.source), code = cast([^]u8)g.source, entrypoint = entry, format = {.MSL},
			stage = stage, num_samplers = samplers, num_uniform_buffers = uniforms,
		})
		if s == nil do fatal(string(entry))
		return s
	}
	vs := shader(g, p.vs, .VERTEX, p.vs_uniforms, 0)
	fs := shader(g, p.fs, .FRAGMENT, p.fs_uniforms, p.fs_samplers)
	defer sdl.ReleaseGPUShader(g.dev, vs)
	defer sdl.ReleaseGPUShader(g.dev, fs)

	buffers := [1]sdl.GPUVertexBufferDescription{{slot = 0, pitch = size_of(Quad), input_rate = .INSTANCE}}
	attributes := [8]sdl.GPUVertexAttribute{0 = {location = 0, format = .SHORT4, offset = 0}, 1 = {location = 1, format = .USHORT4, offset = 8}}
	targets := [1]sdl.GPUColorTargetDescription{{format = p.color}}
	if p.blend {
		targets[0].blend_state = {
			enable_blend = true,
			src_color_blendfactor = .SRC_ALPHA, dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA, color_blend_op = .ADD,
			src_alpha_blendfactor = .ONE, dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA, alpha_blend_op = .ADD,
		}
	}
	info := sdl.GPUGraphicsPipelineCreateInfo {
		vertex_shader = vs, fragment_shader = fs,
		primitive_type = .TRIANGLESTRIP,
		rasterizer_state = {cull_mode = p.cull, front_face = .COUNTER_CLOCKWISE, enable_depth_clip = !p.clamp_depth},
		multisample_state = {sample_count = p.samples, enable_alpha_to_coverage = p.coverage},
		depth_stencil_state = {
			compare_op = p.compare if p.compare != .INVALID else .ALWAYS,
			enable_depth_test = p.compare != .INVALID, enable_depth_write = p.depth_write,
		},
		target_info = {
			color_target_descriptions = raw_data(&targets), num_color_targets = 1 if p.color != .INVALID else 0,
			depth_stencil_format = .D32_FLOAT, has_depth_stencil_target = p.depth,
		},
	}
	if p.quads do info.vertex_input_state = {raw_data(&buffers), 1, raw_data(&attributes), 2}
	if p.ribbon {
		buffers[0] = {slot = 0, pitch = size_of([4]f32), input_rate = .VERTEX}
		attributes[0] = {location = 0, format = .FLOAT4, offset = 0}
		info.vertex_input_state = {raw_data(&buffers), 1, raw_data(&attributes), 1}
	}
	if p.pool {
		buffers[0] = {slot = 0, pitch = size_of(Water_Quad), input_rate = .INSTANCE}
		for &a, i in attributes do a = {location = u32(i), format = .FLOAT3 if i < 4 else .FLOAT4, offset = u32(i*12 if i < 4 else 48 + (i - 4)*16)}
		info.vertex_input_state = {raw_data(&buffers), 1, raw_data(&attributes), 8}
	}
	if p.boxes {
		buffers[0] = {slot = 0, pitch = size_of(Box), input_rate = .INSTANCE}
		for i in 0..<4 do attributes[i] = {location = u32(i), format = .FLOAT4, offset = u32(16*i)}
		info.vertex_input_state = {raw_data(&buffers), 1, raw_data(&attributes), 4}
	}
	pipe := sdl.CreateGPUGraphicsPipeline(g.dev, info)
	if pipe == nil do fatal(string(p.vs))
	return pipe
}

// An atlas of tiles, each a layer, with smaller copies for the distance, so a far hillside is
// the average of the pixels a near one shows. Near by, pixels stay square.
atlas_layers :: proc(g: ^Gpu, file: []u8, rows: int, wrong: string) -> (tex: ^sdl.GPUTexture) {
	atlas, err := png.load_from_bytes(file, {.alpha_add_if_missing})
	if err != nil || atlas.width != 2*TILE || atlas.height != rows*TILE do fatal(wrong)
	pixels := bytes.buffer_to_bytes(&atlas.pixels)
	layers := u32(2*rows)
	tex = sdl.CreateGPUTexture(g.dev, {
		type = .D2_ARRAY, format = .R8G8B8A8_UNORM_SRGB, usage = {.SAMPLER, .COLOR_TARGET},
		width = TILE, height = TILE, layer_count_or_depth = layers, num_levels = 5,
	})
	staging := sdl.CreateGPUTransferBuffer(g.dev, {usage = .UPLOAD, size = layers*TILE*TILE*4})
	mapped := (cast([^]u8)sdl.MapGPUTransferBuffer(g.dev, staging, false))[:layers*TILE*TILE*4]
	for layer in 0..<int(layers) do for y in 0..<TILE {
		from := ((layer/2*TILE + y)*2*TILE + layer%2*TILE)*4
		copy(mapped[(layer*TILE + y)*TILE*4:][:TILE*4], pixels[from:][:TILE*4])
}
	sdl.UnmapGPUTransferBuffer(g.dev, staging)
	cmd := sdl.AcquireGPUCommandBuffer(g.dev)
	pass := sdl.BeginGPUCopyPass(cmd)
	for layer in 0..<layers {
		sdl.UploadToGPUTexture(pass, {transfer_buffer = staging, offset = layer*TILE*TILE*4}, {texture = tex, layer = layer, w = TILE, h = TILE, d = 1}, false)
}
	sdl.EndGPUCopyPass(pass)
	sdl.GenerateMipmapsForGPUTexture(cmd, tex)
	_ = sdl.SubmitGPUCommandBuffer(cmd)
	sdl.ReleaseGPUTransferBuffer(g.dev, staging)
	return
}

gpu_init :: proc(g: ^Gpu, window: ^sdl.Window) {
	g.window = window
	g.dev = sdl.CreateGPUDevice({.MSL}, false, nil)
	if g.dev == nil || !sdl.ClaimWindowForGPUDevice(g.dev, window) do fatal("GPU device")
	_ = sdl.SetGPUSwapchainParameters(g.dev, window, .SDR, .VSYNC)
	g.format = sdl.GetGPUSwapchainTextureFormat(g.dev, window)
	g.source = strings.clone_to_cstring(SHADERS)

	g.shadow = sdl.CreateGPUTexture(g.dev, {
		type = .D2_ARRAY, format = .D32_FLOAT, usage = {.SAMPLER, .DEPTH_STENCIL_TARGET},
		width = SHADOW_RES, height = SHADOW_RES, layer_count_or_depth = 4, num_levels = 1,
	})
	g.shadow_sampler = sdl.CreateGPUSampler(g.dev, {
		min_filter = .LINEAR, mag_filter = .LINEAR,
		address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
		compare_op = .LESS_OR_EQUAL, enable_compare = true,
	})
	g.linear = sdl.CreateGPUSampler(g.dev, {
		min_filter = .LINEAR, mag_filter = .LINEAR,
		address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
	})

	g.blocks = atlas_layers(g, BLOCKS, len(Mat), "assets/blocks.png does not have a row of two tiles for each material")
	g.plant_pics = atlas_layers(g, PLANTS, len(Plant_Kind), "assets/plants.png does not have a row of two pictures for each ground plant")
	g.block_sampler = sdl.CreateGPUSampler(g.dev, {
		min_filter = .LINEAR, mag_filter = .NEAREST, mipmap_mode = .LINEAR,
		address_mode_u = .REPEAT, address_mode_v = .REPEAT, address_mode_w = .REPEAT,
		max_anisotropy = 4, enable_anisotropy = true,
	})
	g.plant_sampler = sdl.CreateGPUSampler(g.dev, {
		min_filter = .LINEAR, mag_filter = .NEAREST, mipmap_mode = .LINEAR,
		address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
		max_anisotropy = 4, enable_anisotropy = true,
	})

	// The field `lifted`, one texel to a cell of the land, read by the cloud cap.
	n := u32(land.n)
	g.lifted = sdl.CreateGPUTexture(g.dev, {type = .D2, format = .R16_FLOAT, usage = {.SAMPLER}, width = n, height = n, layer_count_or_depth = 1, num_levels = 1})
	staging := sdl.CreateGPUTransferBuffer(g.dev, {usage = .UPLOAD, size = n*n*2})
	for &v, i in (cast([^]f16)sdl.MapGPUTransferBuffer(g.dev, staging, false))[:n*n] do v = f16(land.lifted[i])
	sdl.UnmapGPUTransferBuffer(g.dev, staging)
	cmd := sdl.AcquireGPUCommandBuffer(g.dev)
	pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUTexture(pass, {transfer_buffer = staging}, {texture = g.lifted, w = n, h = n, d = 1}, false)
	sdl.EndGPUCopyPass(pass)
	_ = sdl.SubmitGPUCommandBuffer(cmd)
	sdl.ReleaseGPUTransferBuffer(g.dev, staging)

	// Depth runs from 1 at the near plane to 0 at infinity, which keeps precision at long range.
	g.terrain = make_pipeline(g, {
		vs = "vs_terrain", fs = "fs_terrain", vs_uniforms = 2, fs_uniforms = 1, fs_samplers = 4, quads = true,
		cull = .BACK, color = g.format, samples = ._4, depth = true, depth_write = true, compare = .GREATER,
	})
	// Ground plants: crossed pictures cut out by alpha to coverage, seen from both sides, casting no shadow.
	g.plant = make_pipeline(g, {
		vs = "vs_plant", fs = "fs_plant", vs_uniforms = 2, fs_uniforms = 1, fs_samplers = 4, quads = true,
		cull = .NONE, color = g.format, samples = ._4, depth = true, depth_write = true, compare = .GREATER, coverage = true,
	})
	// Creatures: boxes, each a strip of fourteen corners, seen from any side, casting no shadow.
	g.box = make_pipeline(g, {
		vs = "vs_box", fs = "fs_box", vs_uniforms = 1, fs_uniforms = 1, fs_samplers = 3, boxes = true,
		cull = .NONE, color = g.format, samples = ._4, depth = true, depth_write = true, compare = .GREATER,
	})
	g.boxes = sdl.CreateGPUBuffer(g.dev, {usage = {.VERTEX}, size = BOX_MAX*size_of(Box)})
	g.box_staging = sdl.CreateGPUTransferBuffer(g.dev, {usage = .UPLOAD, size = BOX_MAX*size_of(Box)})
	g.shadow_pipe = make_pipeline(g, {
		vs = "vs_shadow", fs = "fs_shadow", vs_uniforms = 2, quads = true,
		cull = .BACK, depth = true, depth_write = true, compare = .LESS, clamp_depth = true,
	})
	g.sky = make_pipeline(g, {vs = "vs_screen", fs = "fs_sky", fs_uniforms = 1, fs_samplers = 1, color = g.format, samples = ._4, depth = true, compare = .GREATER_OR_EQUAL})   // drawn where the terrain left the depth cleared
	g.water = make_pipeline(g, {
		vs = "vs_water", fs = "fs_water", vs_uniforms = 1, fs_uniforms = 1, fs_samplers = 3,
		color = g.format, samples = ._4, depth = true, compare = .GREATER, blend = true,
	})
	// Simulated water writes depth, so a sheet of falling water is not seen through the pool in front of it.
	g.pool = make_pipeline(g, {
		vs = "vs_pool", fs = "fs_water", vs_uniforms = 2, fs_uniforms = 1, fs_samplers = 3, pool = true,
		color = g.format, samples = ._4, depth = true, depth_write = true, compare = .GREATER, blend = true,
	})
	g.present = make_pipeline(g, {vs = "vs_screen", fs = "fs_present", fs_uniforms = 1, fs_samplers = 1, color = g.format})
	g.cloud_pipe = make_pipeline(g, {vs = "vs_screen", fs = "fs_clouds", fs_uniforms = 1, fs_samplers = 1, color = .R16G16B16A16_FLOAT})
	// River water writes depth, so where two reaches meet the water is drawn once.
	g.river = make_pipeline(g, {
		vs = "vs_river", fs = "fs_water", vs_uniforms = 2, fs_uniforms = 1, fs_samplers = 3, ribbon = true,
		color = g.format, samples = ._4, depth = true, depth_write = true, compare = .GREATER, blend = true,
	})

	upload :: proc(g: ^Gpu, data: rawptr, bytes: int) -> ^sdl.GPUBuffer {
		if bytes == 0 do return nil
		buffer := sdl.CreateGPUBuffer(g.dev, {usage = {.VERTEX}, size = u32(bytes)})
		staging := sdl.CreateGPUTransferBuffer(g.dev, {usage = .UPLOAD, size = u32(bytes)})
		copy((cast([^]u8)sdl.MapGPUTransferBuffer(g.dev, staging, false))[:bytes], (cast([^]u8)data)[:bytes])
		sdl.UnmapGPUTransferBuffer(g.dev, staging)
		cmd := sdl.AcquireGPUCommandBuffer(g.dev)
		pass := sdl.BeginGPUCopyPass(cmd)
		sdl.UploadToGPUBuffer(pass, {staging, 0}, {buffer, 0, u32(bytes)}, false)
		sdl.EndGPUCopyPass(pass)
		_ = sdl.SubmitGPUCommandBuffer(cmd)
		sdl.ReleaseGPUTransferBuffer(g.dev, staging)
		return buffer
	}
	g.ribbon, g.ribbon_count = upload(g, raw_data(rivers.ribbon), len(rivers.ribbon)*size_of([4]f32)), u32(len(rivers.ribbon))
	g.falls, g.falls_count = upload(g, raw_data(rivers.falls), len(rivers.falls)*size_of(Water_Quad)), u32(len(rivers.falls))
}

resize :: proc(g: ^Gpu, w, h: u32) {
	if w == g.w && h == g.h do return
	for t in ([4]^sdl.GPUTexture{g.color, g.depth, g.scene, g.clouds}) do if t != nil do sdl.ReleaseGPUTexture(g.dev, t)
	g.w, g.h = w, h
	target :: proc(g: ^Gpu, format: sdl.GPUTextureFormat, usage: sdl.GPUTextureUsageFlags, samples: sdl.GPUSampleCount) -> ^sdl.GPUTexture {
		return sdl.CreateGPUTexture(g.dev, {
			type = .D2, format = format, usage = usage, width = g.w, height = g.h,
			layer_count_or_depth = 1, num_levels = 1, sample_count = samples,
		})
	}
	g.color = target(g, g.format, {.COLOR_TARGET}, ._4)
	g.depth = target(g, .D32_FLOAT, {.DEPTH_STENCIL_TARGET}, ._4)
	g.scene = target(g, g.format, {.COLOR_TARGET, .SAMPLER}, ._1)
	g.clouds = sdl.CreateGPUTexture(g.dev, {type = .D2, format = .R16G16B16A16_FLOAT, usage = {.COLOR_TARGET, .SAMPLER}, width = (w + 1)/2, height = (h + 1)/2, layer_count_or_depth = 1, num_levels = 1})
}

// The direction to the sun at an hour of solar time on a day of the year, at the region's latitude:
// x east, y up, z south. The declination is Cooper's (1969). The land's sunlight reads it too.
sun_dir :: proc(hour, day: f32) -> [3]f32 {
	dec := math.to_radians(f32(23.44))*math.sin(2*math.PI*(day - 80)/365)
	h, lat := (hour - 12)*math.PI/12, math.to_radians(f32(region.latitude))
	return {-math.cos(dec)*math.sin(h), math.sin(dec)*math.sin(lat) + math.cos(dec)*math.cos(lat)*math.cos(h), math.cos(dec)*math.sin(lat)*math.cos(h) - math.sin(dec)*math.cos(lat)}
}

draw_item :: proc(g: ^Gpu, cmd: ^sdl.GPUCommandBuffer, pass: ^sdl.GPURenderPass, it: ^Item, mask: u8) {
	sdl.PushGPUVertexUniformData(cmd, 1, &it.origin, size_of(it.origin))
	binding := sdl.GPUBufferBinding{buffer = it.chunk.buffer}
	sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)
	// Quarters are stored one after another, so neighbouring quarters draw as one run.
	for q := 0; q < 4; {
		if mask & (1 << uint(q)) == 0 {
			q += 1
			continue
		}
		first, count := it.chunk.ranges[q][0], u32(0)
		for ; q < 4 && mask & (1 << uint(q)) != 0; q += 1 do count += it.chunk.ranges[q][1]
		if count > 0 {
			sdl.DrawGPUPrimitives(pass, 4, count, 0, first)
			g.quads_drawn += int(count)
		}
	}
}

// Draw one frame. With `shot` set, also write the frame to that PNG file.
render :: proc(g: ^Gpu, w: ^World, v: View, shot := "") {
	cmd := sdl.AcquireGPUCommandBuffer(g.dev)
	swap: ^sdl.GPUTexture
	sw, sh: u32
	wait_from := sdl.GetPerformanceCounter()
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd, g.window, &swap, &sw, &sh) do swap = nil
	g.waited = f64(sdl.GetPerformanceCounter() - wait_from)/f64(sdl.GetPerformanceFrequency())
	if swap == nil {   // window hidden or minimised
		if shot == "" && !g.unseen {
			_ = sdl.SubmitGPUCommandBuffer(cmd)
			sdl.Delay(16)   // nothing to pace us while hidden
			return
		}
		pw, ph: i32
		sdl.GetWindowSizeInPixels(g.window, &pw, &ph)
		sw, sh = u32(pw), u32(ph)
	}
	resize(g, sw, sh)
	g.quads_drawn, g.plants_drawn = 0, 0
	g.boxes_drawn = min(len(v.boxes), BOX_MAX)
	if g.boxes_drawn > 0 {
		copy((cast([^]Box)sdl.MapGPUTransferBuffer(g.dev, g.box_staging, true))[:g.boxes_drawn], v.boxes[:g.boxes_drawn])
		sdl.UnmapGPUTransferBuffer(g.dev, g.box_staging)
		copy_pass := sdl.BeginGPUCopyPass(cmd)
		sdl.UploadToGPUBuffer(copy_pass, {g.box_staging, 0}, {g.boxes, 0, u32(g.boxes_drawn*size_of(Box))}, true)
		sdl.EndGPUCopyPass(copy_pass)
	}

	// Camera. Positions sent to the GPU are relative to the eye.
	tan_y := math.tan(math.to_radians(f32(FOV))/2)
	tan_x := tan_y*f32(sw)/f32(sh)
	fwd := look_dir(v.yaw, v.pitch)
	right := [3]f32{math.cos(v.yaw), 0, math.sin(v.yaw)}
	up := linalg.cross(right, fwd)
	sun := sun_dir(v.hour, v.day)

	f: Frame
	f.view_proj = {
		right.x/tan_x, right.y/tan_x, right.z/tan_x, 0,
		up.x/tan_y, up.y/tan_y, up.z/tan_y, 0,
		0, 0, 0, NEAR,
		fwd.x, fwd.y, fwd.z, 0,
	}
	f.cascade_r = CASCADE_RADIUS
	f.sun = {sun.x, sun.y, sun.z, v.seconds}
	f.cam = {f32(math.mod(v.eye.x, 65536)), f32(v.eye.y), f32(math.mod(v.eye.z, 65536)), SEA_SURFACE}
	f.cam_r = {right.x*tan_x, right.y*tan_x, right.z*tan_x, 0}
	f.cam_u = {up.x*tan_y, up.y*tan_y, up.z*tan_y, 0}
	f.cam_f = {fwd.x, fwd.y, fwd.z, 0}
	f.screen = {f32(sw), f32(sh), 1 if v.crosshair else 0, 0}
	// The camera in the cloud field, which drifts downwind, and on the land's grid.
	cover, base := weather_at(v.day, v.hour)
	if v.weather.x >= 0 do cover, base = v.weather.x, v.weather.y
	from := math.to_radians(region.shape.swell)
	drift := f64(SKY.wind)*((f64(v.day)*24 + f64(v.hour))*3600 + f64(v.seconds))
	f.cloud = {f32(math.mod(v.eye.x + math.sin(from)*drift, 65536)), f32(math.mod(v.eye.z - math.cos(from)*drift, 65536)), f32(v.eye.x - f64(region.origin.x) + region.size/2), f32(v.eye.z - f64(region.origin.y) + region.size/2)}
	f.weather = {cover, base, SKY.deck, f32(region.size)}
	if v.has_target {
		f.target = {f32(f64(v.target.x) - v.eye.x), f32(f64(v.target.y) - v.eye.y), f32(f64(v.target.z) - v.eye.z), 1}
	}

	// Shadow cascades are boxes centred on the camera, looking along the sunlight. Each
	// centre moves in whole texels so shadow edges hold still while the camera moves. A
	// cascade that is not redrawn this frame is read as it was drawn, sun and all, so a clock
	// that moves the sun costs no extra redraws.
	light := -sun
	l_right := linalg.normalize(linalg.cross(light, [3]f32{0, 1, 0}))
	l_up := linalg.cross(l_right, light)
	along :: proc(p: [3]f64, axis: [3]f32) -> f64 { return p.x*f64(axis.x) + p.y*f64(axis.y) + p.z*f64(axis.z) }
	eye_lit := [3]f64{along(v.eye, l_right), along(v.eye, l_up), along(v.eye, light)}
	radius, interval := CASCADE_RADIUS, CASCADE_INTERVAL
	offset: [4][3]f32
	redraw: [4]bool
	for r, i in radius {
		redraw[i] = g.frame == 0 || g.frame % interval[i] == i % interval[i]
		if redraw[i] {
			texel := f64(2*r/SHADOW_RES)
			o := eye_lit - {math.floor(eye_lit.x/texel)*texel, math.floor(eye_lit.y/texel)*texel, eye_lit.z}
			offset[i] = {f32(o.x), f32(o.y), f32(o.z)}
			d := 4*r   // depth range; casters nearer the sun than this are clamped, not lost
			g.cascade_vp[i] = {
				l_right.x/r, l_right.y/r, l_right.z/r, offset[i].x/r,
				l_up.x/r, l_up.y/r, l_up.z/r, offset[i].y/r,
				light.x/d, light.y/d, light.z/d, offset[i].z/d + 0.5,
				0, 0, 0, 1,
			}
			g.cascade_eye[i] = v.eye
		}
		f.shadow_vp[i] = g.cascade_vp[i]
		moved := v.eye - g.cascade_eye[i]
		for row in 0..<3 do f.shadow_vp[i][row, 3] += f.shadow_vp[i][row, 0]*f32(moved.x) + f.shadow_vp[i][row, 1]*f32(moved.y) + f.shadow_vp[i][row, 2]*f32(moved.z)
	}
	g.frame += 1

	// Everything that could be drawn, with the quarters each chunk should show.
	items := make([dynamic]Item, 0, len(w.chunks), context.temp_allocator)
	lowest := f32(0)   // the lowest ground there is, from the eye: no shadow falls farther
	for key, c in w.chunks {
		if !c.ready || c.buffer == nil do continue
		s := i32(1) << u32(key.level)
		size := f64(CHUNK*s)
		x, z := f32(f64(key.x)*size - v.eye.x), f32(f64(key.z)*size - v.eye.z)
		it := Item{chunk = c, level = key.level, origin = {x, f32(f64(c.y_base) - v.eye.y), z, f32(s)}}
		it.lo = {x, f32(f64(c.y_lo) - v.eye.y), z}
		it.hi = {x + f32(size), f32(f64(c.y_hi) - v.eye.y), z + f32(size)}
		if key.level == 0 {
			it.mask = 1
		} else {
			for q in 0..<4 {
				child := w.chunks[Key{key.level - 1, key.x*2 + i32(q & 1), key.z*2 + i32(q >> 1)}] or_else nil
				if child == nil || !child.ready do it.mask |= 1 << uint(q)
			}
		}
		append(&items, it)
		lowest = min(lowest, it.lo.y)
	}

	// Sun shadows.
	if sun.y > -0.05 {
		min_level := CASCADE_MIN_LEVEL
		// Only what can shade ground in view is drawn: a chunk's box, drawn out down the sunlight as
		// far as its shadow can fall, is tried against the view, widened by what a turn of the head
		// can bring in before the map is next drawn.
		WIDE :: 1.4
		wide := [4][3]f32{fwd*tan_x*WIDE + right, fwd*tan_x*WIDE - right, fwd*tan_y*WIDE + up, fwd*tan_y*WIDE - up}
		for r, i in radius {
			if !redraw[i] do continue
			target := sdl.GPUDepthStencilTargetInfo {
				texture = g.shadow, layer = u8(i), clear_depth = 1, load_op = .CLEAR, store_op = .STORE,
				stencil_load_op = .DONT_CARE, stencil_store_op = .DONT_CARE,
			}
			pass := sdl.BeginGPURenderPass(cmd, nil, 0, &target)
			sdl.BindGPUGraphicsPipeline(pass, g.shadow_pipe)
			sdl.PushGPUVertexUniformData(cmd, 0, &f.shadow_vp[i], size_of(f.shadow_vp[i]))
			casts: for &it in items {
				if it.level < min_level[i] do continue
				centre := (it.lo + it.hi)/2
				reach := r + linalg.length(it.hi - it.lo)/2
				if abs(linalg.dot(centre, l_right) + offset[i].x) > reach || abs(linalg.dot(centre, l_up) + offset[i].y) > reach do continue
				fall := min((it.hi.y - lowest)/max(-light.y, 0.05), 2*r)
				for p in wide {
					far := [3]f32{it.hi.x if p.x > 0 else it.lo.x, it.hi.y if p.y > 0 else it.lo.y, it.hi.z if p.z > 0 else it.lo.z}
					if linalg.dot(p, far) + fall*max(linalg.dot(p, light), 0) < 0 do continue casts
				}
				mask := it.mask
				if it.level == min_level[i] do mask = 1 if it.level == 0 else 0xF
				draw_item(g, cmd, pass, &it, mask)
			}
			sdl.EndGPURenderPass(pass)
		}
	}
	shadow_quads := g.quads_drawn

	// The cloud layer along each line of sight, once for the frame at half size: the sky reads it,
	// and so does whatever is seen through the layer (fs_clouds, shaders.metal).
	lifted := sdl.GPUTextureSamplerBinding{g.lifted, g.linear}
	seen := sdl.GPUTextureSamplerBinding{g.clouds, g.linear}
	sdl.PushGPUFragmentUniformData(cmd, 0, &f, size_of(f))
	to_clouds := sdl.GPUColorTargetInfo{texture = g.clouds, load_op = .DONT_CARE, store_op = .STORE, cycle = true}
	pass := sdl.BeginGPURenderPass(cmd, &to_clouds, 1, nil)
	sdl.BindGPUGraphicsPipeline(pass, g.cloud_pipe)
	sdl.BindGPUFragmentSamplers(pass, 0, &lifted, 1)
	sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
	sdl.EndGPURenderPass(pass)

	// The scene.
	color := sdl.GPUColorTargetInfo {
		texture = g.color, load_op = .DONT_CARE, store_op = .RESOLVE, resolve_texture = g.scene,
		cycle = true, cycle_resolve_texture = true,
	}
	depth := sdl.GPUDepthStencilTargetInfo {
		texture = g.depth, clear_depth = 0, load_op = .CLEAR, store_op = .DONT_CARE,
		stencil_load_op = .DONT_CARE, stencil_store_op = .DONT_CARE, cycle = true,
	}
	pass = sdl.BeginGPURenderPass(cmd, &color, 1, &depth)
	sdl.PushGPUVertexUniformData(cmd, 0, &f, size_of(f))
	sdl.PushGPUFragmentUniformData(cmd, 0, &f, size_of(f))

	sdl.BindGPUGraphicsPipeline(pass, g.terrain)
	terrain_bindings := [4]sdl.GPUTextureSamplerBinding{{g.shadow, g.shadow_sampler}, {g.blocks, g.block_sampler}, lifted, seen}
	sdl.BindGPUFragmentSamplers(pass, 0, &terrain_bindings[0], 4)
	// The view volume as four planes through the eye; a chunk wholly outside one is skipped.
	planes := [4][3]f32{fwd*tan_x + right, fwd*tan_x - right, fwd*tan_y + up, fwd*tan_y - up}
	each: for &it in items {
		for p in planes {
			far := [3]f32{it.hi.x if p.x > 0 else it.lo.x, it.hi.y if p.y > 0 else it.lo.y, it.hi.z if p.z > 0 else it.lo.z}
			if linalg.dot(p, far) < 0 do continue each
		}
		it.seen = true
		draw_item(g, cmd, pass, &it, it.mask)
	}

	// The ground plants in the nearest chunks, two pictures crossed in a strip of ten vertices.
	sdl.BindGPUGraphicsPipeline(pass, g.plant)
	plant_bindings := [4]sdl.GPUTextureSamplerBinding{{g.shadow, g.shadow_sampler}, {g.plant_pics, g.plant_sampler}, lifted, seen}
	sdl.BindGPUFragmentSamplers(pass, 0, &plant_bindings[0], 4)
	PLANT_FAR :: 190   // as in shaders.metal: no plant is drawn farther off
	for &it in items {
		if !it.seen || it.chunk.plant_buf == nil do continue
		if near := linalg.clamp([2]f32{0, 0}, it.lo.xz, it.hi.xz); linalg.length(near) > PLANT_FAR do continue
		sdl.PushGPUVertexUniformData(cmd, 1, &it.origin, size_of(it.origin))
		binding := sdl.GPUBufferBinding{buffer = it.chunk.plant_buf}
		sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)
		sdl.DrawGPUPrimitives(pass, 10, it.chunk.plant_count, 0, 0)
		g.plants_drawn += int(it.chunk.plant_count)
	}

	if g.boxes_drawn > 0 {
		sdl.BindGPUGraphicsPipeline(pass, g.box)
		box_bindings := [3]sdl.GPUTextureSamplerBinding{{g.shadow, g.shadow_sampler}, lifted, seen}
		sdl.BindGPUFragmentSamplers(pass, 0, &box_bindings[0], 3)
		binding := sdl.GPUBufferBinding{buffer = g.boxes}
		sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)
		sdl.DrawGPUPrimitives(pass, 14, u32(g.boxes_drawn), 0, 0)
	}

	sdl.BindGPUGraphicsPipeline(pass, g.sky)
	sdl.BindGPUFragmentSamplers(pass, 0, &seen, 1)
	sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)

	// Water. Near the player it is simulated and drawn chunk by chunk. Beyond that the
	// rivers and the sea are drawn whole, and give way wherever the mask says a chunk has
	// simulated water, so the two never lie over each other.
	water_mask := [3]sdl.GPUTextureSamplerBinding{{w.water.mask, g.linear}, lifted, seen}
	sdl.BindGPUGraphicsPipeline(pass, g.pool)
	sdl.BindGPUFragmentSamplers(pass, 0, &water_mask[0], 3)
	for &it in items {
		if !it.seen || it.chunk.water == nil do continue
		origin := [4]f32{it.origin.x, f32(-v.eye.y), it.origin.z, 1}
		sdl.PushGPUVertexUniformData(cmd, 1, &origin, size_of(origin))
		binding := sdl.GPUBufferBinding{buffer = it.chunk.water}
		sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)
		sdl.DrawGPUPrimitives(pass, 4, it.chunk.water_count, 0, 0)
	}

	if g.ribbon != nil {
		sdl.BindGPUGraphicsPipeline(pass, g.river)
		sdl.BindGPUFragmentSamplers(pass, 0, &water_mask[0], 3)
		from_eye := [4]f32{f32(f64(region.origin.x) - v.eye.x), f32(-v.eye.y), f32(f64(region.origin.y) - v.eye.z), 0}   // the strip is stored relative to the region
		sdl.PushGPUVertexUniformData(cmd, 1, &from_eye, size_of(from_eye))
		binding := sdl.GPUBufferBinding{buffer = g.ribbon}
		sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)
		sdl.DrawGPUPrimitives(pass, g.ribbon_count, 1, 0, 0)
		// Falling water is drawn the same near and far, so the simulated water and the strip
		// both leave the drop to it.
		if g.falls != nil {
			sdl.BindGPUGraphicsPipeline(pass, g.pool)
			sdl.BindGPUFragmentSamplers(pass, 0, &water_mask[0], 3)
			sdl.PushGPUVertexUniformData(cmd, 1, &from_eye, size_of(from_eye))
			binding = {buffer = g.falls}
			sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)
			sdl.DrawGPUPrimitives(pass, 4, g.falls_count, 0, 0)
		}
	}

	sdl.BindGPUGraphicsPipeline(pass, g.water)
	sdl.BindGPUFragmentSamplers(pass, 0, &water_mask[0], 3)
	sdl.DrawGPUPrimitives(pass, 4, 1, 0, 0)
	sdl.EndGPURenderPass(pass)
	g.quads_drawn -= shadow_quads

	if swap != nil {
		to_window := sdl.GPUColorTargetInfo{texture = swap, load_op = .DONT_CARE, store_op = .STORE}
		pass = sdl.BeginGPURenderPass(cmd, &to_window, 1, nil)
		sdl.BindGPUGraphicsPipeline(pass, g.present)
		scene_binding := sdl.GPUTextureSamplerBinding{g.scene, g.linear}
		sdl.BindGPUFragmentSamplers(pass, 0, &scene_binding, 1)
		sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
		sdl.EndGPURenderPass(pass)
	}

	if shot == "" && g.unseen {
		// Wait for the frame to be drawn, then for the next refresh of a 120 Hz display, so a
		// frame that takes too long is late here as it would be on screen.
		wait_from = sdl.GetPerformanceCounter()
		fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
		_ = sdl.WaitForGPUFences(g.dev, true, &fence, 1)
		sdl.ReleaseGPUFence(g.dev, fence)
		refresh := sdl.GetPerformanceFrequency()/120
		for now := sdl.GetPerformanceCounter(); now < g.shown_at + refresh; now = sdl.GetPerformanceCounter() {
			sdl.DelayPrecise((g.shown_at + refresh - now)*1_000_000_000/sdl.GetPerformanceFrequency())
		}
		g.shown_at = sdl.GetPerformanceCounter()
		g.waited += f64(g.shown_at - wait_from)/f64(sdl.GetPerformanceFrequency())
		return
	}
	if shot == "" {
		_ = sdl.SubmitGPUCommandBuffer(cmd)
		return
	}
	staging := sdl.CreateGPUTransferBuffer(g.dev, {usage = .DOWNLOAD, size = sw*sh*4})
	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.DownloadFromGPUTexture(copy_pass, {texture = g.scene, w = sw, h = sh, d = 1}, {transfer_buffer = staging})
	sdl.EndGPUCopyPass(copy_pass)
	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	_ = sdl.WaitForGPUFences(g.dev, true, &fence, 1)
	sdl.ReleaseGPUFence(g.dev, fence)
	pixels := (cast([^]u8)sdl.MapGPUTransferBuffer(g.dev, staging, false))[:sw*sh*4]
	write_png(shot, pixels, int(sw), int(sh), g.format == .B8G8R8A8_UNORM)
	sdl.UnmapGPUTransferBuffer(g.dev, staging)
	sdl.ReleaseGPUTransferBuffer(g.dev, staging)
}

// Write four-byte pixels as an RGB PNG. The image data is stored without compression,
// which keeps this to a page of code at the price of large files.
write_png :: proc(path: string, pixels: []u8, w, h: int, bgr: bool) {
	raw := make([dynamic]u8, 0, h*(w*3 + 1))
	defer delete(raw)
	for y in 0..<h {
		append(&raw, 0)   // no row filter
		for x in 0..<w {
			p := pixels[(y*w + x)*4:]
			append(&raw, p[2] if bgr else p[0], p[1], p[0] if bgr else p[2])
		}
	}
	out := make([dynamic]u8, 0, len(raw) + len(raw)/65535*5 + 128)
	defer delete(out)
	chunk :: proc(out: ^[dynamic]u8, kind: string, data: []u8) {
		be :: proc(out: ^[dynamic]u8, v: u32) {
			b: [4]u8
			endian.put_u32(b[:], .Big, v)
			append(out, ..b[:])
		}
		be(out, u32(len(data)))
		start := len(out)
		append(out, kind)
		append(out, ..data)
		be(out, hash.crc32(out[start:]))
	}
	append(&out, "\x89PNG\r\n\x1a\n")
	header: [13]u8
	endian.put_u32(header[0:], .Big, u32(w))
	endian.put_u32(header[4:], .Big, u32(h))
	header[8], header[9] = 8, 2   // eight bits per channel, RGB
	chunk(&out, "IHDR", header[:])

	stream := make([dynamic]u8, 0, len(raw) + len(raw)/65535*5 + 16)
	defer delete(stream)
	append(&stream, 0x78, 0x01)
	for at := 0; at < len(raw); at += 65535 {
		n := min(65535, len(raw) - at)
		append(&stream, 1 if at + n == len(raw) else 0, u8(n), u8(n >> 8), ~u8(n), ~u8(n >> 8))
		append(&stream, ..raw[at:at + n])
	}
	sum: [4]u8
	endian.put_u32(sum[:], .Big, hash.adler32(raw[:]))
	append(&stream, ..sum[:])
	chunk(&out, "IDAT", stream[:])
	chunk(&out, "IEND", nil)
	if err := os.write_entire_file(path, out[:]); err != nil do fmt.eprintln("could not write", path)
}
