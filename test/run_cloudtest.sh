#!/usr/bin/env bash
# X16 Calendar Sync end to end: test/cloudtest.p8 (the real app code) + X16LINK.BIN in x16emu with
# -uart1 ximodem, against the hub's link server + real calendar sync engine + in-memory CalDAV
# (test/calhub.py). Needs ../x16-office-hub (HUB=...) and its venv (HUBPY=...).
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
HUB="${HUB:-$HERE/../x16-office-hub/hub}"
HUBPY="${HUBPY:-$HUB/.venv/bin/python}"
B="$HERE/build/cloudtest"
rm -rf "$B"; mkdir -p "$B/sd" "$B/out" "$B/ximodem"
P8="${PROG8C:-java -jar $HOME/prog8c.jar} -target cx16 -srcdirs $HERE -srcdirs $HERE/lib/x16link -out $B"
$P8 "$HERE/test/cloudtest.p8" > "$B/cloudtest.log" 2>&1 || { cat "$B/cloudtest.log"; exit 1; }
$P8 "$HERE/lib/x16link/x16link.p8" > "$B/x16link.log" 2>&1 || { cat "$B/x16link.log"; exit 1; }
cp "$B/cloudtest.prg" "$B/sd/CLOUDTEST.PRG"; cp "$B/x16link.bin" "$B/sd/X16LINK.BIN"
"$HUBPY" "$HERE/test/calhub.py" "$HUB" "$B/sd" "$B/out" 6502 > "$B/hub.log" 2>&1 &
HUBPID=$!
for _ in $(seq 50); do grep -q "hub up" "$B/hub.log" 2>/dev/null && break; sleep 0.2; done
"$HERE/test/runemu.sh" "$B/sd/CLOUDTEST.PRG" "$B/cloudtest.out" 300 -uart1 "ximodem:$B/ximodem" || true
touch "$B/out/STOP"; wait $HUBPID || cat "$B/hub.log"
grep -a -E "PASS|FAIL|DONE" "$B/cloudtest.out.txt" || tail -20 "$B/cloudtest.out.txt"
echo "--- ownCloud calendar:"; cat "$B/out/events.txt"
grep -q "10:00 Dentist" "$B/out/events.txt" && grep -q "09:00 Lunch X16" "$B/out/events.txt" \
  && echo "PASS ownCloud has the X16 event and the X16's version of Lunch" || { echo "FAIL ownCloud calendar"; exit 1; }
grep -aq "ALL PASS" "$B/cloudtest.out.txt"
