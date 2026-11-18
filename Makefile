# Build and run the calendar on the Commander X16 emulator.
# Needs Prog8 12.3.x (https://prog8.readthedocs.io) as ~/prog8c.jar (or PROG8C=...), 64tass and Java 11+.
PROG8C ?= java -jar $(HOME)/prog8c.jar
X16EMU ?= /usr/local/x16emu/x16emu

SRC  = calendar.p8 calapp.p8 calview.p8 caldata.p8 vid.p8 icons.p8
PRG  = calendar.prg

.PHONY: all run test clean

all: $(PRG)

$(PRG): $(SRC)
	$(PROG8C) -target cx16 calendar.p8

icons.p8: tools/gen_icons.py
	python3 tools/gen_icons.py

# -fsroot . lets the program save CALENDAR.DAT in this directory. Needs a mouse.
run: $(PRG)
	$(X16EMU) -scale 2 -rtc -fsroot . -prg $(PRG) -run

# drives the real UI headless and checks CALENDAR.DAT; also writes build/uitest/screen.png
test:
	test/run_uitest.sh

clean:
	rm -f $(PRG) *.asm *.vice-mon-list
	rm -rf build
