# Schedule's Employee lists show no names

**Why it waits:** Found 2026-10-18 while checking the switched-on buttons (`parts/c1e-buttons-everywhere.md` in
contractor-design-concept); Jafar asked to log it at emergency priority rather than fix it inside the button work.
**Brings it back:** The next free session; Jafar marked it emergency.
**Known constraints:** Seen on Raad LTD's Schedule (owner login, local app): the Employee lists in the Filters
panel ("Select an option") and in the Map's "Whose route?" box (only "Choose an employee…") are empty, so Show
route can never be pressed. `/api/team/assignable` in the same browser returned five members. Both lists build
from `teamQuery` in `src/routes/(app)/schedule/+page.svelte`. Not yet checked on main or with other logins.
