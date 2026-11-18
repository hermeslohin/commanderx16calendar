#!/usr/bin/env bash
# Build test/uitest.p8 against the real app, run it headless in x16emu, print the results.
# The final screen lands in build/uitest/screen.png.
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
B="$HERE/build/uitest"
mkdir -p "$B/sd"
${PROG8C:-java -jar $HOME/prog8c.jar} -target cx16 -srcdirs "$HERE" -out "$B" "$HERE/test/uitest.p8" > "$B/uitest.log" 2>&1 || { cat "$B/uitest.log"; exit 1; }
cp "$B/uitest.prg" "$B/sd/UITEST.PRG"
rm -f "$B/sd/CALENDAR.DAT" "$B/sd/SHOT.BIN"
"$HERE/test/runemu.sh" "$B/sd/UITEST.PRG" "$B/uitest.out" 120
grep -a -E "PASS|FAIL|DONE" "$B/uitest.out.txt" || cat "$B/uitest.out.txt"
[ -f "$B/sd/SHOT.BIN" ] && python3 "$HERE/test/shot2png.py" "$B/sd/SHOT.BIN" "$B/screen.png" && echo "screen: $B/screen.png"
grep -aq "ALL PASS" "$B/uitest.out.txt"
