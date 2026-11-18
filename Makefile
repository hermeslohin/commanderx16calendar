# Build and run X16 Calendar on the Commander X16 emulator.
# Needs Prog8 12.3.x (https://prog8.readthedocs.io) as ~/prog8c.jar (or PROG8C=...), 64tass and Java 11+.
# Output in build/ (git-ignored): calendar.prg + x16link.bin (the X16Link transport for Sync, sources
# vendored in lib/x16link). For the SD card: CALENDAR.PRG, X16LINK.BIN and the hub's X16LINK.KEY.
PROG8C ?= java -jar $(HOME)/prog8c.jar
X16EMU ?= /usr/local/x16emu/x16emu
LIB    ?= lib/x16link
P8      = $(PROG8C) -target cx16 -srcdirs $(LIB) -out build
SRC     = calendar.p8 calapp.p8 calview.p8 caldata.p8 vid.p8 icons.p8

.PHONY: all run run-modem sd test cloudtest clean

all: build/calendar.prg build/x16link.bin

build/calendar.prg: $(SRC) $(wildcard $(LIB)/*.p8)
	mkdir -p build
	$(P8) calendar.p8

build/x16link.bin: $(wildcard $(LIB)/*.p8)
	mkdir -p build
	$(P8) $(LIB)/x16link.p8

icons.p8: tools/gen_icons.py
	python3 tools/gen_icons.py

# -fsroot build lets the program save CALENDAR.DAT there. Needs a mouse.
run: all
	$(X16EMU) -scale 2 -rtc -fsroot build -prg build/calendar.prg -run

# with the emulator's virtual modem on UART1, for Sync (put X16LINK.KEY into build/ first)
run-modem: all
	cd build && $(X16EMU) -scale 2 -rtc -uart1 ximodem -prg calendar.prg -run

sd: all
	cp build/calendar.prg $(SD)/CALENDAR.PRG
	cp build/x16link.bin $(SD)/X16LINK.BIN

# drives the real UI headless and checks CALENDAR.DAT; also writes build/uitest/screen.png
test:
	test/run_uitest.sh

# Sync end to end: the app's sync code through the emulator's virtual modem to the hub's link
# server with an in-memory CalDAV calendar (needs ../x16-office-hub and its venv)
cloudtest:
	test/run_cloudtest.sh

clean:
	rm -rf build
