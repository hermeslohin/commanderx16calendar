; themetest.p8 - themes, headless (test/run_themetest.sh): X16 Calendar's real code with the theme
; files X16THEME1..6.BIN on the host file system. No X16THEME.CFG -> theme 1 (exactly the built-in
; Sunset Arcade), clicking Quill goes through all six themes and back to the first, X16THEME.CFG
; brings back the chosen theme. Every theme goes into snap.gif twice: the month view with events,
; then the entry bar while adding an event with a dialog on top. Prints PASS/FAIL lines and DONE.
%import calapp
%zeropage basicsafe

main {
    ubyte fails

    sub check(bool ok, str what) {
        txt.print(what)
        if ok
            txt.print(iso:"  PASS\r")
        else {
            txt.print(iso:"  FAIL\r")
            fails++
        }
    }

    ; an event on day d of November 2026, text in PETSCII-compatible ISO
    sub add(ubyte d, str s) {
        cal.sel_day = d
        cal.scan_month()
        app.start_edit(255, 0)
        ubyte i = 0
        while s[i] != 0 {
            app.e_insert(s[i])
            i++
        }
        void app.commit()
    }

    sub frame() {
        repeat 30 {
            sys.waitvsync()
            theme.tick()
        }
        @($9fb5) = 1                    ; x16emu: one frame into snap.gif
        sys.wait(4)
    }

    ; the month view, then the entry bar and a dialog (drawn without waiting for a click)
    sub snap() {
        cal.sel_day = 18
        cal.scan_month()
        cv.sel_ev = cal.event_of(18, 1)
        cv.redraw_everything()
        app.hover(0, cv.STATUS_ROW)     ; Quill's tool tip
        frame()
        app.start_edit(255, 0)
        app.e_insert(iso:'G')
        app.e_insert(iso:'y')
        app.e_insert(iso:'m')
        cv.draw_ebar()
        void cal.text_iso(cv.sel_ev, &cv.tb, cal.TXTMAX)
        cv.title_box(18, 11, 44, 6, iso:"Please confirm", vid.C_RED)
        cv.put(20, 13, iso:"Delete this event?", 0, cv.dbg())
        cv.put(20, 14, &cv.tb, vid.C_BLUE, cv.dbg())
        cv.button(24, 15, iso:" Yes ")
        cv.button(46, 15, iso:" No ")
        cv.title_box(4, 20, 40, 5, iso:"Sync conflicts", vid.C_PURPLE)
        cv.put(6, 22, iso:"2026-11-20", vid.C_BLACK, cv.dbg())
        vid.text(18, 22, iso:"kept: X16", vid.S_BOLD, vid.C_RED, cv.dbg())
        frame()
        app.cancel_edit()
    }

    ubyte[64] rl0
    ubyte[32] dk0
    ubyte[6] desks

    sub start() {
        txt.iso()
        void diskio.delete(iso:"X16THEME.CFG")
        void diskio.delete(iso:"CALENDAR.DAT")
        void cal.load_events()
        sys.memcopy(&theme.rl, &rl0, 64)
        sys.memcopy(&theme.dk, &dk0, 32)
        vid.load_fonts()
        vid.gfx_init()
        cv.upload_icons()
        theme.init()
        cal.today_year = 2026
        cal.today_month = 11
        cal.today_day = 18
        cal.goto_today()

        check(theme.cur == 1, iso:"no X16THEME.CFG: theme 1")
        check(sys.memcmp(&theme.rl, &rl0, 64) == 0 and sys.memcmp(&theme.dk, &dk0, 32) == 0, iso:"theme 1 = the built-in Sunset Arcade roles and desk")
        ; the palette theme 1 put into VERA = vid.p8's Sunset palette
        ubyte i
        bool same = true
        cx16.vaddr(1, $fa00, 0, 1)
        for i in 0 to 15 {
            if cx16.VERA_DATA0 != vid.pal_lo[i] or cx16.VERA_DATA0 != vid.pal_hi[i]
                same = false
        }
        check(same, iso:"theme 1 palette = Sunset Arcade")

        ; some events: three on the 18th (today), chips on other days, a sync conflict on the 20th
        add(18, iso:"09:00 Standup")
        add(18, iso:"12:30 Team lunch")
        add(18, iso:"14:30 Dentist")
        add(20, iso:"Dad's birthday")
        add(20, iso:"18:00 Dinner")
        add(3, iso:"Book club")
        add(11, iso:"10:00 Vet")
        add(27, iso:"Thanksgiving")
        add(28, iso:"Bake sale")
        add(28, iso:"Movie night")
        add(28, iso:"Call Ruth")
        add(14, iso:"Recycling")
        @(cal.rec(cal.event_of(20, 1))) |= cal.F_CONFLICT
        cal.sel_day = 18

        app.hover(0, cv.STATUS_ROW)
        check(strings.compare(cv.status_msg, theme.tip) == 0, iso:"hovering Quill shows its tip")
        desks[0] = theme.rl[theme.R_DESK]
        snap()
        for i in 2 to 6 {
            app.press(0, cv.STATUS_ROW)             ; click Quill
            app.release(0, cv.STATUS_ROW)
            check(theme.cur == i and strings.compare(cv.status_msg, theme.msg) == 0, iso:"Quill: next theme")
            desks[i - 1] = theme.rl[theme.R_DESK]
            snap()
        }
        check(desks[1] == vid.C_ORANGE and desks[2] == vid.C_LGRAY and desks[4] == vid.C_DGRAY, iso:"each theme's desk colour")
        app.press(0, cv.STATUS_ROW)
        app.release(0, cv.STATUS_ROW)
        check(theme.cur == 1 and sys.memcmp(&theme.rl, &rl0, 64) == 0, iso:"after the last theme the first again")
        ; restart: the saved choice
        app.press(0, cv.STATUS_ROW)
        app.release(0, cv.STATUS_ROW)
        app.press(0, cv.STATUS_ROW)
        app.release(0, cv.STATUS_ROW)
        theme.cur = 0
        theme.rl[theme.R_DESK] = 99
        theme.init()
        check(theme.cur == 3 and theme.rl[theme.R_DESK] == vid.C_LGRAY, iso:"X16THEME.CFG brings back theme 3 (Comic Book)")
        check(theme.msg[7] == iso:'C' and theme.msg[13] == iso:'B', iso:"its name for the status bar")
        check(cal.day_cnt[18] == 3 and cal.day_cnt[28] == 3, iso:"the events are still there")

        if fails == 0
            txt.print(iso:"ALL PASS\r")
        else
            txt.print(iso:"SOME FAILED\r")
        txt.print(iso:"DONE\r")
        repeat { }
    }
}
