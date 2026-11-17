; Calendar for the Commander X16, written in Prog8.
;
; Month view with a movable day cursor. Events can be added to / deleted from
; any day and are saved to the file CALENDAR.DAT on the current drive
; (the SD card, or the host fs directory in the emulator) after every change.
;
; Keys:  cursor keys  move between days
;        Ctrl+N / P   next / previous month   Ctrl+F / B  next / previous year
;        Ctrl+A       add event on selected day Ctrl+D     delete an event
;        Ctrl+T       jump to today (needs RTC) Ctrl+X     quit
;        F1           sync with ownCloud (X16Link hub) F3   show sync conflicts
;
; Sync: needs X16LINK.BIN + X16LINK.KEY on the SD card and the TexElec serial/ESP32 card.
; CALENDAR.DAT is saved before every sync; the hub's change counter is kept in CALSYNC.DAT
; (4 bytes, written only after the synced CALENDAR.DAT is saved). Record flag bit2 = conflict.

%import textio
%import diskio
%import syslib
%import strings
%import conv
%import x16cal
%zeropage basicsafe

main {
    const ubyte MAXEV = 128         ; max number of stored events
    const ubyte RECSZ = 32          ; bytes per record
    const ubyte TXTMAX = 27         ; max characters in an event description
    const ubyte MAXDAY = 6          ; max events shown/allowed per day
    const uword FILESZ = 4096       ; MAXEV * RECSZ
    str FILENAME = "calendar.dat"
    str SAVENAME = "@:calendar.dat"
    str CNTNAME = "calsync.dat"
    str CNTSAVE = "@:calsync.dat"
    const ubyte F_CONFLICT = 4
    ubyte[4] sync_counter
    ubyte[2] sync_hdr
    bool dat_loaded = false
    str errbuf = " " * 64

    ; record layout: +0 used flag, +1 year-2000, +2 month, +3 day, +4.. text (0-terminated)
    uword events = memory("events", 4096, 0)

    uword sel_year = 2026
    ubyte sel_month = 1
    ubyte sel_day = 1
    uword today_year = 0
    ubyte today_month = 0
    ubyte today_day = 0
    str message = " " * 60

    ubyte[12] mdays = [31,28,31,30,31,30,31,31,30,31,30,31]
    ubyte[12] sakamoto = [0,3,2,5,0,3,5,1,4,6,2,4]
    str[12] names = ["JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE","JULY","AUGUST","SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"]
    str[7] dow_names = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

    sub start() {
        void cx16.set_screen_mode(3)       ; 40x30, doubled-size font
        txt.lowercase()                    ; mixed-case charset so "Sun" shows as typed
        sys.memset(events, FILESZ, 0)
        get_today()
        load_events()
        load_counter()
        main_loop()
        txt.clear_screen()
        txt.print("goodbye!\n")
    }

    sub main_loop() {
        draw_screen()
        repeat {
            ubyte key = wait_key()
            when key {
                29 -> move_days(1)              ; right
                157 -> move_days(-1)            ; left
                17 -> move_days(7)              ; down
                145 -> move_days(-7)            ; up
                14 -> change_month(1)           ; Ctrl+N
                16 -> change_month(-1)          ; Ctrl+P
                6 -> change_year(1)             ; Ctrl+F
                2 -> change_year(-1)            ; Ctrl+B
                1 -> add_event()                ; Ctrl+A
                4 -> delete_event()             ; Ctrl+D
                20 -> goto_today()              ; Ctrl+T
                24 -> return                    ; Ctrl+X
                133 -> sync_now()               ; F1
                134 -> show_conflicts()         ; F3
            }
            draw_screen()
        }
    }

    ; ---------- date helpers ----------

    sub is_leap(uword y) -> bool {
        uword r = y % 400
        if r == 0
            return true
        r = y % 100
        if r == 0
            return false
        r = y % 4
        return r == 0
    }

    sub days_in_month(uword y, ubyte m) -> ubyte {
        if m == 2 and is_leap(y)
            return 29
        return mdays[m-1]
    }

    ; 0 = Sunday .. 6 = Saturday
    sub day_of_week(uword y, ubyte m, ubyte d) -> ubyte {
        if m < 3
            y--
        uword t = y + (y >> 2)
        t -= y / 100
        t += y / 400
        t += sakamoto[m-1]
        t += d
        return lsb(t % 7)
    }

    sub get_today() {
        ; Read the X16's real-time clock and open on today's date.
        ; Falls back to January 2026 if the clock is unset.
        cx16.r0 = 0
        cx16.r1 = 0
        cx16.r2 = 0
        cx16.r3 = 0
        cx16.clock_get_date_time()
        uword yr = 1900 + (cx16.r0 & 255)
        ubyte mo = lsb(cx16.r0 >> 8)
        ubyte dy = lsb(cx16.r1)
        if yr >= 2000 and mo >= 1 and mo <= 12 and dy >= 1 and dy <= 31 {
            today_year = yr
            today_month = mo
            today_day = dy
            sel_year = yr
            sel_month = mo
            sel_day = dy
        }
    }

    sub goto_today() {
        if today_year != 0 {
            sel_year = today_year
            sel_month = today_month
            sel_day = today_day
        }
    }

    sub clamp_day() {
        ubyte dim = days_in_month(sel_year, sel_month)
        if sel_day > dim
            sel_day = dim
    }

    sub change_month(byte delta) {
        if delta > 0 {
            sel_month++
            if sel_month > 12 {
                sel_month = 1
                sel_year++
            }
        } else {
            sel_month--
            if sel_month == 0 {
                sel_month = 12
                sel_year--
            }
        }
        clamp_day()
    }

    sub change_year(byte delta) {
        if delta > 0 {
            if sel_year < 2200
                sel_year++
        } else {
            if sel_year > 2000
                sel_year--
        }
        clamp_day()
    }

    sub move_days(byte delta) {
        word d = sel_day
        word dim
        d += delta
        if d < 1 {
            change_month(-1)
            dim = days_in_month(sel_year, sel_month)
            d += dim
            sel_day = lsb(d as uword)
        } else {
            dim = days_in_month(sel_year, sel_month)
            if d > dim {
                d -= dim
                sel_day = lsb(d as uword)
                change_month(1)
            } else
                sel_day = lsb(d as uword)
        }
    }

    ; ---------- event storage ----------

    sub rec(ubyte idx) -> uword {
        return events + ((idx as uword) << 5)
    }

    sub rec_matches(ubyte idx, uword y, ubyte m, ubyte d) -> bool {
        uword p = rec(idx)
        if @(p) == 0
            return false
        return @(p+1) == lsb(y - 2000) and @(p+2) == m and @(p+3) == d
    }

    sub count_events(uword y, ubyte m, ubyte d) -> ubyte {
        ubyte n = 0
        ubyte i
        for i in 0 to MAXEV-1 {
            if rec_matches(i, y, m, d)
                n++
        }
        return n
    }

    ; index of the nth (0-based) event on the given day, or 255 if none
    sub nth_event(uword y, ubyte m, ubyte d, ubyte n) -> ubyte {
        ubyte i
        for i in 0 to MAXEV-1 {
            if rec_matches(i, y, m, d) {
                if n == 0
                    return i
                n--
            }
        }
        return 255
    }

    sub free_slot() -> ubyte {
        ubyte i
        for i in 0 to MAXEV-1 {
            if @(rec(i)) == 0
                return i
        }
        return 255
    }

    sub load_events() {
        dat_loaded = false
        if diskio.exists(FILENAME) {
            ; at most 2 + 4096 bytes: an oversized file must not run past the events slab
            sys.memset(events, FILESZ, 0)
            bool ok = false
            if diskio.f_open(FILENAME) {
                ok = diskio.f_read(&sync_hdr, 2) == 2
                if ok
                    void diskio.f_read(events, FILESZ)
                diskio.f_close()
            }
            dat_loaded = ok
            if not ok
                set_message("could not load calendar.dat!")
            else
                set_message("loaded saved events.")
        } else
            set_message("no saved calendar - starting new.")
    }

    sub save_events() {
        if diskio.save(SAVENAME, events, FILESZ)
            set_message("saved to calendar.dat.")
        else
            set_message("save failed! " + diskio.status())
    }

    ; ---------- ownCloud sync (X16Link calendar channel) ----------

    sub load_counter() {
        ; read at most 4 bytes (load_raw would load a long/odd file over whatever follows the array)
        sys.memset(&sync_counter, 4, 0)
        if not dat_loaded
            return          ; no/unreadable CALENDAR.DAT: next sync is a full one (never a mass delete)
        if diskio.f_open(CNTNAME) {
            if diskio.f_read(&sync_counter, 4) != 4
                sys.memset(&sync_counter, 4, 0)     ; damaged: full resync
            diskio.f_close()
        }
    }

    ; ISO-8859 text from the hub -> PETSCII for the lowercase charset
    sub iso_to_pet(uword s) {
        ubyte c
        while @(s) != 0 {
            c = @(s)
            if c >= $41 and c <= $5a
                @(s) = c + $80
            else if c >= $61 and c <= $7a
                @(s) = c - $20
            else if c < 32 or c >= 127
                @(s) = '?'
            s++
        }
    }

    sub add_num(str label, ubyte v) {
        void strings.append(message, label)
        void strings.append(message, conv.str_ub(v))
    }

    sub count_conflicts() -> ubyte {
        ubyte n = 0
        ubyte i
        for i in 0 to MAXEV-1 {
            if @(rec(i)) & F_CONFLICT != 0
                n++
        }
        return n
    }

    sub sync_now() {
        clear_prompt_rows()
        txt.print("syncing with owncloud...")
        if not diskio.save(SAVENAME, events, FILESZ) {
            set_message("save failed - not syncing.")
            return
        }
        if not lkload.load_link() {
            set_message("x16link.bin missing on sd card.")
            return
        }
        ubyte st = lkcal.sync(events, &sync_counter)
        if st != 0 {
            load_events()                       ; back to the saved state
            if not dat_loaded
                sys.memset(&sync_counter, 4, 0)
            lkcal.get_error(errbuf, 30)
            iso_to_pet(errbuf)
            set_message("sync failed: ")
            void strings.append(message, errbuf)
            return
        }
        if not diskio.save(SAVENAME, events, FILESZ) {
            load_events()
            set_message("sync ok but save failed!")
            return
        }
        if diskio.save_raw(CNTSAVE, &lkcal.new_counter, 4)
            sys.memcopy(&lkcal.new_counter, &sync_counter, 4)
        if lkcal.nconf != 0 {
            set_message("synced. conflicts: ")
            add_num("", lkcal.nconf)
            void strings.append(message, " - press f3.")
        } else {
            set_message("synced. out +")
            add_num("", lkcal.created)
            add_num(" *", lkcal.updated)
            add_num(" -", lkcal.deleted)
            add_num("  in ", lkcal.received)
        }
    }

    sub field_name(ubyte f) -> str {
        when f {
            0 -> return "event"
            1 -> return "date"
            2 -> return "time"
        }
        return "text"
    }

    sub show_conflicts() {
        ubyte i
        ubyte y
        uword p
        repeat {
            txt.clear_screen()
            txt.plot(GX, 0)
            txt.print("SYNC CONFLICTS")
            txt.plot(GX, 1)
            txt.print("both sides changed; one version kept")
            y = 3
            if lkcal.nconf_got == 0 {
                txt.plot(GX, y)
                if count_conflicts() != 0
                    txt.print("details: press f1 to sync first.")
                else
                    txt.print("no conflicts.")
            } else {
                for i in 0 to lkcal.nconf_got - 1 {
                    if y > 24
                        break
                    txt.plot(GX, y)
                    p = lkcal.conf_slot[i]
                    if lsb(p) < MAXEV and @(rec(lsb(p))) != 0 {
                        p = rec(lsb(p))
                        txt.print_uw(2000 + @(p+1))
                        txt.chrout('-')
                        print_2d(@(p+2))
                        txt.chrout('-')
                        print_2d(@(p+3))
                        txt.chrout(' ')
                        txt.print(p + 4)
                    } else
                        txt.print("(event not on x16)")
                    txt.plot(GX + 1, y + 1)
                    when lkcal.conf_kind[i] {
                        1 -> txt.print("deleted here, edited in owncloud:")
                        2 -> txt.print("edited here, deleted in owncloud.")
                        else -> {
                            txt.print(field_name(lkcal.conf_field[i]))
                            txt.print(" changed on both; owncloud had:")
                        }
                    }
                    txt.plot(GX + 2, y + 2)
                    if lkcal.conf_kind[i] != 2
                        txt.print(lkcal.conf_text + (i as uword) * lkcal.CTXT)
                    txt.plot(GX + 1, y + 3)
                    if lkcal.conf_kept[i] == 0
                        txt.print("kept: x16 version")
                    else
                        txt.print("kept: owncloud version")
                    y += 5
                }
                if lkcal.nconf > lkcal.nconf_got {
                    txt.plot(GX, 25)
                    txt.print("(more on the hub: calsync conflicts)")
                }
            }
            txt.plot(GX, 27)
            txt.print("A=ACKNOWLEDGE ALL   ESC=BACK")
            ubyte k = wait_key()
            if k == 27 or k == 3 or k == 134
                return
            if k == 'a' or k == 'A' {
                lkcal.ack_all()
                lkcal.nconf_got = 0
                lkcal.nconf = 0
                set_message("acknowledged; cleared at next sync.")
                return
            }
        }
    }

    sub set_message(str msg) {
        void strings.copy(msg, message)
    }

    ; ---------- editing ----------

    sub add_event() {
        if count_events(sel_year, sel_month, sel_day) >= MAXDAY {
            set_message("too many events on this day.")
            return
        }
        ubyte slot = free_slot()
        if slot == 255 {
            set_message("calendar is full!")
            return
        }
        clear_prompt_rows()
        txt.print("new event (enter=save, esc=cancel):")
        txt.plot(GX, 29)
        txt.print("> ")
        str buf = " " * 28
        if read_line(buf, TXTMAX) {
            uword p = rec(slot)
            @(p) = 1
            @(p+1) = lsb(sel_year - 2000)
            @(p+2) = sel_month
            @(p+3) = sel_day
            void strings.copy(buf, p+4)
            save_events()
        } else
            set_message("cancelled.")
    }

    sub delete_event() {
        ubyte n = count_events(sel_year, sel_month, sel_day)
        if n == 0 {
            set_message("nothing to delete on this day.")
            return
        }
        clear_prompt_rows()
        txt.print("delete event number? (esc=cancel)")
        ubyte key = wait_key()
        if key >= '1' and key <= '9' {
            ubyte idx = nth_event(sel_year, sel_month, sel_day, key - '1')
            if idx != 255 {
                @(rec(idx)) = 0
                save_events()
                return
            }
        }
        set_message("cancelled.")
    }

    ; Simple line editor. Returns true on ENTER (with at least 1 char), false on ESC.
    sub clear_prompt_rows() {
        ubyte i
        txt.plot(0, 28)
        for i in 1 to 39
            txt.chrout(' ')
        txt.plot(0, 29)
        for i in 1 to 39
            txt.chrout(' ')
        txt.plot(GX, 28)
    }

    sub read_line(str buffer, ubyte maxlen) -> bool {
        ubyte count = 0
        buffer[0] = 0
        repeat {
            txt.chrout(166)      ; cursor-ish block
            ubyte key = wait_key()
            txt.chrout(157)      ; step back over the cursor...
            txt.chrout(' ')      ; ...erase it
            txt.chrout(157)
            when key {
                13 -> {
                    return count > 0
                }
                27 -> return false
                20 -> {              ; backspace/delete
                    if count > 0 {
                        count--
                        buffer[count] = 0
                        txt.chrout(157)
                        txt.chrout(' ')
                        txt.chrout(157)
                    }
                }
                else -> {
                    if count < maxlen and ((key >= 32 and key <= 126) or (key >= 193 and key <= 218)) {
                        buffer[count] = key
                        count++
                        buffer[count] = 0
                        txt.chrout(key)
                    }
                }
            }
        }
    }

    sub wait_key() -> ubyte {
        repeat {
            ubyte k = cbm.GETIN2()
            if k != 0
                return k
        }
    }

    ; ---------- drawing ----------

    sub print_2d(ubyte v) {
        if v < 10
            txt.chrout(' ')
        txt.print_ub(v)
    }

    const ubyte GX = 2              ; left edge of the grid
    const ubyte CW = 5              ; cell pitch (border + 4 inner chars)
    const ubyte GY = 4              ; top border row of the grid

    sub draw_grid_lines() {
        ubyte w
        ubyte c
        ubyte x
        for w in 0 to 6 {
            ; horizontal border row
            txt.plot(GX, GY + w*2)
            for c in 0 to 6 {
                txt.chrout(219)
                txt.chrout(192)
                txt.chrout(192)
                txt.chrout(192)
                txt.chrout(192)
            }
            txt.chrout(219)
            if w < 6 {
                ; vertical borders of the week row below it
                for c in 0 to 7 {
                    x = GX + c*CW
                    txt.plot(x, GY + 1 + w*2)
                    txt.chrout(221)
                }
            }
        }
    }

    sub draw_screen() {
        txt.clear_screen()
        txt.plot(GX, 0)
        txt.print("COMMANDER X16 CALENDAR")

        txt.plot(GX, 1)
        txt.print(names[sel_month-1])
        txt.chrout(' ')
        txt.print_uw(sel_year)

        ubyte col
        ubyte row
        for col in 0 to 6 {
            txt.plot(GX + 1 + col*CW, 3)
            txt.print(dow_names[col])
        }

        draw_grid_lines()

        ; day cells
        ubyte first = day_of_week(sel_year, sel_month, 1)
        ubyte dim = days_in_month(sel_year, sel_month)
        ubyte d
        for d in 1 to dim {
            ubyte cell = first + d - 1
            col = cell % 7
            row = cell / 7
            txt.plot(GX + 1 + col*CW, GY + 1 + row*2)
            bool selected = d == sel_day
            bool is_today = sel_year == today_year and sel_month == today_month and d == today_day
            if selected
                txt.chrout(18)             ; reverse on
            if is_today
                txt.chrout(158)            ; yellow
            txt.chrout(' ')
            print_2d(d)
            if count_events(sel_year, sel_month, d) != 0
                txt.chrout('*')
            else
                txt.chrout(' ')
            if is_today
                txt.chrout(5)              ; back to white
            if selected
                txt.chrout(146)            ; reverse off
        }

        ; events of the selected day
        txt.plot(GX, 18)
        txt.print("EVENTS ON ")
        txt.print_uw(sel_year)
        txt.chrout('-')
        if sel_month < 10
            txt.chrout('0')
        txt.print_ub(sel_month)
        txt.chrout('-')
        if sel_day < 10
            txt.chrout('0')
        txt.print_ub(sel_day)
        txt.chrout(':')

        ubyte n
        ubyte shown = 0
        for n in 0 to MAXEV-1 {
            if rec_matches(n, sel_year, sel_month, sel_day) and shown < MAXDAY {
                txt.plot(GX + 1, 19 + shown)
                txt.print_ub(shown + 1)
                if @(rec(n)) & F_CONFLICT != 0
                    txt.print("!")
                else
                    txt.print(".")
                txt.chrout(' ')
                txt.print(rec(n) + 4)
                shown++
            }
        }
        if shown == 0 {
            txt.plot(GX + 1, 19)
            txt.print("(none)")
        }

        ; help and status
        txt.plot(GX, 26)
        txt.print("CTRL+  A=ADD  D=DELETE  T=TODAY")
        txt.plot(GX, 27)
        txt.print("       N/P=MONTH  F/B=YEAR  X=QUIT")
        txt.plot(GX, 25)
        txt.print("F1=SYNC OWNCLOUD  F3=CONFLICTS")
        ubyte nc = count_conflicts()
        if nc != 0 {
            txt.print(" !")
            txt.print_ub(nc)
        }
        txt.plot(GX, 29)
        txt.print(message)
        message[0] = 0
    }
}
