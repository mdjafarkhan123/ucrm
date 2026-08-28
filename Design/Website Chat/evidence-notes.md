# Website Chat — HighLevel & Intercom Evidence (captured 2026-08-26)

Behavior notes only — UCRM's own tokens/spacing/colors own the visual language, not these screenshots'
styling. Captured live via browser automation.

## Intercom (`intercom.com/help` — Fin AI Agent messenger)

- `intercom-opened-panel.jpg`: dark-theme opened panel. Header shows the agent identity ("Fin") plus a
  secondary line ("The team can also help") — sets expectation that a human is reachable, not just AI. Header
  controls: back chevron, "..." overflow, close X. A separate floating collapse chevron sits below the panel
  bottom-right (distinct from the header close).
- Composer row: attachment clip, emoji, GIF/sticker, mic icons, then a circular send button. Placeholder text
  changes from "Ask a question..." to "Message..." once a conversation is underway.
- `intercom-ai-conversation.jpg`: mid-conversation state — visitor's own message right-aligned as a plain
  white bubble (no avatar); AI's reply left-aligned in a dark card with an avatar, sender line reading
  "Fin • AI Agent • Just now" (explicit AI identity + timestamp, never ambiguous about who's replying). The AI
  asks a qualifying question (email) *inside* the conversation rather than gating it behind a pre-chat form —
  confirms the research doc's "collect conversationally, not at the front gate" recommendation.
- A three-dot typing indicator (grey pill, left-aligned) appears between the visitor's sent message and the
  AI's reply — the only "is someone replying" signal, no separate status text.
- Footer: persistent "By chatting with us, you agree to our Privacy Policy" line, visible in every state.

## HighLevel-powered widget (`mallardfence.com` — a real contractor site, dev-confirmed safe to test)

This is the simpler, common real-world deployment — closer to a structured lead-capture form styled as chat
than to HighLevel's full conversational Live Chat described in `docs/research/website-chat-channel-review.md`.
Both patterns exist in the wild; UCRM's contract targets the richer conversational behavior, but this evidence
shows the floor real contractor sites actually ship today.

- `highlevel-teaser.png`: teaser bubble slides in with the business's own logo/avatar, a greeting line ("Hi
  there, have a question? Message us here."), and its own dismiss X — independent of the launcher icon itself
  (a filled circular chat-bubble icon, bottom-right).
- `highlevel-identity-form.jpg`: opened panel header carries the business's branding (logo + name) and a
  question-mark headline, with a collapse chevron (not a close X) — collapsing keeps the session, closing via
  the launcher icon doesn't ask for confirmation. Body: one intro sentence, then Name / Phone (with a
  searchable flag+dial-code country dropdown, confirmed scrollable with 200+ countries) / Email / Message
  fields stacked vertically, a pre-checked SMS/email consent line with rate-disclosure text, and a single
  "Send" button. Footer: "Powered by [Business Name]" — the widget attributes to the contractor, not the
  platform.
- Real-time validation: an invalid/incomplete phone shows inline red "Invalid value" text next to the field,
  not a blocking submit-time alert.
- `highlevel-post-submit-confirmation.jpg`: on submit, the entered form fields echo back as one green
  outbound-styled summary bubble (Name/Phone/Email/Message together), followed immediately by a checkmark
  icon and "Thank You! One of our representatives will contact you shortly." The panel then goes idle — no
  open composer, no further messages possible in this session. This is a fire-and-forget lead form, not a
  persistent two-way thread.

## Behavioral takeaways for WC0.4

- Two real patterns exist under the same "chat widget" label: Intercom's persistent two-way messenger (what
  the approved contract targets) and a simpler one-shot lead-capture form (what many live HighLevel sites
  actually run). UCRM's blueprint must build the former — the honest, persistent, two-way version — since
  that's what the contract and unified-inbox model require; ending at a "Thank You" dead end would contradict
  the approved "durable messenger, not a lead form" product promise.
- Header pattern worth adopting: identity + one reassurance line (Intercom's "the team can also help",
  HighLevel's branding) rather than a bare title.
- AI/human identity, when shown, must be as explicit as Intercom's "Fin • AI Agent • Just now" — never
  ambiguous about who's replying, consistent with the contract's disclosure requirement.
- Real-time inline field validation (HighLevel's "Invalid value") beats a blocking alert — same input pattern
  UCRM already uses elsewhere.
- Consent copy sits directly under the form fields, not hidden in a separate step — matches the contract's
  "privacy link beside the form, consent explicit" requirement.
