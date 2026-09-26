# Environment configuration

UCRM loads configuration from environment variables. Keep real values in a local `.env` file or
in the deployment platform's secret/configuration store. `.env` is ignored by Git; commit only
`.env.example` with placeholders.

## Required for the current application

The SvelteKit server validates these variables during server initialization:

| Variable | Scope | Purpose |
| --- | --- | --- |
| `PUBLIC_SUPABASE_URL` | Browser-safe | Supabase project URL |
| `PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Browser-safe | Supabase publishable client key |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-only | Privileged server-side Supabase operations |
| `SUPER_ADMIN_EMAIL` | Server-only | Platform-owner login email |
| `SUPER_ADMIN_PASSWORD_HASH` | Server-only | Bcrypt hash for the platform-owner password |
| `SESSION_SECRET` | Server-only | Signing secret for the owner session cookie |

Values beginning with `PUBLIC_` are available to browser code. Never put service-role keys,
passwords, password hashes, provider secrets, or signing secrets in public variables.

For local setup:

```sh
copy .env.example .env
```

Then replace the six required placeholders with values for the local Supabase project and owner
account. Do not use a plaintext password in `SUPER_ADMIN_PASSWORD_HASH`.

## Deployment configuration

Configure the six required variables in the hosting provider before starting the server. Set
public variables as ordinary deployment configuration and set server-only variables through the
provider's encrypted secret store. Redeploy after changing environment values; the current
validation runs during server initialization.

Keep separate values for local, preview, and production environments. In particular, do not use
the production service-role key, owner credentials, or session secret in local development.

## Reserved integration variables

The template also lists application URLs, Brevo, Cloudflare R2, Twilio/Messenger, worker/database,
appointment, and web-push variables found in the project environment inventory. They are reserved
for planned integrations and are not required by the current startup validator. They must be added
to centralized validation immediately before the feature that consumes each variable is enabled.

When adding a variable:

1. Add a placeholder to `.env.example`.
2. Classify it as browser-safe or server-only.
3. Validate it in the appropriate centralized configuration module.
4. Keep secrets in `$lib/server/*`, `hooks.server.ts`, or `+server.ts` only.
5. Document its deployment source without documenting its value.

## AWS customer-reply pipeline

Customer email replies arrive through fixed-name resources in the SES account and region (`us-east-1`), named
in `src/lib/server/communications/ses-env.ts`:

- receipt rule set `ucrm-ses-inbound-rules` holding ONE rule, `ucrm-inbound-all`, ensured by the Email card's
  Set up and Check: no recipients (every verified domain whose MX points at SES), spam/virus scanning on, and a
  single S3 action that stores the email under `inbound/` in `ucrm-ses-inbound-mime` and notifies the topic. SES
  allows only 200 rules per set, so never add per-organization rules;
- SNS topic `ucrm-ses-inbound`, which only `ses.amazonaws.com` from this account may publish to;
- SQS `ucrm-ses-inbound`, subscribed to the topic, the durable copy (redrive to `ucrm-ses-inbound-dlq` after 5
  receives), drained by `/api/internal/communications/ses-inbound-worker` every minute from pg_cron;
- an HTTPS subscription from the topic to `<PUBLIC_APP_URL>/api/webhooks/ses-inbound`, which verifies the SNS
  signature and starts the same drain at once, so a reply shows within seconds instead of up to a minute.

Each deployed environment needs its own HTTPS subscription, created once:

```bash
aws sns subscribe --region us-east-1 --topic-arn arn:aws:sns:us-east-1:<account>:ucrm-ses-inbound \
  --protocol https --notification-endpoint <PUBLIC_APP_URL>/api/webhooks/ses-inbound
```

The endpoint confirms the subscription itself. Remove an environment's subscription when that environment is
retired. The queue is shared by every environment pointed at this account, so only one environment should
drain it at a time.

## Troubleshooting

If startup fails with `Invalid public environment configuration` or `Invalid server environment
configuration`, check the named variable in the active environment. The error intentionally names
variables only and never prints their values.
