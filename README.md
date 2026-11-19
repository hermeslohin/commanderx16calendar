# X16 Calendar - a mouse-driven calendar for the Commander X16 (Prog8)

Part of the X16 Office suite, with the look of X16 Write and X16 Sheets: month view with up to two
events per day in the grid, the selected day's events below, and **Sync** with an ownCloud (CalDAV)
calendar through the X16 Office sync hub.

It wears the X16 Office themes (`theme.p8`, the same file in every X16 Office app). The first,
"Sunset Arcade", is also built in: a pink/orange striped title bar, a plum toolbar with coloured
icons, cream day cells on a starry night desk, today in yellow, the selected day and event in pink,
events as coloured chips. Quill, a little pencil, sits at the left end of the status bar and hops
after a save or a successful Sync. CALENDAR.DAT is unchanged.

## Themes

Six themes come as files: `X16THEME1.BIN` .. `X16THEME6.BIN` (Sunset Arcade, Crayon Desk, Comic
Book, Beach Hut, Chalkboard, Winter Cabin), written by `tools/mkthemes.py` (the same script in every
X16 Office repository) into `build/` and copied by `make sd`. **Click Quill** for the next theme.
The choice is saved in `X16THEME.CFG` (one byte) on the SD card, which X16 Write, X16 Sheets,
X16 Files and X16 Calendar all read at start, so a theme picked in one app is used by all of them.
A theme changes the colours of the screen (title bar, toolbar, entry bar, headers, status bar,
dialogs, the desk and its pattern) and Quill's band; the calendar's own colours keep their meaning
in every theme: today yellow, the selected day red, other months light grey, coloured event chips,
a red `!` for a sync conflict. Without theme files Quill stays hidden and the calendar uses the
built-in Sunset Arcade colours.

Build: `make` (Prog8 12.3.x as `~/prog8c.jar` or `PROG8C=...`, 64tass, Java 11+). That gives
`build/calendar.prg`, `build/x16link.bin` and the theme files `build/X16THEME1.BIN` .. `6`; the
X16Link sources are vendored in `lib/x16link/` (see `lib/x16link/VENDORED.md`).
`make sd SD=<dir>` copies `CALENDAR.PRG`, `X16LINK.BIN` and `X16THEME*.BIN`.
Run in the emulator: `make run` (needs a mouse), or `make run-modem` with the virtual modem for Sync.

## Using it

* **Click** a day to select it, click an event to select it, **double-click** a day (or an empty
  list row) to add an event, double-click an event to edit it, **drag** an event onto another day to
  move it, **wheel** over the month = previous / next month. Typing starts a new event; Return
  saves, Esc cancels. Start the text with a time like `14:30` for a timed event.
* Toolbar: New, Edit, Delete, Cut, Copy, Paste, Today, previous/next year and month,
  **Sync** (cloud icon, F1) and **Conflicts** (warning icon, F3; highlighted when there are any).
* Keys: arrows move between days, PgUp/PgDn month, Home today, Tab next event, Del delete,
  F1 sync, F3 conflicts, Ctrl+X quit.
* Events are saved to `CALENDAR.DAT` after every change. Limits: 6 events per day, 128 in total,
  27 characters per event.

## Sync with ownCloud

Put `CALENDAR.PRG`, `X16LINK.BIN` and the `X16LINK.KEY` made by the hub
(`python -m x16hub link key new <devid> --sdcard <dir> --host <hub-ip>:6502`) next to each other on
the SD card; you also need the TexElec serial/ESP32 card with Zimodem (see the hub's README).
Sync sends new, changed and deleted events to the hub's calendar (default `x16`) and brings back
what changed in ownCloud. If an event changed on both sides, the X16 version is kept and the event
gets a red `!`; the Conflicts dialog shows what the ownCloud side had, and **Acknowledge all**
clears the marks at the next Sync. Details: `FORMAT.md` (CALENDAR.DAT, CALSYNC.DAT, Sync),
`SYNC-PLAN.md` (how the hub maps slots to CalDAV events).

## Tests

* `make test`: drives the real UI headless (clicks, typing, drag, cut/copy/paste), checks
  CALENDAR.DAT, writes `build/uitest/screen.png`.
* `make cloudtest`: Sync end to end in x16emu with the virtual modem against the hub's link server,
  its real calendar sync engine and an in-memory CalDAV calendar (needs `../x16-office-hub` and its
  venv): push, pull, the hub counter, a conflict, acknowledging it, reload.
* `make themetest`: the theme files headless: no `X16THEME.CFG` = theme 1 (exactly the built-in
  colours), clicking Quill goes through all six and back to the first, `X16THEME.CFG` brings the
  choice back; screenshots of every theme in `build/themetest/month-<n>.png` (month view with
  events) and `entry-<n>.png` (entry bar and dialogs). Splitting the screenshots needs a Python with
  Pillow (`PY=...`, default the hub's venv).

`CALENDAR.DAT` in the repo is a one-event sample.

## License

Copyright (C) 2026 hermeslohin

X16 Calendar is free software: you can redistribute it and/or modify it under the terms of the GNU General
Public License as published by the Free Software Foundation, either version 3 of the License, or (at
your option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See [LICENSE](LICENSE) for the full text of the GNU General Public License v3.
