# CALENDAR.DAT: record format and app features

Source: `calendar.p8` (commit `5f5c6fb`, hermeslohin/commanderx16calendar).
Built with our toolchain: `~/x16-office/tools/prog8c -target cx16 -out build calendar.p8`
(Prog8 12.3.5, 1.0 s). `build/calendar.prg` is byte-identical to the committed `calendar.prg`
(md5 `a9dda636…`). It needs no network and no extra libraries: `textio`, `diskio`, `syslib`, `strings`.

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

The app switches to the **lowercase/uppercase PETSCII** charset (`txt.lowercase()`), and the
text bytes are raw PETSCII keyboard codes. `read_line` accepts `32..126` and `193..218`:

* `$41-$5A` show as **a-z** (unshifted letters), `$C1-$DA` as **A-Z** (shifted).
* `$20-$40`, `[` `]` are ASCII-equal. `$5C`=£, `$5E`=↑, `$5F`=←.
* `$60-$7E`: `$61-$7A` are C64 duplicates of A-Z and the rest are graphics glyphs. You can't
  type them normally. The hub never writes them.
* No accents. **The app does not use ISO-8859-15 mode.** The hub's default charset is
  therefore `petscii`. It also has an `iso-8859-15` codec in case the app ever calls `txt.iso()`.

Hub mapping: 1 Unicode char <-> 1 byte, always. Accents and lookalikes are folded
(é→e, ß→s, €→E, curly quotes→straight, `\ { } | ~ _ ^ backtick` → `/ ( ) ! - - ↑ '`) and
anything else becomes `?`. This only affects the *display copy*: the server keeps the original
text (see SYNC-PLAN.md, "Preservation").

## Features / limits (current app)

* Month grid. Cursor keys move the day, Ctrl+N/P change month, Ctrl+F/B change year, Ctrl+T
  goes to today (RTC) and Ctrl+X quits. A `*` marks days with events.
* **Add** (Ctrl+A): a one-line editor with at most 27 chars and ENTER/ESC. At most
  **6 events per day** (`MAXDAY`) and **128 in total** (`MAXEV`).
* **Delete** (Ctrl+D then 1-9, effectively 1-6): sets byte +0 to 0. The rest of the bytes stay (stale).
* **No edit**, **no times**, **no recurring events**, **no all-day/timed distinction**.
  The list shows events in **slot order**, not time order.
* Hub convention for times: a description that starts with `HH:MM ` (24-hour, `H:MM` also
  accepted) is a timed event in America/New_York. Anything else is all-day.
