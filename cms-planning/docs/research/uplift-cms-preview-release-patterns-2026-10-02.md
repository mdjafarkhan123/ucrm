# Uplift CMS preview and release patterns

Research date: 2026-10-02  
Scope: owner-visible draft preview, publishing, failure handling, release history, restore, deletion recovery, and practical retention for Uplift's owner-only structured CMS connected to Astro and Cloudflare. Official product facts are separated from the V1 recommendation.

## Executive recommendation

Give the owner a protected live preview of the current draft and a direct **Publish changes** action. Publishing must freeze the current draft into an immutable release candidate, validate and build it, test the uploaded Cloudflare version, and only then promote it. Until promotion succeeds, the public domain continues serving the last successful release.

History should show immutable published releases plus failed attempts. Restoring an old release should create a **new draft** for preview and deliberate republishing; it should never erase later history or instantly replace the live site. Deletions should move reusable content and media to a 30-day trash, with reference-aware warnings and recovery.

## Official patterns from mature products

### Private draft preview is a separate view of content

- Contentful separates its public Content Delivery API from a read-only Preview API that returns the latest unpublished entries and assets using a distinct preview token. Its editor supports live side-by-side preview or preview in a new tab. [Contentful: Preview API](https://www.contentful.com/developers/docs/references/content-preview-api/overview/), [Contentful: Set up content preview](https://www.contentful.com/developers/docs/tutorials/preview/content-preview/), and [Contentful: Live preview](https://www.contentful.com/developers/docs/tutorials/preview/live-preview/)
- Sanity uses a `drafts` perspective for preview and a `published` perspective for production. Its secure draft mode uses a secret handshake; draft content is excluded from public unauthenticated delivery. [Sanity: Presenting and previewing content](https://www.sanity.io/docs/content-lake/presenting-and-previewing-content), [Sanity: Implementing draft mode](https://www.sanity.io/docs/visual-editing/implementing-draft-mode), and [Sanity: Drafts and versions](https://www.sanity.io/docs/content-lake/drafts-and-versions)
- Storyblok renders draft content in its visual preview, provides desktop/mobile/full-width views, and can open the preview in a new tab. Published-but-changed content remains preview-only until republished. [Storyblok: Visual Editor](https://www.storyblok.com/docs/manuals/visual-editor)
- Webflow lets teams publish to a staging subdomain without publishing to the custom production domain. [Webflow: Publish or unpublish a site](https://help.webflow.com/hc/en-us/articles/33961351954579-How-do-I-publish-or-unpublish-a-Webflow-site)
- Cloudflare Worker Version URLs can expose an uploaded version before production deployment, but are public by default unless protected with Cloudflare Access. [Cloudflare Workers: Version URLs](https://developers.cloudflare.com/workers/versions-and-deployments/version-urls/)

**Product lesson:** preview must deliberately read draft content and require authorization. A hard-to-guess public URL is not privacy.

### Direct publishing and approval are both valid, but serve different teams

- Storyblok's configurable workflow can move content through Drafting, Reviewing, and Ready to Publish, and can restrict publishing until the required stage. [Storyblok: Workflows](https://www.storyblok.com/docs/manuals/workflows)
- Webflow separates roles that may publish from reviewer or “designer needs approval” roles. It also lets CMS items publish immediately, queue for the next full-site publish, or remain draft. [Webflow: Publish or unpublish a site](https://help.webflow.com/hc/en-us/articles/33961351954579-How-do-I-publish-or-unpublish-a-Webflow-site) and [Webflow: Save and publish Collection items](https://help.webflow.com/hc/en-us/articles/33961230697107-Save-and-publish-Collection-items)

**Product lesson:** approval is useful when writer and publisher are different people. It adds ceremony without adding safety when the only authorized editor is also the business owner.

### Draft, uploaded version, and live deployment are different states

- Sanity keeps a published document intact while edits accumulate in a separate draft; production's published perspective ignores the draft until publication. [Sanity: Drafts and versions](https://www.sanity.io/docs/content-lake/drafts-and-versions)
- Cloudflare separates a Worker **version** from a **deployment**. A version captures code, static assets, bindings, and settings; a deployment decides which version receives live traffic. A version can be uploaded and tested without deploying it. [Cloudflare Workers: Versions and deployments](https://developers.cloudflare.com/workers/versions-and-deployments/) and [Cloudflare Workers: Deployment management](https://developers.cloudflare.com/workers/versions-and-deployments/deployment-management/)
- Cloudflare can roll back by creating a new deployment that points traffic at an older Worker version, but external storage such as R2, KV, and D1 is not rolled back with it. [Cloudflare Workers: Rollbacks](https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/)

**Inference for Uplift:** if build, upload, or smoke testing fails before the deployment step, the active Cloudflare deployment is unchanged. This is the correct way to guarantee that a failed publish leaves the last successful public website online.

### Mature history separates saved work from published releases

- Contentful snapshots an entry each time it is published or republished, records who published it and when, and supports comparing and restoring the whole entry or selected fields. Its entry snapshot does not snapshot linked entries or asset binaries, so a restored reference can point to a deleted asset. [Contentful: Versions](https://www.contentful.com/help/content-and-entries/versions/) and [Contentful: Versioning FAQ](https://www.contentful.com/help/faq/versioning/)
- Storyblok creates a version when a story is saved or its workflow stage changes. Its history shows author, time, and changes; Restore replaces the current story with the selected version. [Storyblok: History](https://www.storyblok.com/docs/manuals/history)
- Elementor separates current-session Actions from saved Revisions; each save or publish creates a revision that can be selected in the History panel. Elementor Hosting retains the latest 25 post revisions. [Elementor: Revision history](https://elementor.com/help/revision-history-undo-and-redo/) and [Elementor: Revision limits](https://elementor.com/help/how-many-versions-of-a-post-does-elementor-store/)
- Webflow can preview an old backup before restoring it and saves the current site as another backup when a restore is performed. Paid Site plans have unlimited backups; free Starter sites can restore only the two most recent unless covered by a paid Workspace. [Webflow: Save and restore backups](https://help.webflow.com/hc/en-us/articles/33961244069395-Save-and-restore-backups)

**Product lesson:** the safest restore preserves the state being replaced. CMS release history must also retain the referenced content and media, not only IDs that may later become broken.

### Trash and retention are explicit product policies

- WordPress defaults `EMPTY_TRASH_DAYS` to 30 days. [WordPress Developer Resources: functionality constants](https://developer.wordpress.org/reference/functions/wp_functionality_constants/)
- Storyblok offers a Trash bin app whose Deleted Content view can restore removed stories and folders. [Storyblok: Stories](https://www.storyblok.com/docs/manuals/stories)
- Sanity can recover deleted documents through its History API only inside the plan's history window. Its documented history retention is 3 days on Free, 90 days on Growth, and 365 days on Enterprise; the newest published and draft state remain available, while older revisions are truncated. [Sanity: Find and restore deleted documents](https://www.sanity.io/docs/developer-guides/find-and-restore-deleted-documents) and [Sanity: History experience](https://www.sanity.io/docs/user-guides/history-experience)
- Cloudflare's interactive rollback list is limited to the 100 most recently published Worker versions. [Cloudflare Workers: Rollbacks](https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/)

**Product lesson:** “version history” is not a promise of permanent retention. The interface must state what is recoverable and for how long, and the CMS cannot rely on Cloudflare's deployment list as its content history.

## Recommended V1 behavior for Uplift

### 1. Preview

1. The owner selects **Preview draft** from the CMS editor.
2. The CMS opens the real assigned website design in an embedded preview or new tab, with desktop and mobile controls.
3. The preview reads the current autosaved draft through a short-lived, site-specific authorization. It sends `noindex` and must not expose CMS or Cloudflare secrets to the browser.
4. Preview clearly says **Draft preview — not live** and shows the draft's last-saved time.
5. The public domain always reads the last published release, never the mutable working draft.

For V1, one current-draft preview is enough. Shareable public preview links, comments, approval requests, scheduled publishing, and multiple named release candidates can wait until real demand exists.

### 2. Direct publish without an approval workflow

The CRM organization owner is the only client editor and publisher, so V1 should use direct publishing. The button should say **Publish changes**, followed by a confirmation summarizing the affected pages/items and confirming that the public site will update. “Request approval” has no useful recipient in the current product boundary.

Publishing must capture a fixed snapshot. If the owner continues editing after the job begins, those later edits remain in the draft and are not silently added to the in-progress release.

### 3. Visible publish states and failure safety

Show one durable publish job with these plain-language states:

`Queued → Checking content → Building website → Testing preview → Making live → Live`

On failure, show `Publish failed`, the failed stage, a useful owner-facing explanation, the time, and **Retry publish**. Preserve both the draft and the technical error for support. The owner may leave and return without losing the job status.

The server-side order should be:

1. wait for pending draft saves;
2. freeze an immutable content snapshot;
3. validate the whole snapshot;
4. build the Astro site;
5. upload a non-live Cloudflare version;
6. smoke-test that exact version;
7. promote it to production;
8. record the release-to-deployment mapping.

Any failure before step 7 leaves the previous deployment live. Only one publish job per website should promote at a time; a second request should point to the existing job or wait behind it.

### 4. History and restore

Owner-visible **Version history** should list successful published releases with release number, publication time, actor, changed pages/items, and deployment status. Failed attempts should appear separately as attempts, not as live versions.

For an earlier release, provide **Preview version**, **Compare with current draft**, and **Restore as draft**. Restore must:

- leave the public website unchanged;
- preserve the old release and every release after it;
- create a new draft from the old immutable snapshot;
- include the media needed to render it;
- require a normal publish to make it live, creating a new release number.

Cloudflare's infrastructure rollback remains an administrator emergency tool. It is not the owner's normal restore button because it does not restore external data and can make Cloudflare's active artifact disagree with CMS history.

### 5. Deletion and recovery

- Fixed required pages and sections cannot be deleted; optional sections can be hidden.
- Deleting a service, testimonial, gallery item, or media asset first shows where it is used.
- Confirmed deletion moves it to **Trash** and removes it from the working draft; the public site stays unchanged until publishing.
- Trash supports Restore and permanent deletion. Restore keeps the original stable ID so references can reconnect.
- An asset still required by a retained published release must not have its underlying file purged, even if it disappears from the active media library.

### 6. V1 retention promise

| Data                                                            | Recommended guaranteed retention                                                               |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Current working draft                                           | For the life of the active website record                                                      |
| Fine-grained draft checkpoints                                  | Whichever is greater: the latest 25 per record or all from the last 30 days                    |
| Successful published release snapshots and their required media | Whichever is greater: the latest 50 releases or 365 days; never prune the current live release |
| Trashed content/media                                           | 30 days, unless a retained release still requires the underlying data                          |
| Detailed failed-publish logs                                    | 90 days; keep the attempt's summary with release history                                       |

These limits are intentionally understandable and stronger than relying on a provider's short operational history. Structured JSON snapshots are small; media retention will be the main storage cost and should be measured before changing the promise.

## Part 3 decision to carry forward

Approve a **protected draft preview + direct immutable publish** model for V1. The owner sees draft versus live clearly, can publish without an approval queue, never loses the last successful site to a failed build, and restores an old release by creating a new draft and release. Add a 30-day trash and publish the retention promise in the product instead of implying unlimited history.
