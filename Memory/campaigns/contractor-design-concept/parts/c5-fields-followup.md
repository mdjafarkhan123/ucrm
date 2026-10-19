# Fields — approved and built

**Stage:** Integrated on main, 2026-10-19. Jafar approved Fields board `khuNF` and the added interaction states.
**Implementation:** `src/lib/components/ui/{Input,Select,Textarea,SearchInput,Badge}.svelte`.

## Delivered

Labels above text boxes and dropdowns; 40px base and 36px small inputs; hover/focus/error/disabled states. Textareas use the approved count wording and error icon. Dropdown menus retain Bits UI interaction, show chosen ticks, wrap long choices, and support corrective errors. Search has clear hover/pressed feedback, respects disabled state, and restores focus after clearing. Badges use roomier pill sizes, 6px dots, and status/record tones.

Preserved component bindings, callbacks, existing native validation behavior, and Select props. New optional Select invalid/errorMessage and Badge record tones implement the approved presentation. Shared parts apply wherever these components are used; separate controls (CountryPicker, MoneyInput, StatusBadge, etc.) remain on the checklist.

## Evidence

- Focused ESLint on the five changed components: pass.
- Svelte preprocessing and client compilation on all five: zero warnings. Svelte MCP autofixer: zero issues; retained SearchInput element binding because clear returns focus to that input (advisory attachment suggestion only).
- Live owner journey on `/clients/new`: typed names, changed communication setting by keyboard, typed notes; counter changed from 500 to 478 left. Checked light and dark; cancelled without saving a client.
- Live `/clients`: searched Sarah, saw No matching clients, cleared search and saw the list return.
- Temporary browser proof using actual components: errors linked with aria-describedby; disabled fields and search clear disabled; selected dropdown option; cleared search and confirmed input focus. Light/dark screenshots and narrow layout inspection. Proof route removed after checks.
- Local screenshots: `tmp/field-proof/fields-light.jpg`, `fields-dark.jpg`, `fields-narrow.jpg`, `clients-search-dark.jpg`.

No full-project typecheck, build, or test suite run, per Jafar's campaign instruction. No server write path changed. Page-specific layouts and controls outside this batch keep their existing appearance until their own redesign.

**Next:** remaining shared parts in `stages/list-1a-parts.md`, then Schedule. This batch is complete.
