# Redesign checklist — tier 3

Key, tick rule and coverage command: `list-index.md`.

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `(public)/f/[token]` |  | ⬜ | ⬜ |
| `(public)/i/[token]` | `invoices/CustomerInvoiceDocument`, `invoices/CustomerInvoicePayment` · pop-ups: "Pay invoice" ◆ | ⬜ | ⬜ |
| ↳ "Pay invoice" pop-up in CustomerInvoicePayment | | ⬜ | ⬜ |
| `(public)/launch/[token]` |  | ⬜ | ⬜ |
| `(public)/q/[token]` | `quotes/CustomerQuoteDepositPayment`, `quotes/CustomerQuoteDocument` | ⬜ | ⬜ |
| `(public)/r/[token]` | `invoices/CustomerPaymentReceiptDocument` | ⬜ | ⬜ |
| `(public)/u/[token]` |  | ⬜ | ⬜ |
| `(public)/v/[token]` |  | ⬜ | ⬜ |
| `(public)/w/[token]` | `jobs/CustomerJobReportDocument` | ⬜ | ⬜ |
| `book/[slug]` | `forms/TurnstileCheck` | ⬜ | ⬜ |
| `book/manage/[token]` |  | ⬜ | ⬜ |
| `forgot-password` |  | ⬜ | ⬜ |
| `forms/[orgSlug]/[formSlug]` |  | ⬜ | ⬜ |
| `get-started` | `packages/PackageCard`, `ui/LocationPicker` · pop-ups: "form" 🔁F · loading | ⬜ | ⬜ |
| `get-started/received` |  | ⬜ | ⬜ |
| `jafar/forgot-password` |  | ⬜ | ⬜ |
| `jafar/join` |  | ⬜ | ⬜ |
| `jafar/login` |  | ⬜ | ⬜ |
| `jafar/reset-password` |  | ⬜ | ⬜ |
| `login` |  | ⬜ | ⬜ |
| `packages/[slug]` | `packages/PackageOfferPage` | ⬜ | ⬜ |
| `reset-password` |  | ⬜ | ⬜ |
| `setup-password` |  | ⬜ | ⬜ |
| `team-invitation` |  | ⬜ | ⬜ |

## Errors and customer emails

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `(public)/v/[token]` error page (`+error.svelte`) | Shown when a customer link is invalid or expired | ⬜ | ⬜ |
| `(public)/f/[token]` error page (`+error.svelte`) | Same, for a form link | ⬜ | ⬜ |
| Email: everyday messages to customers (quotes, invoices, visits, receipts) | Built by `renderManualEmailHtml` in `src/lib/server/communications/manual-email.ts` | ⬜ | ⬜ |
| Email: review request | `renderReviewEmailHtml` in `src/lib/server/reviews/requests.ts` | ⬜ | ⬜ |
| Email: marketing campaign | `renderCampaignEmail` in `src/lib/server/marketing/render-email.ts` (MJML) | ⬜ | ⬜ |

Outside `src/routes` and `src/lib/components` (the coverage command does not list it):

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `src/widget/website-chat.ts` (website chat widget on the contractor's site) | teaser and button, details form, country list, chat, sending, not sent, ended, not set up, loading | 🟡 Batch 66 `yyWfm` A and B drawn 2026-10-22 | ⬜ |
