# Classic theme redesign — design recipe

The short rules for designing Classic screens. Jafar's target is the
[plan](classic-theme-redesign-behavior-contract.md) § Design target. Each value lives in one place:

- **Values and parts:** the design-system page in `classic.pen` (`Classic design system · light` and `· dark`);
  in code, `src/lib/styles/_classic-theme-tokens.scss`. Older pointers to this recipe's § Tokens, § Page and
  shell, § Cards and rows, § Fields and buttons, § Featured card, § Rail cards and § Save bar mean these.
- **Layouts:** the approved frames in `classic.pen` — the six record pages (`… details · 1440`), the two
  Settings reference screens and `Home · Owner · 1440`. When this recipe and a frame disagree, the frame wins.
- **Exact sizes and the approved phone layout** that no frame shows: the full earlier recipe, kept in Git at
  commit `b35552b9` (`git show b35552b9:docs/classic-theme-redesign-design-recipe.md`).

## Working method

1. **Research first.** Study how relevant mature products (Jobber, Housecall Pro and ServiceTitan for
   contractor work) handle the user's task; read the page and its real states. Draw from working behavior and
   approved plans; show any new behavior to Jafar as a proposal.
2. **Create a new concept.** Arrange information around the user's real question and next action; do not
   redraw the live page box for box. Use the approved record-page language where it helps, not as a forced
   template for unrelated screens. Keep an existing idea only when it is genuinely the strongest solution.
3. **Build from parts.** Place instances from the design-system page with token colours. Complete the shared
   parts needed for the approved screen batch before building its screens. When a screen improves a part,
   update its design-system master, app component and guidance together.
4. **Fill with busy, believable data:** one contractor (Raad LTD, Burnaby BC), amounts that add up.
5. **Critique.** Export at scale 1 and read it full size: clipped text, misalignment, a fact shown twice,
   invented features, colour that breaks § Colour rule, or an element that blends into its background. Check
   dark mode. At most three rounds.
6. **Finish one screen before advancing.** Draw new concepts at desktop 1440 and phone 390, show Jafar, and
   wait for approval; he presses Ctrl+S in Pencil before `classic.pen` is committed. For the already approved
   desktop record/list screens, add and review the phone adaptation before code without repeating the desktop
   decision. Check the live screen in both widths and appearances. Remove superseded styling and rejected
   variants only after the approved replacement is saved. A screen can span sessions.

## Colour rule

A calm neutral base, and the brand green `#037741` with white text for each page's one main button. Light mode
uses no light green. Icons and accents may use multiple
colors wherever they improve beauty, recognition or scanning. Keep status meanings consistent; a colored icon
does not always need to announce a status. Use color deliberately and keep text readable.

| Meaning     | Colours                                                                                         |
| ----------- | ----------------------------------------------------------------------------------------------- |
| Section     | Business green, Sales & work teal, Communications blue, Automations amber, Team & access violet |
| Record type | Quote rose, invoice blue, request amber, job green, client violet                               |
| Status      | Red needs action, amber waiting, green done or happening now                                    |

An icon tile may identify a section, record type or action, or simply add a useful visual rhythm. Do not
apply the status palette to unrelated states in a way that changes its meaning.

Every element stands apart from what sits behind it, in light and dark. Never place a fill on a background of
the same or a near-identical colour (for example `chip` on `surface-soft`, or `surface-soft` on `surface-raised`
in dark): change the fill, or separate the two with a border.

## Record page structure

Header card (status pill, record number, title, client, Call / Message / Directions, the main button named for
the next step), then the lifecycle track (Request, Quote, Job, Invoice, Paid; each page lights its own), then
the key facts strip. Work fills the main column; money, wrap-up and reference fill the rail, in that order.
