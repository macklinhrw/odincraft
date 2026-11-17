package main

// The game's clock (docs/adr/0008): the seconds of the world's time that have passed since the game
// began. Everything that moves reads it, or the step it has just taken: the water, the birds and
// fish, the clouds' drift, the ripples and the wind in the plants. Paused, the world stands still
// while the camera goes on moving; at a speed, it all runs that many times faster together. The
// date and the hour are not its to move yet: days and seasons that pass are a later step.
// A key or a panel pauses it and sets its speed by writing the two fields.

Clock :: struct {
	seconds: f64,   // of the world's time
	speed:   int,   // which of SPEEDS
	paused:  bool,
}

// The three speeds are RimWorld's (TickManager.TickRateMultiplier: 1, 3 and 6 times). The water
// steps thirty times a second of the world's time and no more than twice a frame (water_update),
// so at sixty frames a second it follows up to four times and at six runs a third behind: a pool
// fills a little slower than the dwarves dig.
SPEEDS :: [3]f64{1, 3, 6}

// Let `dt` seconds of real time pass: the world's time that passed with them.
clock_step :: proc(c: ^Clock, dt: f64) -> (passed: f64) {
	speeds := SPEEDS
	if !c.paused do passed = dt*speeds[c.speed]
	c.seconds += passed
	return
}
