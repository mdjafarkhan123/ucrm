# B4 — Classic Save bar

**State:** Integration candidate `codex/b4-save-bar-integration` at merge commit `1add398c`, based on `32e5b80d`; waiting to update `main` after the active Schedule Pencil work is saved and the main writer releases the reservation. **Plan:**
`docs/classic-theme-redesign-behavior-contract.md` § Settings additions and
`docs/classic-theme-redesign-design-recipe.md` § Save bar.

## Approved design and behavior

On 2026-10-15 Jafar approved the two reusable states shown in `classic.pen`, design-system page `07 Featured
& saving`: `Save bar · unsaved` and `Save bar · resting` (“apprve”). Full-page forms keep their current bar
and show a resting state when clean; once dirty, show “You have unsaved changes.” Detail pages show the bar
at the same points as before. Save, Cancel, validation, permissions and staged-save behavior stay the same.

## Implementation

`SaveBarStatus.svelte` provides the shared state copy and indicator. `StickyActionBar.svelte` owns the
Classic-only surface and action sizing. `RecordFormLayout.svelte` accepts the existing dirty flag and passes
it to the status; contractor forms and settings forms with existing dirty tracking supply it. The automation
builder keeps its live/publish note and conflict actions alongside the shared status. `DetailEditBar.svelte`
keeps the original edit/dirty visibility and error copy. Styles are gated on `data-presentation="classic"`;
outside Classic the status is hidden, the action wrapper uses `display: contents`, and existing form and
other action bar behavior remains intact. Tokens and the Classic design guide document the reusable state.

## Verification

- Live Classic Business profile at `http://localhost:4176/settings/business-profile`: clean and dirty
  states checked in light and dark at 1280×720; dirty state checked at 390×844. Both buttons remain inside
  the phone viewport. Screenshots: `/tmp/classic-b4-light-clean.png`,
  `/tmp/classic-b4-light-dirty.png`, `/tmp/classic-b4-dark-clean.png`,
  `/tmp/classic-b4-dark-dirty.png`, and `/tmp/classic-b4-phone-dirty.png`.
- Save path: saved a temporary tagline, saw the saved confirmation and clean state, then saved the original
  tagline back and confirmed the original value. Cancel path: changed the tagline again, cancelled, and
  confirmed the original value and disabled actions returned.
- Automation builder clean and dirty states checked in Classic; duplicate helper text is hidden while the
  shared status is visible, and the action row remains aligned. Screenshots:
  `/tmp/classic-b4-automation-clean.png` and `/tmp/classic-b4-automation-dirty.png`. The temporary name was
  cleared before leaving; no draft was saved.
- Botanical Business profile checked at `http://localhost:4175/settings/business-profile`:
  the shared status and Save check icon stay hidden, with the Botanical save area unchanged. Screenshot:
  `/tmp/classic-b4-botanical.png`.
- `npm run dev -- --host 127.0.0.1 --port 4176` and its Botanical preview both reached Vite ready and
  served the checked pages. The only compiler warning shown was the existing unused selector in
  `JobVisitsSection.svelte:1372`.
- `git diff --check` passed. `prettier --check` passed for all changed Svelte, SCSS, route and memory files.
- `npm run check` was run again on the integrated tree. `svelte-check` used more than 4 GB of memory and
  kept running for 3 minutes 53 seconds without producing a result; it was stopped. The full Svelte/TypeScript
  check result is unknown. No test suite was run.

## Next

The save bar and automation builder passed the live screen and behavior checks. The changes are merged in
candidate commit `1add398c` against `32e5b80d`; `main` has not been updated because the root checkout now has
a large uncommitted Schedule Pencil change under an active reservation. Formatting and `git diff --check`
passed on the candidate; the full Svelte/TypeScript check remains inconclusive as noted above. Once the active
writer saves and releases the reservation, fetch current `main`, merge again if needed, rerun the appropriate
check and push. Keep source claim `1dab5a348cb4` and integration claim `023775c30fd3` until successful push.
