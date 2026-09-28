# Delete client, exactly like Jobber

**Why it waits:** Jafar decided 2026-09-29 but said "not now". The Delete button on the Clients list is still
greyed out.
**Brings it back:** Jafar asks for it.
**Known constraints:** Jafar chose Jobber's behavior (help.getjobber.com/en/articles/client-basics): Delete
permanently removes the client and all their work — requests, quotes, jobs, invoices and payments — after a
prompt listing what goes; no undo; bulk delete from the list's tick boxes too (skip and list any refused).
Added safety: a card payment still processing blocks it, and only `customers.delete` (owner, admin). Build on
`delete_property` (`20260929140000`) and `merge_clients` (`20260929170000`); the history triggers that block
an organization purge (`organization-purge-fails-on-history-triggers.md`) will block this too. The client
contract still says "Recently Deleted for 30 days" and needs updating to Jafar's choice.
