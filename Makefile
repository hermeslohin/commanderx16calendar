# Build and run the calendar on the Commander X16 emulator.
PROG8C ?= java -jar $(HOME)/prog8c.jar
X16EMU ?= /usr/local/x16emu/x16emu

SRC  = calendar.p8
PRG  = calendar.prg

.PHONY: all run clean

all: $(PRG)

$(PRG): $(SRC)
	$(PROG8C) -target cx16 $(SRC)

# -fsroot . lets the program save CALENDAR.DAT in this directory
run: $(PRG)
	$(X16EMU) -rtc -fsroot . -prg $(PRG) -run

clean:
	rm -f $(PRG) *.asm *.vice-mon-list
