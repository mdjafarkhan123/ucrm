# Public package presentation

Reviewed 2026-09-29. [Jobber's pricing page](https://www.getjobber.com/pricing/) leads with contractor-readable outcomes and plan prices, then offers a comparison of all features. Its [subscription guidance](https://help.getjobber.com/en/articles/how-to-subscribe/) treats included users, price, and feature set as concrete plan terms. This supports a short comparison card plus a complete detail view, with both representing the same published edition.

The current UCRM `/get-started` card shows name, monthly price, public description, seat limit, and every feature description. Its final review shows only the package name. Sources: `src/routes/get-started/+page.svelte` and `src/routes/get-started/+page.server.ts`. The current page queries published versions rather than creating a separate marketing summary. The proposed marketing site may be separate, so its card copy needs a reliable link to the exact published edition and a check when that edition changes or is archived.

Examples such as a premium website, on-site SEO, missed-call text-back, automated lead follow-up, and Google Business Profile management may mix software capabilities with human-delivered services. They are promises to a buyer only after their availability, delivery scope, and ongoing responsibilities are confirmed. A label in a package editor cannot make them real.
