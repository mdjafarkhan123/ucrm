# Files and Media UI blueprint

The approved product behavior is in `docs/files-media-behavior-contract.md`. This blueprint owns placement and
interaction for the contractor-facing File Manager. Existing design tokens and shared controls own its appearance.

## Desktop workspace

```text
┌ Files ──────────────────────────────────────────────────────────────────────┐
│ Search files…                     Filters     Grid/List      Upload          │
├───────────────┬─────────────────────────────────────────────────────────────┤
│ All files     │ Recent files                                                 │
│ Recent        │ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐                  │
│ Photos        │ │preview │ │preview │ │  PDF   │ │ video  │                  │
│ Videos        │ │name    │ │name    │ │name    │ │name    │                  │
│ Documents     │ │5 uses  │ │1 use   │ │3 uses  │ │2 uses  │                  │
│ Shared with   │ └────────┘ └────────┘ └────────┘ └────────┘                  │
│ customers     │                                                              │
│ Not attached  │                                                              │
│ Trash         │ All files                                                    │
│ Folders       │ bounded grid/list with cursor continuation                    │
└───────────────┴─────────────────────────────────────────────────────────────┘
```

The left rail contains stable smart views and user folders. The main header keeps search dominant, with compact
filter and view controls followed by one green Upload action. Grid is the default for mixed media; list is better
for document-heavy work and exposes name, type, folder, origin, uploaded time, and usage count.

Search matches File names as well as Client names, Property addresses, and Job, Quote, or Invoice numbers. Shared
with customers is deliberately explicit about external visibility. Not attached catches direct uploads that do
not yet have a CRM record link and clears them automatically after attachment.

## Attach existing

Every supported record editor uses the same picker. It leads with Files already connected to the current record
or Client, then Recent, Photos, Documents, and All files. Search remains available throughout. This makes common
reuse fast without inventing copies or forcing the contractor to remember a folder.

## File details

Clicking a tile or row opens the existing `layout/SidePanel.svelte` from the right. The selected item remains
visually selected behind it. The panel is 440px on desktop and full-width on narrow screens.

```text
┌ boiler-before.jpg                                      × ┐
│ [                 large safe preview                  ] │
│ Download     Attach to…                          •••     │
│                                                        │
│ JPEG · 4.2 MB                                          │
│ Uploaded by Maya · Sep 21, 2026                        │
│ Origin: Job #1042 · 16 King Street                     │
│ Folder: Boiler replacement                             │
│                                                        │
│ Used in 5 places                                       │
│ Invoices (3)                                           │
│  Invoice #3108 · Sent        Customer attachment    ›  │
│  Invoice #3091 · Draft       Line image             ›  │
│  Invoice #3074 · Paid        Customer attachment    ›  │
│ Jobs (2)                                               │
│  Job #1042 · Active          Before photo           ›  │
│  Job #998 · Closed           Work report photo      ›  │
└────────────────────────────────────────────────────────┘
```

The header uses the File name and a close button. The preview is useful but bounded. Primary actions stay directly
below it; lower-frequency Rename, Move, Share with customer, and Trash live in the `...` menu. Metadata is a compact definition
list. “Used in” is a plain heading and total, not a chart or graph.

Usage groups use established CRM colors/icons only to aid scanning. Each row remains a normal accessible link with
record name/number, status, context, and the File's role. The list shows ten places before Show more.

The panel query is preheated on tile/row hover and keyboard focus, then enabled on selection. Until ready it shows
a preview-sized skeleton and usage-row skeletons. Closing returns focus to the selected item and preserves scroll.

## Selection and bulk actions

A normal click opens details. Checkboxes enter selection mode without opening the panel. The bulk bar offers Move,
Download, and Trash only when every selected File permits the action; mixed protected selections explain what is
unavailable rather than pretending success.

## Mobile behavior

Smart views and folders move into a filter sheet. Files remain a two-column photo grid or single-column list. The
details panel fills the screen, retains a visible Back/Close action, and uses the same content order. Upload may
offer camera, photo library, video library, and device files where the browser supports them. No offline guarantee
is shown until offline-safe uploads exist.

## Deliberate omissions

No relationship graph, desktop-style tree browser, arbitrary public folder, live customer timeline, embedded
office-document editor, cross-tenant deduplication, or generic file-version history belongs in the first release.
