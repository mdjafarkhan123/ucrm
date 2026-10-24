# Data privacy and deletion

**Status:** Jafar chose all four open behaviours on 2026-10-24 (delete now, one-customer download, whole-business
export, Jafar's privacy tool); the rest restates rules he approved earlier. Whole-plan approval pending.

## Summary

Businesses on Uplift hold their customers' names, phone numbers, messages, files and money records. Today a
business can only archive a customer. It cannot delete one, delete a conversation, or give a customer a copy of
their information. So when someone says "delete everything you have on me", the request has to be emailed to
Uplift and handled by hand. This campaign gives every business the delete, restore and download tools that
HighLevel, Jobber and HubSpot offer. It keeps the invoices and payments that tax law requires a business to keep,
and gives Jafar a panel tool for requests that come straight to Uplift. The tools are shared platform parts, so
the Medspa edition gets them too. Evidence: `docs/research/data-privacy-deletion-top-crms-2026-10-23.md`.

## Problem and audience

- **Business owners and admins** need to clean up: duplicates the merge tool doesn't fit, test records, spam
  leads, and customers who have asked to be forgotten. Privacy laws give them one month to answer a request
  (GDPR) and require them to keep tax records (US: 3–7 years).
- **Their customers** have a right to a copy of their information and to have it deleted. They ask the
  business, because the business decides what happens to their data; Uplift must help the business do it.
- **Jafar** gets requests directly: Uplift's public Data deletion page promises to delete Facebook Messenger
  messages on request. Uplift's own leads and prospects are also personal data that Uplift itself controls.

## First version

1. Delete a customer, with 30 days to restore from Recently Deleted, after which everything except money
   records is permanently deleted.
2. Delete a customer permanently at once, for a privacy request.
3. Permanently delete a conversation.
4. Download everything about one customer.
5. Export all of a business's data in one package.
6. A privacy-request tool in the Jafar panel.
7. Updated public Data deletion and Privacy pages that describe the new tools.

## Deleting a customer

Approved rule (`docs/client-property-behavior-contract.md` § Archive, deletion, and retention): delete moves
the client to Recently Deleted for 30 days, an authorised admin can restore it, and then an automatic purge
removes it while keeping required money history. Archive stays the normal action for a customer who is just
inactive. The details below follow Jobber (what goes with the customer, the counts in the dialog) and HubSpot
(a restore that brings everything back).

- **Where:** the client page's `…` menu (**Delete client**), and the Clients list for selected rows. Needs
  `customers.delete`, which owners and admins hold by default.
- **The confirmation** names how many of each item go with the customer: requests, quotes, jobs and their
  visits, conversations and messages, notes, files, review requests and pipeline opportunities. It names what
  stays (invoices and payments, see below) and says the customer can be restored for 30 days.
- **Refused while money is open:** an unpaid invoice balance, a card payment still settling, or a credit or
  deposit not yet used or refunded. The message names each one and how to settle it: record the payment, void
  the invoice, write it off, or refund it.
- **During the 30 days** the customer and their work disappear from lists, search, the schedule, the inbox and
  work reports. No automation, reminder, marketing email or review request reaches them. If they get in touch
  again, the message arrives as a new contact. Restoring them later offers the existing Merge tool when a newer
  record shares their phone or email.
- **Recently Deleted** opens from the Clients list's More actions. It shows each deleted customer with who
  deleted them, when, and the days left. Restore brings everything back exactly as it was, except that messages
  due during the deleted period are not sent late.
- **On day 30** the permanent delete runs on its own. The audit record keeps who deleted the customer, when, and
  how many items went, never the content.

## Money records after any delete

- Issued invoices, payments, refunds, write-offs, deposits and opening balances stay. Their amounts, numbers
  and totals never change, and each invoice still shows the name and billing address printed on it, because tax
  law needs the invoice as it was issued. Draft invoices go with the customer.
- Kept records stay in the Invoices list, financial reports and the accountant's export, marked as belonging to
  a deleted customer. The customer's own receipt and invoice links keep working.
- The business's own Stripe account keeps Stripe's copy of card payments. The business manages that in Stripe.

## Delete permanently now

Following HubSpot's permanent delete (Jafar, 2026-10-24), for when the customer asked to have their information
deleted.

- Offered in the delete dialog ("They asked us to delete their information") and from Recently Deleted. One
  customer at a time, never in bulk.
- Needs a new permission, `customers.permanently_delete`, held by owners and admins by default. The member types
  the customer's name to confirm. It cannot be undone.
- Removes the same things as the day-30 delete, straight away: the customer, their work, messages, notes and
  files, plus the copies kept by our providers (text message records at Twilio, files in storage).
- Ends with a short receipt: the date, what was deleted (counts), and what was kept and why. The business can
  copy it into its reply to the customer.

## "Don't contact me" survives deletion

A customer's text STOP, email unsubscribe or blocked address outlives any delete as a scrambled fingerprint of
the phone number or email, with no name attached. A later import, automation or campaign can never text or email
them by mistake. If they contact the business again, they get a fresh record with no old history, and the stop
still applies until they opt back in. (HubSpot blocks a deleted email from being re-added; we narrow that to
opt-outs so a customer can still book again.)

## Deleting a conversation

Approved rule (`docs/unified-inbox-behavior-contract.md` § Inbox handling): permanent deletion follows
HighLevel, needs the permanent-delete permission and explicit confirmation, and records the organisation,
member, time, reason, customer and item counts without keeping message content.

- **Where:** a conversation's `…` menu, and inbox bulk selection (up to 100 at a time, as HighLevel does).
- **Who:** `conversations.permanently_delete`. Owners and admins hold it by default (today no role holds it);
  other roles get it when granted in Team access.
- **The confirmation** says every message, internal comment and attachment goes for everyone and cannot be
  recovered. It also says the customer keeps their own copy on their phone, in their email or on Facebook. The
  member gives a short reason.
- The customer's record stays. A new message from them starts a fresh conversation.

## Download one customer's data

Following HubSpot's "Export contact data" (Jafar, 2026-10-24), for when a customer asks for a copy of their
information.

- **Where:** the client page's `…` menu (**Download client data**). Needs `customers.import_export` (owners and
  admins).
- **Contents:** one zip with a readme. It holds their details, contacts, properties and consent history; their
  requests, quotes, jobs, visits, invoices and payments; every message on every channel; notes; and the original
  files. Internal job costs and profit are left out, because they are the business's figures, not the
  customer's information.
- Built in the background; the member is told when it is ready, and the link works for 7 days. Each download is
  recorded in the audit history.

## Export all business data

Jafar, 2026-10-24: in the first version, built last. Today a business can download its clients, Price Book, financial package and files separately. Requests,
quotes, jobs, visits and messages cannot be exported at all.

- **Where:** a new **Data & privacy** page in Settings, with **Export all business data**. Owner only, as with
  the existing files export.
- **Contents:** the existing four packages plus work records, conversations and notes, in one package with a
  readme. Built in the background, with an emailed link valid for 7 days.
- When Jafar closes a business, the owner is offered this export first, and Jafar can produce it for them
  during the 30-day closure window.

## Privacy requests in the Jafar panel

Jafar, 2026-10-24: find, forward, and delete.

- **Log a request:** who asked; how to find them (email, phone, Facebook name and Page); whether they want a
  copy or deletion; when it arrived. The due date is set 30 days later, and Jafar is reminded 7 days before it.
- **Find them:** lists every business holding a matching customer, lead or conversation, with the business
  name and item counts only. Jafar never sees the business's records.
- **Per business, Jafar can:**
  - **Ask the business** (the normal path). Its owner gets the request, the deadline and a link to the
    customer, and acts in the app.
  - **Delete for them.** Used for Messenger requests (the public promise) and for businesses that are closed or
    don't answer. Same result as Delete permanently now, after a private reason, typed confirmation and
    password reconfirmation. The business owner is told.
- Uplift's own leads, deals, prospects and support threads appear in the same search and can be deleted there.
- **States:** Open → Waiting on business → Done, with the date it was finished.

## Public pages

Once the tools ship, the Data deletion page says: a customer of a business on Uplift should ask that business,
which can now delete or download their information in the app; anyone can also email Uplift, and we pass the
request on or act on it within 30 days; Messenger messages we delete directly. The Privacy page says how long
deleted information can remain in backups.

## Success checks

- A customer with no open money → owner deletes them → they vanish from lists, search, schedule and inbox, and
  appear in Recently Deleted with 30 days left.
- That customer is restored on day 10 → their work, messages, notes and files are back as before.
- Day 30 passes → nothing about them remains except kept invoices and payments; financial totals are unchanged.
- A customer with an unpaid invoice → delete is refused, naming the invoice and how to settle it.
- A customer who texted STOP is deleted, then re-imported → no text can be sent to them.
- A member without the permission → sees no delete action, and the server refuses a direct request.
- A conversation is deleted → it is gone for every member; the audit shows who, when, why and counts; the
  client record remains.
- Delete now completes with a receipt; a one-customer download contains their
  messages and files; the business export opens with a readme; Jafar's search finds a test person across two
  businesses and "Ask the business" reaches the owner.

## Assumptions

- Uplift acts for each business (a processor), and the business decides about its customers' data. Confirmed
  against GDPR Art. 28 and California's law (research §6).
- Text message records can be deleted from Twilio through its API. Unverified; checked in the first build part
  that needs it.
- Backup copies age out on their own; production backup retention is not yet set
  (`docs/production-readiness-plan.md`). The Privacy page wording waits on that number.

## Still unclear

None for the first version. Jafar's 2026-10-24 answers: delete now for owners and admins, one customer at a
time; one-customer download in the first version; whole-business export as the last part; the Jafar tool finds,
forwards and deletes.

## Not doing

- A public request form and request manager for each business (HubSpot) — businesses receive requests by phone
  and email today; the audit history records what they did. Reconsider after launch.
- Automatically deleting long-inactive customers (HubSpot retention policy) — not asked for; later.
- Deleting kept invoices once the tax period ends — rules differ by country and need an accountant's guidance.
- Deleting single messages inside a conversation — HighLevel deletes whole conversations; no proven need.
- Deleting a former team member — they are deactivated, as in Jobber, and their name stays on work they did.
- The customer's own copies (their phone, email inbox, Facebook) and the business's Stripe account — outside our
  reach.

## Sources and design decisions

- [Research: how top CRMs handle deletion, export and privacy requests](research/data-privacy-deletion-top-crms-2026-10-23.md)
  — the delete-now, download, export and Jafar-tool behaviour.
- `docs/client-property-behavior-contract.md` § Archive, deletion, and retention — the 30-day delete and kept
  money history (approved).
- `docs/unified-inbox-behavior-contract.md` § Inbox handling — permanent conversation delete (approved).
- `docs/files-media-behavior-contract.md` § Trash, retention, and export — the same 30-day trash for files.
- `docs/jafar-completion-contract.md` § Organization closure — whole-business deletion (built).
- `docs/marketing-site/legal-pages.md` § Data deletion — the public promise this campaign updates.
