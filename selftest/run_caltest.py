#!/usr/bin/env python3
"""End-to-end test of the calendar's F1 Sync against the REAL ownCloud x16 calendar.

Builds a test variant of calendar.p8 (scripted keys, see mk_caltest.py), starts a private hub
(`x16hub serve` on 127.0.0.1:6503 with a temp data dir, so the real hub.db is untouched) and runs
x16emu with -uart1 ximodem several times; between runs it edits/adds/deletes events over CalDAV.
Only touches events whose summary starts with W7TEST, and deletes them all at the end.

Run with the hub venv:  ~/x16-office/hub/.venv/bin/python apps/calendar/selftest/run_caltest.py
"""
from __future__ import annotations

import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = HERE.parent
ROOT = Path(os.environ.get("X16OFFICE") or APP.parent.parent).resolve()   # x16-office workspace (hub, tools, run/)
HUB = ROOT / "hub"
sys.path.insert(0, str(HUB))

from icalendar import Calendar  # noqa: E402

from x16hub import calsync as C  # noqa: E402
from x16hub.backend import owncloud as ocm  # noqa: E402

B = ROOT / "build" / "caltest"
SD = ROOT / "run" / "sd-cal"
SHOTS = ROOT / "run" / "shots-cal"
PORT = 6503
PET = C.Petscii()
F1, F3, ENTER, ESC, RIGHT, LEFT = 133, 134, 13, 27, 29, 157
CTRL_A, CTRL_D, SHOT, LOG = 1, 4, 0xFF, 0xFE
results: list[tuple[bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    results.append((ok, name))
    print(f"{'PASS' if ok else 'FAIL'} {name}{(' - ' + detail) if detail and not ok else ''}", flush=True)


def keys(*parts) -> bytes:
    out = bytearray()
    for p in parts:
        out += PET.encode(p) if isinstance(p, str) else bytes(p if isinstance(p, (list, tuple)) else [p])
    return bytes(out)


def build() -> None:
    B.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(HERE / "mk_caltest.py"), str(APP / "calendar.p8"), str(B / "caltest.p8")],
                   check=True)
    p8 = [os.environ.get("PROG8C") or str(ROOT / "tools/prog8c"), "-target", "cx16", "-srcdirs", str(APP / "lib/x16link"), "-out"]
    for args in ([str(B), str(APP / "lib/x16link/x16link.p8")],
                 [str(B), str(B / "caltest.p8")]):
        r = subprocess.run(p8 + args, capture_output=True, text=True)
        if r.returncode:
            print(r.stdout[-2000:], r.stderr[-2000:])
            raise SystemExit("build failed")


def emu_run(tag: str, script: bytes, timeout: int = 240) -> str:
    (SD / "KEYS.DAT").write_bytes(script + b"\0")
    gif = B / f"{tag}.gif"
    gif.unlink(missing_ok=True)
    env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
    out = B / f"{tag}.out"
    with open(out, "wb") as fo:
        p = subprocess.Popen([str(ROOT / "tools/x16emu.sh"), "-sound", "none", "-rtc", "-fsroot", str(SD),
                              "-gif", f"{gif},wait", "-uart1", f"ximodem:{ROOT}/run/ximodem-data",
                              "-prg", str(SD / "CALTEST.PRG"), "-run"], stdout=fo, stderr=subprocess.STDOUT,
                             env=env, cwd=SD, start_new_session=True)
        t0 = time.time()
        while time.time() - t0 < timeout:
            if b"CALTEST done" in out.read_bytes():
                break
            time.sleep(0.5)
        time.sleep(1.0)
        os.killpg(p.pid, signal.SIGTERM)
        p.wait()
    text = out.read_bytes().decode("latin-1").replace("\r", "\n")
    msgs = [ln[4:].strip() for ln in text.splitlines() if ln.startswith("MSG ")]
    check(f"{tag}: emulator script finished", "CALTEST done" in text, text[-300:])
    for m in msgs:
        print(f"   [{tag}] status line: {PET.decode(m.encode('latin-1'))}")
    if gif.exists():
        n = save_frames(gif, tag)
        print(f"   [{tag}] {n} screenshot(s)")
    return "\n".join(PET.decode(m.encode("latin-1")) for m in msgs)


def save_frames(gif: Path, tag: str) -> int:
    code = ("import sys\nfrom PIL import Image, ImageSequence\nim=Image.open(sys.argv[1])\nn=0\n"
            "c=Image.new('RGB', im.size, (0,0,0))\n"
            "for i,f in enumerate(ImageSequence.Iterator(im)):\n"
            "    a=f.convert('RGBA'); c.paste(a,(0,0),a); c.save(f'{sys.argv[2]}-{i:02d}.png'); n+=1\nprint(n)")
    r = subprocess.run(["/usr/bin/python3", "-c", code, str(gif), str(SHOTS / tag)], capture_output=True, text=True)
    return int(r.stdout.strip() or 0)


def x16_records() -> dict[int, C.X16Rec]:
    _, recs = C.read_dat((SD / "CALENDAR.DAT").read_bytes())
    return {i: C.X16Rec.from_bytes(r) for i, r in enumerate(recs) if r[0]}


def x16_texts() -> dict[str, C.X16Rec]:
    return {PET.decode(r.text): r for r in x16_records().values()}


def server(oc, cal) -> dict[str, dict]:
    out = {}
    start = datetime.now(timezone.utc) - timedelta(days=30)
    for ev in oc.events(cal, start, start + timedelta(days=120)):
        for e in Calendar.from_ical(ev["ics"]).walk("VEVENT"):
            s = str(e.get("summary", ""))
            if s.startswith("W7TEST"):
                out[s] = ev
    return out


def edit_summary(oc, ev, new: str) -> None:
    cal = Calendar.from_ical(ev["ics"])
    for e in cal.walk("VEVENT"):
        e["summary"] = new
    oc.update_event(ev["href"], cal.to_ical(), ev["etag"])


def cleanup(oc, cal) -> int:
    n = 0
    for ev in server(oc, cal).values():
        oc.delete_event(ev["href"], ev["etag"])
        n += 1
    return n


def main() -> int:
    ocm.install_log_redaction()
    oc = ocm.OwnCloud(ocm.load_config())
    cal, _ = oc.ensure_calendar("x16")
    stale = cleanup(oc, cal)
    if stale:
        print(f"removed {stale} W7TEST event(s) left from an earlier run")
    build()
    shutil.rmtree(SD, ignore_errors=True)
    SD.mkdir(parents=True)
    SHOTS.mkdir(parents=True, exist_ok=True)
    for f in SHOTS.glob("*.png"):
        f.unlink()
    shutil.copy(B / "caltest.prg", SD / "CALTEST.PRG")
    shutil.copy(B / "x16link.bin", SD / "X16LINK.BIN")
    key = (ROOT / "run/sd/X16LINK.KEY").read_text()          # device x16-emu; never printed
    (SD / "X16LINK.KEY").write_text(re.sub(r"(?m)^HOST=.*$", f"HOST=127.0.0.1:{PORT}", key))
    os.chmod(SD / "X16LINK.KEY", 0o600)

    data = Path(tempfile.mkdtemp(prefix="w7cal-"))
    os.chmod(data, 0o700)
    hublog = open(B / "hub.log", "w")
    hub = subprocess.Popen([str(HUB / ".venv/bin/python"), "-m", "x16hub", "serve", "--bind", "127.0.0.1",
                            "--port", str(PORT)], cwd=HUB, stdout=hublog, stderr=subprocess.STDOUT,
                           env=dict(os.environ, X16HUB_DATA=str(data), X16HUB_LOG="INFO"))
    time.sleep(2)
    today = datetime.now().date()          # the emulator's -rtc clock = host local date
    try:
        # 0. robustness: oversized CALENDAR.DAT / CALSYNC.DAT must not overrun memory
        (SD / "CALENDAR.DAT").write_bytes(b"\x55\x1a" + bytes(4096) + b"\xee" * 6000)
        (SD / "CALSYNC.DAT").write_bytes(b"\xff" * 3000)
        m = emu_run("0-oversize", keys(LOG))
        check("oversized files load safely (app runs, events loaded)", "loaded saved events" in m, m)
        (SD / "CALENDAR.DAT").unlink()
        (SD / "CALSYNC.DAT").unlink()
        # 1. X16 add (timed) -> CalDAV
        emu_run("1-add", keys(CTRL_A, "10:00 W7TEST x16 add", ENTER, SHOT, F1, LOG, SHOT))
        srv = server(oc, cal)
        ev = srv.get("W7TEST x16 add")
        check("X16 add shows in CalDAV", ev is not None, str(list(srv)))
        if ev:
            st = ev.get("start")
            check("  ...at 10:00 America/New_York on the X16's date",
                  "T100000" in ev["ics"] and today.strftime("%Y%m%d") in ev["ics"] and "America/New_York" in ev["ics"],
                  ev["ics"][:400])
        check("CALSYNC.DAT counter stored", (SD / "CALSYNC.DAT").exists() and
              int.from_bytes((SD / "CALSYNC.DAT").read_bytes()[:4], "little") > 0)

        # 2. CalDAV edit + add -> X16
        if ev:
            edit_summary(oc, ev, "W7TEST x16 add edited")
        tomorrow = today + timedelta(days=1)
        ics = C.build_new_event("w7test-srv-1", tomorrow, (14, 30), "W7TEST from CalDAV")
        oc.create_event(cal, ics, uid="w7test-srv-1")
        emu_run("2-pull", keys(F1, LOG, SHOT, RIGHT, SHOT))
        t = x16_texts()
        check("CalDAV edit shows on the X16", "10:00 W7TEST x16 add edited" in t, str(list(t)))
        r = t.get("14:30 W7TEST from CalDAV")
        check("CalDAV add shows on the X16 (date + time)", r is not None and r.date == tomorrow, str(list(t)))

        # 3. X16 delete -> CalDAV
        emu_run("3-xdel", keys(RIGHT, CTRL_D, "1", F1, LOG, SHOT))
        srv = server(oc, cal)
        check("X16 delete removes the CalDAV event", "W7TEST from CalDAV" not in srv, str(list(srv)))
        check("  ...and only that one", "W7TEST x16 add edited" in srv, str(list(srv)))

        # 4. CalDAV delete -> X16
        ev = srv.get("W7TEST x16 add edited")
        if ev:
            oc.delete_event(ev["href"], ev["etag"])
        emu_run("4-sdel", keys(F1, LOG, SHOT))
        t = x16_texts()
        check("CalDAV delete removes the X16 event", not any(k.startswith("10:00 W7TEST") for k in t), str(list(t)))

        # 5. conflict: X16 deletes an event that was edited in ownCloud meanwhile -> edit kept + reported
        emu_run("5a-add", keys(CTRL_A, "W7TEST conflict", ENTER, F1, LOG))
        srv = server(oc, cal)
        ev = srv.get("W7TEST conflict")
        check("conflict setup: event on CalDAV", ev is not None, str(list(srv)))
        if ev:
            edit_summary(oc, ev, "W7TEST conflict srv")
        m = emu_run("5b-conflict", keys(CTRL_D, "1", F1, LOG, SHOT, F3, SHOT, "a", LOG, SHOT, F1, LOG, SHOT))
        t = x16_texts()
        check("conflict: ownCloud edit kept on the X16", "W7TEST conflict srv" in t, str(list(t)))
        check("conflict: reported in the status line", "conflicts: 1" in m.lower(), m)
        r = t.get("W7TEST conflict srv")
        check("conflict flag cleared after acknowledge + sync", r is not None and not (r.flags & 4),
              f"flags={r.flags if r else None}")
        # 6. lost CALENDAR.DAT (CALSYNC.DAT still there): must re-pull, never delete in ownCloud
        (SD / "CALENDAR.DAT").unlink()
        emu_run("6-lostdat", keys(F1, LOG, SHOT))
        srv = server(oc, cal)
        check("lost CALENDAR.DAT: nothing deleted in ownCloud", "W7TEST conflict srv" in srv, str(list(srv)))
        check("lost CALENDAR.DAT: events pulled back to the X16", "W7TEST conflict srv" in x16_texts(),
              str(list(x16_texts())))
    finally:
        hub.send_signal(signal.SIGINT)
        try:
            hub.wait(10)
        except subprocess.TimeoutExpired:
            hub.kill()
        hublog.close()
        n = cleanup(oc, cal)
        left = server(oc, cal)
        check(f"cleanup: {n} W7TEST event(s) deleted, none left", not left, str(list(left)))
        shutil.rmtree(data, ignore_errors=True)
    fails = [n for ok, n in results if not ok]
    print(f"RESULT {'PASS' if not fails else 'FAIL'} ({len(results) - len(fails)}/{len(results)})")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
