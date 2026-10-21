# Batch 42 client form and no-blend parts — build

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 3.
**Approved:** Jafar 2026-10-21 (records in `parts/c5-shared-parts.md`). **Stage:** waiting to be built.
**Done when:** every step below matches its Pencil board at 1440 light and dark, Built ticks updated, Pencil
drafts tidied (`docs/pencil-workflow.md` step 6), committed and pushed.

## Order (shared parts first; each reaches many screens)

1. **Client colour tokens.** `src/lib/styles/_variables.scss` lines ~300 and ~521: set the four client tokens to
   the values in design `colors.md` → Client colour (light and dark). Today dark mode uses the blue palette;
   replace it. Check the client header, client tiles, sidebar Clients icon.
2. **Switch.** `ui/SegmentedControl.svelte`: chosen option `--color-interactive` fill, text and icon
   `--color-surface`, `--shadow-button--raised`; track per `inputs.md` → Segmented switch (page colour on a
   white card, white on the page or a coloured top: give the component a prop for that). ~30 users; check
   Schedule views, signature pad, New job, client form. Board `SnDlF`.
3. **Buttons.** `ui/Button.svelte` secondary, danger, menu and icon kinds on `--color-interactive-background`,
   white on a coloured top (prop, used by the record header and create-form header); states per `buttons.md`.
   Board: Parts → Buttons.
4. **Fields.** `ui/Input`, `ui/Select`, `ui/SearchInput` box on `--color-surface--background` on white cards,
   `--color-surface` on the page or a coloured top (prop). Notes field (`forms/FormNotesCard`, Notes panel) and
   the empty box in `files/PendingFilesCard` on `--color-surface--background`.
5. **Client form.** `clients/ClientForm.svelte` (pages `(app)/clients/new`, `(app)/clients/[id=uuid]/edit`) to
   board `fJ8Mx` (light `Hk64M`, states `Gk62B`, dark `K1F6h`); look in `layout.md` → New client page. Restyle
   only: same fields, words, warnings, buttons and save logic. The first card replaces the Primary details
   SectionBlock (coloured top with the two switches, then the fields); front icons on email, phone, billing
   email, company; exact duplicate gives the email box the error edge.

**Top bar:** unchanged. Jafar chose to keep it on the page colour (2026-10-21); the white-panel try was undone.

## Proof

Screenshots of every step beside its Pencil frame at 1440 light and dark (memory: compare live with Pencil),
in `docs/evidence/2026-10-2x-no-blend/README.md`. Run the design blend check idea: no part's fill equals what is
behind it.
