# Replaced logo uploads are kept rather than cleaned up

- **Priority:** P3. **Reactivation:** Jafar wants replaced logos swept, or storage cost from old logos becomes visible.
- **Why postponed:** every replaced logo object is kept (`src/routes/api/settings/branding/logo/+server.ts`). Published Quotes now freeze the logo key on `quote_versions.logo_object_key` (`339516b`), so a sweep is now possible for Quotes.
- **Constraint before any sweep:** delete only objects no `quote_versions` row names, after a grace period. Other customer documents (invoices, emails) must be checked for logo use first; none reference a frozen logo key today, so confirm before treating an object as unreferenced.
- The route's comment still says documents do not record their logo; rewrite it when the sweep is built.
