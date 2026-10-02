# Uplift Website area and CMS

**Status:** Planning

## Summary

This project adds a **Website** area inside the existing contractor CRM. The contractor uses the same CRM login. Only the current organization owner can edit or publish. Uplift assigns managed websites to the organization; while an included website is being prepared but not yet assigned, the Website area shows setup progress. If several sites are assigned, the owner chooses one from a list of site names.

The owner edits approved business content without accessing code, hosting, DNS, secrets, or another client's information. Draft changes do not alter the public website until published. Uplift checks the first site release and records the contractor's launch approval before making it live. After launch, the owner may publish ordinary content changes directly. The first implementation will prove the journey with one real Uplift-managed Astro site while the account and access rules support several assigned sites from the start.

## Product boundary

This is controlled content management for websites built and managed by Uplift. It is not an unrestricted visual website builder or a replacement for the CRM. The contractor organization owner manages structured content and approved settings; Uplift remains responsible for design, code, hosting, deployment, and technical safety.

The CRM remains the owner of authentication, contractor accounts, organizations, roles, leads, requests, jobs, quotes, invoices, payments, and conversations. Its Website area uses the current CRM session and checks the current active owner role. Website content, media, drafts, previews, releases, publishing, and rollback history belong to the website subsystem behind that area. Uplift's assignment records determine which sites the organization may open. Every website action must enforce both the organization and selected site on the server; a site ID or address supplied by the browser is never proof of access.

The Website area shows only sites currently assigned to that organization. Each site keeps its own draft, preview, publishing state, and history; switching sites does not carry edits or approvals across. The server checks current ownership and assignment again before saving, previewing, publishing, restoring, or reading private site material. A guessed or formerly assigned site address does not reveal another contractor's site or its status.

If CRM ownership changes while the editor is open, the former owner's next protected action is denied; autosave and publishing stop, and the screen says **Your access changed in CRM**. Previously saved drafts remain with the site for its current owner. If a site is no longer assigned to the organization, its private pages and actions become unavailable. A guessed, removed, or other organization's site shows the same **Website unavailable** response without revealing whether that site exists. Signing out follows the CRM's existing session behavior and offers no separate CMS login or session.

## CMS user journey

1. The contractor signs in to the existing CRM.
2. The CRM shows the owner the **Website** area. If a website is included but none has been assigned yet, it shows setup progress without an empty editor.
3. When Uplift assigns sites, the owner sees their names and chooses one. Every editing, preview, and publishing screen stays scoped to that site.
4. The owner edits only the structured text, images, services, business details, and settings allowed by its design.
5. Changes are saved as drafts and previewed on that site's real design without changing the public website.
6. For the first launch, Uplift checks the site and records the named final approver's approval before making it live. The final approver may differ from the CRM owner, but this does not grant editing or publishing access. Later ordinary content updates can be published by the current owner.
7. Each publish creates a recorded, recoverable release. A failed publish leaves the last successful website online. The owner can inspect history and safely restore an earlier version.
8. Uplift-managed Astro sites use forms designed for each site. Enquiries enter the CRM as traceable intake; the CMS does not provide a form builder. The CRM's iframe form embed remains available for outside websites. A JavaScript form module may be considered later.

## V1 editing model

V1 uses a fixed-template, structured editor. Uplift defines the pages, sections, fields, design, layout, fonts, spacing, and responsive behavior. The owner edits only the approved content through simple forms, including text, images, services, testimonials, FAQs, and gallery items supported by that website's template. The owner cannot freely position elements or edit code in V1.

The content model must remain separate from the rendered Astro design and use versioned template schemas. This keeps V1 focused while leaving a safe path toward a more visual builder later; it does not require V1 to implement visual-builder behavior prematurely.

The owner sees three clear editing areas:

1. **Business details:** shared information such as business name, logo, phone, email, address, opening hours, social links, service-area summary, and primary call-to-action wording.
2. **Pages:** the fixed pages and named section forms supplied by the website template.
3. **Collections:** typed, reusable, ordered items such as services, testimonials, FAQs, team members, and gallery items. Reusing an item must not create conflicting copies of its content.

The owner may show or hide sections that the template marks as optional, but cannot rearrange page sections in V1. The owner may reorder items inside collections. Required sections and template-enforced minimum or maximum item counts cannot be bypassed.

Text controls match the needs of each field. Headings and short labels are plain text. Longer text may allow bold, italic, links, bulleted lists, and numbered lists. V1 provides no controls for fonts, colors, sizes, spacing, alignment, HTML, or CSS; the template owns presentation and heading structure.

Each image slot explains its purpose and preferred shape. The owner may upload, replace, remove, crop, choose a focal point, and provide alternative text. The CMS enforces safe file types, file sizes, image quality, and any slot-specific dimensions. An image may be marked decorative instead of receiving alternative text only where the template supports a genuinely decorative image.

### Draft saving and editing protection

The editor provides both a manual **Save draft** action and configurable autosave. Autosave is on by default at a 60-second interval. In Website settings, the owner may disable autosave or choose another interval, with 15 seconds as the shortest allowed interval. Autosave runs only when the current draft has unsaved changes; it never publishes content. The editor always shows **Saving**, **Saved**, or **Couldn't save**. If a save fails, it keeps the owner's typed content and warns before they leave or reload the page.

Incomplete work may be saved as a draft. Plain-language warnings guide the owner while editing, while serious problems such as missing required content, unsafe files, invalid links, or template-breaking values prevent publishing. All authoritative validation runs again on the server.

Only one browser session may edit the same independently saved content record at a time. Opening a locked record shows which page or item is already being edited and offers **Take over** or **Go back**. A takeover preserves the displaced session's latest work as a recoverable draft or version and tells that session it has lost the lock. Locks use the browser editing session rather than only the CRM user ID, because the same owner may open two tabs or devices. Different pages or collection items remain independently editable, and version checks still prevent an older session from silently overwriting newer content.

## Preview and publishing

**Preview draft** opens the current saved draft in the selected website's real design. It supports desktop and mobile views inside the Website area and an **Open in new tab** action. Preview is protected by short-lived, site-specific authorization, clearly says **Draft preview — not live**, shows when the draft was last saved, and cannot be indexed by search engines. The public domain reads only the last successful published release, never the working draft.

The first live release has a separate launch gate: Uplift checks the completed site and records the named final approver's approval for the exact version, their identity, and the time before publication. The final approver may be someone other than the CRM owner; their approval grants no editing or publishing access. If the version changes, the changed version needs its own check and approval. Once the site is live, the current organization owner may publish ordinary content changes directly, without an Uplift approval queue. **Publish changes** summarizes the affected pages and items and asks for confirmation. Publishing freezes the current draft into a fixed release candidate; edits made after publishing starts remain in the working draft and do not silently enter that release. A new site assigned later to the same organization goes through its own first-launch gate.

The owner sees durable progress: **Queued → Checking content → Building website → Testing preview → Making live → Live**. A publish failure shows the failed stage, a useful explanation, time, and **Retry publish**. The owner may leave and return without losing the job status. Only one release may be made live for a website at a time. Until all checks pass and the new release is promoted, the last successful public website remains unchanged.

## Version history and recovery

Version history separates successful published releases from failed attempts. Each successful release shows its number, publication time, actor, changed pages or items, and deployment result. An earlier release provides **Preview version**, **Compare with current draft**, and **Restore as draft**.

Restoring never changes the public website immediately or erases later history. It creates a new draft from the earlier release, including the media needed to render it. The owner previews and publishes that draft normally, which creates a new release number.

Deleting a reusable item or media asset first shows where it is used. Confirmed deletion moves it to **Trash** and removes it from the working draft; it does not change the public site until another release is published. Trash items can be restored for 30 days and keep their stable identity so references reconnect. Required pages cannot be deleted. A file required by a retained published release cannot be permanently removed from storage.

V1 guarantees the following recovery windows:

- Current working draft: for the life of the active website record.
- Draft checkpoints: whichever retains more—the latest 25 checkpoints per record or all checkpoints from the last 30 days.
- Successful releases and their required media: whichever retains more—the latest 50 releases or one year. The current live release is never automatically removed.
- Trashed content and media: 30 days, unless a retained release still requires the underlying data.
- Detailed failed-publish information: 90 days, with the attempt summary remaining in release history.

## Enquiry forms and CRM intake

Uplift designs native enquiry forms as part of each managed Astro site. The form's presentation and appropriate questions belong to that site design; its submitted enquiry enters the selected organization's CRM through a validated server-side intake path. The submission keeps its source site and page so staff can follow up in the existing CRM workflow. A successful website publish must not silently change how an enquiry is routed. The Website area does not offer a form builder in this release.

For a contractor's outside website, the existing CRM iframe form embed remains an option. A JavaScript form module is a possible later improvement and is not required for this plan.

## Long-term direction

After the structured CMS works reliably, Uplift intends to expand it toward an Elementor- or Bricks-style visual website builder. That future product may add visual section composition, layout controls, reusable components, and broader design editing in separately planned releases.

## Still unclear

- Which setup milestones and next actions should the owner see before Uplift assigns the first site?
- May CRM teammates see read-only Website status, or is the entire area owner-only?
- What should the Website area show when the organization's package does not include a managed website?
- What are the exact first-launch states for a requested revision or withdrawn approval before a site goes live?
- What should happen to an open editor when ownership changes, a site is unassigned, or the CRM session ends?
- How will native Astro form fields map to published CRM intake definitions and a shared submission receiver, including validation, failed or duplicate submissions, and source attribution? The sites are planned as static builds, so this must not assume a separate Astro server for every site.
- What CMS operations, auditing, backup, and recovery controls does Uplift need behind the client experience?
- Which storage, database, deployment, backup, and monitoring services best fit the approved CMS behavior?

## Not doing

- Unrestricted code, layout, GitHub, or Cloudflare access in V1 — it could break the managed website and expose technical systems. Visual layout editing is a later product direction, not part of V1.
- A second client account, login, or separate client-facing CMS application — identity, membership, and owner status come from the CRM.
- Editing or publishing by ordinary CRM staff members — only the current contractor organization owner may perform those actions.
- A form builder for managed Astro websites — Uplift designs their native forms for each site. The existing CRM iframe embed remains for outside sites.
- CRM features, billing, subscriptions, domain and DNS management, email management, analytics, or support tickets — those are outside this CMS build.
- A final provider or database choice before the required behavior is settled — technology must serve the business rules rather than decide them accidentally.

## Research

- Foundation research: `docs/research/uplift-website-admin-foundations.md`.
- CRM integration patterns: `docs/research/contractor-crm-website-integration-patterns.md`.
- Structured editing patterns: `docs/research/uplift-cms-structured-editing-patterns-2026-10-02.md`.
- Preview and release patterns: `docs/research/uplift-cms-preview-release-patterns-2026-10-02.md`.
- CRM-native Website area, launch, and native forms: `docs/research/uplift-crm-website-area-patterns-2026-10-02.md`.
- Existing onboarding progress and final-approver rules: `docs/client-onboarding-delivery-behavior-contract.md` §§ 2, 5–6.
- Existing package distinction between managed website service and CRM access: `docs/package-builder-behavior-contract.md` § Product behavior.
