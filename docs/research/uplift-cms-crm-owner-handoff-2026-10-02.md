# CRM-to-CMS owner handoff research

**Date:** 2026-10-02
**Scope:** Historical Part 4 research for a separate CRM and CMS. The product direction changed on 2026-10-02: the client-facing Website area is inside this CRM, uses its existing login, and lists all sites Uplift assigns. The separate OAuth handoff and separate CMS session proposed below are superseded, not approved requirements. The current plan is [`uplift-website-admin.md`](../plans/uplift-website-admin.md).

## Recommendation in one sentence

Make the CMS a confidential first-party OAuth/OIDC client of the CRM's existing Supabase Auth: the owner clicks **Edit website** in CRM, the browser carries only a short-lived single-use authorization code to the CMS, the CMS exchanges it server-to-server, then creates a host-only CMS session bound to one user, organization, and assigned website. The CMS must never have its own password screen and must re-check current CRM ownership and website assignment on every protected request.

Supabase's native OAuth 2.1/OIDC server is the best fit because it implements the established authorization-code-with-PKCE pattern instead of Uplift inventing an authentication protocol. It is currently **Public Beta**, so Part 4 should include a production-readiness gate; if that gate fails, retain the same user-visible flow but use a narrow internal, hashed, consume-once handoff code until the native server is approved.

## Observed CRM facts

These are facts from `/home/jafar-khan/Documents/Projects/Ucrm`, not proposed CMS behavior.

- The CRM uses `@supabase/ssr` with cookies. Its global SvelteKit hook creates one server client, calls `getClaims()` before route code so refresh cookies can be written, and derives the user ID from the verified `sub` claim. The repository records that this Supabase project uses ES256 signing. ([CRM hook](../../src/hooks.server.ts#L10-L38))
- Identity and organization authority are deliberately separate. After verifying identity, `getOrganizationContext()` queries `organization_members` for the user's **current active** membership and returns its organization and role; pending, deactivated, removed, missing, or failed lookups return no organization. ([organization helper](../../src/lib/server/auth/organization.ts#L9-L49))
- `organization_members` stores `organization_id`, `user_id`, `role`, `status`, and an `access_revision`. Allowed roles include `owner`; allowed statuses are `pending`, `active`, `deactivated`, and `removed`. ([CRM baseline](../../supabase/migrations/20260101000000_baseline_structure.sql#L461-L502))
- A user can belong to at most one organization (`UNIQUE (user_id)`), and the database enforces one owner for an organization. ([membership constraint](../../supabase/migrations/20260101000000_baseline_structure.sql#L58335-L58341), [owner index](../../supabase/migrations/20260101000000_baseline_structure.sql#L60509-L60517))
- Database authorization helpers also require current active membership and an active organization. The existing generic administrator helper allows `owner` **or** `admin`, so it is too broad for the CMS's owner-only rule; Part 4 needs an explicit active-owner check. ([CRM authorization helpers](../../supabase/migrations/20260101000000_baseline_structure.sql#L5816-L5850))
- Ownership transfer is atomic: accepting it demotes the old owner to `admin`, promotes the active administrator to `owner`, and increments both access revisions. Therefore an old but cryptographically valid login token is not proof of current CMS authority. ([ownership transfer](../../supabase/migrations/20260101000000_baseline_structure.sql#L11823-L11861))
- Contractor logout currently calls `supabase.auth.signOut()` without a scope. ([logout endpoint](../../src/routes/api/auth/session/+server.ts#L55-L61)) Supabase currently documents the default as global logout from every device, so this behavior must be made explicit before CMS integration.
- The inspected CRM schema has a business `website` text field, but no CMS site assignment identifier or CRM-to-CMS handoff model. ([organization settings](../../supabase/migrations/20260101000000_baseline_structure.sql#L6912-L6933)) Part 4 therefore needs authoritative organization-to-site assignments, not a URL supplied by the browser.

## Official facts and standards

### The handoff should use a code, not a portable login token

- IETF OAuth security guidance requires exact registered redirect matching, CSRF protection, and PKCE for public clients while recommending PKCE for confidential clients. It recommends authorization-code flow instead of placing access tokens in the browser redirect. ([OAuth Security BCP, RFC 9700](https://datatracker.ietf.org/doc/html/rfc9700#section-2.1))
- Supabase's OAuth 2.1 server implements authorization code with PKCE. Its codes are single-use, PKCE-bound, and valid for 10 minutes; `state` protects the browser transaction. ([Supabase OAuth flows](https://supabase.com/docs/guides/auth/oauth-server/oauth-flows))
- A browser-facing backend should keep OAuth tokens server-side and give the browser only an application session cookie. Current IETF browser-app guidance specifies a confidential backend-for-frontend and `Secure`, `HttpOnly`, narrowly scoped cookies with CSRF protection. ([OAuth for Browser-Based Applications, RFC 10017](https://datatracker.ietf.org/doc/rfc10017/#section-6.1))

### Tokens prove identity; live data proves present authority

- OpenID Connect requires validation of the signature, exact issuer, audience containing the CMS client ID, expiry, and `nonce` when sent. The stable person key is issuer plus subject, not email. ([OIDC Core ID-token validation](https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation), [claim stability](https://openid.net/specs/openid-connect-core-1_0.html#ClaimStability))
- Supabase OAuth access tokens carry `client_id` and `session_id`; their default access-token audience is `authenticated`. OIDC scopes control identity fields, **not** database access. Supabase says RLS must restrict what each OAuth client can reach. ([Supabase token security and RLS](https://supabase.com/docs/guides/auth/oauth-server/token-security))
- OAuth best current practice says tokens should have the minimum privilege and be audience-restricted to the intended resource server. ([RFC 9700, access-token privilege restriction](https://datatracker.ietf.org/doc/html/rfc9700#section-2.3))
- OWASP's current multi-tenant guidance says a client-supplied tenant ID is only a selector: bind tenant context to verified identity and current membership, validate it on every tenant-scoped request, scope lookups to tenant plus resource, and do not serve ordinary tenant traffic through an RLS-bypassing role. ([OWASP Multi-Tenant Security](https://cheatsheetseries.owasp.org/cheatsheets/Multi_Tenant_Security_Cheat_Sheet.html))

### Logout and revocation are not instantaneous unless Uplift checks them

- Supabase sessions consist of a short-lived access JWT and rotating refresh token. Default sessions otherwise last indefinitely, and access JWTs commonly last between 5 minutes and 1 hour. ([Supabase sessions](https://supabase.com/docs/guides/auth/sessions))
- Supabase documents that sign-out removes affected refresh sessions, but an already issued access JWT remains usable until expiry. For a strict cutoff, a sensitive service can check that the JWT's `session_id` still exists in `auth.sessions`. ([Supabase sessions: post-logout guarantee](https://supabase.com/docs/guides/auth/sessions#how-to-ensure-an-access-token-jwt-cannot-be-used-after-a-user-signs-out))
- Supabase JavaScript `signOut()` defaults to `global`; `{ scope: 'local' }` ends only the current session. ([Supabase `signOut`](https://supabase.com/docs/reference/javascript/auth-signout))

## V1 behavior to put in the Part 4 plan

### Entry and session flow

1. The CRM shows **Edit website** only to the organization's current active `owner` and only when that organization has an assigned CMS site.
2. Clicking it starts Supabase OAuth/OIDC authorization for one registered confidential CMS client. Because the owner initiated the action in a trusted first-party app, no extra consent page is needed; CRM still re-checks active owner and assignment before approval.
3. The callback URL contains only `code` and `state`. The CMS backend checks `state`, exchanges the code with PKCE and client authentication, validates the resulting token's signature/issuer/audience/expiry/nonce/client ID, then reads the authoritative CRM membership and site assignment.
4. The CMS creates an opaque, server-stored session. Its browser cookie is host-only (no shared `.uplift...` domain cookie), `Secure`, `HttpOnly`, and `SameSite`; OAuth tokens never enter JavaScript, URLs, logs, analytics, or CMS content storage.
5. Every CMS page/API request resolves the session to `user_id + organization_id + site_id`, then re-checks all four facts: membership is active, role is exactly `owner`, organization is active, and that site is still assigned to that organization. Publish and destructive actions do the same check inside their write boundary. Deny by default on lookup failure.
6. Every content row, media object, cache key, build job, preview, and release carries the verified `organization_id + site_id`. A URL or request body may select a site but can never authorize it. A cross-organization/site attempt returns one generic **Website unavailable** response and is security-logged without revealing whether the other site exists.

### The owner-visible edge cases

| Situation | Recommended behavior |
| --- | --- |
| First visit, no website assigned | Keep the owner in CRM. Show **Your website hasn't been connected yet** with the agreed setup/contact action. Do not open an empty CMS and do not auto-create a site from a query parameter. |
| Expired, reused, altered, or invalid handoff | CMS shows **This secure link has expired** and one **Return to CRM and try again** button. It never offers a CMS password form. Do not disclose which validation failed. |
| Owner role removed while CMS is open | The next server request fails immediately. The open editor also checks on window focus and a short heartbeat so an idle screen changes promptly to **Your access changed in CRM**. Stop autosave/publish, discard the CMS session, and return to CRM; never let a stale owner overwrite the new owner's work. |
| Website reassigned or organization no longer active | Treat it exactly like owner removal. Existing previews and live public pages are not an authorization source. |
| Cross-organization URL or guessed site ID | Show the same generic **Website unavailable** screen. Never switch tenants from a URL, and never reveal the other business's name or site status. |
| Owner selects **Back to CRM** | Normal navigation only; keep both sessions alive. |
| Owner selects **Sign out** | End this browser's CRM session and every CMS session derived from it, clear cached owner data, then land on the CRM login page. Other devices should stay signed in; offer **Sign out everywhere** separately if wanted. |
| CRM logout in another tab | Revoke linked CMS sessions. A CMS write is denied immediately; an idle tab notices on focus/heartbeat and shows **You signed out in CRM**. |

The current CRM's unscoped `signOut()` logs out every device, while the recommendation above is current-browser logout. Jafar must explicitly approve either behavior before implementation; the mature, less surprising default is current browser plus a separate **Sign out everywhere** action.

## Production gate and rejected shortcuts

Before relying on Supabase OAuth 2.1 Public Beta, verify it in staging against the deployed managed Supabase version and the planned self-hosted version: registered redirect matching, PKCE/state/nonce, token validation, owner-only approval, refresh rotation, local/global logout, grant/session revocation, ownership transfer during an open edit, and cross-tenant denial. The 2026-10-02 Supabase changelog was reviewed; implementation must also tolerate the current OAuth token endpoint's standards change from HTTP 201 to HTTP 200 by accepting successful 2xx responses. ([Supabase OAuth token status change](https://supabase.com/changelog/45468-breaking-change-oauth-token-endpoint-will-return-http-200-instead-of-201))

Do not:

- share the CRM's cookies across subdomains;
- pass a Supabase access/refresh token or a long-lived signed JWT in the URL;
- use email, a browser-provided organization ID, or an old `role` claim as authorization;
- let `admin` enter because an existing CRM helper groups owner and admin together;
- make CMS user requests through an unrestricted service-role client;
- rely on hiding the button in CRM—the CMS and data layer must enforce the same rule.

## Part 4 decision

Adopt the standards-based confidential OAuth/OIDC handoff with a separate narrow CMS session and live owner/site checks. Use Supabase's native OAuth 2.1 server only after its Public Beta passes the production gate. V1 should keep first-visit and recovery actions in CRM, revoke a former owner's CMS access on the next request, deny cross-organization access generically, and make logout mean **this browser** unless Jafar deliberately chooses the CRM's current all-devices behavior.
