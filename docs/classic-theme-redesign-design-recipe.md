# Classic theme redesign — design recipe

The short rules for designing Classic screens. Jafar's target is the
[plan](classic-theme-redesign-behavior-contract.md) § Direction agreed so far. Each value lives in one place:

- **Values and parts:** the design-system page in `classic.pen` (`Classic design system · light` and `· dark`);
  in code, `src/lib/styles/_classic-theme-tokens.scss`. Older pointers to this recipe's § Tokens, § Page and
  shell, § Cards and rows, § Fields and buttons, § Featured card, § Rail cards and § Save bar mean these.
- **Layouts:** the approved frames in `classic.pen` — the six record pages (`… details · 1440`), the two
  Settings reference screens and `Home · Owner · 1440`. When this recipe and a frame disagree, the frame wins.
- **Exact sizes and the approved phone layout** that no frame shows: the full earlier recipe, kept in Git at
  commit `b35552b9` (`git show b35552b9:docs/classic-theme-redesign-design-recipe.md`).

## Working method

1. **Research first.** Study how top products (Jobber, Housecall Pro, ServiceTitan) handle the screen and what
   contractors need from it; read the page's `+page.svelte` for its real content. Everything drawn exists in
   code or the plan; anything new goes to Jafar as a proposal.
2. **Redesign.** Give the screen a new layout in the record pages' language: header card with key facts, main
   column beside a 336 rail, one dark featured card at most. Screens Jafar already approved keep their placement.
3. **Build from parts.** Place instances from the design-system page with token colours; when a part must
   change, change it there first.
4. **Fill with busy, believable data:** one contractor (Raad LTD, Burnaby BC), amounts that add up.
5. **Critique.** Export at scale 1 and read it full size: clipped text, misalignment, a fact shown twice,
   invented features, colour that breaks § Colour rule, an element that blends into its background. Check dark
   mode. At most three rounds.
6. **One screen per session.** Desktop 1440 only; phone layouts are adapted while building. Show Jafar and stop;
   he presses Ctrl+S in Pencil before `classic.pen` is committed.

## Colour rule

A calm neutral base, and the brand green `#037741` with white text for each page's one main button. Light mode
uses no light green. Colour appears only when it means something:

| Meaning     | Colours                                                                                         |
| ----------- | ----------------------------------------------------------------------------------------------- |
| Section     | Business green, Sales & work teal, Communications blue, Automations amber, Team & access violet |
| Record type | Quote rose, invoice blue, request amber, job green, client violet                               |
| Status      | Red needs action, amber waiting, green done or happening now                                    |

A coloured icon tile tells the user something — a status needing attention, another record's type, an
automation. Every other icon stays neutral.

Every element stands apart from what sits behind it, in light and dark. Never place a fill on a background of
the same or a near-identical colour (for example `chip` on `surface-soft`, or `surface-soft` on `surface-raised`
in dark): change the fill, or separate the two with a border.

## Record page structure

Header card (status pill, record number, title, client, Call / Message / Directions, the main button named for
the next step), then the lifecycle track (Request, Quote, Job, Invoice, Paid; each page lights its own), then
the key facts strip. Work fills the main column; money, wrap-up and reference fill the rail, in that order.
