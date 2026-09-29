# Public package presentation

Reviewed 2026-09-29. [Jobber's pricing page](https://www.getjobber.com/pricing/) leads with contractor-readable outcomes and plan prices, then offers a comparison of all features. Its [subscription guidance](https://help.getjobber.com/en/articles/how-to-subscribe/) treats included users, price, and feature set as concrete plan terms. This supports a short comparison card plus a complete detail view, with both representing the same published edition.

The current UCRM `/get-started` card shows name, monthly price, public description, seat limit, and every feature description. Its final review shows only the package name. Sources: `src/routes/get-started/+page.svelte` and `src/routes/get-started/+page.server.ts`. The current page queries published versions rather than creating a separate marketing summary. The proposed marketing site may be separate, so its card copy needs a reliable link to the exact published edition and a check when that edition changes or is archived.

Examples such as a premium website, on-site SEO, missed-call text-back, automated lead follow-up, and Google Business Profile management may mix software capabilities with human-delivered services. They are promises to a buyer only after their availability, delivery scope, and ongoing responsibilities are confirmed. A label in a package editor cannot make them real.

## Uplift and Stone Systems review

Jafar clarified that Uplift sells one complete growth system rather than a CRM subscription with unrelated extras. The current [Uplift Contractor site](https://upliftcontractor.com/) presents a premium website, review funnel, missed-call text-back, marketing campaigns, Google Business Profile management, and the contractor management app as one connected foundation. The [Stone Systems site](https://stonesystems.io/) follows the same outcome-first pattern. That pattern is easy for contractors to understand, but Uplift should use its own wording, proof, and service boundaries rather than closely repeating the reference site's voice.

The clean package model has two fulfillment groups and two presentation depths:

- Managed services: website delivery, on-site SEO, and Google Business Profile optimization and ongoing management.
- Software capabilities: CRM, website chat, missed-call text-back, automated lead follow-up, review requests and feedback, and other enabled application features.
- Summary presentation: a short promise and four to six manually curated customer highlights.
- Full presentation: the exact managed-service scope, enabled capabilities, allowances, provider charges, prerequisites, exclusions, introductory terms, normal price, and end-of-service rules for one published edition.

Highlights are display copy and must never control application access. Structured service inclusions and verified software entitlements are the truth. The static marketing site can own persuasive copy, but manually duplicating all exact limits creates avoidable drift. The robust pattern is for its **View details** action to open a public read-only page generated from the CRM's published edition, then carry the edition slug and billing choice into onboarding.

Google's official guidance says a business can invite a manager to help with daily operation without sharing its password, and advises businesses using a third party to retain owner access. It also defines pressuring customers for a particular rating as rating manipulation. Uplift should therefore manage a contractor-owned profile through manager or agency access, ask every eligible customer for honest feedback, and remove “5-Star Reviews Only” or any equivalent promise from public copy. Sources: [Google Business Profile owners and managers](https://support.google.com/business/answer/3403100?hl=en), [protect a Business Profile](https://support.google.com/business/answer/14509283?hl=en), and [Google Maps rating manipulation policy](https://support.google.com/contributionpolicy/answer/16597280?hl=en).
