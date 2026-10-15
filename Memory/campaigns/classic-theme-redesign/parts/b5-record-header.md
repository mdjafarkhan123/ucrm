# B5 — shared work-record header

**Stage:** Complete and integrated 2026-10-15. Implementation `58c09284`.

**Agreement:** Existing approved `classic.pen` record frames, especially Job hero `mO4CI`;
[contract](../../../../docs/classic-theme-redesign-behavior-contract.md) and
[recipe](../../../../docs/classic-theme-redesign-design-recipe.md). Reused the recorded Jobber detail-page
research; this delivery changes presentation and adds the approved contact shortcuts, not record rules.

**Built:** Classic header card, record identity, compact client/address row, contact shortcuts, five-step
journey and facts strip. The record frame uses separate cards and a 336px rail, stacking below 1280px.
History, More, primary actions and staged title editing retain their existing handlers. Message uses the
existing permission query and inbox composer handoff; no send happens here. Directions uses only an explicit
service address. Phone/email and contact actions disappear when unavailable.

The journey uses only information already available to the reader: converted request targets, quote source
requests, progress-invoice jobs and active payment applications. Unknown steps stay neutral; opening a Job
never invents an earlier Request or Quote. Paid invoices show the verified paid state. Per-screen facts,
full upstream history and the rest of each page remain for B6 onward; this is not completion of those pages.

**Proof, 2026-10-15:** Real Job, Quote, Request, Invoice and Payment headers checked at 1440/1100 light/dark;
390px regression, long title/client, missing contacts/property, loading/error and 200% text checked.
Title editing/dirty state/Cancel, keyboard-opened history, Message handoff, converted-record navigation and
payment invoice links pass. Owner, field, sales, finance and office checked; restricted roles hide Message,
field cannot rename. Client frame checked. Private Botanical job/invoice preview retains legacy two-column
headers and no Classic tokens or visible Classic controls in light/dark.

Scripts/screenshots: `/tmp/classic-b5-*.cjs`, `/tmp/classic-b5-*.png`. Focused Svelte check with 1536MB heap:
zero errors, one pre-existing `JobVisitsSection` unused-selector warning. Svelte autofixer has no new issues;
existing title-focus effect and request draft-reset effects were inspected and retained. Three lifecycle
unit tests pass. Full-project checks were not run. Typed ESLint project loading was stopped for memory;
focused syntax lint uses the same repo rules with projectService disabled.

**Next:** B7 line items/totals before B6 Job details.
