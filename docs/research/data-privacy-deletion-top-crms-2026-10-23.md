# Data privacy and deletion — how top CRMs do it

**Date:** 2026-10-23 · **Campaign:** data-privacy-deletion, planning research
**Question:** How do HighLevel, Jobber and HubSpot let a business delete a customer, delete a conversation,
export data, and handle a person's privacy request — and what must a business keep by law?

Labels: **Verified** = read on the vendor's or law's own page. **Inference** = our reading. **Proposal** = what
we would do (the plan, `docs/data-privacy-deletion-behavior-contract.md`, holds the agreed version).

## 1. Deleting a customer

| | HighLevel | Jobber | HubSpot |
| --- | --- | --- | --- |
| Undo window | 60 days ([restore][hl-restore]) | None — "permanent and can't be undone" ([client basics][jb-basics]) | 90 days in a recycle bin ([restore][hs-restore]) |
| What goes with it | Conversations, notes, tasks, activity ([delete][hl-delete]) | "All associated work, such as requests, quotes, jobs, and invoices" ([client basics][jb-basics]) | Activity is unlinked; restored on undo ([deletion types][hs-types]) |
| Who | Admins only ([delete][hl-delete]) | Not stated | "Delete contacts" permission |
| Confirmation | Type DELETE ([delete][hl-delete]) | Prompt lists what will be removed ([client basics][jb-basics]) | Dialog |
| Bulk | Yes, undoable as one job ([restore][hl-restore]) | Yes, trash icon on the list ([client basics][jb-basics]) | Yes |
| Gentler option | — | Archive keeps all history and the client hub ([archiving][jb-archive]) | — |

**Verified:** HighLevel's two help articles disagree on whether a restored contact gets its conversations back
([delete][hl-delete] says no; the newer [restore][hl-restore] article says yes). HighLevel accounts set up for
HIPAA cannot restore at all ([restore][hl-restore]).

**Inference:** a waiting period before data is really gone is the common pattern (HighLevel, HubSpot); Jobber is
the outlier. Our approved client rule already chose a 30-day Recently Deleted
(`docs/client-property-behavior-contract.md` § Archive, deletion, and retention), matching our Files trash
(`docs/files-media-behavior-contract.md` § Trash, retention, and export).

## 2. Deleting for a privacy request ("forget me")

**Verified — HubSpot has a second, stronger delete** ([permanent delete][hs-gdpr], [deletion types][hs-types]):

- Separate "Permanently delete contacts" permission; one record at a time, never bulk or by workflow.
- Skips the recycle bin and cannot be restored; fully purged within 30 days.
- Removes the record, email/call history, form submissions, inbox conversations, quotes; keeps only anonymous
  totals in reports.
- Blocks the email from being re-added by hand or import; a new website form or inbox email still creates a
  fresh record with no history.
- Optional confirmation email to a chosen user, as proof.

HighLevel and Jobber document no separate privacy delete: their ordinary delete is the tool.

**Verified — HubSpot's Data Request Manager** ([requests][hs-requests]) gives businesses a public request page,
a list of incoming deletion/export requests with deadlines, and a "completed" mark. Super Admins only.

## 3. Deleting a conversation

**Verified — HighLevel:** "Permanently deletes the selected conversations… deleted conversations cannot be
recovered", available as a bulk action in the inbox ([conversation bulk actions][hl-convo]). Our approved inbox
rule already follows this (`docs/unified-inbox-behavior-contract.md` § Inbox handling) and the permission
`conversations.permanently_delete` exists with no feature behind it.

## 4. Exporting data

| | HighLevel | Jobber | HubSpot |
| --- | --- | --- | --- |
| Customer list | CSV, admins only, file kept 30 days; no message history ([export][hl-export]) | CSV emailed, admins only, 1,500 rows per file ([export][jb-export]) | CSV/XLSX ([export records][hs-export]) |
| One person's data | — | — | "Export contact data" on the record: properties with history, activities, linked records ([contact export][hs-contact-export]) |
| Everything when leaving | Export before cancelling; deleted 90 days after ([cancel][hl-cancel]) | Reports as CSV, documents one by one; closing is permanent ([close][jb-close]) | Account content export ([export content][hs-content]) |

**Today in our app (code, 2026-10-23):** a client package (zip of CSVs, `src/lib/server/exports/client-export.ts`),
Price Book CSV, the accountant's financial package (`src/lib/server/exports/financial-export.ts`), and a zip of
every file (`src/lib/server/files/organization-export.ts`). Missing: requests, quotes, jobs, messages, and any
one-person download.

## 5. A whole business leaving

**Verified:** HighLevel keeps a cancelled account 90 days, then deletes it permanently; numbers go after 14 days;
a "Data Deletion Request Form" deletes sooner ([cancel][hl-cancel]). Jobber separates cancel (data kept) from
close (gone) ([close][jb-close]). **Ours today:** a 30-day recoverable closure, then full purge, with Jafar's
early delete (`docs/jafar-completion-contract.md` § Organization closure,
`src/lib/server/jafar/organization-closure-cron.ts`).

## 6. Who answers a person's request — the law

- **The business answers; we help.** Under GDPR the business holding its customers' details is the controller;
  we are its processor, who must "assist the controller… to respond to requests" and, when the service ends,
  delete or return the data at the business's choice ([GDPR Art. 28(3)(e),(g)][gdpr-28]). California's rule is
  the same: a service provider "shall cooperate with the business" and need not act on a request sent directly
  to it ([Cal. Civ. Code 1798.105][ccpa-105]). Jobber's policy says the same about its customers' clients
  ([Jobber privacy][jb-privacy]).
- **Deadline:** one month, extendable by two in hard cases with notice ([GDPR Art. 12(3)][gdpr-12]).
- **Records the law makes a business keep win over deletion** ([GDPR Art. 17(3)(b),(e)][gdpr-17]). US tax
  records: normally 3 years, up to 7 for bad-debt claims, 4 for payroll ([IRS][irs]). **Inference:** invoices,
  payments and refunds must survive a privacy delete, unchanged, for at least the tax period.
- **Messenger:** our own Data deletion page promises that Uplift deletes Messenger messages and the linked
  Facebook ID on request and tells the business (`docs/marketing-site/legal-pages.md` § Data deletion).

## 7. What this means for us (inference → proposals in the plan)

1. Keep the approved 30-day Recently Deleted for everyday deletes; add HubSpot's "delete permanently now" for
   privacy requests, one client at a time, owner/admin only.
2. Money records (issued invoices, payments, refunds) stay exactly as issued after any delete; everything else
   about the person goes.
3. Keep a person's "stop messaging me" after deletion so no import or automation can text or email them again
   (HubSpot's blocklist, narrowed to opt-outs).
4. Add HubSpot's one-person download; fill the gaps in the business export (work records, messages).
5. Build the approved permanent conversation delete.
6. Give Jafar a tool to find which businesses hold a person's details and forward or carry out the request, with
   a log and a 30-day due date.

[hl-delete]: https://help.gohighlevel.com/support/solutions/articles/155000000583-how-to-delete-contacts-and-their-data
[hl-restore]: https://help.gohighlevel.com/support/solutions/articles/48001211386-step-by-step-guide-restoring-deleted-contacts
[hl-convo]: https://help.gohighlevel.com/support/solutions/articles/48001222121-overview-of-conversation-filters
[hl-export]: https://help.gohighlevel.com/support/solutions/articles/48001238482-contacts-export-as-csv-upgrade
[hl-cancel]: https://help.gohighlevel.com/support/solutions/articles/155000004281-what-happen-s-to-your-data-when-you-cancel-your-highlevel-subscription-
[jb-basics]: https://help.getjobber.com/en/articles/client-basics/
[jb-archive]: https://help.getjobber.com/en/articles/client-archiving/
[jb-export]: https://help.getjobber.com/hc/en-us/articles/115009619328-Export-Client-Information
[jb-close]: https://help.getjobber.com/hc/en-us/articles/6424318975511-How-Do-I-Permanently-Close-My-Account
[jb-privacy]: https://getjobber.com/legal/privacy-policy/
[hs-restore]: https://knowledge.hubspot.com/records/restore-deleted-records
[hs-gdpr]: https://knowledge.hubspot.com/privacy-and-consent/how-do-i-perform-a-gdpr-delete-in-hubspot
[hs-types]: https://knowledge.hubspot.com/privacy-and-consent/understand-restorable-and-permanent-contact-deletions
[hs-requests]: https://knowledge.hubspot.com/privacy-and-consent/manage-data-privacy-requests
[hs-export]: https://knowledge.hubspot.com/import-and-export/export-records
[hs-contact-export]: https://knowledge.hubspot.com/import-and-export/export-contact-data
[hs-content]: https://knowledge.hubspot.com/articles/kcs_article/account/how-do-i-download-my-content-and-data-when-canceling-my-hubspot-account
[gdpr-12]: https://gdpr-info.eu/art-12-gdpr/
[gdpr-17]: https://gdpr-info.eu/art-17-gdpr/
[gdpr-28]: https://gdpr-info.eu/art-28-gdpr/
[ccpa-105]: https://codes.findlaw.com/ca/civil-code/civ-sect-1798-105/
[irs]: https://www.irs.gov/businesses/small-businesses-self-employed/how-long-should-i-keep-records
