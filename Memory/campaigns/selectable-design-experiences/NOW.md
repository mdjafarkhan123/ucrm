# Selectable design experiences — now

**Goal:** Preserve Classic and offer Botanical with different layouts over shared behaviour, downloading only the selected presentation and shared foundations.
**Plan:** `docs/selectable-design-experiences-behavior-contract.md`

**Progress:** Parts 1–4 are done. The real shell is `SharedAppShell` (permissions, account, search, notifications, dialogs once) over `presentations/ClassicFrame` and `BotanicalFrame`; Classic is the default everywhere, Botanical only with `DESIGN_SHELL_PREVIEW=botanical` on localhost. Proof re-run on final code 2026-10-11: `docs/research/selectable-real-shell-2026-10-11.md`.

**Next part:** Part 5, Botanical coverage — return to `uplift-design-refresh` inventories and focused page parts. Its first job includes the existing dashboard loading shift (`SetupCard.svelte` reserves no space; see the research note). Header additions (such as the Time clock running timer) go through `Topbar.svelte` snippets so both presentations receive them. Full type checking remains unverified because the command stalls. No production deployment is authorized.

**Blockers:** Botanical dark appearance and full coverage require focused approval before public selection; they do not block the private loading proof.
