# Team access, exposed endpoints and launch-blocking hydration audit

**Date:** 2026-09-10
**Scope:** Paid-launch trust campaign, Part 12. Evidence only; nothing was changed.

## A. Nine database functions still answer a stranger with just the public API key

`create_client`, `update_client`, `delete_property`, `create_note`, `manage_platform_package_version`,
`pricing_line_total_minor`, `set_updated_at`, `labor_cost_total_minor` and
`prevent_automation_recipe_version_mutation` are all published at `/rest/v1/rpc/...` to anyone holding the
publishable key (two more than a prior audit found on 2026-08-31). All nine are `security invoker`, so the
row-level security policy still refuses a signed-out caller — no data is exposed today — but a caller
shouldn't be able to reach the function at all. The customer-facing portal already uses its own token routes,
not these RPCs, so none is expected to need a signed-out caller.

A related, lower-risk version of the same mistake: 32 functions in the internal `private` schema (not just
the 11 found earlier) still hold `anon`/`public` execute grants. These are not actually reachable — the API
layer only exposes the `public` schema — so this is tidiness, not exposure.

**Smallest fix:** one migration that revokes `anon` execute from all nine `public` functions, plus a second
cleanup migration for the 32 `private` grants. No behavior change for any real user.

## B. The Pipeline menu item shows to people who shouldn't have Pipeline

`AppShell.svelte` hardcodes "Pipeline" into the menu for everyone; the page itself correctly refuses someone
without access, but they still see and click into a dead end. The underlying cause: the app shell never asks
"what can this person actually do" — it only knows their raw role, not their real permissions. This is a
one-off patch away from becoming a recurring problem: every future menu item needs the same real answer,
not a copy of this one fix.

**Smallest fix:** teach the app shell to ask that question once per page load (already exists as
`resolveOrganizationAccess`, just not wired to the shell) and hide menu items a person can't use, Pipeline
included.

## C. Money-touching actions have no spam/abuse limit

Every quote, invoice and payment action a team member can take (creating, editing, sending, collecting a
payment, refunding one) has **zero** limit on how many times it can be hit per minute. Public, signed-out
pages (a customer viewing a quote link, approving it, the "Get Started" signup) already have this protection.
The gap is entirely on the logged-in, money-moving side.

Why this matters for a paid pilot specifically: a stuck browser tab, a buggy retry, or someone probing your
system can hammer these endpoints with no brake, using up shared server capacity that other paying customers
depend on. The tool to fix it already exists and already works elsewhere in the app — it just needs to be
switched on for these routes too.

**Smallest fix:** turn on the existing rate-limit tool for every logged-in write in one place (the shared
"are you allowed to do this" check every route already goes through), instead of adding it route by route.

## D. A page can briefly flash under the wrong web address on a hard refresh

Caught once during earlier testing: a hard refresh occasionally shows the previous page's content for an
instant before settling on the new one (e.g. a settings screen flashing under the schedule page's address).

I tried to make this happen again on purpose — about a dozen hard refreshes across several pages — and
couldn't. I also checked how the page is built behind the scenes: each page is freshly generated from that
same person's own login, every single time, with nothing shared or cached between different people's
sessions. **This cannot show one person another person's private information.** At worst it is a person
briefly seeing their own screen flicker before it settles — cosmetic, not a security problem.

**Recommendation:** not launch-blocking. Worth a polish pass later, not before taking paying customers.

## E. Four pages spin forever instead of showing an error

When a page is told "no" (you don't have access, or that record doesn't exist), most pages correctly show
"Something went wrong." Four don't — they just keep the loading spinner running forever:

- Quotes list page
- A Request's detail page
- Settings → Quotes
- Settings → Taxes

This matters for a paid launch because it's the same situation a real customer or team member will hit
whenever a permission boundary works correctly (which is the whole point of this campaign) — instead of a
clear message, they get a page that looks broken and never recovers.

One of the four has a clear, fixable cause: the Quotes list page loads its data with a different tool
(built for "infinite scroll" lists) than every working page uses. The other three use the same tool as the
working pages and look identical in the code — the actual cause needs a live debugging session to catch,
not more reading.

**Recommendation:** worth fixing before launch — a customer or a real team member will hit this, not just an
edge case. The Quotes list fix is a known, bounded change. The other three need a short live-debugging
session first to find the real cause, then one shared fix applied to all pages that share the pattern
(so a fifth page doesn't surface the same bug later).

## What stays as-is

The earlier finding that any Field team member could read every request in the business is already fixed
(this campaign's Parts 1-5, live-verified). A broad sweep of all 315 API routes found no route that skips
authentication or team checks entirely — every category (customer portal links, internal background workers,
webhooks, your own Jafar admin tools, regular team routes) has a real, consistent check in place. This part
found no new "anyone can just walk in" hole.
