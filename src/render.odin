package main

import "core:encoding/endian"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"

// Drawing. A frame is: four sun shadow maps, then sky, terrain and water into a 4x
// multisampled target that resolves to the scene texture, then the scene to the window.
// Lighting, fog and tone mapping live in shaders.metal.

SHADERS    :: #load("shaders.metal", string)
SHADOW_RES :: 2048
FOV        :: 70.0   // vertical, degrees
NEAR       :: 0.1

// Shadow cascades: how far each reaches from the camera, the finest level of detail drawn
// into it, and how many frames pass between redraws. A far cascade cannot resolve single
// blocks, so it does not draw them, and it covers so much ground that the camera barely
// moves across it in a few frames.
CASCADE_RADIUS    :: [4]f32{64, 256, 1024, 4096}
CASCADE_MIN_LEVEL :: [4]i32{0, 0, 1, 3}
CASCADE_INTERVAL  :: [4]int{1, 1, 2, 4}

Gpu :: struct {
	dev:            ^sdl.GPUDevice,
	window:         ^sdl.Window,
	format:         sdl.GPUTextureFormat,
	source:         cstring,
	w, h:           u32,
	color, depth:   ^sdl.GPUTexture,   // multisampled
	scene:          ^sdl.GPUTexture,   // resolved frame
	shadow:         ^sdl.GPUTexture,   // one layer per cascade
	shadow_sampler: ^sdl.GPUSampler,
	linear:         ^sdl.GPUSampler,
	terrain, shadow_pipe, sky, water, river, pool, present: ^sdl.GPUGraphicsPipeline,
	ribbon:         ^sdl.GPUBuffer,    // the rivers' water surface
	ribbon_count:   u32,
	quads_drawn:    int,
	frame:          int,
	cascade_at:     [4][3]f64,   // where each shadow map was last drawn, in the sun's frame
	cascade_sun:    [3]f32,      // and the sun direction then
	waited:         f64,   // seconds the last frame spent waiting for the display
}

// What to draw.
View :: struct {
	eye:        [3]f64,
	yaw, pitch: f32,
	hour:       f32,    // time of day, 0..24
	seconds:    f32,
	target:     [3]i32, // block being aimed at
	has_target: bool,
	crosshair:  bool,
}

// Mirrors `Frame` in shaders.metal.
Frame :: struct {
	view_proj: matrix[4, 4]f32,
	shadow_vp: [4]matrix[4, 4]f32,
	cascade_r, sun, cam, target, cam_r, cam_u, cam_f, screen: [4]f32,
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
	cull:                                 sdl.GPUCullMode,
	color:                                sdl.GPUTextureFormat,   // .INVALID for depth only
	samples:                              sdl.GPUSampleCount,
	depth, depth_write:                   bool,
	compare:                              sdl.GPUCompareOp,       // .INVALID for no depth test
	blend, clamp_depth:                   bool,
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
		multisample_state = {sample_count = p.samples},
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
	pipe := sdl.CreateGPUGraphicsPipeline(g.dev, info)
	if pipe == nil do fatal(string(p.vs))
	return pipe
}

gpu_init :: proc(g: ^Gpu, window: ^sdl.Window) {
	g.window = window
	g.dev = sdl.CreateGPUDevice({.MSL}, false, nil)
	if g.dev == nil || !sdl.ClaimWindowForGPUDevice(g.dev, window) do fatal("GPU device")
	_ = sdl.SetGPUSwapchainParameters(g.dev, window, .SDR, .VSYNC)
	g.format = sdl.GetGPUSwapchainTextureFormat(g.dev, window)
	colours := strings.builder_make(context.temp_allocator)
	for m in MATERIALS do fmt.sbprintf(&colours, "float3(%f, %f, %f), ", m.colour.r, m.colour.g, m.colour.b)
	source, _ := strings.replace_all(SHADERS, "MATERIAL_COLOURS", strings.to_string(colours), context.temp_allocator)
	g.source = strings.clone_to_cstring(source)

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

	// Depth runs from 1 at the near plane to 0 at infinity, which keeps precision at long range.
	g.terrain = make_pipeline(g, {
		vs = "vs_terrain", fs = "fs_terrain", vs_uniforms = 2, fs_uniforms = 1, fs_samplers = 1, quads = true,
		cull = .BACK, color = g.format, samples = ._4, depth = true, depth_write = true, compare = .GREATER,
	})
	g.shadow_pipe = make_pipeline(g, {
		vs = "vs_shadow", fs = "fs_shadow", vs_uniforms = 2, quads = true,
		cull = .BACK, depth = true, depth_write = true, compare = .LESS, clamp_depth = true,
	})
	g.sky = make_pipeline(g, {vs = "vs_screen", fs = "fs_sky", fs_uniforms = 1, color = g.format, samples = ._4, depth = true})
	g.water = make_pipeline(g, {
		vs = "vs_water", fs = "fs_water", vs_uniforms = 1, fs_uniforms = 1, fs_samplers = 1,
		color = g.format, samples = ._4, depth = true, compare = .GREATER, blend = true,
	})
	// Simulated water writes depth, so a sheet of falling water is not seen through the pool in front of it.
	g.pool = make_pipeline(g, {
		vs = "vs_pool", fs = "fs_water", vs_uniforms = 2, fs_uniforms = 1, fs_samplers = 1, pool = true,
		color = g.format, samples = ._4, depth = true, depth_write = true, compare = .GREATER, blend = true,
	})
	g.present = make_pipeline(g, {vs = "vs_screen", fs = "fs_present", fs_uniforms = 1, fs_samplers = 1, color = g.format})
	// River water writes depth, so where two reaches meet the water is drawn once.
	g.river = make_pipeline(g, {
		vs = "vs_river", fs = "fs_water", vs_uniforms = 2, fs_uniforms = 1, fs_samplers = 1, ribbon = true,
		color = g.format, samples = ._4, depth = true, depth_write = true, compare = .GREATER, blend = true,
	})

	if bytes := u32(len(rivers.ribbon)*size_of([4]f32)); bytes > 0 {
		g.ribbon_count = u32(len(rivers.ribbon))
		g.ribbon = sdl.CreateGPUBuffer(g.dev, {usage = {.VERTEX}, size = bytes})
		staging := sdl.CreateGPUTransferBuffer(g.dev, {usage = .UPLOAD, size = bytes})
		copy((cast([^]u8)sdl.MapGPUTransferBuffer(g.dev, staging, false))[:bytes], (cast([^]u8)raw_data(rivers.ribbon))[:bytes])
		sdl.UnmapGPUTransferBuffer(g.dev, staging)
		cmd := sdl.AcquireGPUCommandBuffer(g.dev)
		pass := sdl.BeginGPUCopyPass(cmd)
		sdl.UploadToGPUBuffer(pass, {staging, 0}, {g.ribbon, 0, bytes}, false)
		sdl.EndGPUCopyPass(pass)
		_ = sdl.SubmitGPUCommandBuffer(cmd)
		sdl.ReleaseGPUTransferBuffer(g.dev, staging)
	}
}

resize :: proc(g: ^Gpu, w, h: u32) {
	if w == g.w && h == g.h do return
	for t in ([3]^sdl.GPUTexture{g.color, g.depth, g.scene}) do if t != nil do sdl.ReleaseGPUTexture(g.dev, t)
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
}

// The sun rises in the east (+X) and stands 60 degrees high at noon.
sun_dir :: proc(hour: f32) -> [3]f32 {
	a := (hour - 6)/12*math.PI
	return {math.cos(a), math.sin(a)*0.866, math.sin(a)*0.5}
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
		if shot == "" {
			_ = sdl.SubmitGPUCommandBuffer(cmd)
			sdl.Delay(16)   // nothing to pace us while hidden
			return
		}
		pw, ph: i32
		sdl.GetWindowSizeInPixels(g.window, &pw, &ph)
		sw, sh = u32(pw), u32(ph)
	}
	resize(g, sw, sh)
	g.quads_drawn = 0

	// Camera. Positions sent to the GPU are relative to the eye.
	tan_y := math.tan(math.to_radians(f32(FOV))/2)
	tan_x := tan_y*f32(sw)/f32(sh)
	fwd := look_dir(v.yaw, v.pitch)
	right := [3]f32{math.cos(v.yaw), 0, math.sin(v.yaw)}
	up := linalg.cross(right, fwd)
	sun := sun_dir(v.hour)

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
	if v.has_target {
		f.target = {f32(f64(v.target.x) - v.eye.x), f32(f64(v.target.y) - v.eye.y), f32(f64(v.target.z) - v.eye.z), 1}
	}

	// Shadow cascades are boxes centred on the camera, looking along the sunlight. Each
	// centre moves in whole texels so shadow edges hold still while the camera moves. A
	// cascade that is not redrawn this frame keeps its old centre.
	light := -sun
	l_right := linalg.normalize(linalg.cross(light, [3]f32{0, 1, 0}))
	l_up := linalg.cross(l_right, light)
	along :: proc(p: [3]f64, axis: [3]f32) -> f64 { return p.x*f64(axis.x) + p.y*f64(axis.y) + p.z*f64(axis.z) }
	eye_lit := [3]f64{along(v.eye, l_right), along(v.eye, l_up), along(v.eye, light)}
	radius, interval := CASCADE_RADIUS, CASCADE_INTERVAL
	offset: [4][3]f32
	redraw: [4]bool
	for r, i in radius {
		redraw[i] = sun != g.cascade_sun || g.frame % interval[i] == i % interval[i]
		if redraw[i] {
			texel := f64(2*r/SHADOW_RES)
			g.cascade_at[i] = {math.floor(eye_lit.x/texel)*texel, math.floor(eye_lit.y/texel)*texel, eye_lit.z}
		}
		o := eye_lit - g.cascade_at[i]
		offset[i] = {f32(o.x), f32(o.y), f32(o.z)}
		d := 4*r   // depth range; casters nearer the sun than this are clamped, not lost
		f.shadow_vp[i] = {
			l_right.x/r, l_right.y/r, l_right.z/r, offset[i].x/r,
			l_up.x/r, l_up.y/r, l_up.z/r, offset[i].y/r,
			light.x/d, light.y/d, light.z/d, offset[i].z/d + 0.5,
			0, 0, 0, 1,
		}
	}
	g.cascade_sun = sun
	g.frame += 1

	// Everything that could be drawn, with the quarters each chunk should show.
	items := make([dynamic]Item, 0, len(w.chunks), context.temp_allocator)
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
	}

	// Sun shadows.
	if sun.y > -0.05 {
		min_level := CASCADE_MIN_LEVEL
		for r, i in radius {
			if !redraw[i] do continue
			target := sdl.GPUDepthStencilTargetInfo {
				texture = g.shadow, layer = u8(i), clear_depth = 1, load_op = .CLEAR, store_op = .STORE,
				stencil_load_op = .DONT_CARE, stencil_store_op = .DONT_CARE,
			}
			pass := sdl.BeginGPURenderPass(cmd, nil, 0, &target)
			sdl.BindGPUGraphicsPipeline(pass, g.shadow_pipe)
			sdl.PushGPUVertexUniformData(cmd, 0, &f.shadow_vp[i], size_of(f.shadow_vp[i]))
			for &it in items {
				if it.level < min_level[i] do continue
				centre := (it.lo + it.hi)/2
				reach := r + linalg.length(it.hi - it.lo)/2
				if abs(linalg.dot(centre, l_right) + offset[i].x) > reach || abs(linalg.dot(centre, l_up) + offset[i].y) > reach do continue
				mask := it.mask
				if it.level == min_level[i] do mask = 1 if it.level == 0 else 0xF
				draw_item(g, cmd, pass, &it, mask)
			}
			sdl.EndGPURenderPass(pass)
		}
	}
	shadow_quads := g.quads_drawn

	// The scene.
	color := sdl.GPUColorTargetInfo {
		texture = g.color, load_op = .DONT_CARE, store_op = .RESOLVE, resolve_texture = g.scene,
		cycle = true, cycle_resolve_texture = true,
	}
	depth := sdl.GPUDepthStencilTargetInfo {
		texture = g.depth, clear_depth = 0, load_op = .CLEAR, store_op = .DONT_CARE,
		stencil_load_op = .DONT_CARE, stencil_store_op = .DONT_CARE, cycle = true,
	}
	pass := sdl.BeginGPURenderPass(cmd, &color, 1, &depth)
	sdl.PushGPUVertexUniformData(cmd, 0, &f, size_of(f))
	sdl.PushGPUFragmentUniformData(cmd, 0, &f, size_of(f))

	sdl.BindGPUGraphicsPipeline(pass, g.sky)
	sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)

	sdl.BindGPUGraphicsPipeline(pass, g.terrain)
	shadow_binding := sdl.GPUTextureSamplerBinding{g.shadow, g.shadow_sampler}
	sdl.BindGPUFragmentSamplers(pass, 0, &shadow_binding, 1)
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

	// Water. Near the player it is simulated and drawn chunk by chunk. Beyond that the
	// rivers and the sea are drawn whole, and give way wherever the mask says a chunk has
	// simulated water, so the two never lie over each other.
	water_mask := sdl.GPUTextureSamplerBinding{w.water.mask, g.linear}
	sdl.BindGPUGraphicsPipeline(pass, g.pool)
	sdl.BindGPUFragmentSamplers(pass, 0, &water_mask, 1)
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
		sdl.BindGPUFragmentSamplers(pass, 0, &water_mask, 1)
		from_eye := [4]f32{f32(-v.eye.x), f32(-v.eye.y), f32(-v.eye.z), 0}
		sdl.PushGPUVertexUniformData(cmd, 1, &from_eye, size_of(from_eye))
		binding := sdl.GPUBufferBinding{buffer = g.ribbon}
		sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)
		sdl.DrawGPUPrimitives(pass, g.ribbon_count, 1, 0, 0)
	}

	sdl.BindGPUGraphicsPipeline(pass, g.water)
	sdl.BindGPUFragmentSamplers(pass, 0, &water_mask, 1)
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
