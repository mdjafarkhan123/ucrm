# C1e — Hand-made buttons replaced by the shared Button

**State:** Done and merged into main 2026-10-18 (fast-forward, `cf0dee87`). Five parallel helpers moved the rest in two rounds; about 100 files changed, the remaining `<button>`s were judged not to be buttons (cards, rows, chips, drag handles, photo overlays, tabs, links in sentences).

**Built:** `Button` now has `iconOnly` + `label` (square, white bordered, icon in `--color-icon`) and passes extra props through, so a bits-ui menu trigger can use it. `DropdownMenu` draws its trigger with `Button`: icon button by default (small), or a text button with `triggerText` (+ `triggerLeadingIcon`, `triggerChevron`, `triggerVariant`, `triggerSize`). A custom `trigger`/`triggerClass` still works for pickers that are not buttons (assignee, owner avatar, status badge, topic, channel, saved filters). `PencilButton` wraps `Button` (its `variant`/`variation` props are gone). Moved: client and work-record headers (History, More), clients page, Add menus (visits, block, question, variable), Call, pipeline bulk menus, deal Change stage, owner Change, route Save/Directions/Close, top bar (Add new, theme, menu), and the move/remove icon groups in stage list, checklist, campaign block, form question/section and booking-services editors, file labels, report photo layout, record files Add, composer minimise/expand.

**Switched-on look (2026-10-18):** Jafar approved option A on the `concept.pen` board "Switched-on buttons"
(green outline; rules in `buttons.md` § Switched on). `Button` has `pressed` (sets `aria-pressed`, except on a
menu/popover trigger, which has `aria-expanded`) and `count` (number bubble). Schedule Unscheduled, Map, Filters
and the calendar bar's Today use it; the old `.calendar-bar__button` styles are gone. Checked live (owner login,
light and dark): off, Unscheduled on, Map on, Map on + hover, Filters on with "1" and keyboard focus. Jafar also
approved the small bordered row-menu dots, so nothing waits on him for this part.
Seen while testing, not fixed (ask Jafar first): on Raad LTD's Schedule the Employee lists in Filters and in
"Whose route?" show no names although `/api/team/assignable` returns five members.

**Checked:** Live screenshots (owner login): Clients list, client record + open More menu, quote record + open More menu, job record, top bar. Row dots menus now show as small bordered icon buttons — Jafar has not seen this yet.

**Left (2026-10-18):** format, lint and type check on every changed file, deferred by Jafar to campaign end (round one's bulk scripts broke four files; they were restored and redone, the others were only syntax-checked). Time-clock Stop/Clock out should use the spinner. Editor toolbar toggles (QuoteTermsEditor) need a compact on/off look. Schedule date arrows stay a joined pair. Botanical header keeps its old button rules. Not seen live: the Button loading look, the Settings confirm buttons, SMS editor, setup stage lists.
