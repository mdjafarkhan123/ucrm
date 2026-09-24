# Work report photo presentation: how mature products arrange photos for the customer

Researched 2026-09-24 for UCRM's customer-facing work report. Sources are first-party help centres, product pages and
official blogs from CompanyCam, Housecall Pro, Jobber, ServiceTitan, Procore, Fieldwire and Buildertrend. Anything the
official docs did not state is marked **not found in official docs**. No product code or live data was changed.

Note on CompanyCam: its older "Reports" and "Pages" help articles (e.g. `7048115-creating-a-report`,
`6828448-creating-and-using-report-templates`) now return 404. The product has been folded into **Documents**. This note
uses the current Documents articles, plus one archived Reports article (April 2026) where it adds detail.

## Executive finding

The two products that ship a real customer-facing **photo report** (CompanyCam Documents, Housecall Pro Photo Reports)
use the same shape:

1. the contractor picks photos (the report never auto-includes every job photo);
2. the report is split into **free-text titled sections** ("Before", "During", "After", "Kitchen");
3. photos are **dragged** to reorder inside a section and between sections;
4. each photo shows its existing **description/caption** (optional per section or per report);
5. a small set of **layout switches** (list vs grid, or photo size/aspect), not a free-form canvas;
6. sent as a **web link** plus a **PDF** download.

Neither product derives sections from tags automatically. Tags are used as a filter to help pick photos, and section names
are typed by the contractor. Before/after comparisons are a separate photo tool, not a report block. Everyone else (Jobber,
ServiceTitan, Procore, Fieldwire, Buildertrend) either attaches loose photos to a document or exports photos in a fixed
order, with no real layout control.

## CompanyCam (most mature)

### Ordering

- In a Document, "click and hold the 12 dots icon that appears when hovering over a photo, then drag it anywhere in your
  Document to rearrange it — within its current photo group or into a different one." A drop indicator shows where it will
  land. [Editing Documents](https://help.companycam.com/en/articles/15880536-editing-documents)
- Photos cannot be dragged into a Notes Section or Table Section; only within or between Photo Sections.
  [Editing Documents](https://help.companycam.com/en/articles/15880536-editing-documents)
- In the older Reports flow, photos added to an existing report were "added to the end of the Report. Reorder the photos
  in the Report if needed." [Create a Report with Tags (archived 2026-05-14)](http://web.archive.org/web/20260514105757/https://help.companycam.com/en/articles/6828358-create-a-report-with-tags)
- Default order when a Document is first created from a selection: **not found in official docs**.
- For comparison, CompanyCam's live **Timeline** share link shows photos "in the order you shot them".
  [Galleries and Timelines Explained](https://help.companycam.com/en/articles/16879590-galleries-and-timelines-explained)

### Sections, grouping and text

- Blocks inserted with **+**: **Photo Section**, **Table Section**, **Notes Section**, plus Cover Page and page breaks.
  The editor also has headers, bold/italic, lists and text snippets, so text sits between photo groups.
  [Editing Documents](https://help.companycam.com/en/articles/15880536-editing-documents)
- Section headings are free text. The older Reports flow described sections as a way to break a job "out by area, phase,
  or trade", each with a Section Summary text box. [How to create a PDF report (class)](https://companycam.com/resources/classes/how-to-create-a-pdf-report)
- Tags are **not** auto-converted into sections. The official "Create a Report with Tags" method is manual: tag photos,
  filter the project by the tag, select them, "Add to Existing Report", repeat per group.
  [Create a Report with Tags (archived)](http://web.archive.org/web/20260514105757/https://help.companycam.com/en/articles/6828358-create-a-report-with-tags)
- Templates save the layout/structure for reuse; photos are not saved in a template.
  [Using Document Templates](https://help.companycam.com/en/articles/16024162-using-document-templates),
  [Build photo reports faster with templates (blog)](https://companycam.com/resources/blog/page-templates-build-photo-reports-faster)

### Before/after

- Separate tool. Web: select any two photos, then **Create Before & After**. You can "swap Before/After position" and
  "choose a template from the bottom of the screen". Mobile: take the After photo with an overlay of the Before (blurry or
  outline) to line it up. [Create a Before & After Photo](https://help.companycam.com/en/articles/6828372-create-a-before-after-photo)
- Described as pairing "two photos of the same job side by side". The result is "automatically tagged with the 'Before and
  After' tag" and shared via gallery or timeline link, which suggests it is stored as its own project item.
  [Create a Before & After Photo](https://help.companycam.com/en/articles/6828372-create-a-before-after-photo)
- Marketing copy mentions "20+ branded layout templates" and logo stickers.
  [Before & After tool (blog)](https://companycam.com/resources/blog/best-before-after-photo-tool-for-contractors),
  [Before & After product page](https://companycam.com/advanced-features/before-after-photos)
- It is **not** driven by Before/After tags; the user picks the two photos. Slider view: **not found in official docs**.
  Whether it is saved as one flattened image: **not stated explicitly**. A dedicated before/after block inside Documents:
  **not found in official docs**.

### What the customer sees

- Per-section layout control: "Photo Size, Layout, and Aspect Ratio". Document settings toggle Capture Details, Photo
  Tags, Photo Location and Photo Numbers. "Show Photo Text" pulls in photo descriptions.
  Headers/footers carry logo, company and project details; optional Cover Page.
  [Editing Documents](https://help.companycam.com/en/articles/15880536-editing-documents)
- The older Reports flow let you "choose how many photos you want on each page".
  [How to create a PDF report (class)](https://companycam.com/resources/classes/how-to-create-a-pdf-report)
- Annotating a photo inside a Document changes only the document's copy, not the original project photo.
  [Editing Documents](https://help.companycam.com/en/articles/15880536-editing-documents)
- Sharing: **Copy Link**, or export; "When you export a Document, it's automatically saved as a PDF in the Project."
  [Sharing and Exporting Documents](https://help.companycam.com/en/articles/15888440-sharing-and-exporting-documents)

### Edits after sending

- Whether a shared Document link reflects later edits: **not found in official docs**.
- Exported PDFs are separate saved files, so they are fixed at export time
  ([Sharing and Exporting Documents](https://help.companycam.com/en/articles/15888440-sharing-and-exporting-documents)).
- CompanyCam **does** document the snapshot/live distinction for photo links: "A Gallery won't update. It shows the photos
  you selected when you shared it." A Timeline "updates itself" as new photos are added.
  [Galleries and Timelines Explained](https://help.companycam.com/en/articles/16879590-galleries-and-timelines-explained)
- Gallery links "can not be disabled on the User's end". [Sharing Photos](https://help.companycam.com/en/articles/6828401-sharing-photos-in-companycam)

### Auto-building

- AI layouts (Summary, Daily Log, Progress Recap, Walkthrough) draft a document from selected photos and their
  descriptions, then the user edits. How AI groups/orders photos: **not found in official docs**.
  [Using AI Features for Documents](https://help.companycam.com/en/articles/8991633-using-ai-features-for-documents),
  [Creating Documents](https://help.companycam.com/en/articles/8695593-creating-documents)
- Non-AI auto-grouping by tag or date: **not found in official docs**.

## Housecall Pro (closest match to a small-contractor report)

All from [Photo Report on Jobs](https://help.housecallpro.com/en/articles/14299953-photo-report-on-jobs) unless noted.

- **Built per job**, from the Job Details "Photo Reports" card. Multiple reports per job allowed, "for example, a 'Before'
  report and an 'After' report."
- **Cover page** auto-fills logo, business details, customer and job info; editable title, optional rich-text description,
  optional cover photo.
- **Sections**: "Add section" with a free-text title such as "Before", "During", "After" or "Equipment Installed", each
  with an optional rich-text description. Photos are added per section with "Add attachments".
- **Ordering**: "Drag and drop photos to reorder them" within sections; sections are reorganised in the left navigation
  panel.
- **Layout**: "Attachments display in list view by default" (description beside the image); "grid view" is a compact
  layout where "descriptions are hidden".
- **Captions**: editing a photo's description "updates the description throughout the report". One description per photo.
- **Before/after**: handled by naming sections Before/After; no pair or slider feature documented. Before/after pairing:
  **not found in official docs**.
- **Delivery**: Preview, then "Save and send" by email/SMS, or download/print PDF. Customers also see it in the customer
  portal under "Gallery > Photo Reports", listed by title, date sent and service address.
- **Edits after sending**: "When you save edits, the report is updated immediately. If you want the customer to see the
  changes, send them the updated report." Whether the already-sent link shows the edit without resending is ambiguous.
- **Auto-building**: none documented; sections and photo selection are manual.
- Before Photo Reports existed, the pattern was loose attachments: pick files, send a gallery link that expires after 7 days
  (auto-reissued), and images are not embedded in the invoice PDF by default.
  [Attachments: Send Customers Photos & Documents](https://help.housecallpro.com/en/articles/1079307-send-customers-photos-documents)

## Jobber

- **No photo report product** found in official docs. Photos live on notes/attachments and in a client-level Files and
  Media library "organized by date", filterable by property, source, type and date. Manual reorder: **not found**.
  [Files and Media Library](https://help.getjobber.com/en/articles/files-and-media-library/)
- **Invoices** (Grow/Plus): pick images from the library, "for example ... before and after photos". Images show in the
  Images section in client hub; they "do not display inline in the PDF" — the PDF lists filenames and links to client hub.
  Ordering/captions: **not found**. [Invoice Basics](https://help.getjobber.com/en/articles/invoice-basics/)
- **Checklists (job forms)**: image fields (up to 10 photos per field) inside named, reorderable **sections**; emailed as a
  PDF that includes the photos. The structure comes from the form template, not from arranging photos.
  [Checklists](https://help.getjobber.com/hc/en-us/articles/115009740048-Checklists)
- Jobber points users who want richer photo docs to its CompanyCam integration.
  [Jobber product update: CompanyCam](https://productupdates.getjobber.com/9132-let-your-photos-do-the-heavy-lifting-with-companycam)

## ServiceTitan

- Photos attach to the job; techs can rename and mark up. Ordering, tags, captions and customer sharing:
  **not found** in [Manage photos, videos and files](https://help.servicetitan.com/docs/manage-photos-videos-and-files-in-fma).
- Customer-facing photos come through **forms**: "the customer receives a PDF version of the completed form including any
  pictures or notes you added". Sections can be duplicated/deleted while filling. Editing after sending: **not found**.
  [Complete and send forms in ServiceTitan Mobile](https://help.servicetitan.com/docs/forms-in-servicetitan-mobile)
- A dedicated photo report or before/after tool: **not found in official docs**.

## Procore and Fieldwire (construction, office-facing exports)

- **Procore**: export Photos as PDF at "1 per page, 2 per page, or 4 per page", all or selected, only what is filtered.
  [Export Photos as a PDF](https://v2.support.procore.com/product-manuals/photos-project/tutorials/export-photos-as-a-pdf).
  Albums can be drag-reordered ([Reorder Photo Albums](https://support.procore.com/products/online/user-guide/project-level/photos/tutorials/reorder-photo-albums));
  reordering photos inside an album: **not found**. Sections = albums; no before/after or text blocks documented.
- **Fieldwire**: photos auto-grouped in folders "in chronological order by the date the photos ... were added"; tags
  filter/group. Task reports choose sort/filter and what to include; photos follow task order. Help pages block automated
  fetching, so this is from the official KB search snippets for
  [Introduction to the Photos Tab](https://help.fieldwire.com/hc/en-us/articles/211358926-Introduction-to-the-Photos-Tab)
  and [How to Sort and Filter Reports](https://help.fieldwire.com/hc/en-us/articles/360000489886-How-to-Sort-and-Filter-Reports)
  — **not directly verified**.
- **Buildertrend**: daily logs carry photos and are shared to the Owner Portal by a share toggle; no report layout control.
  Help pages returned 403; **not directly verified** ([Daily Logs on Mobile](https://buildertrend.com/help-article/daily-logs-on-mobile/)).

## Answers by question

| Question | CompanyCam | Housecall Pro | Others |
| --- | --- | --- | --- |
| 1. Ordering | Drag within/between photo sections; new photos append to end | Drag within section; reorder sections | Fixed: by date (Jobber, Fieldwire) or upload order (Procore) |
| 2. Sections | Free-text Photo/Notes/Table sections, rich text between | Free-text titled sections + rich-text description | Form sections (Jobber, ServiceTitan); albums (Procore) |
| 3. Before/after | Separate tool: pick 2 photos, side-by-side template, auto-tagged | Just a section named "Before"/"After" | Loose photos; no pairing tool |
| 4. Customer view | Link + PDF; photo size/layout/aspect; toggle descriptions, tags, dates; cover, header/footer | Link + PDF + portal; list (with captions) or grid (no captions); cover | PDF with 1/2/4 per page (Procore); client hub images (Jobber) |
| 5. After sending | Link behaviour not documented; PDF fixed; photo Gallery = frozen, Timeline = live | "Updated immediately"; resend to notify | Not documented |
| 6. Auto-build | AI drafts from photos + descriptions, then edit; tags only as a pick filter | None | Date folders (Fieldwire) |

No product documents a before/after **slider** in a customer report.

## Common pattern

**What most do:** the contractor chooses which photos go in; groups them under **typed section headings**; drags to reorder;
shows each photo's single caption; picks from two or three fixed layouts; sends a branded web link with a PDF version.
Tags help *find* photos but do not *build* the report. Before/after is either a separately created side-by-side image
(CompanyCam) or simply two sections named Before and After (Housecall Pro).

**Where they differ:** CompanyCam is a free-form document editor (notes, tables, AI drafting, many layouts). Housecall Pro
is a fixed, simple structure (cover, then sections, then photos, list or grid). Construction tools (Procore, Fieldwire) only
export in a fixed order with a photos-per-page choice. Live vs frozen links: only CompanyCam states it clearly, and only for
photo links (Gallery frozen, Timeline live); Housecall Pro re-sends after edits.

**Recommendation for UCRM (simplest proven model): follow Housecall Pro's Photo Report structure.**

1. **Sections with typed headings**, each with an optional short text note. When the report is created, pre-fill sections
   from the existing labels in a fixed order (Before, During, After, Damage, then "Other" for unlabelled photos), ordered by
   time taken inside each section. This is a starting point the contractor can rename, delete or reorder — labels are used
   only to seed, not kept in sync (this matches CompanyCam's "tags help pick, contractor arranges").
2. **Drag to reorder** photos within and between sections, plus up/down buttons for keyboard and mobile users.
3. **Keep the one caption per photo**; show it under the photo in the default list layout. Offer only two layouts: **list**
   (large photo + caption) and **grid** (2-up, caption hidden or small), like Housecall Pro. The PDF follows the same order.
4. **Before/after:** do not build a slider or image-merging tool now. The Before and After sections cover the common case.
   If a pairing tool is added later, copy CompanyCam: pick two photos, swap positions, render side by side.
5. **After sending:** keep UCRM's frozen snapshot per issued link (consistent with CompanyCam's Gallery rule and fixed PDF
   exports). An edit creates a new version; the contractor re-sends, as Housecall Pro instructs. Show "sent version is
   older than current" on the report so they know to re-send.
