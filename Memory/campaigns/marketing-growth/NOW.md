# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M5 all complete. M5's completion gate passed 2026-09-23 on a real launched Raad LTD campaign
(`bbea9712-bdd8-4720-9d56-b02d041db413`): CTA attribution and open/click tracking both proven end to end in
the real UI (Results tab showed 100% click rate, credited Request). See ROADMAP.md's M5 row for what that
gate found and fixed (a real SES account-level VDM gap) and what it deferred (reply-tracking re-verification,
until the `operational-email-ses` migration replaces Brevo as the receiving path).

## Exact next action

M6a and M6b are both closed (M6b's live browser proof completed 2026-09-23 -- see ROADMAP.md's M6 row for
the concurrent-launch race result and cleanup confirmation).

Next: pick the next M6 slice with Jafar -- M6c load test + DLQ alert (needs sign-off on the alert), M6d
branded click-tracking domain (needs sign-off, blocks real-customer send), M6e replies (blocked on
`operational-email-ses`), or check 15 doc review (trivial, anytime). Read ROADMAP.md's M6 row and
`docs/marketing-first-release-plan.md` §3 M6 / blueprint §19 before starting the next one.

Also flag to Jafar (found in passing, not caused by this session): `npx supabase test db` has many
pre-existing "Bad plan" failures outside marketing's scope (`contractor_settings_*`, most `communications_*`,
`files_*`, `quotes_pricing_foundation`, and marketing's own `marketing_reputation_pause.sql`) -- looks like a
wider regression worth someone's attention.

## Session-setup notes (2026-09-23)

- `.claude/settings.local.json` has `"permissions": {"disableAutoMode": "disable"}` plus an allowlist for
  routine `mcp__claude-in-chrome__*` calls and `mcp__supabase__execute_sql` -- routine browser/DB steps don't
  prompt. **Hard limit that no setting changes:** entering a password into any field stays prohibited for the
  agent regardless of permission config.
- SES is out of sandbox and VDM engagement tracking is on account-wide -- both promoted to
  `docs/marketing-first-release-plan.md` §2.

## Blockers / open findings (raise with Jafar)

- Both marketing wake cron jobs fail every minute (Vault target URLs unset). Harmless; noisy.
- DLQ alert, warmup-cap starvation, and branded click-tracking domain are M6 gates.
- M9 SMS marketing blocked on Communications A2. Raad LTD Marketing override + allowance expire 2026-09-24.
- Blueprint §12 Results Q4 ("which campaign, group, or service appears strongest") reads as a cross-campaign
  insight, not a single-campaign fact -- scoped OUT of M5c's Results tab and left for the list page's own
  insight cards, not yet built. Flag to Jafar if he expects it here instead.
- Pre-existing, unrelated bug spotted while verifying M5: the OLD test campaign "Launch test - full delivery"
  (`cce6af97-...`) fails to open at `/marketing/campaigns/{id}` -- ErrorState, overview fetch never fires. Not
  diagnosed; low priority (isolated to that stale row, new campaigns load fine).

## Pointers

`docs/marketing-first-release-plan.md` §3; `docs/marketing-product-blueprint.md` §12-13. Resume:
`continue marketing growth`.
