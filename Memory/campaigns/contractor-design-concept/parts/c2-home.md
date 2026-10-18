# C2 — Home in the concept

**State:** Approved by Jafar 2026-10-18 (option A). `concept.pen` frame "Concept · Home · Owner · 1440"
(`rKrbu`, x 4712, y 0); the plain version and option B are deleted.

**Content source:** the approved Home plan `docs/home-and-reports-behavior-contract.md` § Home (Jobber-based
research, approved 2026-10-12). No new content was added; the layout is new.

**What it shows, top to bottom:** greeting with date and a one-line day summary, day clock card at the right
(on the clock, since, week hours, Clock out) · setup guide strip (4 of 6, Continue setup) · To do: four
columns Requests/Quotes/Jobs/Invoices in record colours, each line with label, value under it and a count chip
coloured by status · Today's schedule (By visit/By person switch, Completed/In progress/Still to do/Late
counts, time-ordered items, Anytime last, "Late from earlier days" block) beside a right column of Money owed
(total, not-yet-due/overdue bar, three most overdue clients) and Business performance (three figures with
up/down change).

**Asked, not yet answered (default: keep as drawn):** the live schedule card shows no "In progress" yet though
the approved plan has it; "Changes requested" drawn in Waiting yellow (colour still open); Business performance
moved beside Money owed instead of a row of its own; down-trend shown in Waiting yellow, not red.

**Green feature card (2026-10-18, Jafar asked):** the live Home's schedule card is dark (`--color-surface--reverse`).
Two options drawn below the Home frame: A "green Today card" (`rKrbu`, greeting + day clock on a deep-green
gradient) and B "green schedule card" (`jZMZ9`). New Pencil-only colours `color-feature-start` #02532d,
`-end` #037741, `-text`, `-text-secondary`, `-subtle`, `-border` (same in light and dark); they go into code and
the design skill only once Jafar picks an option.

Jafar deleted option B and approved A the same day. Feature colours and `font-size-display` 28 are now in
Pencil, `_variables.scss` and the design modules.

**Next:** C3 Jobs list. Dark mode of Home not drawn.
