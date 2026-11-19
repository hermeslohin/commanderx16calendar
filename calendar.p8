; X16 CALENDAR - a mouse driven calendar for the Commander X16, written in Prog8.
; A companion to X16 Write and X16 Sheets: same 80x30 bitmap screen, icons, tool tips and dialogs.
;
; Month view with up to two events per day shown in the grid, the selected day's events below it.
; Events are saved to CALENDAR.DAT on the current drive after every change (format: FORMAT.md).
;
; Mouse: click a day to select it, click an event to select it, double-click a day or an empty
;        list row to add an event, double-click an event to edit it, drag an event onto another
;        day to move it, wheel over the month = previous / next month. Toolbar: New, Edit, Delete,
;        Cut, Copy, Paste, Today, previous / next year and month, Sync with ownCloud, Conflicts.
;        Quit is at the top right. Quill (bottom left) = next theme (X16THEME<n>.BIN, X16THEME.CFG).
; Keys:  cursor keys move between days, PgUp/PgDn (Ctrl+P/N) change month, Home = today,
;        typing starts a new event, Return edits the selected event (or adds one), Tab selects the
;        next event, Del deletes it, F1 syncs, F3 shows sync conflicts, Ctrl+X quits.
;        In the entry bar: Return saves, Esc cancels.
; Sync: the X16 Office hub's calendar channel (lib/x16link/x16cal.p8) through X16LINK.BIN (bank 60);
;        needs X16LINK.BIN + X16LINK.KEY next to the program and the TexElec serial/ESP32 card.
;
; calapp.p8 = start-up and input, calview.p8 = screen, caldata.p8 = records and dates,
; vid.p8 = bitmap text renderer (from X16 Write / X16 Sheets), icons.p8 = tools/gen_icons.py.

%import calapp
%zeropage basicsafe

main {
    sub start() {
        app.run()
    }
}
