# Classic redesign — remaining shared parts

**Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Design and build loop · **Order approved:**
Jafar, 2026-10-15. B1–B4 and B3b are integrated. Next is B5; do not repeat completed shared parts.

Build only the shared parts needed by approved and next-up screens. Reuse the existing component when its
structure and behavior match. Pencil is the visual source; the live app and product contracts own behavior.
Each group covers light, dark, hover, focus, disabled, error or empty states that apply, and desktop-width checks.
Verify a real use of each part in the app and compare Botanical before closing it.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| B3b.1 Catalogue in Pencil | Copy approved examples to the Classic design-system page and complete missing states for Dialog, ConfirmDialog, DropdownMenu, Popover, Tabs, table/list rows, Banner, Toast, Tooltip, Avatar, FilterChip, SearchInput, date picker and Segmented control icons | B4 | The parts needed by the approved record, list and Schedule screens are named, reusable, visually checked and approved by Jafar; speculative parts are left for their screen | Done 2026-10-15 — Jafar approved Option A, light and dark; [note](../parts/b3b-inventory.md) |
| B3b.2 Overlays and choices | Classic Dialog, ConfirmDialog, DropdownMenu, Popover, Tabs and Segmented control icons | B3b.1 | Existing open, dismiss, keyboard, focus and disabled behavior remains; approved visuals match in real record and Schedule examples | Done 2026-10-15 — [proof](../parts/b3b2-b3b3-proof.md) |
| B3b.3 Finding and showing records | Table/list rows, FilterChip, SearchInput, Avatar and date picker | B3b.1 | List and form examples use the shared parts; searching, filtering, selection and date choice still work for permitted roles | Done 2026-10-15 — [proof](../parts/b3b2-b3b3-proof.md) |
| B3b.4 Feedback | Banner, Toast and Tooltip | B3b.1 | Success, error, loading and help states remain understandable and reachable; Classic matches Pencil and Botanical stays unchanged | Done 2026-10-15 — [proof](../parts/b3b4-feedback.md); focused checks and live Classic/Botanical verification passed |

If the inventory finds one of these already covered by B3, record that evidence and close that item without
rebuilding it. A material visual change to an approved part returns to Jafar before code.
