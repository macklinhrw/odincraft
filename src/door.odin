package main

import sdl "vendor:sdl3"

door_first :: proc(opt: ^Options) -> bool { return false }
door_run :: proc(opt: ^Options, g: ^Gpu, window: ^sdl.Window, to: Leave) {}
chart_painter_begin :: proc() {}
chart_painter_end :: proc() {}
