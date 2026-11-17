package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Command-line options. The game is played with none; the rest put the camera somewhere, take a
// picture or measure frame times without a window, or run one of the offline tools that print or
// draw what the generator made and exit (map, archipelago, why, survey, plates, plates-why).
//
// The game begins in the view from above (above.odin), over the start. Any of pos, above, look,
// fly, place and first begins it in first person instead, and so does bench without over.
//
// Options, each as --name=value
//   over=x,z        the view from above, over this point of the world
//   span=metres     how much ground lies across its picture (default 160: a hold's ground)
//   tilt=degrees    how far it looks down, from 35 to 90, straight down (default 50)
//   turn=degrees    which way the picture's top faces: 0 north, 90 east (default: downstream at the start)
//   cut=level       cut the world at this height over the sea, so nothing from there up is drawn;
//                   cut=ground keeps the cut over the ground under the view's middle
//   bare            leaves are not drawn
//   cursor=x,y      where the pointer is in the picture, in pixels from its top left: the block under
//                   it is marked and said, and with why its ground explained; cursor=x,y,x,y marks the
//                   box of blocks between two points
//   why             with cursor: print what the block under the pointer is and why its ground is so
//   pace=N          how fast the world's clock runs: 0 paused, or 1, 2 or 4 times (default 1)
//   first           first person, at the start
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
//   kind=name       which kind of island that one is, whatever the history would make (names in KINDS,
//                   land.odin); the start island of that kind is put where its host holds best
//   origin=x,z      where island 0's middle lies in the world, in whole metres (default 0,0); the
//                   islands near it and the stand-in's plates move with it
//   map=file.png    save a map of the island's land and exit
//   archipelago=file.png   form every island near the start side by side, save a map of them and the
//                   continent they lie off, and exit
//   known=file.png  save a map of the known world as its regional history of the plates left it, and exit
//   overlay=name    with map: paint one field over the relief (names in FIELDS, fields.odin)
//   why=x,z         print what the ground is at this point in the world and why, and exit
//   survey          print what the island holds and the ranked candidates for named places, and exit
//   plates=dir      run the world's history of moving plates, write its frames through time, the known
//                   world's map and the comparison grids into dir, say what it made, and exit (plates.odin)
//   plates-why=x,z  print what happened through that history at this point in the world (as for why), and exit
//   place=N         look at named place N (from 1, as start-up lists them) from 1 to 2 km off, flying
//   site=x,z        an expedition site: the landmass's pieces within `near` km of this point in the world are
//                   formed before entering, as the start's are, and the camera is put 60 m over it
//   continent=0     leave the land larger than a region a record, as before step 21, even where it can be formed
//   bench=seconds   travel straight ahead and report frame times: flying at `speed` m/s
//                   with fly, otherwise running on the ground; with over, the view from above
//                   panned toward its picture's top at `speed` m/s
//   show            with shot or bench: open the window. Without it they draw unseen and take no focus
//   dwarves=seconds run the dwarves' world this long with no window and print what happened (hold.odin); alone, exit
//                   then; with shot or why, the picture or the answer is of that moment; with bench, it runs on from there
//   orders=file     the orders the dwarves' world obeys, each with its time (hold.odin)
//   party=N         how many dwarves the boat brings (default 7), to measure what a larger hold costs
//   send            with cursor, from above: send the dwarves to the block under the pointer, as a right click does
//
// The interface (play.odin) is drawn over every picture. These put it in a state, for a picture or --say:
//   plain           draw no interface: the world alone
//   scale=percent   its size, from 75 to 200 in steps of 25 (default: by the picture's height, 100 at 1,440 pixels)
//   select=x,y      as if that pixel of the picture had been clicked: the thing under it is in the hand
//   tab=name        with select: the card's depth shown (rock, ground, plants, near, world, or the thing's own)
//   list=name       that list open (dwarves, places); row=N chooses the Places list's Nth named place, which takes the view there
//   group=name      how the Dwarves list is grouped (need, trade, place), or kept for only those kept in view
//   find=words      what has been typed in the list's field
//   who=N[,N]       those dwarves in the hand, numbered from 1 as start-up lists them: one, or several as a group
//   keep=N[,N]      those dwarves kept in view at the top, beside the first boat's
//   lens=name       a lens on: leaves, or a field (rock, water-table, rain, livable, plants, soil); lenses opens their choices
//   drag            the cut's mark as it is while the pointer drags it (with cut=level)
//   menu            the menu open
//   lessons         the one-line lessons shown, as to someone who has learned none
//   tell=words      a message; alert=words an alert (begin it with ? for a caution)
//   say             with shot: print what the screen says, area by area

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
	known:         string,
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
	site:          [2]f64,
	has_site:      bool,
	continent:     bool,
	over:          [2]f64,
	has_over:      bool,
	span, tilt:    f64,
	turn:          f32,
	has_turn:      bool,
	cut:           f64,
	has_cut:       bool,
	cut_ground:    bool,
	bare, first:   bool,
	cursor:        [4]f64,
	has_cursor:    bool,
	cursor_box:    bool,
	why_cursor:    bool,
	pace:          int,
	dwarves:       f64,
	orders:        string,
	party:         int,
	send:          bool,
	plain, lenses, menu, lessons, say, drag: bool,
	scale, row:    int,
	select:        [2]f64,
	has_select:    bool,
	tab, list, lens, tell, alert, group, find: string,
	who, keep:     [dynamic]int,
	}

options :: proc() -> Options {
	o := Options{hour = 9.5, day = 80, weather = {-1, -1}, width = 1280, height = 720, speed = 60, near = 64, span = 160, tilt = 50, pace = 1, party = LANDING, continent = true}
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
		case "known": o.known = value
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
		case "why":
			if value == "" do o.why_cursor = true
			else do ok, o.has_why = numbers(value, ",", o.why[:]), true
		case "over":  ok = numbers(value, ",", o.over[:]); o.has_over = true
		case "span":  ok = numbers(value, ",", v[:1]); o.span = v.x
		case "tilt":  ok = numbers(value, ",", v[:1]); o.tilt = v.x
		case "turn":  ok = numbers(value, ",", v[:1]); o.turn, o.has_turn = f32(v.x), true
		case "cut":
			if value == "ground" do o.cut_ground = true
			else {
				ok = numbers(value, ",", v[:1])
				o.cut, o.has_cut = v.x, true
			}
		case "bare":  o.bare = true
		case "first": o.first = true
		case "pace":
			ok = numbers(value, ",", v[:1]) && (v.x == 0 || v.x == 1 || v.x == 2 || v.x == 4)
			o.pace = int(v.x)
		case "cursor":
			o.has_cursor, o.cursor_box = true, numbers(value, ",", o.cursor[:])
			ok = o.cursor_box || numbers(value, ",", o.cursor[:2])
		case "fly":   o.fly = true
		case "survey": o.survey = true
		case "place": ok = numbers(value, ",", v[:1]); o.place = int(v.x)
		case "show":  o.show = true
		case "site":  ok = numbers(value, ",", o.site[:]); o.has_site = true
		case "continent": ok = numbers(value, ",", v[:1]); o.continent = v.x != 0
		case "dwarves": ok = numbers(value, ",", v[:1]); o.dwarves = v.x
		case "orders": o.orders = value
		case "send":  o.send = true
		case "party": ok = numbers(value, ",", v[:1]) && v.x >= 1; o.party = int(v.x)
		case "plain": o.plain = true
		case "lenses": o.lenses = true
		case "menu":  o.menu = true
		case "lessons": o.lessons = true
		case "say":   o.say = true
		case "drag":  o.drag = true
		case "scale":
			ok = numbers(value, ",", v[:1]) && v.x >= 75 && v.x <= 200 && int(v.x)%25 == 0
			o.scale = int(v.x)/25
		case "row":   ok = numbers(value, ",", v[:1]); o.row = int(v.x)
		case "select": ok = numbers(value, ",", o.select[:]); o.has_select = true
		case "tab":   o.tab = value
		case "list":  o.list, ok = value, value == "places" || value == "dwarves"
		case "group": o.group, ok = value, value == "need" || value == "trade" || value == "place" || value == "kept"
		case "find":  o.find = value
		case "who", "keep":
			for n in strings.split(value, ",", context.temp_allocator) {
				k, good := strconv.parse_int(n)
				ok &&= good && k >= 1
				append(&o.who if name == "who" else &o.keep, k)
			}
		case "lens":  o.lens = value
		case "tell":  o.tell = value
		case "alert": o.alert = value
		case:         ok = false
		}
		if !ok {
			fmt.eprintln("bad option:", arg)
			os.exit(2)
		}
	}
	return o
}
