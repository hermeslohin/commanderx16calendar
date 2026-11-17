#!/usr/bin/env python3
"""Make build/caltest.p8: calendar.p8 with scripted keys (KEYS.DAT on the fsroot) for headless tests.

Script bytes: key codes as the X16 keyboard sends them; $FF = grab a GIF frame ($9FB5=1),
$FE = log the status message to the emulator console ("MSG ..."), $00 = end (quit + "CALTEST done").
Only wait_key() changes; everything else is the real app.
"""
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text()
out = Path(sys.argv[2])

old_wait = src[src.index("    sub wait_key() -> ubyte {"):]
old_wait = old_wait[:old_wait.index("\n    }\n") + 7]
new_wait = '''    uword kscript = memory("kscript", 1024, 0)
    uword ksp = 0
    bool kdone = false
    sub wait_key() -> ubyte {
        ubyte k
        repeat {
            if kdone
                return 24
            k = @(kscript + ksp)
            ksp++
            if k == 0 {
                kdone = true
                emudbg.console_write(iso:"CALTEST done\\n")
                return 24
            }
            if k == $ff {
                sys.wait(20)
                poke($9fb5, 1)
                sys.wait(4)
            } else if k == $fe {
                emudbg.console_write(iso:"MSG ")
                emudbg.console_write(message)
                emudbg.console_write(iso:"\\n")
            } else
                return k
        }
    }
'''
assert old_wait in src
src = src.replace(old_wait, new_wait)
src = src.replace("%import x16cal\n", "%import x16cal\n%import emudbg\n", 1)
src = src.replace("        load_events()\n        load_counter()\n",
                  "        load_events()\n        load_counter()\n"
                  "        sys.memset(kscript, 1024, 0)\n"
                  "        void diskio.load_raw(\"keys.dat\", kscript)\n", 1)
# messages are shown on the next redraw; keep them for the $FE logger
src = src.replace("        txt.print(message)\n        message[0] = 0\n", "        txt.print(message)\n", 1)
out.write_text(src)
