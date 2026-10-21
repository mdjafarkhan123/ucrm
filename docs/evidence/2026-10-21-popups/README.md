# Batches 43 and 44 — Merge clients and Collect payment pop-ups, proof (2026-10-21)

Live app from branch `claude/batch43-44-popups`, 1440 wide, contractor owner login, light and dark. Compared
with Pencil `XddjD` (Merge clients, ready `qIn0z`, states `j16og3`, dark `cQwiA`) and `b5ZAe` (Collect payment,
ready `bqUvT`, states `nfO7N`, dark `B90qrN`).

| Shot | What it shows |
|---|---|
| `merge-empty-light.png` | Both boxes empty with the search hint; Merge clients off; no footer warning |
| `merge-same-light.png`, `merge-same-dark.png` | Same client twice: duplicate box red edge, "Choose a different client." |
| `merge-checking-light.png` | Live "Checking what … has…" line and five tile bones |
| `merge-ready-light.png`, `merge-ready-dark.png` | Real preview: ten record-coloured move tiles, two rules with icons, warning notice strip, red "… will be deleted" line in the footer |
| `pay-ready-light.png`, `pay-ready-dark.png` | Invoice #33: big amount box, method and date side by side, Reference with `#`, Details, blue panel with the ticked bill card and the applied bar |
| `pay-over-light.png`, `pay-over-dark.png` | Bill amount above what it owes: card and its box red, live error with icon under the words |
| `pay-missing-light.png` | Amount 0: field error "Enter how much was paid." |

Not pressed: Merge clients (deletes a real client) and Collect payment (records money); their save logic is
unchanged. Payment date keeps the live date field (segments and weekday) rather than the drawing's text box.
Fix payment shares the component (only the title line and buttons differ); not screenshotted.
