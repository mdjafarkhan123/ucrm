# Sidebar variant 2 — revision 1

Open `/demo/app-shell-v2/index.html`. Jafar explicitly requested a duplicate of the first demo for a
second, more premium and clear sidebar direction. Variant 1 remains at `/demo/app-shell/index.html`.
This is a standalone review demo with fictional data and in-memory actions; live components are unchanged.

## Research and adaptation

- [NN/g: vertical navigation](https://www.nngroup.com/articles/vertical-nav/) recommends left-aligned,
  visible, descriptive navigation labels; optional collapse is a compromise for daily-use apps. It also
  identifies scrolling and space as trade-offs. We retain text labels by default, preserve existing
  destination names and groups, and make collapse optional. Navigation scrolls independently while the
  collapse control stays reachable. No new nested menus hide familiar destinations.
- [Linear: interface refresh](https://linear.app/now/behind-the-latest-design-refresh) describes reducing
  interface noise, improving hierarchy and alignment, and balancing information density with comfort.
  Our adaptation strengthens business identity, quiets group headings and gives selected navigation
  more emphasis. This does not establish that Linear uses our specific sidebar arrangement.
- [W3C navigation semantics](https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/examples/disclosure-navigation/)
  supports ordinary navigation links rather than menu-widget roles. Existing grouped links and
  `aria-current` remain, with explicit accessible names when collapsed.
- [W3C modal pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/) supplies the phone drawer’s
  keyboard containment, Escape dismissal and focus return requirements, retained from variant 1.

The inset forest panel, unboxed business identity, larger business mark, sentence-case group headings,
fine separators, quieter icons and pale-sage selected row are our visual interpretation of the approved
Botanical foundations. They require Jafar’s review; research is not a usability study of this design.

## Scope

Only the sidebar composition and its phone presentation change. The header, destinations, permissions,
access samples, placeholder page content and simulated header actions are inherited from variant 1.
Contractor views retain the requested absence of the Uplift logo; Control Room retains its identity.
Long business names wrap. All links remain available by scrolling; unavailable entries remain explicit.
Dark appearance, production record search, record editors and universal dialog styling remain outside
this review. Restricted scenarios illustrate filtering, not production role presets.

## Verification

See `evidence/` for desktop (1440×900), phone (390×900), collapsed and long-name captures and checks.
The first demo’s research and capability inspection remain recorded in `../app-shell/README.md`.
No application rollout is approved by building this variant. Assistive-technology and outdoor usability
remain unverified; full text-resizing support still needs review before implementation.

Compile: `npx sass static/demo/app-shell-v2/styles.scss static/demo/app-shell-v2/styles.css --no-source-map`.
