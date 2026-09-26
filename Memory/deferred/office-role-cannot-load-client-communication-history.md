# The office role cannot load a client's communication history

- **Priority:** P2
- **Why postponed:** Found while checking role access for Google review Part 5B. Signed in as the office test
  login on Raad LTD, the client page's Communication tab shows "Something went wrong — Communication history
  could not be loaded." The same tab works for the owner. Not investigated further; it was outside the
  review work.
- **Reactivate when:** Role permissions for Communications are next touched, or a non-owner reports an empty
  or failing client Communication tab.
- **Constraint:** Check `/api/communications/email-history` and what permission it requires against what the
  office role actually holds — the failure may be a missing grant rather than a bug in the tab.
