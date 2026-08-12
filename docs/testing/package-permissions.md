# Package and employee-access verification

## Automated checks

Run the application checks and deterministic access tests from the repository root:

```text
npm run check
npm run test:unit -- --run
npm run build
git diff --check
```

The database regression suite uses the project’s pgTAP command. Docker and the local Supabase stack must be running first:

```text
npx supabase start
npx supabase test db --local supabase/tests/database/package_access.sql
```

The test is intentionally transactional and rolls back its fixtures. It verifies package defaults, tenant-scoped overrides, employee visibility, audit triggers, and last-administrator protection.

## Browser verification

The repository currently has no production package-management or team-management screens, so there is no honest Playwright business flow for these APIs yet. Once those screens exist, the critical browser flow should cover:

1. Sign in as a contractor owner/admin and open team management.
2. Change an employee role and confirm the effective permissions update.
3. Grant, deny, and inherit an employee permission.
4. Confirm a disabled package feature still blocks a granted employee permission.
5. Confirm a non-admin cannot access team management.
6. Confirm the last owner/admin cannot be demoted.
7. In `/jafar`, change a package and verify the effective package and audit history.

Until then, verify the API responses with an authenticated browser session or API client, and run the pgTAP suite for database enforcement. Do not treat the existing demo Playwright page as coverage for package or employee access behavior.
