# Redesign checklist — tier 2 (b)

Key, tick rule and coverage command: `list-index.md`.

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `(app)/invoices/[id=uuid]` | `invoices/InvoiceHistoryCard`, `invoices/InvoiceLifecycleDialog` 🔁C, `invoices/ReplaceInvoiceDialog` 🔁F · pop-ups: "confirm" 🔁C, "form" 🔁F · tabs ×1 · loading, empty, permission-limited | ⬜ | ⬜ |
| ↳ `invoices/AddDepositDialog` | ◆ pop-up · loading | ⬜ | ⬜ |
| ↳ `invoices/InvoiceEmailDialog` | ◆ pop-up | ⬜ | ⬜ |
| `(app)/invoices/new` | `invoices/InvoiceForm`, `invoices/SelectWorkDialog` 🔁F · pop-ups: "form" 🔁F · loading | ⬜ | ⬜ |
| `(app)/invoices/ready-to-bill` | `invoices/ReadyToBillVisitsPanel` · loading, empty | ⬜ | ⬜ |
| `(app)/invoices/send` | loading, empty | ⬜ | ⬜ |
| `(app)/payments/[id=uuid]` | `invoices/PaymentReceiptCard`, `invoices/UnapplyPaymentDialog` 🔁C · pop-ups: "confirm" 🔁C · menus ×1 · loading | ⬜ | ⬜ |
| ↳ `invoices/MovePaymentDialog` | ◆ pop-up · loading | ⬜ | ⬜ |
| ↳ `invoices/RefundPaymentDialog` | ◆ pop-up | ⬜ | ⬜ |
| ↳ `invoices/StripeRefundDialog` | ◆ pop-up | ⬜ | ⬜ |
