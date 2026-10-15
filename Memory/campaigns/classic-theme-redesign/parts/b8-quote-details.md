# B8 — Quote details

**Stage:** Built and verified 2026-10-15 on branch `claude/classic-b8` (worktree `.worktrees/classic-b8`),
reservation `5420b8009b65`.

**Agreement:** Approved `classic.pen` frame `e5HXY` "Quote details · 1440": main = hero (status, "QUOTE #",
"Version N · sent date", four facts), Introduction, Products and services (B7), Client message and disclaimer;
rail = Profit, Deposit, Discount and tax, Automation, Photos and files, Notes. No behaviour change was needed,
so nothing was asked of Jafar beyond the approved frame.

**Built (Classic only; the old look is unchanged and shares the same editor snippets):**
- Header meta line and facts Created / Sent / Approved-or-Declined / Quote total; Approved is amber while
  waiting. Primary button carries its icon (mail, send or check).
- Introduction and "Client message and disclaimer" as RecordCards with per-row pencils. With no client
  message the card shows only the disclaimer and its pencil moves into the card heading.
- Photos and files moved to the rail (`look="record"`), Notes in a rail RecordCard (`look="record"`).
- New shared `work/ProfitFeatureCard`; `JobProfitCard` now uses it and `quotes/QuoteProfitCard` feeds it the
  version's cost/profit/margin (only for price + cost viewers).
- `QuoteDepositCard` and `QuoteAutomationCard` draw the classic.pen look when Classic is on.
- Sent quote: no pencils anywhere (existing `editable` rule); locked footer says "Locked because this quote
  was sent. Start a new version to change it." (second sentence only when a new version is allowed).

**Proof:** Playwright, Raad LTD owner, quotes #42 (awaiting), #33 (converted, intro + message), #45 (draft),
1440 and 1100, light and dark; compared with the `e5HXY` export. Live journey: draft #45 disclaimer pencil →
Unsaved badge + save bar → Save changes → stored, then restored to the original text. "Record deposit
received" opens its dialog on #42. Job #20 profit card unchanged. ESLint and Prettier clean on changed files.

**Known differences left on purpose:** Automation shows a loading bar until hovered (existing load-on-hover
rule); a draft still shows the existing "Add section" buttons, which the Pencil frame (a sent quote) does not
cover; a signed quote shows a Signature card the frame does not draw; Deposit's edit pencil sits beside its pill.
