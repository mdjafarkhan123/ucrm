# Redesign checklist — tier 5

Key, tick rule and coverage command: `list-index.md`.

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `(app)/marketing` | `marketing/CampaignsPanel`, `marketing/CustomerGroupsPanel`, `marketing/MarketingWarmupCard`, `marketing/TemplatesPanel` · pop-ups: "Delete this campaign?" 🔁C, "Cancel this campaign?" 🔁C, "Delete this customer group?" 🔁C · tabs ×1 · menus ×4 · loading, empty | ⬜ | ⬜ |
| `(app)/marketing/campaigns/[id=uuid]` | `marketing/CampaignRecipientsPanel`, `marketing/CampaignResultsPanel` · pop-ups: "Cancel this campaign?" 🔁C · tabs ×1 · loading, empty | ⬜ | ⬜ |
| `(app)/marketing/campaigns/[id=uuid]/edit` | loading, empty | ⬜ | ⬜ |
| `(app)/marketing/campaigns/new` |  | ⬜ | ⬜ |
| `(app)/reviews` | `reviews/ReviewFeedbackPanel` · pop-ups: "Cancel this review request?" 🔁C · tabs ×1 · menus ×2 · loading, empty, permission-limited | ⬜ | ⬜ |
| `(app)/reviews/settings` | `reviews/ReviewFeedbackFormEditor`, `reviews/ReviewMessageSetEditor`, `reviews/ReviewMessageStylesEditor`, `reviews/ReviewRequestPlanEditor`, `reviews/ReviewRoutingSection` · pop-ups: "Preview: your customer's feedback page" 🔁F, "Turn on review routing?" 🔁F · loading | ⬜ | ⬜ |
