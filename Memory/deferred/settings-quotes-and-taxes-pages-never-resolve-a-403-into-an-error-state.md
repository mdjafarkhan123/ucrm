# Settings Quotes and Taxes hang after a 403

- **Priority:** P3
- **Why postponed:** The APIs deny correctly, but both pages remain in loading state; the fix belongs to the shared Settings loading/error pattern.
- **Reactivate when:** Settings data-state handling is touched or a restricted member reports a hanging page.
- **Constraint:** Apply one consistent error pattern across Settings rather than page-specific patches.
- **Pointers:** Settings quotes, taxes, and price-book pages.
