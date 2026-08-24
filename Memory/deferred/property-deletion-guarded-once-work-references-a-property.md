# Property deletion guarded once work references a property

- **Priority:** P2


- **Campaign:** `clients-properties` Part 7, deferred out of scope on 2026-08-17.
- **Reason:** There are no requests, quotes, jobs or invoices yet, so there is nothing to guard against.
  Removing a property today can only orphan attachments and notes, which already cascade correctly.
- **What is missing:** `public.delete_property` removes a property with no check for work that points at it,
  and `propertySchema` in `src/lib/server/validation/foundation.schema.ts` has no spec file — starting the
  validation-spec pattern is Jafar's call, not the agent's.
- **Reactivation trigger:** The first work object that references `properties.id` ships (Requests is next).
- **Prerequisites:** A work table with a property foreign key exists. Decide with Jafar what a blocked delete
  says to the user and whether the property becomes read-only instead.
- **Checkpoint:** `public.delete_property`, `src/lib/server/validation/foundation.schema.ts`.

