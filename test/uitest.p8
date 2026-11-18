; uitest.p8 - drives X16 Calendar's real code (calapp/calview/caldata) with clicks, typing and
; toolbar buttons, checks the records, reloads CALENDAR.DAT, prints PASS/FAIL and DONE at the end.
; It also writes the final screen (VERA bitmap) to SHOT.BIN; test/shot2png.py turns it into a PNG.
%import calapp
%zeropage basicsafe

main {
    ubyte fails
    ubyte dx
    ubyte dy

    sub check(bool ok, str what) {
        txt.print(what)
        if ok
            txt.print(iso:"  PASS\r")
        else {
            txt.print(iso:"  FAIL\r")
            fails++
        }
    }

    sub typ(str s) {
        ubyte i = 0
        while s[i] != 0 {
            if cv.editing
                app.edit_key(s[i])
            else
                app.nav_key(s[i])
            i++
        }
    }

    sub click(ubyte cx, ubyte cy) {
        app.press(cx, cy)
        app.release(cx, cy)
    }

    ; screen position of line ln (0..2) of a day of the shown month
    sub dayxy(ubyte d, ubyte ln) {
        cv.grid_setup()
        ubyte k = cv.g_first + d - 1
        dx = cv.GXL + (k % 7) * cv.CW + 3
        dy = cv.GRID0 + (k / 7) * 3 + ln
    }

    ; is slot's stored text (PETSCII) equal to the ISO string want?
    sub text_is(ubyte slot, str want) -> bool {
        ubyte[32] t
        void cal.text_iso(slot, &t, 27)
        return strings.compare(&t, want) == 0
    }

    sub find(str want) -> ubyte {
        ubyte i
        for i in 0 to cal.MAXEV - 1 {
            if @(cal.rec(i)) != 0 and text_is(i, want)
                return i
        }
        return 255
    }

    sub start() {
        txt.iso()
        void cal.load_events()
        vid.load_fonts()
        vid.gfx_init()
        cv.upload_icons()
        theme.init()
        cal.today_year = 2026
        cal.today_month = 11
        cal.today_day = 18
        cal.goto_today()
        cal.scan_month()
        cv.redraw_everything()

        ; add by typing (the first key opens the entry), add with the toolbar, add with a double-click
        typ(iso:"Team lunch\r")
        click(1, cv.TOOL)
        typ(iso:"14:30 Dentist\r")
        dayxy(18, 0)
        click(dx, dy)
        click(dx, dy)
        check(cv.editing and cv.edit_slot == 255, iso:"double-click day opens new entry")
        typ(iso:"09:00 Standup\r")
        check(cal.day_cnt[18] == 3, iso:"3 events on the 18th")
        check(text_is(cal.event_of(18, 0), iso:"09:00 Standup"), iso:"sorted: standup first")
        check(text_is(cal.event_of(18, 2), iso:"Team lunch"), iso:"sorted: lunch last")
        ubyte s = find(iso:"14:30 Dentist")
        check(s != 255 and @(cal.rec(s)) == 1 and @(cal.rec(s) + 1) == 26 and @(cal.rec(s) + 2) == 11 and @(cal.rec(s) + 3) == 18, iso:"record bytes")
        check(@(cal.rec(s) + 4) == $31 and @(cal.rec(s) + 10) == $c4 and @(cal.rec(s) + 11) == $45, iso:"PETSCII text")

        ; click the 2nd list row, double-click it to edit, change the text
        click(10, cv.LIST0 + 1)
        check(cv.sel_ev == s, iso:"click selects event in list")
        click(10, cv.LIST0 + 1)
        check(cv.editing and cv.edit_slot == s, iso:"double-click edits event")
        typ(iso:"\x14\x14\x14\x14\x14\x14\x14Doctor\r")
        check(text_is(s, iso:"14:30 Doctor"), iso:"edited text")
        check(@(cal.rec(s)) == 3, iso:"edit sets flag bit1")

        ; drag the event from the list onto the 20th
        dayxy(20, 1)
        app.press(10, cv.LIST0 + 1)
        app.drag(30, 26)
        app.drag(dx, dy)
        app.release(dx, dy)
        check(@(cal.rec(s) + 3) == 20 and cal.sel_day == 20 and cv.sel_ev == s, iso:"drag moves event to the 20th")

        ; copy, click the 21st, paste
        click(15, cv.TOOL)
        dayxy(21, 0)
        click(dx, dy)
        click(18, cv.TOOL)
        check(cal.day_cnt[21] == 1 and text_is(cal.event_of(21, 0), iso:"14:30 Doctor"), iso:"copy + paste")

        ; delete with the toolbar: No keeps it, Yes deletes it
        click(10, cv.LIST0)
        cv.keyscript = iso:"n"
        click(7, cv.TOOL)
        check(cal.day_cnt[21] == 1, iso:"delete: No keeps it")
        cv.keyscript = iso:"y"
        click(7, cv.TOOL)
        check(cal.day_cnt[21] == 0, iso:"delete: Yes deletes it")

        ; next / previous month buttons, wheel-free navigation, keys
        click(34, cv.TOOL)
        check(cal.sel_month == 12, iso:"next month button")
        app.nav_key($82)
        check(cal.sel_month == 11, iso:"PgUp")
        app.nav_key($1d)
        check(cal.sel_day == 22, iso:"cursor right")
        click(23, cv.TOOL)
        check(cal.sel_day == 18, iso:"today button")
        ; click a grayed day of the next month
        dayxy(30, 0)
        click(dx + cv.CW, dy)
        check(cal.sel_month == 12 and cal.sel_day == 1, iso:"click next month's day")
        click(23, cv.TOOL)
        typ(iso:"Pay rent {now}\r")
        check(find(iso:"Pay rent (now)") != 255, iso:"ISO folding like the hub")

        ; reload from disk
        void cal.load_events()
        cal.scan_month()
        check(cal.day_cnt[18] == 3 and cal.day_cnt[20] == 1, iso:"reload CALENDAR.DAT")

        ; final screen: select the Doctor event on the 20th and hover a tool tip
        cal.sel_day = 18
        click(10, cv.LIST0 + 1)
        cal.scan_month()
        cv.redraw_everything()
        app.hover(1, cv.TOOL)
        shot()

        if fails == 0
            txt.print(iso:"ALL PASS\r")
        txt.print(iso:"DONE\r")
        repeat { }
    }

    ubyte[256] buf
    sub shot() {
        if not diskio.f_open_w(iso:"@:SHOT.BIN")
            return
        uword i
        for i in 0 to 299 {
            cx16.vaddr(lsb(i >> 8), i << 8, 0, 1)
            ubyte j = 0
            repeat 256 {
                buf[j] = cx16.VERA_DATA0
                j++
            }
            void diskio.f_write(&buf, 256)
        }
        diskio.f_close_w()
    }
}
