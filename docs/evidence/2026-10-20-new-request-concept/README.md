# Shared create form — approved A, 20 October 2026

Jafar chose **A · Quiet white** for Request, Quote, Job and Invoice. The previous session's drawings were
discarded. This session changes the top form's design; the full New Request preview assembles the existing
approved page shell, fields, card headers, Notes, Attachments, Products and services, and save-bar parts.
The right sidebar remains. App code has not been changed.

## References checked

- Live app as owner: `/requests/new`, `/jobs/new`, `/quotes/new`, `/invoices/new`.
- Saved references: `Design/Jobber Request New/01-page-top.jpg`, `02-assessment-and-products-empty.jpg`,
  `Design/Jobber Jobs/2026-08-31/05-create-one-off-default.png`; earlier project wireframes were also inspected.
- Jobber live: `https://secure.getjobber.com/requests/new`; blank form, client list, selected-client contact
  block and More options, and the inline assessment. No request was saved.
- Source component inventory confirms shared RecordFormLayout/PrimaryInfoCard/ClientPicker and pricing parts;
  Job's first card currently differs. No new product workflow was implemented.

## Final exports

- `m4ibfF.png`: approved shared header in light and dark mode.
- `el2At.png`: full 1440px New Request with Notes and Attachments in the right rail.
- `pM2Vf.png`: Quote, Job and Invoice field/colour adaptations of the same header.

## Verification

- Pencil screenshots reviewed for spacing, hierarchy, field alignment and clipping at 1440px.
- Layout inspection: no visible clipped content. Disabled hidden header-action slots are excluded.
- Resolved text-size inspection: no text below 12px in the new boards/screens.
- Corrected a Pencil nested-instance issue that hid the client placeholder in dark mode; the final header
  uses the existing select-field component directly.
- B was removed after selection; no new design tokens were added.
- Jafar saved the final cleaned design at 20:49 Bangladesh time; the saved Pencil file is committed as
  `ac1ec3fe` on `codex/new-request-concept`.
- `git diff --check`: passed. App tests were not run because this is a Pencil-only design delivery.

Implementation will need the project's live screen check after the shared top form is built. These drawings
do not establish functioning app changes or phone-layout approval.
