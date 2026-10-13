# 2 — Design: record page family

**Campaign:** classic-theme-redesign · **Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Design
principles, § Direction agreed so far
**Stage:** Design
**Code:** `classic.pen` in the main folder (Pencil saves there); commit it from main in its own commit, under a
claim covering `classic-pen`.
**Done when:** Jafar says yes to the named screens; date and names recorded in the plan.
**Read next:** `docs/classic-theme-redesign-design-recipe.md` — its working method governs every step below;
`.claude/skills/design/SKILL.md` § Design in Pencil first, then `design-classic`; the Pencil
MCP's own skill and `execute.md`; each page's `src/routes/(app)/<record>/[id=uuid]/+page.svelte` for its real
sections.

## Steps

- [x] Switch every text node in `Job details · Claude concept · Job cockpit · 1440` (frame `oNoOG`, including
      its sidebar and top-bar copies) from Plus Jakarta Sans to Inter; re-check nothing clips — done
      2026-10-13, all 216 texts use `$font-family`
- [x] Add the recipe's raw values (colours, 20px card corner, shadows) to the Classic design-system page as
      named tokens with light and dark values; point the job concept and the recipe at the token names —
      done 2026-10-13: 23 tokens; Card part, Button part (`$radius-control`, primary glow) updated to match
      (Jafar: "if new design require to change any design system we will do it to match")
- [x] Design the quote and invoice pages from the same parts; show Jafar them beside the job page — drawn
      2026-10-13 (`Quote details · Classic redesign · 1440`, `Invoice details · Classic redesign · 1440`,
      right of the job screen); job track and wording aligned to them. Jafar 2026-10-13: "Looks good, continue",
      including the four layout moves listed below
- [x] Design a Settings page with the new cards — drawn 2026-10-13: `Settings · Business profile · Classic
      redesign · 1440` (form cards, floating Save bar) and `Settings · Home · Classic redesign · 1440` (group
      cards with setting tiles), right of the invoice. Jafar 2026-10-13: "Looks right but… too plain, not
      like Dribbble"
- [x] Claude's own concept, free of the current design system (Jafar 2026-10-13: "what you will design
      despite of existing design … would be the main"; "not too much colorful … like rainbow, rather follow
      the best ui/ux designer") — drawn 2026-10-13 below the originals: `Settings · Home · Claude concept ·
      1440` (frame `XwqtP`) and `Settings · Business profile · Claude concept · 1440` (frame `ofzTY`). Dark ink
      sidebar, dark-green business banner with lime glow, ink primary buttons; raw hex values, no tokens yet;
      light mode only. Colour rule (Jafar 2026-10-13: "use rainbow like different color where it make
      sense"): section colour — Business green, Communications blue, Automations amber, Team & access violet
      on tab dot, group icon and soft tiles; record colour — quotes rose, invoices blue, requests amber, jobs
      green; status colour — red to do, amber in review, green ready. Ideas not in the app yet, each
      needing Jafar's yes: settings search, Setup status card, "What customers see" preview, "Where this is
      used" card, unsaved-changes text in the Save bar
- [ ] Jafar picks a direction: the concept becomes the main look (then restyle job, quote, invoice to match
      and turn its values into tokens), or keep the current family
- [ ] Design the request, payment and client pages
- [ ] Record Jafar's yes, the date and the screen names in the plan

## Next

1. Get Jafar's verdict on the two Claude-concept screens and on each listed idea; record it here and in the
   plan. If he picks the concept, update the recipe and design-system page before more screens.
2. Then design the request, payment and client pages: read each `+page.svelte`, copy the shell and parts from
   the quote/invoice screens, follow the recipe.

Layout moves Jafar accepted 2026-10-13: invoice Terms & dates folded into the key facts strip (pencil);
discount and tax as rows in the totals block; quote photos moved to the rail; History card tabs on the
invoice. Before any `classic.pen` change, claim `classic-pen` (`agent-work.py`); ask Jafar to press Ctrl+S
in Pencil before committing it.
