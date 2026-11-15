package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Command-line options. The game is played with none; the rest put the camera somewhere, take a
// picture or measure frame times without a window, or run one of the offline tools that print or
// draw what the generator made and exit (map, archipelago, why, survey, plates, plates-why).
//
// Options, each as --name=value
//   pos=x,y,z  above=x,height,z (over the ground)  look=yaw,pitch (degrees)  hour=0..24  fly  size=WxH
//   day=N           day of the year, 0 on 1 January (default: the first fair day from 80, the March
//                   equinox, on): sets the sun's path
//   weather=c[,b]   force the cloud cover, 0 clear to 1 overcast, and the cloud base in metres (default
//                   1000, too high for a cap); otherwise both are drawn from the seed, the day and the hour
//   shot=file.png   wait for the world to load, save one frame and exit
//   after=seconds   with shot: let this much time pass first, so water can move; with bench as
//                   well, the frame is saved then without waiting, in mid-flight. A picture's birds and
//                   fish are posed this many seconds into the hour, so two runs show the same ones
//   dig=x0,y0,z0,x1,y1,z1   once the world has loaded, clear this box of blocks; may be repeated
//   probe=x0,z0,x1,z1       on exit, print the ground and water in these columns
//   seed=N          which world: every random choice is keyed from it (default 7)
//   island=N        which island near the start the start, map, why, survey and place act on (default 0,
//                   the start island at the origin); it says all its start-up lines
//   near=km         the islands within this many km of that one are formed beside it before entering (default 64);
//                   the rest form in the background, nearest first, and the world waits for each
//   kind=name       which kind of island that one is, whatever the seed would pick (names in KINDS, land.odin)
//   origin=x,z      where island 0's middle lies in the world, in whole metres (default 0,0); the
//                   islands near it and the stand-in's plates move with it
//   map=file.png    save a map of the island's land and exit
//   archipelago=file.png   form every island near the start side by side, save a map of them and the
//                   continent they lie off, and exit
//   overlay=name    with map: paint one field over the relief (names in FIELDS, fields.odin)
//   why=x,z         print what the ground is at this point in the world and why, and exit
//   survey          print what the island holds and the ranked candidates for named places, and exit
//   plates=dir      run the world's history of moving plates, write its frames through time, the known
//                   world's map and the comparison grids into dir, say what it made, and exit (plates.odin)
//   plates-why=x,z  print what happened through that history at this point in the world (as for why), and exit
//   place=N         look at named place N (from 1, as start-up lists them) from 1 to 2 km off, flying
//   bench=seconds   travel straight ahead and report frame times: flying at `speed` m/s
//                   with fly, otherwise running on the ground
//   show            with shot or bench: open the window. Without it they draw unseen and take no focus

Options :: struct {
	pos:           [3]f64,
	has_pos:       bool,
	has_look:      bool,
	yaw, pitch:    f32,
	hour, day:     f32,
	has_day:       bool,
	weather:       [2]f32,
	fly, show:     bool,
	width, height: i32,
	shot:          string,
	after:         f64,
	digs:          [dynamic][6]i32,
	probe:         [4]i32,
	has_probe:     bool,
	map_path:      string,
	archipelago:   string,
	overlay:       string,
	above:         bool,
	bench, speed:  f64,
	kind:          string,
	why:           [2]f64,
	has_why:       bool,
	survey:        bool,
	place:         int,
	island:        int,
	near:          f64,
	origin:        [2]i32,
	plates:        string,
	plates_why:    [2]f64,
	has_plates_why: bool,
}

options :: proc() -> Options {
	o := Options{hour = 9.5, day = 80, weather = {-1, -1}, width = 1280, height = 720, speed = 60, near = 64}
	numbers :: proc(s, sep: string, out: []f64) -> bool {
		parts := strings.split(s, sep, context.temp_allocator)
		if len(parts) != len(out) do return false
		for p, i in parts do out[i] = strconv.parse_f64(p) or_return
		return true
	}
	for arg in os.args[1:] {
		name, _, value := strings.partition(strings.trim_prefix(arg, "--"), "=")
		ok := true
		v: [3]f64
		switch name {
		case "pos":   ok = numbers(value, ",", v[:]); o.pos, o.has_pos = v, true
		case "above": ok = numbers(value, ",", v[:]); o.pos, o.has_pos, o.above = v, true, true   // the ground is added once the land is formed
		case "seed":  ok = numbers(value, ",", v[:1]); world_seed = u32(v.x)
		case "overlay": o.overlay = value
		case "kind":  o.kind = value
		case "origin": ok = numbers(value, ",", v[:2]); o.origin = {i32(v.x), i32(v.y)}
		case "island": ok = numbers(value, ",", v[:1]); o.island = int(v.x)
		case "near":  ok = numbers(value, ",", v[:1]); o.near = v.x
		case "look":  ok = numbers(value, ",", v[:2]); o.yaw, o.pitch, o.has_look = f32(v.x), f32(v.y), true
		case "size":  ok = numbers(value, "x", v[:2]); o.width, o.height = i32(v.x), i32(v.y)
		case "hour":  ok = numbers(value, ",", v[:1]); o.hour = f32(v.x)
		case "day":   ok = numbers(value, ",", v[:1]); o.day, o.has_day = f32(v.x), true
		case "weather":
			ok = numbers(value, ",", v[:2]) || numbers(value, ",", v[:1])
			o.weather = {f32(v.x), f32(v.y) if strings.contains(value, ",") else SKY.base[1]}
		case "bench": ok = numbers(value, ",", v[:1]); o.bench = v.x
		case "speed": ok = numbers(value, ",", v[:1]); o.speed = v.x
		case "shot":  o.shot = value
		case "after": ok = numbers(value, ",", v[:1]); o.after = v.x
		case "probe":
			box: [4]f64
			ok = numbers(value, ",", box[:])
			o.probe, o.has_probe = {i32(box[0]), i32(box[1]), i32(box[2]), i32(box[3])}, true
		case "dig":
			box: [6]f64
			ok = numbers(value, ",", box[:])
			append(&o.digs, [6]i32{i32(box[0]), i32(box[1]), i32(box[2]), i32(box[3]), i32(box[4]), i32(box[5])})
		case "map":   o.map_path = value
		case "archipelago": o.archipelago = value
		case "plates": o.plates = value
		case "plates-why": ok = numbers(value, ",", o.plates_why[:]); o.has_plates_why = true
		case "why":   ok = numbers(value, ",", o.why[:]); o.has_why = true
		case "fly":   o.fly = true
		case "survey": o.survey = true
		case "place": ok = numbers(value, ",", v[:1]); o.place = int(v.x)
		case "show":  o.show = true
		case:         ok = false
		}
		if !ok {
			fmt.eprintln("bad option:", arg)
			os.exit(2)
		}
	}
	return o
}
