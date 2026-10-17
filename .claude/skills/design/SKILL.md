---
name: design
description: Route every screen, component, styling or frontend task to its design guidance and run the shared screen check.
---

# Shared design workflow

## Choose the look

1. **New concept** (the app's next look, drawn in `concept.pen`): follow the brief below, the approved Foundation
   boards in that file, and the [concept plan](../../../docs/contractor-design-concept-behavior-contract.md).
2. **Fixing or extending a live screen:** load [Classic](../design-classic/SKILL.md) and keep the screen as it is.
   Classic stays live until Jafar approves a new look for rollout.
3. **Botanical:** load [Botanical](../design-botanical/SKILL.md).

Control Room, login and customer-facing pages keep their current look.

## Jafar's design brief

Every design, in Pencil or in code, meets this brief (Jafar, 2026-10-17).

- **Premium and calm.** Clean spacing, clear hierarchy, soft cards, one focal point per screen.
- **Contractor first.** Each block answers a question a contractor has on that screen. Remove blocks that do not.
- **Meaningful colour.** Colour names a kind of record, a part of the app, or a status. Icons carry that colour
  on tinted tiles across the whole app; actions (edit, delete, share, download) stay neutral. The colour map is
  the "Colour that means something" board in `concept.pen`.
- **One green action.** Brand green `#037741` (`--color-interactive`) marks the main button of each area. Light
  greens are for dark mode only.
- **Contrast with the background.** Every fill differs from the colour behind it, in light and dark mode.
- **App variables first.** Build from `src/lib/styles/_variables.scss`. Add a variable only when none fits.
- **Researched, not copied.** Check what Jobber and other leading products show and leave out; draw our own look.
- **Desktop web.** Design at 1440px wide.
- **Design → review → approve → build.** When a design needs data or behaviour the app lacks, list it for Jafar's
  decision before building.

In code, use semantic HTML and design tokens, and give every interactive control hover, focus and disabled
states. For a record detail page, its save bar or image attachments, read
[record page behaviour](../../../docs/record-page-behaviour.md) first.

## Design in Pencil first

Each look has its own Pencil file in the main project folder: `concept.pen`, `classic.pen`, `botanical.pen`.
Each opens with its design-system page: the app's colours, text sizes, spacing and parts.

1. **Open the right file.** Call `get_app_state`; the Pencil tools change only the open file. If it is the wrong
   one, ask Jafar to open the right one and wait.
2. **Design from the file's own parts.** Use copies of its parts and its colour and size names, never raw values.
   To change a part, change it on the design-system page first so every screen follows. Use the Lucide icon that
   matches the Tabler icon used in code. Finished when each screen exists at 1440px and a screenshot shows
   nothing cut off or misaligned.
3. **Show Jafar and wait.** Name the screens, say what each shows and which parts changed. Finished when he says
   yes; record his yes, the date and the screen names in the campaign's part note.
4. **Keep Pencil, code and skill the same.** A colour, size or part changed in Pencil changes in
   `src/lib/styles/_variables.scss` (or the component) and in this skill's pages in the same commit.

**Saving.** Pencil writes to disk only when the file is saved in the app (Ctrl+S). Before committing, check the
`.pen` file's modified time is newer than your last edit; if not, ask Jafar to save. Commit it in its own commit,
under a claim. Read a part again just before changing it, and leave changes you did not make as they are.

## Screen check

Run this before calling any visible change done.

1. Open the changed screen in the running app, signed in with a role from `Login.md` that sees the change.
2. Screenshot it at 1440px and 390px wide in every state the change touches: real data, empty, loading, error,
   long names; dark mode too when colour changed. A small change from existing parts needs only the changed spot.
3. Compare each screenshot with its approved Pencil screen: alignment, spacing, hierarchy, crowding, cut-off
   text, overflow.
4. Check keyboard use, visible focus, labels, contrast, and any permission difference the change touches.
5. Fix what you found and screenshot again. Done when a fresh round finds nothing to fix (at most three rounds;
   report what is left). Tell Jafar which screens and states you checked and the link to open.
