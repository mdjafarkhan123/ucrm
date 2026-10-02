# Uplift CMS

**Status:** Planning

## Summary

This project builds only Uplift's CMS for contractor websites. The contractor CRM already exists and owns all login, account, organization, and role management. The CMS has no separate client login. A contractor reaches it only through the CRM's **Website** area, and only the owner of that CRM organization may enter and edit its assigned website.

The CMS lets that owner edit approved business content without accessing code, hosting, DNS, secrets, or another client's information. Draft changes do not alter the public website until they are published. The owner can preview changes on the real website design, publish permitted changes, inspect version history, and restore an earlier version safely. The first implementation will prove this CMS journey with one real Uplift-managed Astro website before expanding to more designs.

## Product boundary

This is a controlled content-management system for websites built and managed by Uplift. It is not an unrestricted visual website builder or a replacement for the CRM. The contractor organization owner manages structured content and approved settings; Uplift remains responsible for design, code, hosting, deployment, and technical safety.

The CRM remains the owner of authentication, contractor accounts, organizations, roles, leads, requests, jobs, quotes, invoices, payments, and conversations. It authorizes a short-lived, server-verified handoff into the CMS for the organization owner and identifies the exact organization and website they may access. The CMS owns website content, media, drafts, previews, releases, publishing, and rollback history. Every CMS request must enforce the assigned organization and website on the server; hiding another website in the interface is not sufficient protection.

## CMS user journey

1. The contractor signs in to the existing CRM.
2. The CRM shows the **Website** area only to the organization owner.
3. Opening it securely hands the owner into the CMS with the correct organization and website assignment; there is no second login.
4. The owner edits only the structured text, images, services, business details, and settings allowed by the website design.
5. Changes are saved as drafts and previewed on the real design without changing the public website.
6. Publishing creates a recorded, recoverable release. A failed publish leaves the last successful website online.
7. The owner can inspect version history and safely restore an earlier version.
8. Website forms may send enquiries into the CRM through an explicit integration, but the CMS does not recreate CRM workflows.

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

The CMS provides both a manual **Save draft** action and configurable autosave. Autosave is on by default at a 60-second interval. In CMS settings, the owner may disable autosave or choose another interval, with 15 seconds as the shortest allowed interval. Autosave runs only when the current draft has unsaved changes; it never publishes content. The editor always shows **Saving**, **Saved**, or **Couldn't save**. If a save fails, the CMS keeps the owner's typed content and warns before they leave or reload the page.

Incomplete work may be saved as a draft. Plain-language warnings guide the owner while editing, while serious problems such as missing required content, unsafe files, invalid links, or template-breaking values prevent publishing. All authoritative validation runs again on the server.

Only one browser session may edit the same independently saved content record at a time. Opening a locked record shows which page or item is already being edited and offers **Take over** or **Go back**. A takeover preserves the displaced session's latest work as a recoverable draft or version and tells that session it has lost the lock. Locks use the browser editing session rather than only the CRM user ID, because the same owner may open two tabs or devices. Different pages or collection items remain independently editable, and version checks still prevent an older session from silently overwriting newer content.

## Preview and publishing

**Preview draft** opens the current saved draft in the real assigned website design. It supports desktop and mobile views inside the CMS and an **Open in new tab** action. Preview is protected by short-lived, site-specific authorization, clearly says **Draft preview — not live**, shows when the draft was last saved, and cannot be indexed by search engines. The public domain reads only the last successful published release, never the working draft.

The organization owner publishes directly without an Uplift approval queue. **Publish changes** first summarizes the affected pages and items and asks for confirmation. Publishing freezes the current draft into a fixed release candidate; edits made after publishing starts remain in the working draft and do not silently enter that release.

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

## Long-term direction

After the structured CMS works reliably, Uplift intends to expand it toward an Elementor- or Bricks-style visual website builder. That future product may add visual section composition, layout controls, reusable components, and broader design editing in separately planned releases.

## Still unclear

- How does the CRM securely hand the authenticated organization owner and exact website assignment to the CMS?
- Who creates and assigns a website record to a CRM organization before the owner first enters?
- What CMS operations, auditing, backup, and recovery controls does Uplift need behind the client experience?
- Which storage, database, deployment, backup, and monitoring services best fit the approved CMS behavior?

## Not doing

- Unrestricted code, layout, GitHub, or Cloudflare access in V1 — it could break the managed website and expose technical systems. Visual layout editing is a later product direction, not part of V1.
- A second client account or direct CMS login — client identity, organization membership, and owner status come only from the CRM.
- Access for ordinary CRM staff members — only the contractor organization's owner may enter the CMS and edit its website.
- CRM features, billing, subscriptions, domain and DNS management, email management, analytics, or support tickets — those are outside this CMS build.
- A final provider or database choice before the required behavior is settled — technology must serve the business rules rather than decide them accidentally.

## Research

- Foundation research: `docs/research/uplift-website-admin-foundations.md`.
- CRM integration patterns: `docs/research/contractor-crm-website-integration-patterns.md`.
- Structured editing patterns: `docs/research/uplift-cms-structured-editing-patterns-2026-10-02.md`.
- Preview and release patterns: `docs/research/uplift-cms-preview-release-patterns-2026-10-02.md`.
