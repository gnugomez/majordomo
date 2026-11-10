# Scroll performance harness

Small tools for measuring how the main window scrolls, used to profile
the board. Build each Swift file with `swiftc -O -o <name> <name>.swift`
(from any directory; they are standalone). The terminal running them
needs Accessibility and Screen Recording permission.

- `winfo <pid>`: the process's on-screen windows, with ids and frames.
- `front <x> <y>`: the windows under a screen point, front to back —
  check that the target is first before posting wheel events there.
- `axwin <pid> <x> <y> <w> <h>`: moves and resizes the first window.
- `hidscroll <x> <y> v|h <seconds> [px] [hz]`: posts trackpad-style wheel
  events at a point, reversing every second. Takes the pointer there.
- `axscroll <pid> v|h <seconds> [hz] [span]`: sweeps the board's scroll
  bar through Accessibility instead; no pointer, but every step runs
  synchronously on the app's main thread, so it is not a frame-rate test.
- `fpscount <windowID> <seconds>`: per second, how many display
  refreshes carried new content for the window — its achieved rate.
- `monitor.sh <seconds> <pid>`: per second, WindowServer CPU, the app's
  CPU, and GPU utilization.

A run: launch a scaled demo (`MAJORDOMO_DEMO=1 MAJORDOMO_OPEN_MAIN=1
MAJORDOMO_DEMO_SCALE=30 .build/release/Majordomo`), move its window
clear of other windows with `axwin`, confirm with `front`, then start
`fpscount` and `monitor.sh` in the background, run `hidscroll`, and
`sample <pid> 5` meanwhile for the main thread's call tree.
- `hidkeys <pid> <keycode> <count> [ms]`: brings the process to the front
  through Accessibility, posts key presses only while it stays there, then
  puts the previous app back. Arrows: left 123, right 124, down 125, up 126.
- `hidclick <x> <y>`: moves the pointer to a screen point and clicks.
- `run.sh <tag> <board-id>`: the whole scroll measurement on a scaled demo
  of one board (`starter-reviews` has no lanes, `starter-my-work` has
  them): launch, park, count updates, monitor, wheel for 7 s, sample the
  main thread, quit. Writes `fps-<tag>.txt`, `mon-<tag>.txt`, `s-<tag>.txt`.
- `check.sh <tag>`: launches the Reviews demo, wheels a column to its foot
  and screenshots it, then walks the arrows down the long column and back
  up, screenshotting where the selection ends — the lazy slots' check.

Both scripts expect the tools built beside them and the release binary at
`.build/release/Majordomo`; they set the `Majordomo` defaults domain's
`sidebarBoard`, so export it first (`defaults export Majordomo backup.plist`)
and import it back after.
- `pane.sh <tag>`: launches the Reviews demo with the preview placed under
  the board, selects a card, opens the preview with Space, and screenshots
  the window in a burst through the pane's slide — for checking that the
  scrollers ride the pane's edge rather than jump ahead of it. Sets
  `boardPreviewPlacement` in the defaults too.
