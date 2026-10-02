# Uplift CMS structured editing patterns

Research date: 2026-10-02
Scope: the editing model for the separate Uplift CMS. CRM-owned login and owner-only entry are already settled. This note covers structured website content only, uses official product documentation, and does not change the product plan.

## Recommendation in one sentence

Use a **template-bound, schema-driven editor**: Uplift defines each website design's pages, sections, fields, list limits, image slots, and responsive behaviour; the business owner edits the allowed content through simple forms with a real preview, but cannot construct layouts or change code.

This combines three established patterns:

- Shopify's developer-defined section and block settings, including the ability to restrict which block types a section accepts and how many items it may contain. Shopify specifically warns that overly granular blocks make the editor cluttered and complex. [Shopify: Settings](https://shopify.dev/docs/storefronts/themes/architecture/settings), [Shopify: Blocks](https://shopify.dev/docs/storefronts/themes/architecture/blocks), and [Shopify: sections and blocks best practices](https://shopify.dev/docs/storefronts/themes/best-practices/templates-sections-blocks)
- Contentful's typed content model, reusable entry/media references, field validation, and separate draft/changed/published states. [Contentful: Data model](https://www.contentful.com/developers/docs/concepts/data-model/), [Contentful: Entry and asset links](https://www.contentful.com/developers/docs/concepts/links/), and [Contentful: Entry and asset states](https://www.contentful.com/developers/docs/tutorials/general/determine-entry-asset-state/)
- Storyblok's developer-ordered form fields beside a draft preview, including desktop/mobile preview modes, without requiring the owner to edit the underlying implementation. [Storyblok: Visual Editor](https://www.storyblok.com/docs/manuals/visual-editor)

## Proven product patterns

### 1. The template owns layout; the owner owns content

Shopify defines settings in developer-authored JSON at theme, section, and block level. Blocks may be reusable, or restricted to one section; sections can accept only approved block types, and `max_blocks` can reduce the number owners may add. Shopify's own guidance says to choose the amount of flexibility deliberately and avoid blocks that are too granular because they add code and editing complexity. [Shopify: Settings](https://shopify.dev/docs/storefronts/themes/architecture/settings), [Shopify: Blocks](https://shopify.dev/docs/storefronts/themes/architecture/blocks), and [Shopify: sections and blocks best practices](https://shopify.dev/docs/storefronts/themes/best-practices/templates-sections-blocks)

**Uplift fit:** each template should publish a versioned CMS schema describing:

- its fixed pages and named section slots;
- which fields appear in each section;
- which sections may be hidden or repeated;
- allowed list item types and minimum/maximum counts;
- text guidance and hard length limits;
- image aspect, file, alt-text, and focal-point requirements.

The owner should not receive controls for columns, spacing, breakpoints, fonts, arbitrary colours, HTML, CSS, scripts, or third-party blocks. A template may offer a few safe choices such as section visibility, approved alignment variants, or an approved colour treatment, but only when the design explicitly supports them.

### 2. Separate shared facts, page content, and reusable lists

Contentful models information as typed entries and assets. Reference fields link one entry to another, arrays hold ordered lists, and references can be restricted to a particular content type or asset file type. This lets one source item appear in several places without copying it. [Contentful: Data model](https://www.contentful.com/developers/docs/concepts/data-model/) and [Contentful: Entry and asset links](https://www.contentful.com/developers/docs/concepts/links/)

**Uplift fit:** use three simple content groups:

1. **Business details:** one site-wide record for business name, logo, phone, email, address, hours, social links, service area summary, and primary call-to-action wording. This is CMS content; live two-way CRM syncing is not required for the CMS build.
2. **Pages:** the template's fixed pages, each containing named section forms such as Hero, About, Trust points, and Contact introduction.
3. **Collections:** typed, ordered records such as Services, Testimonials, FAQs, Team members, and Gallery items. A page section selects or displays these records instead of duplicating their text and images.

This keeps a phone number or service description consistent wherever the design reuses it. Switching to another approved template can preserve shared facts and collections; only template-specific section fields need an explicit compatibility check or mapping. A switch must never silently discard unsupported content.

### 3. Autosave a private draft; publish deliberately

Contentful automatically saves entry changes but does not make them live until Publish is selected. It distinguishes Draft, Changed, Published, and Archived states; its delivery API continues returning the last published content while preview/management access can read pending changes. [Contentful: Content and entries](https://www.contentful.com/help/content-and-entries/) and [Contentful: Entry and asset states](https://www.contentful.com/developers/docs/tutorials/general/determine-entry-asset-state/)

Sanity follows the same separation: editing a published document creates or updates one draft while the published document remains intact until publication. Sanity Studio also saves automatically as the editor works. [Sanity: Drafts and versions](https://www.sanity.io/docs/content-lake/drafts-and-versions) and [Sanity: Studio keyboard shortcuts](https://www.sanity.io/docs/studio/sanity-studio-keyboard-shortcuts)

**Uplift fit:**

- save the working draft automatically after a short typing pause;
- always show `Saving`, `Saved`, or `Couldn't save` near the editor;
- keep the last published release untouched while the owner edits;
- preview the complete draft in the real template;
- run whole-site validation when Publish is requested;
- make the new content public only after the publishing process succeeds.

Although only one organization owner has access, two browser tabs can still conflict. Contentful's API uses version-based optimistic locking to reject an update based on an older version; Uplift should use the same principle instead of silently overwriting newer draft data. [Contentful: Content Management API overview](https://www.contentful.com/developers/docs/references/content-management-api/overview/)

### 4. Validation protects the design without punishing drafting

Contentful supports required fields, text and array size limits, regular expressions, numeric ranges, allowed rich-text nodes/marks, image dimensions, file sizes, and allowed referenced content types. [Contentful: Content types and validation](https://www.contentful.com/developers/docs/references/content-management-api/content-types/)

Sanity distinguishes blocking errors from non-blocking warnings: an error prevents publication, while a warning can guide the editor toward better content. [Sanity: Validation](https://www.sanity.io/docs/studio/validation)

**Uplift fit:** use two levels:

- **Guidance while editing:** recommended headline length, image quality, or list size. These should be plain-language warnings and live counters.
- **Publish blockers:** missing required content, invalid links or phone/email values, unsupported file types, unsafe rich text, an item count outside the template's supported range, or an image that cannot satisfy a critical slot.

Rich text should expose only the formatting a slot needs—usually paragraphs, bold, italic, links, and lists. The template, not the owner, sets heading levels and visual styling. Validate again on the server; browser-only checks are never the authority.

### 5. Images need slot rules and a focal point, not manual responsive design

Sanity separates reusable image assets from their use in a document. A particular use can carry its own caption, crop, and hotspot; the hotspot marks the important area to preserve when the frontend crops the image at different sizes. [Sanity: Image field](https://www.sanity.io/docs/studio/image-type) and [Sanity: Presenting images](https://www.sanity.io/docs/apis-and-sdks/presenting-images)

Storyblok's preview provides desktop, mobile, and full-width modes. [Storyblok: Visual Editor](https://www.storyblok.com/docs/manuals/visual-editor)

**Uplift fit:** every image slot should explain what it is for, show its preferred shape, accept only safe formats/sizes, require meaningful alt text unless marked decorative, and allow a focal point. The owner previews desktop and mobile, but never sets separate positions, pixel widths, or breakpoints. Responsive layout remains part of the tested template.

## Recommended owner experience

1. Enter from the CRM's **Website** area and land on the assigned site's content dashboard.
2. Choose **Business details**, a named **Page**, or a reusable list such as **Services** or **Gallery**.
3. Edit a short, labelled form. Selecting an item in the preview may focus its corresponding form, but it does not turn the page into a free-form canvas.
4. See changes autosave to the draft and update in desktop/mobile preview.
5. Resolve clear warnings or publish blockers.
6. Select **Publish changes** deliberately; until publishing succeeds, visitors continue seeing the previous release.

The first CMS version should prove this with one real template. Add another template only after the shared facts, collections, template schema, draft, preview, and validation contract work end to end.

## Avoid in the first product

- a blank page canvas or arbitrary drag-and-drop layout;
- user-created section types, nested blocks, custom code, or plugins;
- raw typography, spacing, breakpoint, or animation controls;
- a separate CMS login or CMS-managed roles;
- automatic two-way syncing of website facts with CRM records;
- saving draft changes directly into the public content record;
- per-device content copies that can drift apart.

## Decision to carry into Part 2

Approve the **fixed-template, structured-content** model: globally reusable business facts, fixed page/section forms, typed reusable collections, guarded media with focal points, autosaved private drafts, desktop/mobile preview, warning-plus-blocker validation, and deliberate publishing. This is simpler for a non-technical contractor owner and preserves the professional responsive design Uplift is responsible for.

## Follow-up verification: autosave and editing collisions

Verified 2026-10-02 against current official documentation and source.

### Bricks Builder autosave

Bricks creates an autosave by default every **60 seconds**, but only when the current builder area has unsaved element changes. An administrator can change the interval or disable autosave at **Bricks > Settings > Builder**. The documented minimum interval is **15 seconds**. The recovery copy contains the canvas elements, not global data such as components, classes, or variables, and can be restored from **Manage > History / Revisions**. Bricks also warns before an accidental reload when it detects unsaved changes. Saving an unpublished draft does not publish it; publishing remains a separate action. [Bricks Academy: Save & Publish](https://academy.bricksbuilder.io/builder/interface/save-publish/) and [Bricks Academy: Settings—Autosave](https://academy.bricksbuilder.io/builder/setup/settings/#autosave)

**Uplift lesson:** a selectable interval is a legitimate administrator preference, but owner-facing autosave should remain on by default. Label it as draft recovery, not publication, and be explicit about which data it protects.

### WordPress core post locking

Normal WordPress core editing uses a lock stored on the individual post record as `_edit_lock`; the lock contains a timestamp and user ID. `wp_check_post_lock()` checks the specific post ID and treats **another user's** lock as active within a default **150-second** window, which can be filtered. It deliberately returns no conflict when the lock belongs to the current user, so two tabs or devices signed into the same account are not separated by this mechanism. The editor refreshes the lock through the Heartbeat API. This means a page or post is locked, not the entire website: two people may edit different page/post IDs at the same time. [WordPress Developer Resources: `wp_set_post_lock()`](https://developer.wordpress.org/reference/functions/wp_set_post_lock/), [`wp_check_post_lock()`](https://developer.wordpress.org/reference/functions/wp_check_post_lock/), and [`wp_refresh_post_lock()`](https://developer.wordpress.org/reference/functions/wp_refresh_post_lock/)

When a second editor opens the same locked record, WordPress's standard dialog names the current editor and asks whether to **Take over**; it may also offer Go back and Preview. Plugins can disable takeover through the `override_post_lock` filter. If takeover occurs, the first editor's next lock refresh reports that the other user has taken over. The lock-lost dialog saves the first editor's latest changes as a revision before directing them away. [WordPress Developer Resources: `_admin_notice_post_locked()`](https://developer.wordpress.org/reference/functions/_admin_notice_post_locked/) and [`wp_refresh_post_lock()`](https://developer.wordpress.org/reference/functions/wp_refresh_post_lock/)

WordPress 7.0 did **not** ship real-time collaborative editing; WordPress removed it before release because it was not considered robust enough. As of this verification, collaboration remains active development rather than the ordinary core editing model to copy for production. [Make WordPress Core: Real-time collaboration will not ship in WordPress 7.0](https://make.wordpress.org/core/2026/05/08/rtc-removed-from-7-0/) and [Make WordPress Core: Moving to a server-aware approach for collaboration](https://make.wordpress.org/core/2026/09/18/moving-to-a-server-aware-approach-for-collaboration/)

### Elementor on WordPress

Elementor uses WordPress's post lock for the current Elementor document. Its server-side editor calls `wp_check_post_lock()` and `wp_set_post_lock()` with that document's post ID. While the editor is open, Elementor sends the same `post_ID` through WordPress Heartbeat; the server either renews the lock, returns the other editor's display name, or force-sets the lock after a takeover request. Because it relies on WordPress's check, the ordinary Elementor page lock also does not distinguish two editing sessions signed into the same WordPress user. [Elementor source: editor lock methods](https://github.com/elementor/elementor/blob/main/core/editor/editor.php) and [Elementor source: Heartbeat handler](https://github.com/elementor/elementor/blob/main/includes/heartbeat.php)

When Elementor receives another locked user's name, it first triggers its automatic save if the current document has unsaved changes, then shows a modal naming that user with **Take Over** and **Go Back** actions. Choosing Take Over sends `elementor_force_post_lock` on the next heartbeat; choosing Go Back returns to the previous screen. Elementor therefore prevents ordinary simultaneous editing of the same page/document but does not block editing a different page elsewhere on the site. It is a takeover model, not real-time co-editing. [Elementor source: editor Heartbeat UI](https://github.com/elementor/elementor/blob/main/assets/dev/js/editor/utils/heartbeat.js)

**Uplift lesson:** because client access is owner-only, the likely collision is the same owner using two tabs or devices. A WordPress-style user-ID lock alone would miss that case. Give every editor tab/session its own identifier, lock the smallest independently saved CMS record, and pair the temporary lock with version checks on save. Show exactly where the other session is editing, preserve the displaced tab's work as a recoverable draft/version, and require an explicit takeover. Do not lock the whole website merely because one page or collection item is open.
