# Screen check

Run this before calling any change a user can see done.

1. Open the changed screen in the running app, signed in with a role from `Login.md` that sees the change. Use
   the available browser tools, or Playwright.
2. Screenshot it at 1440px and 390px wide in every state the change touches: real data, empty, loading, error,
   long names; dark mode too when colour changed. A small change built from existing parts needs only the
   changed spot.
3. Compare each screenshot with its approved Pencil screen (or, for screens without one, the matching design
   skill rules): alignment, spacing, hierarchy, crowding, cut-off text, overflow, anything that reads as a
   spreadsheet rather than a product.
4. Press each button that waits on the server: it shows its loading state and ignores a second press. Check
   keyboard use, visible focus, labels, contrast, text resizing, dismissal, phone navigation, and any
   permission difference the change touches.
5. Fix what you found and screenshot again. Done when a fresh round finds nothing to fix (at most three rounds;
   report what is left). Tell Jafar which screens and states you checked, what you fixed, and the link to open.
