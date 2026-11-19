#!/usr/bin/env bash
# Themes, headless: test/themetest.p8 (the real app code) + X16THEME1..6.BIN in x16emu on the host
# file system. Checks the PASS lines; two screenshots per theme n: build/themetest/month-n.png (the
# month view with events) and build/themetest/entry-n.png (the entry bar and dialogs).
# Env: PROG8C (default java -jar ~/prog8c.jar), EMU (default /usr/local/x16emu/x16emu), PY (a python3
# with Pillow to split snap.gif into PNGs; default ../x16-office-hub/hub/.venv/bin/python3 if it exists).
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
B="${BUILD:-$HERE/build/themetest}"
EMU="${EMU:-/usr/local/x16emu/x16emu}"
PY="${PY:-$HERE/../x16-office-hub/hub/.venv/bin/python3}"
[ -x "$PY" ] || PY=python3
export PROG8C="${PROG8C:-java -jar $HOME/prog8c.jar}"
rm -rf "$B"; mkdir -p "$B"
$PROG8C -target cx16 -srcdirs "$HERE" -srcdirs "$HERE/lib/x16link" -out "$B" "$HERE/test/themetest.p8" \
  > "$B/themetest.log" 2>&1 || { cat "$B/themetest.log"; exit 1; }
python3 "$HERE/tools/mkthemes.py" "$B" > /dev/null
cd "$B"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$EMU" -sound none -echo iso -fsroot . -gif snap.gif,wait \
  -prg themetest.prg -run > out.txt 2>&1 &
P=$!
for _ in $(seq 600); do grep -aq "DONE" out.txt 2>/dev/null && break; kill -0 $P 2>/dev/null || break; sleep 0.2; done
sleep 0.5; kill $P 2>/dev/null; wait $P 2>/dev/null || true
tr '\r' '\n' < out.txt | tr -d '\000' | grep -a -E "PASS|FAIL|DONE" || tail -20 out.txt
ok=1
grep -aq "ALL PASS" out.txt || ok=0
if [ -f snap.gif ]; then
  "$PY" - <<'PY' || echo "(no Pillow: screenshots not split)"
from PIL import Image
im = Image.open("snap.gif")
i = 0
while True:
    im.convert("RGB").save(f"{('month', 'entry')[i % 2]}-{i // 2 + 1}.png")
    i += 1
    try:
        im.seek(im.tell() + 1)
    except EOFError:
        break
PY
  echo "screenshots: $B/month-*.png $B/entry-*.png"
fi
[ $ok = 1 ] && echo "RESULT PASS" || { echo "RESULT FAIL"; exit 1; }
