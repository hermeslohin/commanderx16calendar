# Commander X16 Calendar (Prog8)

A month-view calendar for the Commander X16, with F1 sync to an ownCloud/CalDAV calendar through
the X16 Office sync hub.

Build: `make PROG8C="<prog8c 12.3.x command>"` (Prog8 12.3.x + 64tass + Java 11+). That gives
`build/calendar.prg` and `build/x16link.bin`. The X16Link sources are vendored in `lib/x16link/`
(see `lib/x16link/VENDORED.md`). Run in the emulator: `make run`.

Keys: cursor keys = move between days, Ctrl+N/P = month, Ctrl+F/B = year, Ctrl+A = add, Ctrl+D = delete,
Ctrl+T = today, Ctrl+X = quit, **F1** = sync with ownCloud, **F3** = sync conflicts.

To sync, put these on the SD card next to each other: `CALENDAR.PRG`, `X16LINK.BIN` and the
`X16LINK.KEY` made by the hub (`python -m x16hub link key new <devid> --sdcard <dir> --host
<hub-ip>:6502`). You also need the TexElec serial/ESP32 card with Zimodem. The hub's README covers
the Wi-Fi/Zimodem setup.

Docs: `FORMAT.md` (CALENDAR.DAT, CALSYNC.DAT and the sync button), `SYNC-PLAN.md` (how the hub maps
slots to CalDAV events). Test: `selftest/run_caltest.py` drives the real app (scripted keys) in
x16emu against a private hub and a real CalDAV calendar. It needs the X16 Office workspace
(`X16OFFICE=<dir>`), only touches `W7TEST` events and deletes them afterwards.
(`calendar.prg`/`.asm` in the repo root are the original pre-sync build, kept for reference.
`CALENDAR.DAT` is a one-event sample.)
