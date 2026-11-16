# One clock for everything that moves

The world's time is one count of seconds (`Clock`, `clock.odin`), stepped each frame by the real time that passed times the speed, or not at all while paused. Everything that moves reads it or the step it has just taken: the water steps by it, the birds and fish are posed from it, the clouds drift by it, and the ripples and the wind in the plants are drawn from it. The camera, the pointer and the level of the cut move in real time, so a paused world can be looked over and given orders. We chose this over letting each system keep its own time, which is what the first build did with the seconds since the program began: nothing could then be paused or hurried together.

## Consequences

- **A new thing that moves takes the world's time, never the wall clock.** The dwarves' world (`plan.md`, section 6) steps by the same count, on its own thread, and the same seed and orders must give the same events at any speed.
- **The speeds are 1, 2 and 4.** The water steps thirty times a second of the world's time and at most twice a frame, so four times is as fast as it can follow at sixty frames a second. A faster speed needs a water step that can be skipped or shared out.
- **The date and the hour are not the clock's yet.** A picture's day and hour are set by options and keys, so two pictures can be compared. Days and seasons that pass (P4) will move them from this clock.
- **A picture's animals are posed from `--after`, not from the clock**, as before, so two runs show the same ones.
- A key or a panel pauses the world and sets its speed by writing the clock's two fields.
