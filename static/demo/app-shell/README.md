# Botanical shell demo — revision 2

Review at `/demo/app-shell/index.html`. Standalone HTML/SCSS; fictional data, in-memory actions,
no API calls or real writes. The selected job-details reference and live components are unchanged.
This revision is awaiting Jafar’s review, not approved implementation guidance.

## Evidence and design choices

The problem is keeping every permitted destination reachable on desktop and phone while extending the
approved Botanical identity. Navigation labels, order, unavailable items, longest-match selection,
Control Room differences, account actions and the empty Add New control come from
`src/lib/components/layout/{AppShell,Sidebar,Topbar,MobileNav}.svelte` and
`src/lib/server/access/navigation.ts`. Existing components are the reuse targets for Part 4.

- [W3C navigation example](https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/examples/disclosure-navigation/)
  supports semantic navigation links rather than application-menu roles. We retain grouped lists,
  ordinary Tab navigation, meaningful labels and a selected-page marker.
- [W3C modal guidance](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/)
  supports contained keyboard focus, Escape dismissal, a visible close button and focus return.
  We adapt that behavior to a full-height phone navigation drawer.
- [MDN dialog reference](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog)
  documents `showModal()` and the inert background. Native dialogs supply the standalone demo’s
  modal mechanism; implementation should reuse the project’s Bits UI wrappers.
- Approved [Botanical foundations](../../../docs/design/botanical-v3/README.md) supply colour,
  hierarchy, surfaces and type. The 242px forest sidebar, cream header, pinned collapse control,
  phone drawer composition and tinted destination placeholder are our adaptation for review,
  not a competitor-validated design or usability-study result.

## Coverage and exclusions

Business full access; illustrative restricted staff and smaller-package samples; full Control Room
and restricted teammate sample. Restricted scenarios demonstrate filtering, not production role
presets. Actual access still belongs to server-resolved packages and permissions. Long organization
and account names, collapsed navigation, support unread badge, unavailable items and reachable
phone navigation are included. Search appears only for Business Workspace, including Ctrl/Command K;
its page-only results and empty state are simulated. Production record-search design remains separate.

Header notifications demonstrate populated, empty, loading and retryable-error states. Account actions
include a simulated sign-out failure, photo-editor destination and Business Workspace security link.
Add New keeps the existing empty behavior. Theme controls remain reachable (inside phone navigation
on narrow screens); Botanical dark appearance is explicitly awaiting focused approval. No account
switcher, new create shortcuts, unsold features or production permission changes are introduced.
Dialogs are supporting interaction previews, not approval of a universal dialog system. Their detailed
record content, editing and actual delivery are outside this shell review.

## Verification

Chromium checks at 1440×900 and 390×900 cover layout, overflow, keyboard dismissal/focus return,
phone destination selection, long names, collapsed sidebar, workspace scenarios, search empty state,
notification states and account failure. Screenshots and final results are in `evidence/`.
Login through the connected app’s existing sign-in screen was attempted, but did not reach the
workspace; source inspection establishes existing shell coverage pending live corroboration before
implementation. No record or account changes were made. Automated accessibility checks supplement
visual review; assistive-technology and outdoor usability testing remain unproven.

Compile with `npx sass static/demo/app-shell/styles.scss static/demo/app-shell/styles.css --no-source-map`.

## Revision round 1

Jafar requested removing the Uplift logo above the contractor identity. Revision 2 shows only the
contractor business identity there, including its own mark when collapsed. This applies on desktop and
phone; Control Room branding is retained. This visual revision does not establish a platform-wide
white-label policy.
