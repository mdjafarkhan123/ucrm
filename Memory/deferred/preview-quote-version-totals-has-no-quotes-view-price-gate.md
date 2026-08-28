# Quote preview totals lack the view-price gate

- **Priority:** P0
- **Why postponed:** The preview route/function checks quotes.view but exposes customer money fields without quotes.view_price; the affected default role matrix is not yet seeded.
- **Reactivate when:** Restricted Quote roles ship or the preview route/function is touched.
- **Constraint:** Gate or redact subtotal, discount, tax, total, and deposit consistently with docs/quote-behavior-contract.md.
- **Pointers:** src/routes/api/quotes/[id]/preview/+server.ts and the current preview_quote_version_totals function.
