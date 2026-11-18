; caldata.p8 - X16 Calendar's data: the 128 event records (CALENDAR.DAT, format in FORMAT.md),
; date arithmetic, the per-day index of the month on screen, and the PETSCII <-> ISO conversion.
; The records keep their PETSCII text (the hub and older versions of the app expect it); the screen
; and keyboard run in ISO mode like X16 Write and X16 Sheets, so text is converted at the edges.

%import syslib
%import diskio
%import strings

cal {
    %option ignore_unused

    const ubyte MAXEV = 128         ; max number of stored events
    const ubyte TXTMAX = 27         ; max characters in an event description
    const ubyte MAXDAY = 6          ; max events per day
    const uword FILESZ = 4096       ; MAXEV * 32
    const ubyte F_EDITED = 2        ; flag bit1: edited in place (see SYNC-PLAN.md)
    const ubyte F_CONFLICT = 4      ; flag bit2: sync conflict (set by the hub)
    str FILENAME = iso:"CALENDAR.DAT"
    str SAVENAME = iso:"@:CALENDAR.DAT"

    ; record layout: +0 flags (0 = free), +1 year-2000, +2 month, +3 day, +4.. text (PETSCII, 0-terminated)
    uword events = memory("events", FILESZ, 0)

    uword sel_year = 2026
    ubyte sel_month = 1
    ubyte sel_day = 1
    uword today_year = 0
    ubyte today_month = 0
    ubyte today_day = 0

    ubyte[12] mdays = [31,28,31,30,31,30,31,31,30,31,30,31]
    ubyte[12] sakamoto = [0,3,2,5,0,3,5,1,4,6,2,4]
    str[12] names = [iso:"January", iso:"February", iso:"March", iso:"April", iso:"May", iso:"June",
                     iso:"July", iso:"August", iso:"September", iso:"October", iso:"November", iso:"December"]
    str[7] dow_short = [iso:"Sun", iso:"Mon", iso:"Tue", iso:"Wed", iso:"Thu", iso:"Fri", iso:"Sat"]
    str[7] dow_long = [iso:"Sunday", iso:"Monday", iso:"Tuesday", iso:"Wednesday", iso:"Thursday",
                       iso:"Friday", iso:"Saturday"]

    ; events of each day of the selected month, sorted by text (so "HH:MM " times come first)
    ubyte[32] day_cnt               ; index = day 1..31
    ubyte[186] day_ev               ; (day-1)*MAXDAY + k -> slot
    ubyte nused                     ; used slots in the whole file

    ; ---------- dates ----------

    sub is_leap(uword y) -> bool {
        ; (kept as separate statements: Prog8 12.3.5's optimizer crashes on "return y % 4 == 0")
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

    ; read the real-time clock and open on today's date (stays on January 2026 if the clock is unset)
    sub get_today() {
        cx16.r0 = 0
        cx16.r1 = 0
        cx16.r2 = 0
        cx16.r3 = 0
        cx16.clock_get_date_time()
        uword yr = 1900 + (cx16.r0 & 255)
        ubyte mo = lsb(cx16.r0 >> 8)
        ubyte dy = lsb(cx16.r1)
        if yr >= 2000 and yr <= 2200 and mo >= 1 and mo <= 12 and dy >= 1 and dy <= 31 {
            today_year = yr
            today_month = mo
            today_day = dy
            goto_today()
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
            if sel_year == 2200 and sel_month == 12
                return
            sel_month++
            if sel_month > 12 {
                sel_month = 1
                sel_year++
            }
        } else {
            if sel_year == 2000 and sel_month == 1
                return
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
        word d = sel_day as word
        d += delta
        if d < 1 {
            if sel_year == 2000 and sel_month == 1
                return
            change_month(-1)
            d += days_in_month(sel_year, sel_month) as word
        } else {
            ubyte dim = days_in_month(sel_year, sel_month)
            if d > (dim as word) {
                if sel_year == 2200 and sel_month == 12
                    return
                d -= dim as word
                change_month(1)
            }
        }
        sel_day = lsb(d as uword)
    }

    ; ---------- records ----------

    sub rec(ubyte idx) -> uword {
        return events + ((idx as uword) << 5)
    }

    sub on_day(ubyte idx, uword y, ubyte m, ubyte d) -> bool {
        uword p = rec(idx)
        if @(p) == 0
            return false
        return @(p+1) == lsb(y - 2000) and @(p+2) == m and @(p+3) == d
    }

    sub count_on(uword y, ubyte m, ubyte d) -> ubyte {
        ubyte n = 0
        ubyte i
        for i in 0 to MAXEV-1 {
            if on_day(i, y, m, d)
                n++
        }
        return n
    }

    sub free_slot() -> ubyte {
        ubyte i
        for i in 0 to MAXEV-1 {
            if @(rec(i)) == 0
                return i
        }
        return 255
    }

    ; rebuild day_cnt / day_ev for the selected month and count the used slots
    sub scan_month() {
        sys.memset(&day_cnt, 32, 0)
        nused = 0
        ubyte yb = lsb(sel_year - 2000)
        ubyte i
        for i in 0 to MAXEV-1 {
            uword p = rec(i)
            if @(p) == 0
                continue
            nused++
            if @(p+1) != yb or @(p+2) != sel_month
                continue
            ubyte d = @(p+3)
            if d == 0 or d > 31
                continue
            ubyte n = day_cnt[d]
            if n >= MAXDAY
                continue
            ubyte base = (d - 1) * MAXDAY
            ubyte k = n
            while k != 0 {
                if not text_less(p + 4, rec(day_ev[base + k - 1]) + 4)
                    break
                day_ev[base + k] = day_ev[base + k - 1]
                k--
            }
            day_ev[base + k] = i
            day_cnt[d] = n + 1
        }
    }

    ; a < b, byte by byte unsigned (strings.compare would put the shifted capitals $C1-$DA first)
    sub text_less(uword a, uword b) -> bool {
        ubyte i
        for i in 0 to TXTMAX - 1 {
            ubyte ca = @(a + i)
            ubyte cb = @(b + i)
            if ca != cb
                return ca < cb
            if ca == 0
                return false
        }
        return false
    }

    ; k-th event (sorted) of day d of the selected month
    sub event_of(ubyte d, ubyte k) -> ubyte {
        return day_ev[(d - 1) * MAXDAY + k]
    }

    ; position of a slot in the selected day's list, 255 if it isn't there
    sub pos_in_day(ubyte slot) -> ubyte {
        ubyte k
        ubyte n = day_cnt[sel_day]
        if n == 0
            return 255
        for k in 0 to n - 1 {
            if event_of(sel_day, k) == slot
                return k
        }
        return 255
    }

    sub day_has_conflict(ubyte d) -> bool {
        ubyte n = day_cnt[d]
        ubyte k
        if n == 0
            return false
        for k in 0 to n - 1 {
            if @(rec(event_of(d, k))) & F_CONFLICT != 0
                return true
        }
        return false
    }

    ; 0 = no file (new calendar), 1 = loaded, 2 = load error.
    ; Reads at most the 2-byte PRG header + 4096 bytes: an oversized file can't run past the slab.
    bool dat_loaded                 ; CALENDAR.DAT was read: the sync counter may be trusted
    ubyte[2] hdr
    sub load_events() -> ubyte {
        sys.memset(events, FILESZ, 0)
        dat_loaded = false
        if not diskio.exists(FILENAME)
            return 0
        if not diskio.f_open(FILENAME)
            return 2
        bool ok = diskio.f_read(&hdr, 2) == 2
        if ok
            void diskio.f_read(events, FILESZ)
        diskio.f_close()
        if not ok {
            sys.memset(events, FILESZ, 0)
            return 2
        }
        dat_loaded = true
        return 1
    }

    ; ---------- ownCloud sync counter (CALSYNC.DAT: 4 bytes, no header) ----------
    str CNTNAME = iso:"CALSYNC.DAT"
    str CNTSAVE = iso:"@:CALSYNC.DAT"
    ubyte[4] sync_counter

    ; read at most 4 bytes; 0 (= a full, non-destructive sync) if CALENDAR.DAT wasn't read or the
    ; counter is missing / damaged
    sub load_counter() {
        sys.memset(&sync_counter, 4, 0)
        if not dat_loaded
            return
        if diskio.f_open(CNTNAME) {
            if diskio.f_read(&sync_counter, 4) != 4
                sys.memset(&sync_counter, 4, 0)
            diskio.f_close()
        }
    }

    sub save_counter(uword c) -> bool {
        if not diskio.save_raw(CNTSAVE, c, 4)
            return false
        sys.memcopy(c, &sync_counter, 4)
        return true
    }

    sub count_conflicts() -> ubyte {
        ubyte n = 0
        ubyte i
        for i in 0 to MAXEV - 1 {
            if @(rec(i)) & F_CONFLICT != 0
                n++
        }
        return n
    }

    sub save_events() -> bool {
        return diskio.save(SAVENAME, events, FILESZ)
    }

    ; ---------- text ----------

    ; PETSCII (lowercase/uppercase set, as stored) -> ISO for the screen
    sub to_iso(ubyte c) -> ubyte {
        if c >= $41 and c <= $5a
            return c + $20              ; a-z
        if c >= $c1 and c <= $da
            return c - $80              ; A-Z
        if c >= $61 and c <= $7a
            return c - $20              ; C64 duplicates of A-Z
        if c >= $20 and c <= $40
            return c
        when c {
            $5b -> return $5b           ; [
            $5d -> return $5d           ; ]
            $5c -> return 163           ; pound
            $5e -> return $5e           ; up arrow -> ^
            $5f -> return $5f           ; left arrow -> _
        }
        return $3f                      ; ?
    }

    ; ISO keyboard code -> PETSCII to store, 0 = can't be stored. Folds like the hub does (FORMAT.md).
    sub to_pet(ubyte c) -> ubyte {
        if c >= $61 and c <= $7a
            return c - $20              ; a-z
        if c >= $41 and c <= $5a
            return c + $80              ; A-Z
        if c >= $20 and c <= $40
            return c
        when c {
            $5b -> return $5b           ; [
            $5d -> return $5d           ; ]
            163 -> return $5c           ; pound
            $5e -> return $5e           ; ^ -> up arrow
            $5c -> return $2f           ; \ -> /
            $7b -> return $28           ; { -> (
            $7d -> return $29           ; } -> )
            $7c -> return $21           ; | -> !
            $7e, $5f -> return $2d      ; ~ _ -> -
            $60 -> return $27           ; ` -> '
        }
        return 0
    }

    ; copy a record's text into dst as ISO, at most maxn chars; returns the length
    sub text_iso(ubyte slot, uword dst, ubyte maxn) -> ubyte {
        uword p = rec(slot) + 4
        ubyte n = 0
        while n < maxn and n < TXTMAX and @(p + n) != 0 {
            @(dst + n) = to_iso(@(p + n))
            n++
        }
        @(dst + n) = 0
        return n
    }

    ; store n ISO chars as the record's text (0-terminated, rest zeroed). true if the text changed
    sub set_text(ubyte slot, uword src, ubyte n) -> bool {
        ubyte[28] nt
        sys.memset(&nt, 28, 0)
        ubyte i
        ubyte j = 0
        if n > TXTMAX
            n = TXTMAX
        if n != 0 {
            for i in 0 to n - 1 {
                ubyte c = to_pet(@(src + i))
                if c != 0 {
                    nt[j] = c
                    j++
                }
            }
        }
        uword p = rec(slot) + 4
        bool same = strings.compare(p, &nt) == 0
        sys.memcopy(&nt, p, 28)
        return not same
    }
}
