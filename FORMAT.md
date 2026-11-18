# CALENDAR.DAT: record format and app features

Source: `caldata.p8` (records, dates, charset), with the UI in `calapp.p8` / `calview.p8`.
Built with `make` (Prog8 12.3.5). The file format is the same as in the first, keyboard-only
version (commit `5f5c6fb`), so files move freely between the two and the hub.

## File

| Offset | Size | Meaning |
|---|---|---|
| 0 | 2 | PRG load-address header written by `diskio.save` = address of the `events` slab (`$1A55` in this build, i.e. `55 1A`). **Ignored on load** (`diskio.load(name, events)` uses an address override), so any value works. Keep it as found. |
| 2 | 4096 | 128 records x 32 bytes, slot *n* at `2 + 32*n` |

Total 4098 bytes. It is saved with `@:calendar.dat` (overwrite) after **every** add/delete,
on the current drive (SD card, or the `-fsroot` dir in the emulator). It is loaded once at start.
If the file is missing, the app starts empty. A shorter file loads partially and the rest stays zero.

## Record (32 bytes)

| Off | Type | Meaning |
|---|---|---|
| +0 | u8 | **used flag**: `0` = free slot. The app writes `1` and tests only `== 0`. The sync hub uses bit1 = *edited in place* (for a future edit feature) and bit2 = *conflict*. The current app sees any non-zero value as "used", so these bits are safe. |
| +1 | u8 | year - 2000 (`lsb(year-2000)`). The UI navigates 2000..2200 (Ctrl+F/B clamp; Ctrl+N past Dec 2200 can reach 2201+). |
| +2 | u8 | month 1..12 |
| +3 | u8 | day 1..31 (not validated on load) |
| +4 | 28 | description: up to **27** chars, NUL-terminated (`TXTMAX=27`; the buffer is `" " * 28`). Bytes after the NUL are garbage or zero. |

There is **no** record ID, time, end, duration, recurrence, location, notes, category,
or modified stamp. The slot index is the only identity and it is *not* stable for the
user: `add_event` takes the **lowest free slot**, so delete + add on the same day reuses the slot.

## Charset

The text bytes are PETSCII codes of the **lowercase/uppercase** charset. (The first version of the app
ran in that charset and stored raw keyboard codes. The current, mouse-driven version draws an ISO
bitmap screen like X16 Write / X16 Sheets and converts at the edges, `cal.to_iso` / `cal.to_pet` in
`caldata.p8`, so the bytes on disk are unchanged.) Stored bytes are `32..64`, `[ ]`, `$41-$5A`, `$C1-$DA`, `£ ↑`:

* `$41-$5A` show as **a-z** (unshifted letters), `$C1-$DA` as **A-Z** (shifted).
* `$20-$40`, `[` `]` are ASCII-equal. `$5C`=£, `$5E`=↑, `$5F`=←.
* `$60-$7E`: `$61-$7A` are C64 duplicates of A-Z and the rest are graphics glyphs. You can't
  type them normally. The hub never writes them.
* No accents. **The file is not ISO-8859-15**, even though the screen is: the hub's default
  charset stays `petscii`. Typed `\ { } | ~ _ ^ backtick` are folded the same way the hub folds them.

Hub mapping: 1 Unicode char <-> 1 byte, always. Accents and lookalikes are folded
(é→e, ß→s, €→E, curly quotes→straight, `\ { } | ~ _ ^ backtick` → `/ ( ) ! - - ↑ '`) and
anything else becomes `?`. This only affects the *display copy*: the server keeps the original
text (see SYNC-PLAN.md, "Preservation").

## Features / limits (current app)

* Mouse driven, in the X16 Office style (title bar, icon toolbar with tool tips, entry bar, status bar).
  Month grid with the first two events of each day (`+N more` after that) and the selected day's
  list below. A red `!` marks days and events with a sync conflict (flag bit2).
* **Add**: double-click a day or an empty list row, the New icon, or just type. **Edit**: double-click
  an event, the Edit icon, or Return. Editing in place sets flag bit1 (`|= $02`), as SYNC-PLAN.md asks.
  An empty text deletes the event. **Move**: drag an event onto another day (also sets bit1).
  **Delete** (icon or Del, with a Yes/No box) sets byte +0 to 0; the rest of the bytes stay (stale).
  Cut / Copy / Paste copy an event's text to the selected day (Paste creates a new event, flag 1).
* At most **6 events per day** (`MAXDAY`) and **128 in total** (`MAXEV`). The UI navigates 2000..2200.
* The day list is **sorted by text** (unsigned bytes), so `HH:MM ` times come first, all-day events after.
* **No times as data**, **no recurring events**, **no all-day/timed distinction**: see the hub convention below.
* Hub convention for times: a description that starts with `HH:MM ` (24-hour, `H:MM` also
  accepted) is a timed event in America/New_York. Anything else is all-day.
