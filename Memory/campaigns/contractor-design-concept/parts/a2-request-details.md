# A2 Request details (App look) - status

Branch `claude/a2-request-details` (worktree `.worktrees/a2-request-details`). Pencil frame `RyYaY`.

**Built:** Request details now uses the App look the Job details page uses: open page container, `RecordDetailLayout cards`,
the shared header (status, history, main action, client row with avatar, four fact tiles with icons incl. Request
subtotal from the pricing the page already loads), card sections with a second line under each title (Service
overview, On-site assessment, Products and services "n items", total row "Request subtotal"), the booked on-site visit as
a date tile + who + timer strip with a complete footer, and rail cards: dark Automatic follow-up (only when a follow-up
exists), Notes (flat rows, composer last, "Only your team sees these"), Photos and files.
Save bar / DetailEditBar behaviour is unchanged.

**Shared parts touched:** `SectionBlock` (hint = two-line header in cards, bordered pencil button), `RailCard` (`hint`,
count span), `ProductsAndServicesBlock` (`hint`, `totalLabel`), `NotesPanel` (cards CSS), `InquiryAutomationCard`
(dark feature look; also used by the Inbox rail, unchanged outside cards), `AssessmentBlock` (booked layout).
`AssessmentBlock` and the Service overview no longer render a fieldset on the detail page (a legend cut a gap in the card border).

**Evidence:** live screenshots 1440 light/dark and 1100 light, edit mode and save bar, mocked follow-up for the dark card
(scratchpad `a2req/`). Pencil was compared from its frame data and an earlier screenshot (Pencil app disconnected later).

**Not built (differs from Pencil, same call as Job details):** lifecycle strip (Request > Quote > Job > Invoice > Paid),
call/text/directions buttons, "REQUEST #n - From your website" label (no number or known source values in the data),
"More" text button (app uses the kebab menu everywhere), Follow-up "Pause, skip or stop" text button and "Messages sent"
legend (kept the existing menu), Photos card thumbnail grid (existing files card kept).
Jafar to decide: build the lifecycle strip and quick-contact buttons, or trim them from the design.
