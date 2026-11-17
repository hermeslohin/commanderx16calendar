# Build and run the calendar on the Commander X16 emulator.
# PROG8C = Prog8 12.3.x compiler command, e.g.  make PROG8C="java -jar ~/prog8c-12.3.5-all.jar"
# Output in build/ (git-ignored): calendar.prg + x16link.bin (the X16Link transport for F1 Sync,
# sources vendored in lib/x16link). For the SD card: CALENDAR.PRG, X16LINK.BIN, X16LINK.KEY.
PROG8C ?= prog8c
X16EMU ?= x16emu
LIB    ?= lib/x16link
P8      = $(PROG8C) -target cx16 -srcdirs $(LIB) -out build

.PHONY: all run sd clean
all: build/calendar.prg build/x16link.bin

build/calendar.prg: calendar.p8 $(wildcard $(LIB)/*.p8)
	mkdir -p build
	$(P8) calendar.p8

build/x16link.bin: $(wildcard $(LIB)/*.p8)
	mkdir -p build
	$(P8) $(LIB)/x16link.p8

# -fsroot build lets the program save CALENDAR.DAT there
run: all
	$(X16EMU) -rtc -fsroot build -prg build/calendar.prg -run

sd: all
	cp build/calendar.prg $(SD)/CALENDAR.PRG
	cp build/x16link.bin $(SD)/X16LINK.BIN

clean:
	rm -rf build
