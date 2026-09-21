# Updated HighLevel Conversations UI audit

Date: 2026-09-18  
Scope: visual and interaction audit only; no inbox code changed.

## Evidence

- `Design/Communications Inbox/ghl-2026-09-18-main-inbox.jpg`
- `Design/Communications Inbox/ghl-2026-09-18-email-composer.jpg`
- `Design/Communications Inbox/ghl-2026-09-18-filter-drawer.jpg`
- `Design/Communications Inbox/ucrm-2026-09-18-current-inbox.jpg`
- Live HighLevel route inspected in Jk LTD: Team inbox → Unread → Test One.
- Current UCRM route inspected locally as Raad LTD owner: `/communications`.

## What survived from the earlier work

The UCRM inbox redesign was not deleted. The current page still has the important working foundation:

- a three-pane desktop workspace;
- Team Inbox and My Inbox;
- All and Unread views;
- search and a new-conversation action;
- a mixed-channel chronological timeline;
- email, SMS, and website-chat composers;
- assignment, following, customer details, and related work;
- real delivery, permission, consent, and channel-availability states.

The earlier deferred note also correctly records unfinished GHL surfaces: Recents/Starred, richer filtering and
sorting, bulk actions, priority/read/delete actions, a docked composer, jump-to-latest, and a richer contact rail.

## Updated GHL structure

Current HighLevel uses four nested navigation/content layers:

1. the product sidebar;
2. a Conversations sub-navigation row (Conversations, Manual Actions, Snippets, Trigger Links, Analytics,
   Settings);
3. a narrow inbox switcher rail (new conversation, import, search, My Inbox, Team Inbox, Internal Chat,
   Views);
4. the working area: conversation list, active timeline, contact details, plus a narrow context icon rail.

UCRM currently starts directly at layer 4 inside its normal app shell. We should copy the useful inbox workspace,
not HighLevel's unrelated product navigation.

## Largest visible differences

### Conversation list

- **GHL:** compact fixed-width list, `Unread / All / Recent / Starred`, filter and sort icon buttons, Select all,
  per-row checkbox, channel badge, unread count, star, date, and one dense preview line.
- **UCRM:** wider list, `Team Inbox / My Inbox` and `All / Unread` segmented controls, a large search row with
  text button, no filter/sort/bulk controls, no Recent/Starred, and taller rows.
- **Direction:** retain Team/My as inbox identity, then reproduce GHL's compact tab row and action controls.
  Search belongs behind the GHL-style search action or in a compact field, not as the dominant list block.

### Timeline header and message area

- **GHL:** one compact header with avatar/name and icon actions for filter, star, read/unread, and delete. The
  timeline sits on a pale neutral canvas. Email is rendered as a full-width card with subject header, sender
  row, reply/more controls, expand control, and collapsed earlier-message stack. System events are small pills.
- **UCRM:** name plus a secondary “View client” line and little conversation handling in the header. The
  timeline is visually sparse; SMS appears as a rounded chat bubble and email/status cards use the older UCRM
  treatment.
- **Direction:** match GHL's header density and card geometry while preserving UCRM's truthful delivery badges
  and the approved full-width email-card rule.

### Composer

- **GHL collapsed:** a single bottom bar with channel selector, “Type a message,” and split send button.
- **GHL expanded email:** a bordered docked panel with channel/Internal Comment header, From/From Name/To/CC/BCC,
  subject, rich editor, a dense capability toolbar, discard, and split send. It overlays/reclaims timeline space
  without becoming a permanently tall form.
- **UCRM:** the composer is permanently expanded and consumes roughly the lower third of the timeline. Channel
  tabs sit above it and SMS metadata/help text is always visible.
- **Direction:** the docked collapsed/expanded composer is the biggest UX improvement. Preserve channel-specific
  safety and price/consent details, but reveal them inside the expanded state instead of permanently shrinking
  the conversation.

### Contact rail

- **GHL:** Contact Details has owner, followers, tags, `All fields / DND / Actions`, search, editable grouped
  fields, created-by/on metadata, and audit logs. A narrow icon rail switches to activities, associations,
  opportunities, tasks, notes, appointments, documents, payments, and logs.
- **UCRM:** a static Customer Context panel with identity, contact values, assignment, follow, related work, and
  automation summary.
- **Direction:** keep UCRM permissions and contractor records, but adopt the denser header and switchable context
  rail. Map GHL modules to contractor concepts rather than adding fake modules.

### Overall visual system

- **GHL:** light neutral canvas, hairline separators, almost no outer card radius, 12–14px dense typography,
  small controls, and blue reserved for selection/action emphasis.
- **UCRM current capture:** dark theme, large rounded outer container, strong green outlines, larger vertical
  spacing, and card-like treatment around the whole workspace.
- **Direction:** reproduce GHL's geometry, spacing, density, and hierarchy using UCRM semantic tokens. Pixel-level
  comparison should be made in matching light and dark themes; current screenshots are not a color-for-color
  comparison because the two apps were captured in different themes.

## Proposed redesign slices

1. **Workspace shell and list:** compact boundaries, Team/My placement, four list tabs, search, filter, sort,
   selection, and row anatomy.
2. **Timeline and conversation controls:** compact header, system pills, email cards, message density, and
   jump-to-latest.
3. **Docked composer:** collapsed bar, expanded email/SMS/web-chat states, internal comment boundary, and
   channel-specific safety details.
4. **Contact/context rail:** compact contact header, tabs/search/groups, contractor record modules, and responsive
   drawer behavior.
5. **Responsive and accessibility pass:** keyboard list behavior, focus management, narrow-screen pane switching,
   and visual comparison at fixed desktop widths.

Each slice should be approved and verified independently. Features that need new backend behavior—per-user
stars/recents, saved filters, bulk operations, internal comments, or permanent deletion—must not be simulated
as decorative controls.

## Audit conclusion

This is a redesign of the existing inbox, not a rebuild from zero. The safest route is to keep the working data,
permissions, realtime, and channel logic, then replace the surface one independently verifiable slice at a time.
The saved 2026-09-18 screenshots supersede the older public GHL screenshots for layout and interaction reference.
