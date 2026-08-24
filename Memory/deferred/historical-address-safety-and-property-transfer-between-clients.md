# Historical address safety and property transfer between clients

- **Priority:** P2


- **Campaign:** `clients-properties` Part 7, deferred out of scope on 2026-08-17.
- **Reason:** Editing a property address today silently rewrites history everywhere it is shown. That only
  matters once a past quote, job or invoice carries an address that must stay as it was on that day.
- **What is missing:** No address snapshot onto work records, and no way to move a property from one client
  to another with its history intact.
- **Reactivation trigger:** The first work object stores or prints a property address.
- **Prerequisites:** Agree with Jafar whether work snapshots the address at creation or at completion.
- **Checkpoint:** `docs/client-property-behavior-contract.md`, `20260817150000_property_add_and_remove.sql`.

