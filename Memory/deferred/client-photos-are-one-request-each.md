# Client photos are one request each

- **Priority:** P3


- **Campaign:** `clients-properties`, accepted limit rather than a defect.
- **Reason:** Attachment photos are private, so each one is fetched through our own server rather than
  straight from storage. A first view of N photos is N round trips, each cached privately for a day.
- **Reactivation trigger:** A client carries dozens of photos, or a client page feels slow to open.
- **Prerequisites:** Decide with Jafar between signed storage URLs handed to the browser in one batch, or a
  sprite/manifest response. Both change how private files are served, so it is his call.
- **Checkpoint:** `src/lib/components/collaboration/AttachmentsCard.svelte` and the attachment API route.

