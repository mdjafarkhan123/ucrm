# One-time flash of full nav + "not connected to an organization" after using the account menu

- **Priority:** P3
- **Why postponed:** Seen once during the Part 17 live re-verification (field role): after opening the
  account menu and re-navigating, the dashboard briefly rendered with the full nav (Quotes, Invoices,
  Pipeline, Clients all visible, which field should never see) plus a banner reading "your account is signed
  in, but it is not connected to an organization yet." A follow-up hard navigation to `/dashboard`
  immediately showed the correct, properly-scoped state, and the anomaly did not recur on a second attempt.
  Never reproduced on demand, so the exact trigger is unknown — possibly a stale-cache or hydration race
  right after a client-side navigation from the account menu.
- **Reactivate when:** Anyone reports the "not connected to an organization" banner appearing for a real,
  connected member, or the full-nav flash recurs and can be captured reliably.
- **Constraint:** Do not investigate further without a reproduction — this file exists only so it isn't
  forgotten if it resurfaces.
- **Pointers:** `src/routes/(app)/+layout.svelte` (nav-visibility probes, organization data), account menu
  navigation flow.
