# Jobber operational-email gap review

Research date: 2026-08-15  
Scope: approved UCRM email decisions through Q80, excluding SMS

## Conclusion

The approved UCRM model already covers provider isolation, authenticated contractor domains, inbound parsing, allowances, abuse controls, suppressions, templates, history, and closure more deeply than Jobber's published product behavior. The remaining Jobber patterns worth adopting are mainly **work-item rules**, not new email-platform decisions. They can be treated as proven defaults when the Clients, Requests/Assessments, Quotes, Jobs/Schedule, Invoices, Reputation, Settings, Communications, and Client Portal campaigns document their detailed behavior.

## Proven Jobber behavior to adopt without another grill

1. **Keep client preferences category-specific and contact-specific.** A client/contact separately controls outstanding quote follow-ups, overdue invoice follow-ups, assessment/visit reminders, job-closure follow-ups, and review requests. Automated quote and invoice follow-ups go only to recipients of the original document who remain eligible for that category. This sharpens Q34 and should not become one global operational-email opt-out. [Jobber: Client Basics](https://help.getjobber.com/hc/en-us/articles/115009450867-Client-Basics)

2. **Separate internal reminders from client follow-ups.** A quote reminder is an internal schedule task; a quote follow-up is a client message. An invoice reminder prompts staff to create an invoice and can move the job into `Requires Invoicing`; an overdue-invoice follow-up asks the client to pay. Do not model these as one email automation. [Jobber: Reminders on the Schedule](https://help.getjobber.com/hc/en-us/articles/38530989862295-Reminders-on-the-Schedule), [Jobber: Invoice Reminders](https://help.getjobber.com/hc/en-us/articles/115009517847-Invoice-Reminders)

3. **Make schedule changes invalidate old notifications.** When a visit is rescheduled, cancel reminders tied to the previous time. Let the staff member choose whether to notify the client, choose email, and review/edit the reschedule message before sending. For a recurring job, the change and notification apply only to the selected visit unless the user explicitly edits the series. [Jobber: Assessment and Visit Reminders](https://help.getjobber.com/hc/en-us/articles/360033608974-Assessment-and-Visit-Reminders)

4. **Tie send and reply eligibility to work-item permissions.** Communication settings are admin-only. A user should send or act on request, quote, job, or invoice email only when authorized for that object and any protected pricing/payment data. If an assigned recipient loses permission or is deactivated, remove the assignment automatically and preserve a safe fallback. [Jobber: Emails and Text Messages Settings](https://help.getjobber.com/hc/en-us/articles/9335574672151-Emails-and-Text-Messages-Settings), [Jobber: User Permissions](https://help.getjobber.com/hc/en-us/articles/115009568687-User-Permissions)

5. **Treat document email as a portal action, not merely an attachment.** Quote and invoice email should contain a secure button plus a copyable fallback URL to the client portal. Staff preview recipients and content before sending and may attach a generated PDF. Clients can download PDFs in the portal. Quote view, approval/change request, signature, deposit, invoice view/payment, and receipt are domain events linked to the originating email and work item. [Jobber: Client Document Settings](https://help.getjobber.com/hc/en-us/articles/115009566987-Client-Document-Settings), [Jobber: What clients see in Client Hub](https://help.getjobber.com/hc/en-us/articles/1500011237822-What-Do-Your-Clients-See-in-Client-Hub)

6. **Give clients a self-serve portal entry path.** Operational emails for quotes, invoices, booking confirmations, appointment reminders, and payment-method requests lead to the relevant portal object. The portal also supports viewing appointments, paying invoices, printing receipts, and requesting more work. Whether all sent quotes/invoices appear in portal navigation can be an organization setting; when disabled, direct emailed links still work. [Jobber: Client Hub Settings](https://help.getjobber.com/hc/en-us/articles/115009571307-Client-Hub-Settings), [Jobber: What clients see in Client Hub](https://help.getjobber.com/hc/en-us/articles/1500011237822-What-Do-Your-Clients-See-in-Client-Hub)

7. **Keep campaigns operationally separate.** A campaign unsubscribe blocks later campaigns but does not stop quotes, invoices, or operational reminders. UCRM's approved essential/optional/marketing preferences are stricter and should remain authoritative; Jobber confirms the product separation. [Jobber: Campaigns](https://help.getjobber.com/hc/en-us/articles/19885016029207-Campaigns-Marketing-Tools)

8. **Keep a client communication report as well as work-item timelines.** Show all client emails with delivery/open state while each quote, assessment, job, and invoice also links its own communications. Under Q53, opens remain approximate and visually weaker than delivery, reply, portal view, approval, and payment. [Jobber: Client Basics](https://help.getjobber.com/hc/en-us/articles/115009450867-Client-Basics)

9. **Payment email has explicit settings.** Let an organization administrator enable client receipts after successful deposits/payments and admin payment notifications. A receipt remains essential operational email under Q34. [Jobber: Payments Settings](https://help.getjobber.com/hc/en-us/articles/115009590727-Manage-your-Jobber-Payments-Settings)

## Intentional differences and conflicts

- **Reply ownership (Q35):** Jobber configures one reply recipient per work type, defaults to the sender, permits a per-message override, and falls back to the sender when the configured team member becomes ineligible. UCRM explicitly chose the GHL-style model: contact assigned user owns the conversation, the shared inbox retains visibility, and inactive/unassigned ownership falls back to the shared inbox. Keep that decision. Jobber's permission-based eligibility and safe fallback still apply. [Jobber: Emails and Text Messages Settings](https://help.getjobber.com/hc/en-us/articles/9335574672151-Emails-and-Text-Messages-Settings)
- **Templates (Q61):** Jobber exposes admin-managed templates per communication type and allows individual-message customization. UCRM chose GHL-style platform templates copied into organization ownership and automation-specific copies. Keep UCRM's model, but borrow Jobber's clear event taxonomy and admin-only global settings.
- **Sender infrastructure:** Jobber publicly sends client mail through Jobber domains. UCRM intentionally requires a verified contractor sending subdomain, a separate reply subdomain, and no platform-sender fallback. ContractorOs proves this Brevo pattern and its organization-scoped opaque aliases; the approved UCRM decision is stronger branding and isolation than Jobber's published behavior.
- **Closure/offboarding:** Jobber's public help material does not establish a tenant purge or recoverable inbound-routing contract. UCRM's approved 30-day inbound recovery window, strict permanent purge, and retryable Brevo cleanup remain UCRM-specific.

## Genuine UCRM-specific choices still to settle in the relevant campaigns

These are not answered safely by copying Jobber:

1. **Portal-link authorization for CC recipients.** Jobber warns that anyone given a Client Hub link, including a CC recipient, can access the client's portal information. UCRM approved CC in Q59 but should not copy this broad access. Proposal: CC grants receipt of that message only; portal access requires an explicit client-contact invitation or a narrowly scoped, expiring document link. Decide exact scope and expiry in the Client Portal campaign. [Jobber: What clients see in Client Hub](https://help.getjobber.com/hc/en-us/articles/1500011237822-What-Do-Your-Clients-See-in-Client-Hub)
2. **Default recipients by work type.** Jobber confirms per-contact eligibility but does not decide UCRM's exact rules for primary contact, billing contact, property contact, and manually added recipients. Define these within each domain campaign, with invoice/receipt defaults owned by Invoices and Payments.
3. **Portal visibility and retention after contractor closure.** Q69-Q72 settle email routing and deletion, but each campaign must decide what a client can still view, download, or pay during suspension and the 30-day recovery window.
4. **Review-funnel branching.** Jobber confirms a distinct review-request preference and post-payment trigger, but UCRM's Magic Review Funnel, rating branch, escalation, consent, and anti-gating rules belong to the Reputation campaign.

## Effect on the approved email proposal

No approved Q1-Q80 decision needs reopening. Add the proven rules above to the relevant contractor-facing campaign contracts. The only cross-cutting issue that merits a future explicit decision is portal authorization for CC recipients; the safest default is message access without automatic account-wide portal access.
