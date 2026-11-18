# Calendar sync plan (X16 calendar <-> ownCloud CalDAV)

Hub side: **done and tested**, in `hub/x16hub/calsync.py` (tests: `hub/tests/test_calsync.py`,
live: `hub/tests/live_calsync.py`). This file says what the X16 app and the wire protocol
(W5: `PROTOCOL.md`, `lib/x16link`, `hub serve`) need to plug in. The record format is in FORMAT.md.

## How sync works (one paragraph)

The X16 keeps a 4-byte **counter** (`CALSYNC.DAT`, u32 little-endian, start 0). A sync:
the X16 sends its counter plus records. The hub pulls ownCloud changes (RFC 6578
sync-collection), applies the X16 changes (create/delete/edit, with conflicts handled) and
returns every slot that changed after the counter, plus a new counter. The X16 writes those slots,
saves CALENDAR.DAT, **then** saves the counter. Every step is idempotent: if the link drops anywhere,
the next Sync redoes it without duplicates or lost deletes. Counter 0 (or one the hub doesn't
know) means a full reply with all 128 slots.

## Calendar ops for the wire protocol (proposal for W5)

All integers are little-endian, records are the raw 32-byte slots, and slot is u8 0..127.
The engine already has these functions, so the wire layer only moves bytes:

| Op | Request | Reply | Engine call |
|---|---|---|---|
| `CAL_SYNC` | u32 counter, u8 n, n x (u8 slot, 32B rec) | u8 status, u32 new_counter, u8 flags (bit0 full), u8 m, m x (u8 slot, 32B rec), u8 created, u8 updated, u8 deleted, u8 conflicts, u8 unplaced | `CalSync.sync(records, since)` -> `(PushResult, PullResult)` |
| `CAL_PULL` | u32 counter | same as the second half of CAL_SYNC | `x16_changes_since(counter)` |
| `CAL_PUSH` | u32 counter, n x (slot, rec) | u8 status + the counts | `apply_x16_changes(records, since)` |
| `CAL_CONFLICTS` | - | u8 k, k x (u8 slot, u8 field: 0 event/1 date/2 time/3 text, u8 kept: 0 x16/1 server, 27B server value in PETSCII, 0-padded) | `conflicts()` |
| `CAL_ACK` | u8 k, k x u8 slot (k=0: all) | u8 acked | `ack_conflicts(slots)` |
| `CAL_STATUS` | - | u32 counter, u8 used, u16 server events, u8 unplaced, u8 open conflicts | `status()` |

* **Frame sizes:** a full push or pull is 128 x 33 = 4224 bytes. If X16Link frames are smaller,
  chunk it (`CAL_SYNC_BEGIN/CHUNK/END`) or have the X16 send only *dirty* slots. Sending clean
  slots is harmless: the engine treats a slot equal to any version it already knows as "no change".
  **The simplest correct X16 client sends all 128 slots.** Doing that over the TCP link
  at 9600+ baud is about 4.5 s; at 115200, under 0.5 s.
* **Busy:** the engine takes an exclusive lock per sync (flock + SQLite transaction). A second
  sync waits for it. Reply status codes: 0 ok, 1 server unreachable (nothing changed, retry),
  2 bad request.
* Status 1 is also used when the ownCloud request fails mid-way. The hub DB is rolled back.
  Whatever already reached ownCloud is recognised on the retry (deterministic UIDs,
  If-None-Match / If-Match).

## X16 app UI changes

> Status: the app is now mouse driven (X16 Office look, see FORMAT.md). Items 2's `!` marks, 3, 4
> (edit in place sets `$02`, also when an event is dragged to another day) and 5 (sorted day list)
> are done. Still to do: the Sync button / key (1), the conflict detail box (2) and the hint (6).
> The status bar is row 29 and messages go through `cv.set_status`.

1. **Sync key: `Ctrl+S`** (shown in the help line as `S=SYNC`).
   * Save first, if dirty. Show `syncing...` in the message row (row 29).
   * Open the link (W5 `x16link`), send `CAL_SYNC` with all 128 slots + counter.
   * Apply the reply into `events`, `diskio.save` CALENDAR.DAT, **then** save CALSYNC.DAT.
   * Message: `sync ok: +3 -1 ~2` (created/deleted/updated on the server, plus slots received),
     or `sync failed: hub offline` and change nothing.
   * If `unplaced > 0`: `5 events did not fit` (more than 6 on a day, or more than 128 in total).
2. **Conflict display.** Records with flag bit2 (`$04`) get a `!` instead of the `.` in the
   day list (`1! 14:30 Dentist`), and days with a conflicted event show `!` instead of `*` in the grid.
   * `Ctrl+C` (or `?`) on a day with conflicts sends `CAL_CONFLICTS` and shows rows 19-24 as
     `X16 kept / server had: <27 chars>`. Any key sends `CAL_ACK` for those slots. The next sync clears the bit.
   * Nothing is ever lost: the losing text is also in the event's DESCRIPTION on ownCloud.
3. **Keep the flag byte as is.** The add code writes `1`, which is right. Never test
   `== 1`, only `!= 0`, because synced records can be `$05` (used + conflict).
4. **Optional: edit in place (`Ctrl+E`).** Load the record into the line editor and on ENTER
   set flag `|= $02`. Today the app can only delete + add. The hub then has to treat a
   changed slot as "delete the old event and create a new one", which drops server-only
   data (location, notes, reminders). With `$02` the hub does a field-level edit instead and
   keeps all of that. Strongly recommended before synced events are edited on the X16.
5. **Optional: sort the day list by text.** Times are `HH:MM ` prefixes, so a plain byte compare
   sorts timed events by time with all-day events after them.
6. **Time entry hint** in the add prompt: `new event (hh:mm text, enter=save):`.

## Mapping rules (hub)

| X16 | ownCloud VEVENT |
|---|---|
| date (y/m/d) | DTSTART date (all-day, DTEND = +1 day) or the date part of DTSTART in America/New_York |
| `HH:MM ` prefix | DTSTART;TZID=America/New_York:...THHMM00, DTEND = +1h (new events). Existing events keep their duration |
| text | SUMMARY. The X16 shows the first 27 - 6 (timed) chars, folded to PETSCII |
| slot | hub.db `cal_slot_ver` (slot, rev) -> UID, RECURRENCE-ID, href, etag, hash |
| flag bit2 | an unacknowledged row in `cal_conflicts` for that event |

* **New X16 events** get UID `x16-<24 hex>` (deterministic, so a retry can't duplicate),
  `X-X16-ORIGIN`, DTSTAMP/CREATED/LAST-MODIFIED and a VTIMEZONE.
* **Preservation.** Hub edits are a GET-modify-PUT of the stored ICS with If-Match. Only
  SUMMARY / DTSTART / DTEND / DTSTAMP / LAST-MODIFIED / SEQUENCE are touched, so DESCRIPTION,
  LOCATION, VALARM, ATTENDEE, X-props and the summary beyond what the X16 shows all survive.
  Text edits are diffed against the PETSCII copy the X16 had. Unchanged parts keep their
  original Unicode (e.g. `Crème BRULEE ☕ Zoë` after the X16 changed only "brulee" to "BRULEE").
* **Server -> X16 window:** single events always (any date 2000-2200). **Recurring events are
  expanded** to occurrences in [today-31 d, today+366 d], at most 400 per series. SECONDLY and
  MINUTELY rules are skipped. Occurrence overrides (RECURRENCE-ID) and EXDATEs are honoured,
  and so is DST (wall clock in New York).
* **Room:** at most 6 per day and 128 in total, nearest upcoming first. When the X16 is full, events
  older than 31 days are evicted **from the X16 only**. The `unplaced` count is reported.
* **X16 -> server for recurring events:** deleting an occurrence adds an EXDATE. Editing one
  (with `$02`) creates a RECURRENCE-ID override. A brand-new X16 event is always a single event.
* **Invalid X16 records** (bad date, year outside 2000..2200, empty text) stay on the X16 as
  "local" and are never sent or overwritten.

## Conflict rules

| X16 | ownCloud | Result |
|---|---|---|
| delete | edited | server version kept and comes back with `!`. Conflict logged. |
| edit (`$02`) | deleted | event recreated from the X16 record, `!`. Logged. |
| edit field A | edit field B | merged (e.g. X16 moved the date, phone renamed it), no conflict |
| edit field A | edit field A differently | X16 wins (it arrived last), the server value goes to DESCRIPTION `[X16 sync conflict ...: text: ownCloud had '...']` + `X-X16-CONFLICT` + cal_conflicts, `!` |
| delete | delete | fine |
| replace slot (delete + add, no `$02`) | edited | old event kept (conflict) + the new one created |

## Hub CLI (works today, without the wire link)

```sh
cd ~/x16-office/hub
.venv/bin/python -m x16hub.calsync status
.venv/bin/python -m x16hub.calsync dat /path/to/CALENDAR.DAT   # act as the X16: sync a .DAT file in place
.venv/bin/python -m x16hub.calsync conflicts | ack
.venv/bin/python -m x16hub.calsync --calendar personal ...     # another calendar (default x16)
.venv/bin/python -m x16hub.calsync reset                         # forget sync state (server untouched)
```

`dat` lets you sync by copying the SD card's CALENDAR.DAT (or using the emulator's `-fsroot`)
before the network link exists. Verified: the real calendar.prg in x16emu loads a hub-written file
and lists `14:30 Cafe with Zoe ?`.

## Known limitations

* Without in-place edit (`$02`) an X16 change is delete + create, so server-only fields of that event are dropped (the old event is kept as a conflict if it changed on the server too).
* Long summaries are cut to 27 (21 with a time) chars on the X16. Non-Latin text shows as `?`. Both are display only.
* Multi-day events show on their start day only, and the end time is not shown.
* Events outside 2000-2200 and occurrences outside the recurring window are not on the X16.
* VTODO/VJOURNAL are ignored. Only the one bound calendar is synced. To switch calendars, run `reset` and do a full sync.
* One X16 per hub calendar binding. A second X16 would need its own hub.db (or a device ID in the protocol).
