; calapp.p8 - X16 Calendar's application: start-up, the mouse/keyboard loop, editing events,
; dragging events to other days, cut/copy/paste. Works the way X16 Sheets does: click to select,
; double-click (or just type) to edit, Return / Esc in the entry bar, tool tips in the status bar.

%import syslib
%import textio
%import strings
%import diskio
%import vid
%import caldata
%import calview

app {
    bool running = true
    ubyte prev_btn
    ubyte last_tip
    ubyte last_click_time
    ubyte last_click_day
    ubyte last_click_row = 255
    ubyte drag_slot = 255               ; event pressed on (may become a drag)
    bool dragging
    ubyte press_cx
    ubyte press_cy

    sub run() {
        txt.iso()
        cal.get_today()
        ubyte ok = cal.load_events()
        vid.load_fonts()
        vid.gfx_init()
        cv.upload_icons()
        cal.scan_month()
        when ok {
            0 -> cv.set_status(iso:"No CALENDAR.DAT yet - starting a new calendar. Click a day, then type.")
            1 -> cv.set_status(iso:"Welcome! Click a day, double-click to add an event. Drag events to move them.")
            else -> cv.set_status(iso:"CALENDAR.DAT is empty or unreadable - starting a new calendar.")
        }
        cv.redraw_everything()
        while running {
            sys.waitvsync()
            handle_keys()
            handle_mouse()
        }
        vid.gfx_off()
    }

    sub status(uword s) {
        cv.set_status(s)
        cv.draw_status()
    }

    sub save() {
        if cal.save_events()
            cv.set_status(iso:"Saved to CALENDAR.DAT")
        else {
            cv.set_status(iso:"Save failed! ")
            void strings.append(cv.status_msg, diskio.status())
        }
    }

    ; something about the month changed: re-index it and redraw everything but the title
    sub refresh() {
        cal.scan_month()
        if cv.sel_ev != 255 and cal.pos_in_day(cv.sel_ev) == 255
            cv.sel_ev = 255
        cv.redraw_month()
        cv.draw_status()
    }

    ; ======================= navigation =======================
    sub select_day(uword y, ubyte m, ubyte d) {
        bool same_month = y == cal.sel_year and m == cal.sel_month
        ubyte oldwk = (cv.g_first + cal.sel_day - 1) / 7
        cal.sel_year = y
        cal.sel_month = m
        cal.sel_day = d
        cv.sel_ev = 255
        if same_month {
            ; only the weeks that changed
            cv.grid_setup()
            ubyte newwk = (cv.g_first + d - 1) / 7
            cv.draw_ebar()
            cv.draw_header()
            cv.draw_week(oldwk)
            if newwk != oldwk
                cv.draw_week(newwk)
            cv.draw_dayhdr()
            cv.draw_list()
        } else
            refresh()
    }

    sub select_event(ubyte slot) {
        if slot == cv.sel_ev
            return
        cv.sel_ev = slot
        cv.grid_setup()
        cv.draw_week((cv.g_first + cal.sel_day - 1) / 7)
        cv.draw_ebar()
        cv.draw_list()
    }

    sub nav(ubyte what) {
        if cv.editing and not commit()
            return
        when what {
            cv.B_PREVM -> cal.change_month(-1)
            cv.B_NEXTM -> cal.change_month(1)
            cv.B_PREVY -> cal.change_year(-1)
            cv.B_NEXTY -> cal.change_year(1)
            cv.B_TODAY -> {
                if cal.today_year == 0 {
                    status(iso:"The clock isn't set, so today is unknown")
                    return
                }
                cal.goto_today()
            }
        }
        cv.sel_ev = 255
        refresh()
    }

    sub move_sel(byte delta) {
        uword y = cal.sel_year
        ubyte m = cal.sel_month
        cal.move_days(delta)
        ubyte d = cal.sel_day
        uword ny = cal.sel_year
        ubyte nm = cal.sel_month
        cal.sel_year = y                ; select_day compares with the old month
        cal.sel_month = m
        select_day(ny, nm, d)
    }

    ; ======================= editing =======================
    sub start_edit(ubyte slot, ubyte firstkey) {
        if slot == 255 {
            if cal.day_cnt[cal.sel_day] >= cal.MAXDAY {
                status(iso:"This day is full (6 events at most)")
                return
            }
            if cal.free_slot() == 255 {
                status(iso:"The calendar is full (128 events)")
                return
            }
            cv.elen = 0
            if firstkey != 0 {
                cv.ebuf[0] = firstkey
                cv.elen = 1
            }
            cv.set_status(iso:"Type the event. Start with a time like 14:30 for a timed event.")
        } else {
            cv.elen = cal.text_iso(slot, &cv.ebuf, cal.TXTMAX)
            cv.set_status(iso:"Change the text; an empty text deletes the event.")
        }
        cv.edit_slot = slot
        cv.ecur = cv.elen
        cv.editing = true
        cv.draw_toolbar()
        cv.draw_ebar()
        cv.draw_list()
        cv.draw_status()
    }

    sub cancel_edit() {
        cv.editing = false
        cv.draw_toolbar()
        cv.draw_ebar()
        cv.draw_list()
        status(iso:"")
    }

    sub e_insert(ubyte c) {
        if cv.elen >= cal.TXTMAX or cal.to_pet(c) == 0
            return
        ubyte i = cv.elen
        while i > cv.ecur {
            cv.ebuf[i] = cv.ebuf[i - 1]
            i--
        }
        cv.ebuf[cv.ecur] = c
        cv.elen++
        cv.ecur++
    }

    sub e_delete(ubyte at) {
        if at >= cv.elen
            return
        ubyte i = at
        while i < cv.elen - 1 {
            cv.ebuf[i] = cv.ebuf[i + 1]
            i++
        }
        cv.elen--
    }

    ; store the entry; false if it couldn't be stored (the entry stays open)
    sub commit() -> bool {
        while cv.elen != 0 and cv.ebuf[cv.elen - 1] == 32
            cv.elen--
        cv.editing = false
        ubyte slot = cv.edit_slot
        if slot == 255 {
            if cv.elen == 0 {
                refresh()
                status(iso:"")
                return true
            }
            slot = cal.free_slot()
            if slot == 255 or cal.count_on(cal.sel_year, cal.sel_month, cal.sel_day) >= cal.MAXDAY {
                status(iso:"No room for this event")
                return true
            }
            uword p = cal.rec(slot)
            @(p) = 1
            @(p+1) = lsb(cal.sel_year - 2000)
            @(p+2) = cal.sel_month
            @(p+3) = cal.sel_day
            void cal.set_text(slot, &cv.ebuf, cv.elen)
            save()
        } else if cv.elen == 0 {
            @(cal.rec(slot)) = 0
            slot = 255
            save()
            cv.set_status(iso:"Event deleted (the text was empty)")
        } else if cal.set_text(slot, &cv.ebuf, cv.elen) {
            @(cal.rec(slot)) |= cal.F_EDITED
            save()
        } else
            cv.set_status(iso:"")
        cv.sel_ev = slot
        refresh()
        return true
    }

    ; ======================= event operations =======================
    sub need_event() -> bool {
        if cv.sel_ev == 255 {
            status(iso:"Click an event first")
            return false
        }
        return true
    }

    sub delete_event(bool ask) {
        if not need_event()
            return
        if ask {
            void cal.text_iso(cv.sel_ev, &cv.tb, cal.TXTMAX)
            bool yes = cv.yesno(iso:"Delete this event?")
            cv.redraw_everything()
            if not yes
                return
        }
        @(cal.rec(cv.sel_ev)) = 0
        save()
        cv.sel_ev = 255
        refresh()
    }

    sub copy_event() -> bool {
        if not need_event()
            return false
        cv.clip_len = cal.text_iso(cv.sel_ev, &cv.clip, cal.TXTMAX)
        return true
    }

    sub paste_event() {
        if cv.clip_len == 0 {
            status(iso:"Copy or cut an event first")
            return
        }
        start_edit(255, 0)
        if not cv.editing
            return
        sys.memcopy(&cv.clip, &cv.ebuf, cv.clip_len)
        cv.elen = cv.clip_len
        void commit()
    }

    ; move an event to another day (drag and drop); y/m/d is the target
    sub move_event(ubyte slot, uword y, ubyte m, ubyte d) {
        uword p = cal.rec(slot)
        if @(p+1) == lsb(y - 2000) and @(p+2) == m and @(p+3) == d
            return
        if cal.count_on(y, m, d) >= cal.MAXDAY {
            status(iso:"That day is full (6 events at most)")
            return
        }
        @(p+1) = lsb(y - 2000)
        @(p+2) = m
        @(p+3) = d
        @(p) |= cal.F_EDITED
        cal.sel_year = y
        cal.sel_month = m
        cal.sel_day = d
        save()
        cv.sel_ev = slot
        refresh()
    }

    ; ======================= buttons =======================
    sub do_button(ubyte id) {
        if cv.editing {
            when id {
                cv.B_ECANCEL -> {
                    cancel_edit()
                    return
                }
                cv.B_EOK -> {
                    void commit()
                    return
                }
                else -> {
                    if not commit()
                        return
                }
            }
        }
        when id {
            cv.B_ADD -> start_edit(255, 0)
            cv.B_EDIT -> {
                if need_event()
                    start_edit(cv.sel_ev, 0)
            }
            cv.B_DEL -> delete_event(true)
            cv.B_CUT -> {
                if copy_event() {
                    delete_event(false)
                    status(iso:"Cut. Select a day and click Paste.")
                }
            }
            cv.B_COPY -> {
                if copy_event() {
                    cv.draw_toolbar()
                    status(iso:"Copied. Select a day and click Paste.")
                }
            }
            cv.B_PASTE -> paste_event()
            cv.B_TODAY, cv.B_PREVM, cv.B_NEXTM, cv.B_PREVY, cv.B_NEXTY -> nav(id)
            cv.B_QUIT -> running = false
        }
    }

    ; ======================= keyboard =======================
    sub handle_keys() {
        ubyte k
        repeat 8 {
            k = cbm.GETIN2()
            if k == 0
                return
            if cv.editing
                edit_key(k)
            else
                nav_key(k)
        }
    }

    sub nav_key(ubyte k) {
        when k {
            $1d -> move_sel(1)                  ; right
            $9d -> move_sel(-1)                 ; left
            $11 -> move_sel(7)                  ; down
            $91 -> move_sel(-7)                 ; up
            $82, 16 -> nav(cv.B_PREVM)          ; PgUp, Ctrl+P
            $02, 14 -> nav(cv.B_NEXTM)          ; PgDn, Ctrl+N
            $13 -> nav(cv.B_TODAY)              ; Home
            9 -> next_event()                   ; Tab
            13, 137 -> {                        ; Return, F2
                if cv.sel_ev != 255
                    start_edit(cv.sel_ev, 0)
                else
                    start_edit(255, 0)
            }
            8, 20, 25, 127 -> delete_event(true)
            24 -> running = false               ; Ctrl+X
            else -> {
                if (k >= 32 and k < 127) or k == 163
                    start_edit(255, k)
            }
        }
    }

    sub next_event() {
        ubyte n = cal.day_cnt[cal.sel_day]
        if n == 0
            return
        ubyte i = cal.pos_in_day(cv.sel_ev)
        if i == 255 or i + 1 >= n
            i = 0
        else
            i++
        select_event(cal.event_of(cal.sel_day, i))
    }

    sub edit_key(ubyte k) {
        when k {
            13 -> {
                void commit()
                return
            }
            27, 3 -> {
                cancel_edit()
                return
            }
            $9d -> {
                if cv.ecur != 0
                    cv.ecur--
            }
            $1d -> {
                if cv.ecur < cv.elen
                    cv.ecur++
            }
            $13 -> cv.ecur = 0
            $04 -> cv.ecur = cv.elen
            8, 20 -> {
                if cv.ecur != 0 {
                    cv.ecur--
                    e_delete(cv.ecur)
                }
            }
            25, 127 -> e_delete(cv.ecur)
            else -> {
                if (k >= 32 and k < 127) or k == 163
                    e_insert(k)
            }
        }
        cv.draw_ebar()
    }

    ; ======================= mouse =======================
    sub handle_mouse() {
        cv.poll_mouse()
        ubyte left = cv.mouse_btn & 1
        ubyte cx = cv.mouse_cx
        ubyte cy = cv.mouse_cy
        if cv.mouse_wheel != 0 and not cv.editing and cy >= cv.HDR and cy < cv.DAYHDR {
            if cv.mouse_wheel < 0
                nav(cv.B_PREVM)
            else
                nav(cv.B_NEXTM)
        }
        if left != 0 and prev_btn == 0
            press(cx, cy)
        else if left != 0
            drag(cx, cy)
        else {
            if prev_btn != 0
                release(cx, cy)
            hover(cx, cy)
        }
        prev_btn = left
    }

    sub hover(ubyte cx, ubyte cy) {
        ubyte id = cv.find_button(cx, cy)
        if id != last_tip {
            last_tip = id
            cv.show_tip(id)
        }
    }

    ; grid cell under the mouse -> hit_y/m/d (hit_off -1/0/1), hit_slot (event line, 255 = none)
    uword hit_y
    ubyte hit_m
    ubyte hit_d
    byte hit_off
    ubyte hit_slot
    sub grid_hit(ubyte cx, ubyte cy) -> bool {
        if cy < cv.GRID0 or cy >= cv.GRID0 + cv.GRIDN or cx < cv.GXL or cx >= cv.GXR
            return false
        ubyte c = (cx - cv.GXL) / cv.CW
        ubyte sr = cy - cv.GRID0
        ubyte ln = sr % 3
        cv.grid_setup()
        cv.day_at((sr / 3) * 7 + c)
        hit_d = cv.at_day
        hit_off = cv.at_off
        hit_y = cal.sel_year
        hit_m = cal.sel_month
        if hit_off < 0 {
            if hit_m == 1 {
                if hit_y == 2000
                    return false
                hit_m = 12
                hit_y--
            } else
                hit_m--
        } else if hit_off > 0 {
            if hit_m == 12 {
                if hit_y == 2200
                    return false
                hit_m = 1
                hit_y++
            } else
                hit_m++
        }
        hit_slot = 255
        if hit_off == 0 and ln != 0 {
            ubyte n = cal.day_cnt[hit_d]
            if ln == 1 and n != 0
                hit_slot = cal.event_of(hit_d, 0)
            else if ln == 2 and n == 2
                hit_slot = cal.event_of(hit_d, 1)
        }
        return true
    }

    sub dbl_click(ubyte d, ubyte row) -> bool {
        ubyte now = lsb(cbm.RDTIM16())
        bool dbl = d == last_click_day and row == last_click_row and (now - last_click_time) < 25
        last_click_time = now
        last_click_day = d
        last_click_row = row
        if dbl
            last_click_row = 255        ; a third click starts over
        return dbl
    }

    sub press(ubyte cx, ubyte cy) {
        drag_slot = 255
        dragging = false
        press_cx = cx
        press_cy = cy
        ubyte id = cv.find_button(cx, cy)
        if id != 0 {
            do_button(id)
            return
        }
        ; entry bar text: start editing / place the cursor
        if cy == cv.EBAR and cx > cv.EDX and cx < cv.EDX + cv.EDW {
            if not cv.editing {
                start_edit(cv.sel_ev, 0)
                if not cv.editing
                    return
            }
            ubyte p = cx - cv.EDX - 1
            if p > cv.elen
                p = cv.elen
            cv.ecur = p
            cv.draw_ebar()
            return
        }
        if cv.editing and (grid_hit(cx, cy) or (cy >= cv.LIST0 and cy < cv.LIST0 + cal.MAXDAY)) {
            if not commit()
                return
        }
        if grid_hit(cx, cy) {
            bool dbl = dbl_click(hit_d, cy)
            if hit_y != cal.sel_year or hit_m != cal.sel_month or hit_d != cal.sel_day
                select_day(hit_y, hit_m, hit_d)
            if hit_slot != 255 {
                select_event(hit_slot)
                drag_slot = hit_slot
            }
            if dbl {
                if hit_slot != 255
                    start_edit(hit_slot, 0)
                else if cy == cv.GRID0 + ((cy - cv.GRID0) / 3) * 3
                    start_edit(255, 0)          ; double-click on the day number: new event
            }
            return
        }
        ; the day's event list
        if cy >= cv.LIST0 and cy < cv.LIST0 + cal.MAXDAY and cx >= cv.GXL and cx < cv.GXR {
            ubyte i = cy - cv.LIST0
            bool dbl2 = dbl_click(cal.sel_day, cy)
            if i < cal.day_cnt[cal.sel_day] {
                ubyte slot = cal.event_of(cal.sel_day, i)
                select_event(slot)
                drag_slot = slot
                if dbl2
                    start_edit(slot, 0)
            } else {
                if cv.sel_ev != 255 {
                    cv.sel_ev = 255
                    cv.draw_week((cv.g_first + cal.sel_day - 1) / 7)
                    cv.draw_ebar()
                    cv.draw_list()
                }
                if dbl2
                    start_edit(255, 0)
            }
        }
    }

    ubyte last_drop
    sub drag(ubyte cx, ubyte cy) {
        if drag_slot == 255
            return
        if not dragging {
            if cx == press_cx and cy == press_cy
                return
            dragging = true
            last_drop = 0
            status(iso:"Moving the event: drop it on a day")
        }
        ubyte nd = 0
        if grid_hit(cx, cy) and hit_off == 0
            nd = hit_d
        if nd != last_drop {
            last_drop = nd
            show_drop(nd)
        }
    }

    sub show_drop(ubyte d) {
        ubyte old = cv.drop_day
        cv.drop_day = d
        cv.grid_setup()
        if old != 0
            cv.draw_week((cv.g_first + old - 1) / 7)
        if d != 0 and (old == 0 or (cv.g_first + d - 1) / 7 != (cv.g_first + old - 1) / 7)
            cv.draw_week((cv.g_first + d - 1) / 7)
    }

    sub release(ubyte cx, ubyte cy) {
        if not dragging {
            drag_slot = 255
            return
        }
        dragging = false
        show_drop(0)
        ubyte slot = drag_slot
        drag_slot = 255
        if grid_hit(cx, cy)
            move_event(slot, hit_y, hit_m, hit_d)
        else
            status(iso:"Not moved (drop the event on a day of the month)")
    }
}
