# Contractor website editing

**Status:** Planning — Jafar's editing, publishing, and buyout choices are open.

## Summary

Uplift plans to provide managed Astro websites as part of some contractor packages. This campaign will define how a contractor signs into the CRM, finds their website, changes its content, previews the result, and publishes safely. It will also define what Uplift controls, what a contractor can change, and what happens when service ends or the website is bought out. The plan must work with the approved customer setup and launch journey, including explicit approval before the initial launch. No hosting or source-transfer implementation is authorized by this planning document.

## Existing product commitments

- The contractor owns their domain. Uplift uses delegated access, exact DNS instructions, or supervised setup; onboarding does not ask for registrar or email passwords. Initial website launch requires separately recorded contractor approval. See [client onboarding and delivery](client-onboarding-delivery-behavior-contract.md).
- An organization's paid access is based on its assigned package edition and confirmed coverage, with a seven-day overdue grace period before access pauses. The package builder records that a website is included as a managed service, but does not define website hosting or editing rights. See [package builder](package-builder-behavior-contract.md).

## Still unclear

- What website content and structure can a contractor edit or delete, and which changes remain Uplift-managed?
- Does Publish go live after automated checks, wait for Uplift approval, or use different rules by change type?
- What exactly is handed over after a one-time website buyout, when does handover occur, and who hosts and maintains it afterward?
- Who in the contractor's team may view, edit, publish, restore, or manage each website?
- How do drafts, previews, version history, failed builds, restores, and simultaneous editors behave?
- How are media, forms, SEO settings, domains, and third-party integrations edited without breaking lead capture or email?
- What happens to the public site, editing access, content export, domain, and retained data during overdue grace, suspension, cancellation, and buyout?
- Which Git, build, Cloudflare hosting, DNS custody, and backup arrangement meets the expected number of sites and publishes at an acceptable cost? What must be proven before committing to capacity?

## Not doing

- Changing customer DNS, hosting, GitHub repositories, or other infrastructure during this planning stage — the topology and migration require Jafar's later approval.
- Giving a contractor direct GitHub or source access as part of the normal monthly service — Jafar's stated commercial boundary.

## Research

- [Git-backed CMS and Cloudflare platform comparison](research/contractor-website-cms-platforms-2026-10-02.md)
- [Earlier Astro and Cloudflare scale review](research/astro-contractor-sites-cloudflare-platform-architecture.md)
