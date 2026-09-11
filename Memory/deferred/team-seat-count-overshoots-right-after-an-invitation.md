# Team seat count overshoots right after an invitation is sent

Observed 2026-09-11 on Raad LTD: the Team page read `5 of 50 seats used`, an invitation was sent, and the
banner jumped straight to `8 of 50` while only one seat had been taken. A reload showed the correct `6`, and
`private.employee_seats_used` returned 6 throughout, so the database was never wrong -- only the number on
screen, between the send and the next fetch.

Deferred because it self-corrects on reload and misleads nobody into a bad action. Reactivate when seat limits
become enforceable on a paid plan, or when the Team page's cache invalidation is touched for any other reason.

Constraint already known: seats are `organization_members` in `pending`/`active` plus invitations in
`reserving` only -- an `invited` row is already counted through its pending membership, so any optimistic
client-side bump must not add a seat for both.
