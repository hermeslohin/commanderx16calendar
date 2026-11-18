; cloudtest.p8 - X16 Calendar's Sync end to end: the real app code (calapp/calview/caldata + x16cal)
; through the emulator's virtual modem (-uart1 ximodem) to the hub's link server with its real
; calendar sync engine and an in-memory CalDAV calendar (test/calhub.py). Prints PASS/FAIL, DONE.
%import calapp
%zeropage basicsafe

main {
    ubyte fails

    sub check(bool ok, str what) {
        txt.print(what)
        if ok
            txt.print(iso:"  PASS\r")
        else {
            txt.print(iso:"  FAIL  [")
            txt.print(cv.status_msg)
            txt.print(iso:"]\r")
            fails++
        }
    }

    sub typ(str s) {
        ubyte i = 0
        while s[i] != 0 {
            app.edit_key(s[i])
            i++
        }
    }

    ; slot of the event whose (ISO) text starts with `prefix`, 255 = none
    ubyte[32] t
    sub find(str prefix) -> ubyte {
        ubyte i
        for i in 0 to cal.MAXEV - 1 {
            if @(cal.rec(i)) != 0 {
                void cal.text_iso(i, &t, cal.TXTMAX)
                if strings.startswith(&t, prefix)
                    return i
            }
        }
        return 255
    }

    sub start() {
        txt.iso()
        void cal.load_events()
        cal.load_counter()
        vid.load_fonts()
        vid.gfx_init()
        cv.upload_icons()
        app.select_day(2026, 11, 20)
        cv.redraw_everything()

        ; 1) a new X16 event, then Sync: it goes to ownCloud, "Lunch" comes back
        app.start_edit(255, 0)
        typ(iso:"10:00 Dentist")
        void app.commit()
        app.sync_now()
        check(strings.startswith(cv.status_msg, iso:"Synced"), iso:"first sync")
        ubyte lunch = find(iso:"09:00 Lunch")
        check(lunch != 255 and @(cal.rec(lunch) + 3) == 21, iso:"ownCloud event arrived on the 21st")
        check(cal.sync_counter[0] != 0 or cal.sync_counter[1] != 0, iso:"hub counter kept")
        check(diskio.exists(iso:"CALSYNC.DAT"), iso:"CALSYNC.DAT written")

        ; 2) wait for the server-side edit of Lunch, edit it on the X16 too: a conflict
        sys.wait(180)
        app.select_day(2026, 11, 21)
        app.select_event(lunch)
        app.start_edit(lunch, 0)
        typ(iso:" X16")
        void app.commit()
        check(@(cal.rec(lunch)) & cal.F_EDITED != 0, iso:"edit sets the edited flag")
        app.sync_now()
        check(lkcal.nconf == 1 and lkcal.nconf_got == 1, iso:"conflict reported")
        check(cal.count_conflicts() == 1, iso:"conflict flag on the event")
        check(lkcal.conf_kept[0] == 0, iso:"X16 version kept")

        ; 3) conflicts dialog -> Acknowledge all, sync: the mark is gone
        cv.keyscript = iso:"a"
        app.show_conflicts()
        app.sync_now()
        check(strings.startswith(cv.status_msg, iso:"Synced") and cal.count_conflicts() == 0, iso:"acknowledged, cleared on the next sync")

        ; 4) reload from the SD card: the synced state is what was saved
        void cal.load_events()
        check(find(iso:"10:00 Dentist") != 255 and find(iso:"09:00 Lunch X16") != 255, iso:"CALENDAR.DAT has both events")
        if fails == 0
            txt.print(iso:"ALL PASS\r")
        txt.print(iso:"DONE\r")
    }
}
