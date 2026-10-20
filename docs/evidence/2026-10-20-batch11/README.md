# Shared batch 11 — 2026-10-20

Approved board K04pQm and design/files.md. FilePicker has a places column, file pick boxes, already-added veil, tray with unpick, and shared footer. Selected file records stay available across places/search/pages, fixing select mode returning only the final visible page. Attached lookup has its own cache shape. Library refusal sits in the file area so record-authorized upload remains available. Existing safety checks and attachment commands remain unchanged.

Photo labels use the grey icon/header, grey chips, inline rename, dashed empty card and trash confirmation. Photo details use the caption/labels card and Not saved strip. Inputs/actions freeze during saves. Dialog gained an optional subtitle, delegated to its existing header.

Focused ESLint and SCSS-preprocessed Svelte compiler passed on all four changed components, zero warnings. MCP autofixer: no issues; existing debounce and input/uploader references retained. No full-project checks.

Browser fixture: cross-section selection returns both records, tray unpick works, already-added is disabled, attachment refusal retains selection and succeeds on retry (two attempts), busy attach/caption save cannot repeat, label rename refreshes. Pickers, captions and labels at 1440/390 light/dark; no page/dialog overflow or page errors. Screenshots included; temporary fixture removed. No real storage upload in fixture.

Live owner app: existing client → Add files → Recent → choose/unpick/cancel. Files → existing photo → type draft caption → Cancel; Manage labels → Rename Before → Cancel. No real files, captions or labels changed. live-picker.png, live-caption.png and live-label-rename.png.
