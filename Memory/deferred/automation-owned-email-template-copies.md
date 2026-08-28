# Automation-owned Email Template copies

Deferred because the Automation system itself doesn't exist yet — contractor-settings Part 6A is only an
approved architecture blueprint, no production automation entity to own a copy or trigger a sync.

Reactivates when: an Automation step/action exists in production (contractor-settings Part 6B+ ships).

Known constraint from docs/contractor-email-contract.md § "Templates, snippets, and branding": sync must be
off by default and require an impact preview before applying. Design the automation-step-to-template link so
it can point at either a platform template or an org-owned copy (see `platform_email_templates.version` and
the org-side copy-on-write table, once built) without needing a schema change to the automation side.
