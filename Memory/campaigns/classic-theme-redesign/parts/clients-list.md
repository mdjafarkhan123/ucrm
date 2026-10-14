# Clients list — design

**Campaign:** classic-theme-redesign · **Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Later stages
**Stage:** Design · **Follows:** the list-pages note on branch `claude/jobs-list-design`
(`parts/list-pages.md`; Jobs list approved 2026-10-14, "list pages come first").
**Code:** `classic.pen` in the main folder; commit it from main under a claim covering `classic-pen-clients-list`.
**Done when:** Jafar approves `Clients · 1440` and the answer is written here.

## Steps

- [x] Research: Jobber's client list (new-lead and new-client counts on top, Tags and Status filters, sort by
      name or last activity, More actions holds Import, Export and Merge); Housecall Pro's customer list (filters
      by tag, status, lead source and customer type); the real page `src/routes/(app)/clients/+page.svelte`.
- [x] `Clients · 1440` (`iJgiT`, x 6160, y 4338) drawn from `Jobs · 1440`, light and dark checked. Waiting for
      Jafar.
- [ ] Jafar's answer on the proposals below.

## Proposals on the screen (new; not in the app today)

- **Client book tiles** Leads, Customers and Archived show counts and filter the table when pressed. Today the
  status filter has no counts.
- **Popular tags** strip: the most-used tags with counts; pressing one filters by that tag.
- **Dark card, from Jobber's metrics**: new customers in the past 30 days compared with the 30 days before,
  new leads in the past 30 days, and new clients this year. It needs counts from `created_at` and
  `converted_to_customer_at`.
- **Table:** search and the Status and Tags filters always show in the card header, with no Filters button. Each
  row shows the phone number above the email (today only one shows), and Person or Company with the lead
  source under the name. The Updated column shows `updated_at`, which is already the default sort. Tags show
  one chip plus "+N". Lead is amber and Customer is green.

## Notes

- Kept from the real page: row checkboxes and bulk Archive/Restore, the row menu (View, Edit,
  Archive/Restore), More actions (Import; Merge for `customers.merge`; Export for owner or admin), Load more
  with keyset paging, and the refused, empty, loading and error states. These states were not drawn; build
  them from the existing components.
- Lead-to-customer rule: not checked. The tile hints avoid stating one.
