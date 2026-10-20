# Shared batch 15 — Notes panel — 2026-10-20

Approved board `l9ZBWI` (A) and design `notes.md` → Notes panel. Restyle of the compact panel on record pages
(`collaboration/NotesPanel`, `compact`); the full panel in the visit records pop-up keeps its live look. Every control and
the staged-save flow are unchanged: nothing reaches the server until the page's Save.

- Notes are bands 10 apart in a 16 padded body; pinned band amber with its edge and a 16 pin before the ⋯.
- ⋯ is a 28 quiet square; the menu is Pin/Unpin, Edit, a divider, Delete in red (`DropdownMenu` now draws the
  footer divider after plain items too).
- Waiting for Save is a status line: new note "Not saved yet" with Remove on a white band with an amber edge; edited
  note "Edit waiting for Save" (a pin-only change reads "Pin/Unpin waiting for Save"); deleted note faded, struck,
  "Deleted when you save" with Undo. Replaces the "Unsaved" and "Not saved yet" badges.
- Editing replaces the text with a green-edged box and small Cancel / Done; loading shows three note bones;
  empty, view-only empty and couldn't load (Try again refetches) as drawn. Note field under a hairline with the
  32 send square, green only when there is text.

Checked on the running app (owner, Raad LTD job page, 1440, light and dark). The job had no notes, so the note
states use three fixture notes served in place of `/api/notes` in the browser (authors read "Unknown" for that
reason); loading, couldn't load and empty were forced the same way. Adding, editing and deleting were pressed
for real and only staged; Save was not pressed, so no data changed. No page errors. Checks deferred to campaign
close (Jafar, 2026-10-20): type check, lint, test suites.
