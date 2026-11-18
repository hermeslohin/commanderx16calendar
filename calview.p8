; calview.p8 - X16 Calendar's screen, in the style of X16 Write / X16 Sheets (same renderer, colours,
; icons, title bar, tool tips in the status bar and dialogs).
;
;  row 0      title bar                                   (quit icon at the right)
;  row 1      icon toolbar (incl. ownCloud Sync and Conflicts) + month name
;  row 2      entry bar: date | cancel | accept | event text   (like Sheets' formula bar)
;  row 3      weekday headers
;  rows 4-21  month grid: 6 weeks x 3 rows (day number, 2 event lines), 7 columns of 11
;  row 22     selected day heading
;  rows 23-28 the selected day's events (6 at most)
;  row 29     status bar

%import syslib
%import conv
%import strings
%import vid
%import icons
%import caldata

cv {
    %option ignore_unused

    const ubyte TOOL = 1
    const ubyte EBAR = 2
    const ubyte HDR = 3
    const ubyte GRID0 = 4
    const ubyte GRIDN = 18
    const ubyte DAYHDR = 22
    const ubyte LIST0 = 23
    const ubyte STATUS_ROW = 29
    const ubyte GXL = 1                 ; left edge of the grid
    const ubyte CW = 11                 ; cell width (the last char carries the grid line)
    const ubyte GXR = GXL + 7 * CW      ; first column right of the grid
    const ubyte EDX = 20                ; entry bar text field
    const ubyte EDW = 29
    const ubyte LTX = 6                 ; event text in the day list

    ; button ids
    const ubyte B_ADD = 1
    const ubyte B_EDIT = 2
    const ubyte B_DEL = 3
    const ubyte B_CUT = 4
    const ubyte B_COPY = 5
    const ubyte B_PASTE = 6
    const ubyte B_TODAY = 7
    const ubyte B_PREVY = 8
    const ubyte B_PREVM = 9
    const ubyte B_NEXTM = 10
    const ubyte B_NEXTY = 11
    const ubyte B_QUIT = 12
    const ubyte B_ECANCEL = 13
    const ubyte B_EOK = 14
    const ubyte B_SYNC = 15
    const ubyte B_CONF = 16

    ubyte[24] bt_x
    ubyte[24] bt_y
    ubyte[24] bt_id
    ubyte bt_n

    ; ---------------- UI state (changed by app) ----------------
    ubyte sel_ev = 255                  ; selected event slot, 255 = none
    bool editing
    ubyte edit_slot = 255               ; slot being edited, 255 = new event
    ubyte[32] ebuf                      ; entry text (ISO)
    ubyte elen
    ubyte ecur
    ubyte clip_len                      ; clipboard: one event text
    ubyte[28] clip
    ubyte drop_day                      ; day cell highlighted while dragging an event (0 = none)
    str status_msg = iso:"                                                                              "
    ubyte[32] tb

    sub set_status(uword s) {
        ubyte i = 0
        while @(s + i) != 0 and i < 78 {
            status_msg[i] = @(s + i)
            i++
        }
        status_msg[i] = 0
    }

    ; ---------------- row composition ----------------
    sub rclear(ubyte fg, ubyte bg) {
        ubyte x
        ubyte k = (bg << 4) | fg
        for x in 0 to 79 {
            vid.r_ch[x] = 32
            vid.r_sty[x] = 0
            vid.r_col[x] = k
        }
    }

    sub rcol(ubyte x0, ubyte x1, ubyte fg, ubyte bg) {
        ubyte x
        for x in x0 to x1
            vid.r_col[x] = (bg << 4) | fg
    }

    ; put a 0-terminated ISO string; returns the column after it
    sub rput(ubyte x, uword s, ubyte fg, ubyte bg, ubyte sty) -> ubyte {
        ubyte k = (bg << 4) | fg
        while @(s) != 0 and x < 80 {
            vid.r_ch[x] = @(s)
            vid.r_sty[x] = (vid.r_sty[x] & $c0) | sty
            vid.r_col[x] = k
            x++
            s++
        }
        return x
    }

    sub rnum(ubyte x, uword n, ubyte fg, ubyte bg, ubyte sty) -> ubyte {
        return rput(x, conv.str_uw(n), fg, bg, sty)
    }

    sub put(ubyte col, ubyte row, uword s, ubyte fg, ubyte bg) {
        vid.text(col, row, s, 0, fg, bg)
    }

    ; "YYYY-MM-DD" of the selected day into tb
    sub date_str() {
        uword s = conv.str_uw(cal.sel_year)
        void strings.copy(s, &tb)
        tb[4] = iso:'-'
        tb[5] = iso:'0' + cal.sel_month / 10
        tb[6] = iso:'0' + cal.sel_month % 10
        tb[7] = iso:'-'
        tb[8] = iso:'0' + cal.sel_day / 10
        tb[9] = iso:'0' + cal.sel_day % 10
        tb[10] = 0
    }

    ; ---------------- buttons ----------------
    sub add_btn(ubyte x, ubyte y, ubyte id) {
        ubyte i
        if bt_n != 0 {
            for i in 0 to bt_n - 1 {
                if bt_x[i] == x and bt_y[i] == y {
                    bt_id[i] = id
                    return
                }
            }
        }
        if bt_n < len(bt_x) {
            bt_x[bt_n] = x
            bt_y[bt_n] = y
            bt_id[bt_n] = id
            bt_n++
        }
    }

    sub icon(ubyte col, ubyte row, ubyte k, ubyte id, bool active) {
        ubyte bg = vid.C_WHITE
        if active
            bg = vid.C_LBLUE
        vid.r_ch[0] = k * 2
        vid.r_ch[1] = k * 2 + 1
        vid.r_sty[0] = vid.S_RAW | $30
        vid.r_sty[1] = vid.S_RAW | $30
        vid.r_col[0] = bg << 4
        vid.r_col[1] = bg << 4
        vid.render_run(row, col, 2)
        add_btn(col, row, id)
    }

    sub find_button(ubyte cx, ubyte cy) -> ubyte {
        ubyte i
        if bt_n == 0
            return 0
        for i in 0 to bt_n - 1 {
            if bt_y[i] == cy and (cx == bt_x[i] or cx == bt_x[i] + 1)
                return bt_id[i]
        }
        return 0
    }

    sub upload_icons() {
        ubyte k
        ubyte r
        sys.set_irqd()
        cx16.vaddr(1, vid.FONT_VRAM + 3 * 2048, 0, 1)
        for k in 0 to icons.COUNT - 1 {
            for r in 0 to 7
                cx16.VERA_DATA0 = icons.ic_hi[k * 8 + r]
            for r in 0 to 7
                cx16.VERA_DATA0 = icons.ic_lo[k * 8 + r]
        }
        sys.clear_irqd()
    }

    ; ---------------- title bar and toolbar ----------------
    sub draw_title() {
        rclear(vid.C_WHITE, vid.C_BLUE)
        void rput(1, iso:"X16 CALENDAR", vid.C_YELLOW, vid.C_BLUE, 0)
        void rput(14, iso:"-", vid.C_WHITE, vid.C_BLUE, 0)
        void rput(16, cal.FILENAME, vid.C_WHITE, vid.C_BLUE, 0)
        vid.render_run(0, 0, 80)
        icon(77, 0, icons.I_QUIT, B_QUIT, false)
    }

    sub draw_toolbar() {
        rclear(0, vid.C_LGRAY)
        ubyte x = rput(49, cal.names[cal.sel_month - 1], vid.C_BLACK, vid.C_LGRAY, vid.S_BOLD)
        void rnum(x + 1, cal.sel_year, vid.C_BLACK, vid.C_LGRAY, vid.S_BOLD)
        void rput(66, iso:"events", vid.C_DGRAY, vid.C_LGRAY, 0)
        x = rnum(73, cal.nused, vid.C_BLACK, vid.C_LGRAY, 0)
        void rput(x, iso:"/128", vid.C_DGRAY, vid.C_LGRAY, 0)
        vid.render_run(TOOL, 0, 80)
        icon(1, TOOL, icons.I_ADD, B_ADD, editing and edit_slot == 255)
        icon(4, TOOL, icons.I_EDIT, B_EDIT, editing and edit_slot != 255)
        icon(7, TOOL, icons.I_DEL, B_DEL, false)
        icon(12, TOOL, icons.I_CUT, B_CUT, false)
        icon(15, TOOL, icons.I_COPY, B_COPY, false)
        icon(18, TOOL, icons.I_PASTE, B_PASTE, clip_len != 0)
        icon(23, TOOL, icons.I_TODAY, B_TODAY, false)
        icon(28, TOOL, icons.I_PREVY, B_PREVY, false)
        icon(31, TOOL, icons.I_PREVM, B_PREVM, false)
        icon(34, TOOL, icons.I_NEXTM, B_NEXTM, false)
        icon(37, TOOL, icons.I_NEXTY, B_NEXTY, false)
        icon(42, TOOL, icons.I_SYNC, B_SYNC, false)
        icon(45, TOOL, icons.I_CONF, B_CONF, cal.count_conflicts() != 0)
    }

    ; ---------------- entry bar ----------------
    sub draw_ebar() {
        ubyte i
        rclear(0, vid.C_LGRAY)
        rcol(0, 11, vid.C_BLACK, vid.C_WHITE)
        date_str()
        void rput(1, &tb, vid.C_BLACK, vid.C_WHITE, 0)
        rcol(EDX, EDX + EDW - 1, vid.C_BLACK, vid.C_WHITE)
        if editing {
            for i in 0 to elen {
                if i < elen
                    vid.r_ch[EDX + 1 + i] = ebuf[i]
            }
            vid.r_col[EDX + 1 + ecur] = vid.C_WHITE         ; cursor: black block
            if edit_slot == 255
                void rput(EDX + EDW + 1, iso:"New event:", vid.C_DGRAY, vid.C_LGRAY, 0)
            else
                void rput(EDX + EDW + 1, iso:"Edit event:", vid.C_DGRAY, vid.C_LGRAY, 0)
            void rput(EDX + EDW + 13, iso:"Return saves, Esc cancels", vid.C_DGRAY, vid.C_LGRAY, 0)
        } else if sel_ev != 255 {
            i = cal.text_iso(sel_ev, &tb, cal.TXTMAX)
            void rput(EDX + 1, &tb, vid.C_BLACK, vid.C_WHITE, 0)
        }
        vid.render_run(EBAR, 0, 80)
        icon(13, EBAR, icons.I_QUIT, B_ECANCEL, false)
        icon(16, EBAR, icons.I_OK, B_EOK, false)
    }

    ; ---------------- month grid ----------------
    ubyte g_first                       ; weekday of the 1st
    ubyte g_dim                         ; days in the month
    ubyte g_pdim                        ; days in the previous month

    sub grid_setup() {
        g_first = cal.day_of_week(cal.sel_year, cal.sel_month, 1)
        g_dim = cal.days_in_month(cal.sel_year, cal.sel_month)
        if cal.sel_month == 1
            g_pdim = 31
        else
            g_pdim = cal.days_in_month(cal.sel_year, cal.sel_month - 1)
    }

    ; grid cell k (0..41) -> at_day, at_off (-1 previous month, 0 this month, 1 next month)
    ubyte at_day
    byte at_off
    sub day_at(ubyte k) {
        word d = (k as word) - (g_first as word) + 1
        at_off = 0
        if d < 1 {
            at_off = -1
            d += g_pdim as word
        } else if d > (g_dim as word) {
            at_off = 1
            d -= g_dim as word
        }
        at_day = lsb(d as uword)
    }

    sub draw_header() {
        ubyte c
        rclear(vid.C_BLACK, vid.C_LGRAY)
        ubyte sc = cal.day_of_week(cal.sel_year, cal.sel_month, cal.sel_day)
        for c in 0 to 6 {
            ubyte x = GXL + c * CW
            if c == sc
                rcol(x, x + CW - 1, vid.C_BLACK, vid.C_GRAY)
            vid.r_sty[x + CW - 1] = vid.S_GRIDR
            void rput(x + 4, cal.dow_short[c], vid.C_BLACK, vid.r_col[x] >> 4, 0)
        }
        vid.render_run(HDR, 0, 80)
    }

    sub draw_grid() {
        ubyte sr
        grid_setup()
        for sr in 0 to GRIDN - 1
            draw_grid_row(sr)
    }

    sub draw_week(ubyte wk) {
        ubyte sr
        grid_setup()
        for sr in wk * 3 to wk * 3 + 2
            draw_grid_row(sr)
    }

    sub draw_grid_row(ubyte sr) {
        ubyte wk = sr / 3
        ubyte ln = sr % 3
        ubyte c
        ubyte x
        ubyte i
        rclear(vid.C_BLACK, vid.C_LGRAY)
        for c in 0 to 6 {
            x = GXL + c * CW
            day_at(wk * 7 + c)
            ubyte d = at_day
            ubyte bg = vid.C_WHITE
            if at_off == 0 and d == cal.sel_day
                bg = vid.C_YELLOW
            if at_off == 0 and d == drop_day
                bg = vid.C_LGREEN
            rcol(x, x + CW - 1, vid.C_BLACK, bg)
            ubyte gs = vid.S_GRIDR
            if ln == 2
                gs = vid.S_GRIDR | vid.S_GRIDB
            for i in x to x + CW - 1
                vid.r_sty[i] = gs & vid.S_GRIDB
            vid.r_sty[x + CW - 1] = gs
            if ln == 0 {
                ; day number, today in a red box
                ubyte fg = vid.C_BLACK
                ubyte sty = vid.S_BOLD
                if at_off != 0 {
                    fg = vid.C_GRAY
                    sty = 0
                }
                ubyte nbg = bg
                if at_off == 0 and d == cal.today_day and cal.sel_month == cal.today_month and cal.sel_year == cal.today_year {
                    fg = vid.C_WHITE
                    nbg = vid.C_RED
                    rcol(x, x + 3, fg, nbg)
                }
                if d >= 10
                    vid.r_ch[x + 1] = iso:'0' + d / 10
                vid.r_ch[x + 2] = iso:'0' + d % 10
                vid.r_sty[x + 1] |= sty
                vid.r_sty[x + 2] |= sty
                rcol(x + 1, x + 2, fg, nbg)
                if at_off == 0 and cal.day_has_conflict(d) {
                    vid.r_ch[x + 9] = iso:'!'
                    vid.r_sty[x + 9] |= vid.S_BOLD
                    rcol(x + 9, x + 9, vid.C_RED, bg)
                }
            } else if at_off == 0 {
                ubyte n = cal.day_cnt[d]
                if ln == 2 and n > 2 {
                    tb[0] = iso:'+'
                    void strings.copy(conv.str_ub(n - 1), &tb + 1)
                    void strings.append(&tb, iso:" more")
                    void rput(x + 1, &tb, vid.C_DGRAY, bg, 0)
                } else if ln - 1 < n {
                    ubyte slot = cal.event_of(d, ln - 1)
                    ubyte efg = vid.C_BLUE
                    ubyte ebg = bg
                    if @(cal.rec(slot)) & cal.F_CONFLICT != 0
                        efg = vid.C_RED
                    if slot == sel_ev {
                        efg = vid.C_WHITE
                        ebg = vid.C_BLUE
                        rcol(x, x + CW - 2, efg, ebg)
                    }
                    void cal.text_iso(slot, &tb, CW - 1)
                    void rput(x + 1, &tb, efg, ebg, 0)
                }
            }
        }
        vid.render_run(GRID0 + sr, 0, 80)
    }

    ; ---------------- selected day ----------------
    sub draw_dayhdr() {
        rclear(vid.C_WHITE, vid.C_BLUE)
        ubyte x = rput(1, cal.dow_long[cal.day_of_week(cal.sel_year, cal.sel_month, cal.sel_day)], vid.C_WHITE, vid.C_BLUE, vid.S_BOLD)
        x = rput(x, iso:", ", vid.C_WHITE, vid.C_BLUE, vid.S_BOLD)
        x = rput(x, cal.names[cal.sel_month - 1], vid.C_WHITE, vid.C_BLUE, vid.S_BOLD)
        x = rput(x + 1, conv.str_ub(cal.sel_day), vid.C_WHITE, vid.C_BLUE, vid.S_BOLD)
        x = rput(x, iso:", ", vid.C_WHITE, vid.C_BLUE, vid.S_BOLD)
        void rnum(x, cal.sel_year, vid.C_WHITE, vid.C_BLUE, vid.S_BOLD)
        ubyte n = cal.day_cnt[cal.sel_day]
        x = rnum(64, n, vid.C_YELLOW, vid.C_BLUE, 0)
        if n == 1
            void rput(x + 1, iso:"event", vid.C_YELLOW, vid.C_BLUE, 0)
        else
            void rput(x + 1, iso:"events", vid.C_YELLOW, vid.C_BLUE, 0)
        vid.render_run(DAYHDR, 0, 80)
    }

    sub draw_list() {
        ubyte i
        for i in 0 to cal.MAXDAY - 1
            draw_list_row(i)
    }

    sub draw_list_row(ubyte i) {
        ubyte x
        ubyte n = cal.day_cnt[cal.sel_day]
        rclear(vid.C_BLACK, vid.C_LGRAY)
        rcol(GXL, GXR - 1, vid.C_BLACK, vid.C_WHITE)
        for x in GXL to GXR - 1
            vid.r_sty[x] = vid.S_GRIDB
        if i < n {
            ubyte slot = cal.event_of(cal.sel_day, i)
            ubyte bg = vid.C_WHITE
            if slot == sel_ev
                bg = vid.C_CYAN
            if editing and slot == edit_slot
                bg = vid.C_YELLOW
            rcol(GXL, GXR - 1, vid.C_BLACK, bg)
            x = rnum(2, i + 1, vid.C_DGRAY, bg, 0)
            void rput(x, iso:".", vid.C_DGRAY, bg, 0)
            void cal.text_iso(slot, &tb, cal.TXTMAX)
            void rput(LTX, &tb, vid.C_BLACK, bg, 0)
            if @(cal.rec(slot)) & cal.F_CONFLICT != 0
                void rput(LTX + 30, iso:"! sync conflict - see ownCloud", vid.C_RED, bg, vid.S_BOLD)
        } else if i == n and editing and edit_slot == 255 {
            rcol(GXL, GXR - 1, vid.C_BLACK, vid.C_YELLOW)
            void rput(LTX, iso:"(new event - type in the bar at the top)", vid.C_DGRAY, vid.C_YELLOW, vid.S_ITAL)
        } else if i == n and n < cal.MAXDAY {
            if n == 0
                void rput(LTX, iso:"No events. Double-click here, or just start typing, to add one.", vid.C_GRAY, vid.C_WHITE, 0)
            else
                void rput(LTX, iso:"Double-click to add an event", vid.C_GRAY, vid.C_WHITE, 0)
        }
        vid.render_run(LIST0 + i, 0, 80)
    }

    ; ---------------- status bar ----------------
    sub draw_status() {
        rclear(vid.C_BLACK, vid.C_LGRAY)
        void rput(1, status_msg, vid.C_BLACK, vid.C_LGRAY, 0)
        vid.render_run(STATUS_ROW, 0, 80)
    }

    uword[] tips = [
        iso:"",
        iso:"New event on the selected day (or double-click a day / just type)",
        iso:"Edit the selected event (or double-click it)",
        iso:"Delete the selected event",
        iso:"Cut the selected event",
        iso:"Copy the selected event",
        iso:"Paste the copied event on the selected day",
        iso:"Go to today",
        iso:"Previous year",
        iso:"Previous month (or scroll the wheel up over the month)",
        iso:"Next month (or scroll the wheel down over the month)",
        iso:"Next year",
        iso:"Quit (events are saved after every change)",
        iso:"Cancel the entry (Esc)",
        iso:"Save the entry (Return)",
        iso:"Sync with ownCloud through the X16 Office hub (F1)",
        iso:"Sync conflicts: an event changed on both sides (F3)" ]

    sub show_tip(ubyte id) {
        if id >= len(tips)
            id = 0
        set_status(tips[id])
        draw_status()
    }

    sub redraw_month() {
        draw_toolbar()
        draw_ebar()
        draw_header()
        draw_grid()
        draw_dayhdr()
        draw_list()
    }

    sub redraw_everything() {
        bt_n = 0
        draw_title()
        redraw_month()
        draw_status()
    }

    ; ---------------- dialogs ----------------
    sub draw_box(ubyte x, ubyte y, ubyte w, ubyte h) {
        ubyte r
        for r in y to y + h - 1
            vid.fill(x, r, w, 0, vid.C_LGRAY)
        vid.fill(x, y, w, 0, vid.C_BLACK)
        vid.fill(x, y + h - 1, w, 0, vid.C_BLACK)
    }

    sub title_box(ubyte x, ubyte y, ubyte w, ubyte h, uword title, ubyte bg) {
        draw_box(x, y, w, h)
        vid.fill(x, y, w, vid.C_WHITE, bg)
        put(x + 2, y, title, vid.C_WHITE, bg)
    }

    ; Yes / No question about the text in tb; true = yes. The caller redraws the screen.
    sub yesno(uword question) -> bool {
        ubyte k
        title_box(18, 11, 44, 6, iso:"Please confirm", vid.C_RED)
        put(20, 13, question, 0, vid.C_LGRAY)
        put(20, 14, &tb, vid.C_BLUE, vid.C_LGRAY)
        put(24, 15, iso:"[ Yes ]", 0, vid.C_WHITE)
        put(46, 15, iso:"[ No ]", 0, vid.C_WHITE)
        prev_btn = true
        repeat {
            k = click()
            if k == 2
                return false
            if k == 3 {
                k = last_key | 32
                if k == iso:'y' or last_key == 13
                    return true
                if k == iso:'n'
                    return false
            }
            if k == 1 and mouse_cy == 15 {
                if mouse_cx >= 24 and mouse_cx < 31
                    return true
                if mouse_cx >= 46 and mouse_cx < 52
                    return false
            }
        }
    }

    ; ---------------- sync conflicts ----------------
    ubyte[40] cb
    sub cb_add(uword src) {
        ubyte n = strings.length(&cb)
        while @(src) != 0 and n < 39 {
            cb[n] = @(src)
            n++
            src++
        }
        cb[n] = 0
    }

    ; the conflicts of the last sync (lkcal.conf_*); true = acknowledge all. The caller redraws.
    sub conflicts_dialog() -> bool {
        const ubyte X = 4
        const ubyte Y = 3
        ubyte i
        ubyte y = Y + 4
        ubyte k
        title_box(X, Y, 72, 24, iso:"Sync conflicts", vid.C_RED)
        put(X + 2, Y + 2, iso:"These events changed on the X16 and in ownCloud since the last sync;", 0, vid.C_LGRAY)
        put(X + 2, Y + 3, iso:"one version was kept. Acknowledge them to clear the red ! marks.", 0, vid.C_LGRAY)
        if lkcal.nconf_got == 0 {
            if cal.count_conflicts() != 0
                put(X + 2, y + 1, iso:"Click Sync first: the details come from the hub.", vid.C_BLUE, vid.C_LGRAY)
            else
                put(X + 2, y + 1, iso:"No conflicts.", vid.C_BLUE, vid.C_LGRAY)
        } else {
            for i in 0 to lkcal.nconf_got - 1 {
                if y > Y + 19
                    break
                ubyte slot = lkcal.conf_slot[i]
                if slot < cal.MAXEV and @(cal.rec(slot)) != 0 {
                    uword p = cal.rec(slot)
                    ; "20YY-MM-DD"
                    tb[0] = iso:'2'
                    tb[1] = iso:'0'
                    tb[2] = iso:'0' + @(p + 1) / 10
                    tb[3] = iso:'0' + @(p + 1) % 10
                    tb[4] = iso:'-'
                    tb[5] = iso:'0' + @(p + 2) / 10
                    tb[6] = iso:'0' + @(p + 2) % 10
                    tb[7] = iso:'-'
                    tb[8] = iso:'0' + @(p + 3) / 10
                    tb[9] = iso:'0' + @(p + 3) % 10
                    tb[10] = 0
                    put(X + 2, y, &tb, vid.C_BLACK, vid.C_LGRAY)
                    void cal.text_iso(slot, &tb, cal.TXTMAX)
                    put(X + 14, y, &tb, vid.C_BLUE, vid.C_LGRAY)
                } else
                    put(X + 2, y, iso:"(an event that is not on the X16)", vid.C_BLACK, vid.C_LGRAY)
                cb[0] = 0
                when lkcal.conf_kind[i] {
                    1 -> cb_add(iso:"deleted here, edited in ownCloud: ")
                    2 -> cb_add(iso:"edited here, deleted in ownCloud")
                    else -> {
                        when lkcal.conf_field[i] {
                            0 -> cb_add(iso:"event")
                            1 -> cb_add(iso:"date")
                            2 -> cb_add(iso:"time")
                            else -> cb_add(iso:"text")
                        }
                        cb_add(iso:" changed on both; ownCloud had: ")
                    }
                }
                put(X + 4, y + 1, &cb, vid.C_DGRAY, vid.C_LGRAY)
                if lkcal.conf_kind[i] != 2 {
                    ; the ownCloud value (PETSCII) -> ISO
                    uword t = lkcal.conf_text + (i as uword) * lkcal.CTXT
                    k = 0
                    while @(t + k) != 0 and k < 27 {
                        tb[k] = cal.to_iso(@(t + k))
                        k++
                    }
                    tb[k] = 0
                    put(X + 4 + strings.length(&cb), y + 1, &tb, vid.C_BLACK, vid.C_LGRAY)
                }
                if lkcal.conf_kept[i] == 0
                    put(X + 56, y, iso:"kept: X16", vid.C_RED, vid.C_LGRAY)
                else
                    put(X + 56, y, iso:"kept: ownCloud", vid.C_RED, vid.C_LGRAY)
                y += 2
            }
            if lkcal.nconf > lkcal.nconf_got
                put(X + 2, Y + 20, iso:"(more on the hub: python -m x16hub.calsync conflicts)", vid.C_DGRAY, vid.C_LGRAY)
        }
        put(X + 2, Y + 22, iso:"[Acknowledge all]", 0, vid.C_WHITE)
        put(X + 22, Y + 22, iso:"[ Close ]", 0, vid.C_WHITE)
        prev_btn = true
        repeat {
            k = click()
            if k == 2
                return false
            if k == 3 {
                if last_key | 32 == iso:'a'
                    return true
                if last_key == 13 or last_key == 134
                    return false
            }
            if k == 1 and mouse_cy == Y + 22 {
                if mouse_cx >= X + 2 and mouse_cx < X + 19
                    return true
                if mouse_cx >= X + 22 and mouse_cx < X + 31
                    return false
            }
        }
    }

    ; ---------------- mouse ----------------
    ubyte mouse_btn
    ubyte mouse_cx
    ubyte mouse_cy
    byte mouse_wheel

    sub poll_mouse() {
        ubyte b
        uword mx
        uword my
        byte wh
        b, mx, my, wh = cx16.mouse_pos()
        mouse_btn = b
        mouse_wheel = wh
        mouse_cx = lsb(mx >> 3)
        mouse_cy = lsb(my >> 3)
        if mx >= 640
            mouse_cx = 79
        if my >= 240
            mouse_cy = 29
    }

    ; for dialogs: 0 = nothing, 1 = fresh click (mouse_cx/cy), 2 = Esc, 3 = key (in last_key)
    bool prev_btn
    ubyte last_key
    uword @shared keyscript             ; test hook: keys for dialogs (0 = keyboard)
    sub click() -> ubyte {
        sys.waitvsync()
        if keyscript != 0 and @(keyscript) != 0 {
            last_key = @(keyscript)
            keyscript++
            if last_key == 27
                return 2
            return 3
        }
        last_key = cbm.GETIN2()
        if last_key == 27 or last_key == 3
            return 2
        if last_key != 0
            return 3
        poll_mouse()
        if mouse_btn & 1 != 0 {
            if not prev_btn {
                prev_btn = true
                return 1
            }
        } else
            prev_btn = false
        return 0
    }
}
