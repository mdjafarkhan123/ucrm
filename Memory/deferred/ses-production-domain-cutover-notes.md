# SES production-domain cutover: capacity cap and rehearsal notes

Carried over from operational-email-ses (all parts done, campaign closed 2026-09-26). Not actionable until
Jafar's real domain goes live on SES.

**Capacity cap:** SES allows 10,000 verified identities per AWS region. Each organization uses about 3 (mail,
bounce.mail, reply alias), so roughly 3,300 organizations is the ceiling on this one account/region before
identities must be requested to be raised or sharded. Check with AWS before growth nears it -- this bounds any
future capacity claim beyond ~3,300 live organizations.

**Rehearsal notes for cutting Jafar's own real domain over to SES:** export the Cloudflare zone first, test
outside business hours, and check the Hostinger inbox still sends/receives before and after. Choose unoccupied
subdomain prefixes for the rehearsal -- `bounce.mail.upliftcontractor.com` already carries live SES MAIL FROM
records from earlier testing.

**Reactivation trigger:** before provisioning production SES capacity for real organizations at scale, or
before rehearsing/cutting over Jafar's own domain to SES.
