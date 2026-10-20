# Shared batches 16–23 — 2026-10-20

Built by Claude from the approved boards; restyle only, same queries, words and flows. Checked on the live app
(owner, Raad LTD; `/jafar` signed out) at 1440 light and dark, compared with each Pencil board.

| Batch | Board | What changed | Proof |
| --- | --- | --- | --- |
| 16 Email From line | `I5mY7I` B | `EmailSenderLabel` is the teal sender chip; loading bone, red/amber chips; cut-off address shows the full one in the new shared `ui/Tooltip` (Bits UI; the file was empty) | `composer-*.png` |
| 17 Caption and labels | `Y0ECPJ` A | Grey photo tile, "file · Job #" hint, 200-high photo, one-line caption box with a quote mark, LABELS row with green Manage labels, save strip as the footer, bones / couldn't load / nothing yet | `caption-*.png` |
| 18 Record files card | `pH9PB` A | 3-a-row photos 92 high, hover ring with two round white buttons, document lines with ⋯ menu (Download; Remove in critical), notice rows, bones, empty and couldn't load with Try again, unlink remove pop-up | `job-files-*.png`, `photo4-light.png` |
| 19 Writing boxes | `qf1uu` | `FormNotesCard` Notes-panel field with Team only and count; new `ui/MessageSheet` (subject + message + values bar) for automation email and text; cost meter; teal step tiles | `client-new-notes-*.png`, `auto-*.png` |
| 20 Pop-over, chips | `e18rX` B | `ui/Popover` tinted band + white tile + arrow (callers pass meaning and icon); date chip with time tile and 440 From → To panel; multi chip with icon, green +N, menu head, count pills, Clear foot | `sendlater-*.png`, `datepanel-*.png`, `multi-light.png` |
| 21 Activity feed | `gZ6rR` A | Day pills and rule, meaning-colour markers joined by a line, inline author line, row bones, standard couldn't-load with Try again; history cards say "Newest first" with the history icon | `history-*.png` |
| 22 Files on a message | `mZdBv` B | Cards two across under the message words (moved there with `cardsTarget`), paperclip stays in the footer; uploading bar, failed red edge, rejection line | `composer-*.png`, `emaildialog-light.png`, `emailfiles-*.png`, `support-light.png` |
| 23 Jafar sign-in | `Y0A1Z` B | `JafarAuthCard` split screen; status tiles (48, new `IconTile` size) on message pages; critical error box | `jafar-*.png` |

Found and fixed during the check: photos inset in grey boxes, no gap under the Files header, caption box drawn
as a labelled text area, a global `*::placeholder { padding-top: 24px }` pushing hints down (cancelled only
inside the new boxes; the global rule itself is untouched and waits for Jafar), long names in the people menu.

Limits: uploads from this worktree's port fail at storage (CORS), so "ready" file cards were shown with the
storage reply faked in the test browser; the failed look is the real one. No type check or test suites were run
(Jafar: run them when the campaign finishes); every changed Svelte file compiled in the dev server.
