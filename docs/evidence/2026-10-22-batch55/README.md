# Batch 55 — New campaign · Delivery step (Pencil `DWtO4`, approved B)

Checked live on 2026-10-22 in Chrome (Raad LTD owner, side-by-side dev server on port 5191; the step column is
760). Light and dark compared with the Pencil board.

- `delivery-form-light.jpg`, `delivery-form-dark.jpg`: a form picked: path stops 3 and 4 show the form's real
  button words ("Book an assessment") and the form; the form row opens its Form select and Open form.
- `delivery-phone-light.jpg`: phone picked: "Call us" and the number in the path.

## Checked and working

Nothing picked (stops 3 and 4 open, "Pick one to continue."); Continue with nothing picked → form error card,
scrolled into view with focus; picking clears it; no website on file → row can't be picked with its reason; no
sender, no forms and no Marketing allowance (server answer faked in the browser only) → stop 1 warning edge,
`mail-x` tile, the warning notice strip with Set up a sender, the form row off, "Not in your plan yet" with a
warning mark; loading bones and couldn't load (each forced briefly in code, then undone); Continue → Review,
whose email shows the same button words.

## Changed beside the look

- Button words moved to `$lib/marketing/campaign-content.ts` (`MARKETING_FORM_CTA_LABELS`, website, phone),
  which the send code (`call-to-action.ts`) now reads too, so the step and the sent email can't disagree.
- Step track: step 4 hint "Button and replies", `send` icon (as drawn).
- Fixed: the Delivery error came back after Back then Continue; Back now clears it.

Unit checks: `npx vitest run src/lib/marketing/campaign-content.spec.ts src/lib/server/marketing/render-email.spec.ts
src/lib/server/marketing/dispatcher.spec.ts src/lib/server/marketing/test-send.spec.ts` (35/35). No type check
(Jafar: once at campaign end).

## Left as is / for Jafar

- The website-picked look was drawn but Raad LTD has no website on file, so it was checked only with the faked
  answer's row, not picked live.
- Stop 2's small line is the group's description, else its customer count (the drawing showed a rule).
- `MarketingSenderSummary` and `MarketingAllowanceNotice` are no longer used here; Review still uses them until
  Batch 56 is built.
