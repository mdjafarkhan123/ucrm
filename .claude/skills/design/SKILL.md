---
name: design
description: Route every screen, component, styling or frontend task to its design guidance and run the shared screen check.
---

# Shared design workflow

## Choose the presentation first

1. **New concept** (the app's next look, drawn in `concept.pen`): follow the brief below, the approved Foundation
   boards in that file, and the [concept plan](../../../docs/contractor-design-concept-behavior-contract.md).
2. **Existing-app maintenance:** load [Classic](../design-classic/SKILL.md) and preserve the actual screen. Classic
   stays live until a new look is approved for rollout.
3. **Botanical**, including private demos: load [Botanical](../design-botanical/SKILL.md). Theme switching and
   selected-only delivery are owned by the [CRM design-system agreement](../../../docs/crm-design-system-behavior-contract.md).

Work spanning two looks loads each and checks each. Control Room, login and customer-facing pages keep their
current look in the first release.

## Jafar's design brief

Every design, in Pencil or in code, meets this brief (Jafar, 2026-10-17). Read it before drawing anything.

- **Premium and calm.** Polished, modern product work, as a top Dribbble product designer would make it: crafted
  enough to feel premium, quiet enough to read at a glance.
- **Contractor first.** Each screen shows what a contractor most needs right now; every block earns its place.
- **Meaningful colour.** Colour names a kind of record, a part of the app, or a status. Icons carry that colour
  across the whole app on tinted tiles; actions (edit, delete, share, download) stay neutral. The colour map is
  the "Colour that means something" board in `concept.pen`.
- **One green action.** Brand green `#037741` (`--color-interactive`) marks the main button of each area. Light
  greens belong to dark mode.
- **Contrast with the background.** Every fill stands apart from what sits behind it, in light and dark mode.
- **App variables first.** Build from `src/lib/styles/_variables.scss`. Add a variable only when none fits.
- **Proven, then original.** Research what leading products show and leave out; design our own look.
- **Desktop web.** Design at 1440px; phone layouts wait for the native-app phase.
- **Design → review → approve → build.** When a design needs data or behaviour the app lacks, list it for Jafar's
  decision before building.

In code, use semantic HTML and semantic design tokens, and give every interactive control hover, focus and
disabled states. Building a record detail page, its save bar, or image attachments: read
[record page behaviour](../../../docs/record-page-behaviour.md) first.

## Design in Pencil first

The project rule decides which work starts here. Each look has its own Pencil file in the main project folder:
`concept.pen` (new concept), `classic.pen` (Classic), `botanical.pen` (Botanical). Each file opens with its
design-system page — the colours, text sizes, spacing and parts copied from the app's real styles — and screens
sit beside it.

1. **Open the right file.** Call `get_app_state`: it names the file open in Pencil, and the Pencil tools change
   only that file. If it is the wrong one, ask Jafar to open the right one and wait.
2. **Design from the file's own parts.** Place copies of its parts and use its colour and size names, never raw
   values. If a part has to look different, change it on the design-system page first, so every screen using
   it follows. Pencil has no Tabler icons; use the Lucide icon with the same meaning, and Tabler in code.
   Finished when each screen exists at 1440px wide and a screenshot of each shows nothing cut off or misaligned.
3. **Show Jafar and wait.** Tell him the names of the screens to look at, what each shows, and which parts
   changed. Finished when he says yes; write his yes, the date and the screen names in the campaign's part
   note.
4. **Keep the three copies the same.** When a colour, size or part changed in Pencil, change it in the app's
   code (`src/lib/styles/_variables.scss` or the component) and in the design skill page that describes it, in
   the same commit. Finished when Pencil, the code and the skill page all give the same value.

**Saving the file.** Pencil writes to disk only when the file is saved in the app (Ctrl+S); edits made through the
tools stay in memory until then. Before committing, check the `.pen` file's modified time is newer than your last
edit, and ask Jafar to save if it is not. Commit the `.pen` file from the folder Pencil opened, under a claim
covering it, in its own commit. Jafar or another agent may be editing the same file, so read the parts you are
about to change again just before changing them, and leave changes you did not make as they are.

## Before calling a screen done

Look at the real screen the way a picky designer would, not at the code. A new screen or layout gets the full
check; a small change built from existing parts (a field, option, card or line) gets one 1440px and one 390px
screenshot of that spot, fixed until nothing looks off. Use the available browser tools, or Playwright.

1. Open each changed screen in the running app, signed in with a role from `Login.md` that sees the change.
2. Screenshot it at 1440px and 390px wide, in every state the change touches: realistic data, empty, loading,
   error, long names. Add dark mode when the change touches colour.
3. Critique each screenshot against its approved Pencil screen (or, for untouched screens, the existing
   blueprint): alignment, spacing, hierarchy, crowding, truncation, overflow, and anything that reads as a
   spreadsheet rather than a product.
4. Check keyboard navigation, visible focus, labels, text resizing, contrast, dismissal and phone navigation
   for the affected controls, and any permission differences the change touches.
5. Fix what the critique found, then screenshot again.

Done when a fresh round at both widths turns up nothing you would fix. Cap it at three rounds, then report
what still looks off. Tell Jafar which screens and states you checked, what you fixed, and the URL to open.
