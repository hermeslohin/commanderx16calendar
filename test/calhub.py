#!/usr/bin/env python3
"""Run the X16 Office hub's link server (x16-office-hub/hub) on 127.0.0.1:<port> with the hub's real
calendar sync engine and an in-memory CalDAV calendar (the hub's FakeOC test double), for
X16 Calendar's Sync test.

usage: calhub.py <hub-dir> <sd-dir> <out-dir> [port]
  * writes <sd-dir>/X16LINK.KEY for device x16-cal-test
  * seeds ownCloud with "Lunch" on 2026-11-21 09:00 (New York time)
  * after the X16's first sync has created its event in CalDAV, renames "Lunch" on the server
    (so the X16's own edit of it makes a conflict on the next sync)
  * runs until <out-dir>/STOP exists, then writes every event as "date time summary" to
    <out-dir>/events.txt
"""
import asyncio
import sqlite3
import sys
import tempfile
from datetime import date, datetime
from pathlib import Path

hub, sd, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
port = int(sys.argv[4]) if len(sys.argv) > 4 else 6502
sys.path[:0] = [str(hub), str(hub / "tests")]

from fake_caldav import FakeOC                           # noqa: E402
from test_calsync import vevent                          # noqa: E402
from x16hub import calsync as C                          # noqa: E402
from x16hub.backend.owncloud import parse_event          # noqa: E402
from x16hub.link import keys as K                        # noqa: E402
from x16hub.link.server import Limits, LinkServer        # noqa: E402

KEY = bytes(range(60, 92))
DEV = "x16-cal-test"
TODAY = date(2026, 11, 17)


async def main():
    tmp = Path(tempfile.mkdtemp())
    db = tmp / "hub.db"
    oc = FakeOC()
    oc.server_put("srv-lunch", vevent("srv-lunch", datetime(2026, 11, 21, 9, 0, tzinfo=C.NY), "Lunch"))
    K.write_sd_keyfile(sd, f"127.0.0.1:{port}", DEV, KEY)
    srv = LinkServer(keys_loader=lambda: {DEV: KEY}, oc_factory=lambda: oc,
                     limits=Limits(handshake=60, idle=600, partial=30),
                     cal_engine_factory=lambda: C.CalSync(oc, sqlite3.connect(db), today=lambda: TODAY,
                                                          lock_path=tmp / "lock"),
                     cal_db_factory=lambda: sqlite3.connect(db))
    s = await srv.start("127.0.0.1", port)
    print("hub up", flush=True)
    out.mkdir(parents=True, exist_ok=True)
    edited = False
    while not (out / "STOP").exists():
        await asyncio.sleep(0.1)
        if not edited and any(c == "create" for c in oc.calls):
            await asyncio.sleep(0.5)
            oc.server_put("srv-lunch", vevent("srv-lunch", datetime(2026, 11, 21, 9, 0, tzinfo=C.NY),
                                              "Lunch (moved to the cafe)"))
            edited = True
            print("server edit done", flush=True)
    lines = []
    for ics, _etag in oc.objs.values():
        ev = parse_event(ics)
        lines.append(f"{ev['start']:%Y-%m-%d %H:%M} {ev['summary']}")
    (out / "events.txt").write_text("\n".join(sorted(lines)) + "\n", encoding="utf-8")
    s.close()


asyncio.run(main())
