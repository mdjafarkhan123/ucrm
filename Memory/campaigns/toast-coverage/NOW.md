# Toast Coverage: Current Checkpoint

## Goal

Every save, delete, and archive action gives clear success feedback and appropriate failure feedback through the shared toast system.

## Current state

Part 5 in progress. Clients, Requests, Quotes, Pipeline, Jafar, shared discount/tax cards, Collaboration,
and Team are done — browser-verified and committed (latest `9c24472`, 2026-09-18). Decided and left as is:
Jafar action components (inline `role="status"`), notification bells' mark-all-read, TagPicker's
optimistic toggles, `ProductsAndServicesBlock` inline notice, auth/public pages, import wizards (own
result screens).

## Exact next action

Final sweep of the pages that still write without any `toast.` call: `settings/automation/*`,
`settings/security`, `settings/communications/email`, `dashboard`, and `AppShell`. Survey each write,
add `toast.success` where success feedback is missing, keep inline error display, browser-verify, commit,
then close the campaign. Other agents have unrelated dirty files (Communications/inbox, CLAUDE.md,
Design/) — do not stage them.

## Constraints

Reuse ToastManager (`$lib/components/ui/ToastManager.svelte`, `getToastManager()`). Only success
feedback moves to toast, consistent with the existing Invoices pattern. Tunnel saves are slow, so verify
toasts with a MutationObserver on `.toast-viewport` rather than relying on a screenshot beating the 4s
timeout.

## Completion gate

Each surveyed mutation has honest success/failure feedback without duplicated page-level handling.
