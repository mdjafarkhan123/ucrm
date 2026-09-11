# Request access isolation audit

**Date:** 2026-09-10  
**Scope:** Paid-launch trust campaign, Part 1. Evidence only; no access rule was changed.

## Proven failure

A read-only live-database check impersonated an active Field member with no assigned assessments. The authenticated
RLS path returned all 11 Requests in that organization; all 11 were unassigned to that member. No customer text or
identity was returned by the check.

The repeatable signal is an authenticated `select` on `public.requests` for a Field member, split into assigned and
unassigned counts. It is red while `unassigned_visible_requests` is greater than zero and must be zero after the
correction.

## Cause and affected boundaries

- `public.requests` SELECT and UPDATE policies accept any organization member.
- `public.request_pricing_lines` SELECT accepts any organization member independently of the parent Request.
- `private.can_view_request` also accepts any organization member. Request notes, tags and attachments inherit it;
  their manage rule currently adds no Request-specific edit check.
- The Request list, Request detail, CRM overview and Conversation client-context APIs read Requests directly and
  rely on those broad database rules.
- Request detail also returns client contact details, Property access notes and assessment instructions.
- Request pricing returns protected cost as well as price, making the child-table policy a separate privacy hole.
- Schedule assessment rows are already narrowed for assigned-scope Field members. Their embedded Request context
  will safely inherit a corrected Request policy.

There is no Request access regression suite. Existing Request route tests cover pricing and Quote conversion, not
role or assignment isolation.

## Smallest production pattern

Use one scoped `requests.view` permission as the source of truth: Owner, Administrator, Office, Sales and Finance
keep all-scope access; Field receives assigned scope. A Request is assigned when its assessment is assigned to the
member. Enforce that rule in database RLS and `private.can_view_request`, then make Request pricing and linked
records inherit the parent decision. API checks improve error clarity, while RLS remains the final authority.

Implement and verify this in separate sessions: permission seam, parent/child RLS, linked/API boundaries, then
browser journeys. Write the database regression test before each correction.

