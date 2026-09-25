# Marketing drain tail trickles and SES event handling falls behind

Found by the M6c load test (520-recipient Raad LTD campaign, 2026-09-23); not fixed.

1. `runBoundedDrain` stops the whole wake when any slot sees idle, and the PL/pgSQL FOR-loop prefetch locks up to
   ~10 candidate rows per claim, so a queue's last <10 rows go out 1-3 per wake. Operational email's drain shares it.
2. The SES events worker handles at most 50 messages per wake (~21s). There are about 2 events per send, so at a
   once-a-minute cadence events fall ~2x behind sends and Results lag grows with campaign size.

Deferred because the 520 burst completed with no operational-email impact. Reactivate when
`operational-email-ses` Part 6 re-runs the shared-SES load check, at the production scheduler decision, or when
Results lag or slow tails are reported.
