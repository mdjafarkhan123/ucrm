# A5 — Question editor

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1
**Code:** `main`
**Done when:** Jafar adds a question, publishes, and a client mid-setup sees and answers it; a built-in question
offers no Delete; a stage tied to Website shows only to a client whose package includes Website

## Steps

- [x] Migration `20261008090000_setup_question_editor` applied to dev; rules proven in SQL (rolled back)
- [x] Yes/no (radio) and date (calendar) answers in the client wizard; date validation
- [x] API `PATCH /api/jafar/setup/draft/stages/[stage]` + Zod; page `/jafar/setup/[stage]`; "Edit questions" link; publish review lists question changes
- [x] Unit tests (full suite green), svelte-check 0 errors, browser-checked (add pick-one question, empty-choice error, save, review wording, discard), committed
- [ ] Jafar's hands-on proof of the done-check (needs a real publish)

## Next

Waiting on Jafar. Ask him to: start a draft on `/jafar/setup`, Edit questions on "Your business", add a real
question he wants clients asked, save, publish; then log in as the contractor owner (CLAUDE.md logins) and
answer it on `/setup/business`. Website-only proof needs a stage with a question tied to Website plus a client
whose package edition includes Website (none on dev yet). While there, he can also give one question a "Show this question: Only when…" rule and watch it appear on
`/setup/business` only after the matching answer (A5b's live look). A5d's client boxes (tick several with Other,
money, distance, time, colours…) also get their first live look here: check the money sign lines up and does not
cover the label. A5c's live look too: add a "Photo or file" question, upload a photo as the client, see
"Checking for viruses…" turn ready within about a minute, then open it from the organization's setup in Jafar's panel.
Then close A5.
Do NOT publish test questions yourself — keys are never reused.

## Notes

- Moving a built-in question to a different stage is not in this part; only reordering within its stage.
