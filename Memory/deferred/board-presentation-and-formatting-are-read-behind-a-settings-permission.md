# Board presentation and formatting are read behind a settings permission

- **Priority:** P2
- **Campaign:** `sales-pipeline` — found during Part 5C-iii's API performance review, 2026-08-24.

## What is wrong

`/api/pipeline/summary` reads two things straight off `organization_settings` through PostgREST, as the
signed-in member:

- `pipelinePresentation` (`src/lib/server/pipeline/presentation.ts`) — the five-vs-seven column preference.
- `organizationFormatting` (`src/lib/server/requests/timezone.ts`) — timezone, currency, locale. Pre-existing.

That table's select policy is `private.has_permission(organization_id, 'settings.business.view')`. A member
who can see the Pipeline but has had `settings.business.view` denied by a per-member override reads **no
row**, and both helpers answer with their defaults rather than failing. The board then silently shows the
collapsed five columns while their teammates see seven, and money and dates fall back to UTC/USD.

Every seeded role currently grants `settings.business.view` (checked 2026-08-24 against `role_permissions`:
owner, admin, office, sales, field, finance all have it), so only an explicit deny override reaches this.

## Reactivation trigger

Someone reports a board or a currency that looks different for one teammate, or per-member permission
overrides start being used in a real organization.

## Likely approach

Serve both values through a security-definer read gated on `pipeline.view` instead of a direct table select
— the same shape `pipeline_board_page` and `pipeline_stage_counts` already use. That is a migration, so it
should be batched with whatever else needs one rather than run on its own.
