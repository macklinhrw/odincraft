package main

import "core:fmt"
import "core:math"

// The game's clock (docs/adr/0008): the seconds of the world's time that have passed since the game
// began. Everything that moves reads it, or the step it has just taken: the water, the birds and
// fish, the clouds' drift, the ripples and the wind in the plants. Paused, the world stands still
// while the camera goes on moving; at a speed, it all runs that many times faster together.
// A key or a panel pauses it and sets its speed by writing the two fields.
//
// The date and the hour are read from the same seconds (plan.md, P4): a day is DAY of them, the
// year YEAR_DAYS days, and the boat stands off at LANDS_AT on the first day of spring. The dwarves'
// world reads its own ticks by the same rule (date_at), so what the screen says is the day they
// live by.

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

// ---- the day and the year -----------------------------------------------------------------------

// A day is twenty minutes at the clock's own pace, 6:40 at three times and 3:20 at six. RimWorld's
// is 16:40 (60,000 ticks of 60 a second, GenDate.TicksPerDay), Ingnomia's 12 (14,400 ticks of 50 ms)
// and Dwarf Fortress's fortress day 12 s (1,200 ticks at 100 a second). Ours is RimWorld's and a
// fifth, since a dwarf here walks to a stream to drink and over pathless slopes to its work. The
// year is 48 days, four seasons of twelve, which is Ingnomia's; RimWorld's is 60 and takes 16:40
// hours at its own pace where ours takes 16 (colony-sim-reference.md, section 14).
DAY         :: 1200.0   // seconds of the world's time in a day
SEASON_DAYS :: 12
YEAR_DAYS   :: 4*SEASON_DAYS
LANDS_AT    :: 8.0      // the hour the boat stands off, on the first day of spring
NIGHT       :: [2]f32{22, 6}   // the hours a dwarf sleeps for choice: RimWorld's default timetable sleeps from 22 to 6 (Pawn_TimetableTracker)
SPRING      :: 80.0     // the day of the sun's year spring begins on: the March equinox, 0 on 1 January
SEASONS     := [4]string{"spring", "summer", "autumn", "winter"}

Date :: struct {
	day:    int,   // days since the one the boat landed on, which is 0
	hour:   f32,   // 0 to 24, by the sun
	year:   int,   // years since the landing's
	season: int,   // which of SEASONS
	nth:    int,   // the day of the season, from 1
	sun:    f32,   // the day of the sun's year it stands for, 0 on 1 January: where the sun rides, and what grows and swims
}

// The date so many seconds of the world's time after the boat stood off.
date_at :: proc(seconds: f64) -> (d: Date) {
	t := seconds/DAY + LANDS_AT/24
	whole := math.floor(t)
	d.day, d.hour = int(whole), f32((t - whole)*24)
	of_year := d.day%%YEAR_DAYS
	d.year, d.season, d.nth = d.day/YEAR_DAYS, of_year/SEASON_DAYS, of_year%SEASON_DAYS + 1
	d.sun = f32(math.mod(SPRING + (f64(of_year) + (t - whole))*365/YEAR_DAYS, 365))
	return
}

date_tick :: proc(tick: int) -> Date { return date_at(f64(tick)*TICK) }

// Whether dwarves sleep for choice at an hour.
night :: proc(hour: f32) -> bool { return hour >= NIGHT[0] || hour < NIGHT[1] }

// A count as its place in a row: 1st, 2nd, 3rd, 11th.
nth_words :: proc(n: int) -> string {
	ending := "th" if n%100 >= 11 && n%100 <= 13 else "st" if n%10 == 1 else "nd" if n%10 == 2 else "rd" if n%10 == 3 else "th"
	return fmt.tprintf("%d%s", n, ending)
}

// The date in words: "3rd of spring", and from the second year on which year it is.
date_words :: proc(d: Date) -> string {
	if d.year == 0 do return fmt.tprintf("%s of %s", nth_words(d.nth), SEASONS[d.season])
	return fmt.tprintf("%s of %s, year %d", nth_words(d.nth), SEASONS[d.season], d.year + 1)
}

// The part of the day an hour falls in, for a line that says when.
hour_words :: proc(hour: f32) -> string {
	return "night" if hour < 5 else "dawn" if hour < 7 else "morning" if hour < 11.5 else "noon" if hour < 13 else "afternoon" if hour < 17.5 else "evening" if hour < 22 else "night"
}
