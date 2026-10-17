# C1d — Concept buttons in the live app

**State:** Done — merged into main 2026-10-17 (Jafar chose to update buttons now rather than with the first concept screen).

**Built:** `src/lib/components/ui/Button.svelte` draws the `concept.pen` button set: `primary` = Main (green, raised; red Danger · confirm when `destructive`); `secondary` and `tertiary` = white bordered (red Danger text when `destructive`); new `quiet` variant for link-like actions. Sizes 32/36/44; 16px icons (18 large); loading keeps the button's colour, spinner replaces the icon or centres when there is none. Tokens added: `--shadow-button`, `--shadow-button--raised`, `--color-border--interactive--hover`, `--typography--fontSize-label` (13px; Pencil variable still to add, NOW step 1). Page-level overrides that forced old sizes/colours removed (list headers, client header, Home schedule card, payment receipt, quote deposit/automation, work header). Disabled list-header buttons stay white so they do not blend into the page.

**Checked:** Live screenshots (owner): list headers, Home, client and quote records, hover, focus, dark mode.

**Not yet in the concept look (own components, not `Button`):** menu triggers (`DropdownMenu` callers), `PencilButton`, top-bar Add new, icon buttons. Loading look not seen live yet.
