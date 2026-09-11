# Jobber — Team Members, Roles, Ownership

Covers who works inside a Jobber account: adding and removing users, what deactivation does to their work,
account ownership, seats, and notifications. The permission _matrix_ itself lives in
`jobber-04-jobs-visits-scheduling.md` § 9.6 — read that for the custom permission options and preset ladder;
read this file for the member **lifecycle** around it.

Help center checked 2026-09-11. Jobber's GraphQL schema does not expose the permission or membership model,
so everything here is help-center sourced or explicitly `(unverified)`.

---

## 1. Adding a user

Invitations go out over **email and text message**. The invitee clicks **Accept the Invitation**, "then they
will be prompted to create a password and access Jobber under your account". A user is not active until they
accept and set a password. [[manage-team]]

---

## 2. Deactivate vs Delete

Jobber offers two distinct destructive actions, and steers firmly toward the first.

### Deactivate

- Reached from _Gear Icon > Manage Team >_ three-dot menu _> Deactivate_, or a red **Deactivate User** button
  on the user's profile.
- Deactivated users **stay visible** on Manage Team, sorted "at the end of your list of team members".
- **Frees a seat:** "Deactivating a user still opens up a spot for another team member, so deleting them isn't
  necessary if you want to add someone else as an active user."
- **Whether a deactivated user can still sign in is never stated** `(unverified)`. Neither the Manage Team nor
  the User Permissions article addresses login or existing sessions.

### Delete

- **Destroys history.** Verbatim: "If a user is deleted from Jobber, all records of that user's past activity
  is deleted as well. For example, you will no longer have access to their time entries or completed tasks on
  the calendar."
- Jobber's own guidance: "While deleting a user is possible, we recommend deactivating users instead."

[[manage-team]]

---

## 3. Assigned work when someone is deactivated — the important rule

**Jobber auto-unassigns and does not force a decision.** Verbatim:

> "If you choose to deactivate a user, they will be unassigned from all incomplete items assigned to them on
> the calendar (visits, tasks, requests, reminders)."

Reassignment is advisory only: "It is recommended to re-assign their schedule to another user before
deactivating them."

And it is one-way: "Reactivating a user will not re-assign the work that was unassigned by deactivating them,
they will need to be scheduled once more."

The four affected surfaces are **visits, tasks, requests, reminders**. [[manage-team]]

---

## 4. Account ownership

- One owner per account: "The account owner is the individual that owns the rights to the Jobber account and
  all associated information," and "No other user is able to edit the account owner's information or settings."
- **Transfer is request-and-accept.** Manage Team → select the user → "Make 'their name' the account owner".
  The recipient gets an email invitation and "will need to be logged in to accept the ownership role."
- **Recipient must already be an admin:** "Only admin users can have account ownership."
- Jobber warns to update the billing card promptly so the former owner cannot dispute charges.
- `(unverified)`: any password/2FA step for the outgoing owner, cancelling a pending transfer, and which role
  the former owner lands in.

[[account-ownership]]

---

## 5. Notifications for team events

- **Invite:** email + SMS to the invitee (§ 1).
- **Ownership transfer:** email to the recipient (§ 4).
- **Role change, deactivation, deletion:** no notification is documented anywhere `(unverified)`. The User
  Permissions article is silent on notifications entirely.
- The **Activity Feed**'s documented triggers are business events — timers, clients, requests, quotes, jobs,
  visits, invoices, deposits, payments, automatic payments, notes, cards, reviews. **Team-management events
  are absent from it.** [[activity-feed]]

---

## 6. Access / audit history — **Account Activity** (observed live 2026-09-11)

The help center documents no team audit log, but the product has one. Settings → **Team Organization →
Account Activity**, subtitle verbatim:

> "A record of permission, admin access, and team changes made in your account."

It is **account-level, not per-member** — one reverse-chronological feed. Each entry is a single line:
actor avatar + a plain-sentence headline, then a category label and timestamp underneath. Observed entry:

```
[avatar]  System added you to the account
          New user · Aug 31, 6:58 PM
```

So the shape is: **headline sentence / category · timestamp**, with no before-after diff column and no
filtering controls visible on an account this small.

## 6b. Active Login Sessions (observed live 2026-09-11)

**Jobber exposes per-member session management**, reached from an `Active login sessions` link on each row of
Manage Team → `/settings/manage_team/{id}/active_login_sessions`. This is the session-revocation surface the
help center never mentions.

Header copy, verbatim: "These devices are currently signed in to Jobber as {name}. **Sign out anything that
looks unfamiliar.**" It shows an **Active sessions** count, the member's email, a **Sign out all sessions**
action, and one row per device:

```
Other
Brave · Linux · Barisal, BD · IP 202.136.89.239  ·  in 15 sec.     [Sign out]
```

Per row: device/browser, OS, city + country, IP, relative last-seen time, and its own **Sign out** button.

This matters for our Part 3E: it confirms an admin-facing "end their sessions" capability is Jobber-precedented,
even though what _deactivation itself_ does to sessions is still undocumented and was not observable (below).

---

## 7. Seats and plans

| Plan    | Users                                            |
| ------- | ------------------------------------------------ |
| Core    | 1 (one extra seat addable; beyond that, upgrade) |
| Connect | up to 5                                          |
| Grow    | up to 10                                         |
| Plus    | up to 15                                         |

Extra seats can be bought in bulk in-account. [[core-plan]] [[connect-plan]] [[grow-plan]] [[plus-plan]]

**Observed live 2026-09-11:** seats are a first-class element of the Manage Team header, not a buried limit.
The header carries a `1/1 seat assigned` counter beside two buttons — **Invite New Member** and **Manage
Seats** — and the page subtitle reads "Manage your team members and seats in one place. Assign open seats,
update team access, or adjust your team size." The list groups under a heading that names the count:
**Assigned seats (1)**. What appears when the limit is actually reached remains `(unverified)` — the toured
account had a single seat in use.

## 7b. Manage Team list shape (observed live 2026-09-11)

Columns: **Name** (avatar + name) · **Role** · **Last Active** · **Status**, then a trailing action cell.

- **Last Active** is a real column, formatted `09/11/2026 at 12:34` — Jobber shows recency per member on the
  list itself.
- **Status** is a green `Active` pill.
- The trailing cell holds the `Active login sessions` link (§ 6b).
- Above the list: a **Search team members** box; below it: `Showing 1-1 of 1 items` with a 25/50/100 per-page
  selector.

**Not observable in the toured account:** the deactivate confirmation dialog, the member detail page, and the
delete flow — the account held only the Owner, who cannot be deactivated. Whether Jobber's deactivate
confirmation _names_ the incomplete work it is about to unassign (§ 3) therefore stays `(unverified)`; the
help center says only that the unassignment happens.

---

## 8. Re-inviting someone previously removed

`(unverified)` — Jobber documents only _reactivation of a deactivated_ user, and only to say prior work is not
restored (§ 3). Nothing covers inviting a deleted person's email again.

---

## § How WE compare

Decisions Jafar made 2026-09-11 after seeing the above. The settings blueprint
(`docs/contractor-settings-blueprint.md` § Confirmed Part 3 behavior) is the authoritative record; this is the
Jobber-side rationale.

| Area                     | Our behavior                                                                                                  | Relation to Jobber                                                                                                                                                                                                 |
| ------------------------ | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Work at deactivation     | Auto-unassign incomplete work; name it in the confirmation first; reassignment offered, never required        | **Match.** An earlier UCRM decision forced the choice; dropped for Jobber parity.                                                                                                                                  |
| Reactivation             | Never restores old assignments                                                                                | **Match** — verbatim the same rule.                                                                                                                                                                                |
| Permanent removal        | Keeps the person's name on completed work; removes login and personal contact details                         | **Deliberate divergence.** Jobber's delete erases the activity history; Jobber itself advises against it.                                                                                                          |
| Notifications            | Email the invitee and the ownership-transfer recipient; nothing for role/status changes                       | **Match.**                                                                                                                                                                                                         |
| Login after deactivation | Locked out immediately; revoked authority never survives in a stale page or session                           | **Ours** for deactivation itself (Jobber undocumented), but admin-driven session termination **is** Jobber-precedented — see § 6b.                                                                                 |
| Ownership transfer       | Request → recipient accepts; recipient must be an active Administrator; outgoing Owner confirms with password | **Match**, plus our password confirmation and cancel-before-acceptance.                                                                                                                                            |
| Access history           | Recorded on every command; reader surface still to be decided                                                 | **Jobber HAS one** — account-level Account Activity (§ 6). The help center omits it entirely; the live tour found it. The 2026-09-11 decision to drop our reader was taken on the docs alone and needs revisiting. |
| Seats                    | Platform-controlled limit; invite blocked at the limit with the count explained                               | Jobber gates by plan; its limit-time UX is undocumented, so our message is ours.                                                                                                                                   |

---

## Sources

- [[manage-team]] https://help.getjobber.com/hc/en-us/articles/115009568647-Manage-Team-How-to-Add-Manage-and-Deactivate-Team-Members
- [[account-ownership]] https://help.getjobber.com/hc/en-us/articles/115009736948-Account-Ownership
- [[user-permissions]] https://help.getjobber.com/hc/en-us/articles/115009568687-User-Permissions
- [[activity-feed]] https://help.getjobber.com/hc/en-us/articles/360037055533-Activity-Feed
- [[security-passwords]] https://help.getjobber.com/hc/en-us/articles/115009378607-Security-Passwords
- [[core-plan]] https://help.getjobber.com/hc/en-us/articles/360048155913-The-Core-Plan
- [[connect-plan]] https://help.getjobber.com/hc/en-us/articles/12296620144919-The-Connect-Plan
- [[grow-plan]] https://help.getjobber.com/hc/en-us/articles/360050124513-The-Grow-Plan
- [[plus-plan]] https://help.getjobber.com/hc/en-us/articles/29668508840727-The-Plus-Plan
