# Product manual writing guide

## Purpose

Use this guide when a major user-facing journey reaches its completion gate or when shipped behavior
already described in the product manual changes.

The product manual teaches nontechnical people how to understand and use UpliftContractor. It is not
a development specification, implementation record, release log, or list of planned features.

## When to write

Create or update a manual page when all of these are true:

1. A complete, useful user journey is available.
2. Its main behavior and language have been approved.
3. Its acceptance checks pass.
4. The journey has been checked through the real interface when browser verification is meaningful.
5. No known unfinished work prevents a person from following the documented journey.

A large product area may be documented in stable parts. For example, Platform Owner onboarding may
be documented before organization closure or provider controls are finished.

Update an existing page in the same work that changes its shipped behavior. Small visual changes
that do not change meaning, workflow, or available actions do not require a manual update.

## Sources of truth

Before writing, verify the behavior against:

1. the newest approved product document or contract;
2. the working interface and server behavior;
3. relevant tests and browser verification; and
4. the project glossary in `CONTEXT.md`.

The manual explains verified shipped behavior. It does not replace approved product contracts,
technical decisions, code, migrations, or tests. If these sources disagree, resolve the conflict
before updating the manual.

## How to write

Assume the reader is using this kind of software for the first time.

- Use plain, friendly English and short sentences.
- Explain an unfamiliar term before relying on it.
- Use the same product term consistently. Do not invent a second name for the same thing.
- Explain what the person sees, what they can do, and what happens next.
- Describe statuses as human situations, not database values.
- Use realistic scenarios when a rule, warning, or next step could be confusing.
- Explain why a blocked action is unsafe and what the person can do instead.
- Separate ordinary work from exceptional recovery.
- State when an action cannot be undone or affects another person.
- Link to a related guide instead of copying its full explanation.
- Keep sensitive internal details, credentials, private reasons, and security mechanisms out of the
  manual.

Use natural interface wording. Avoid developer language such as API, query, schema, migration,
table, payload, cache, RLS, or HTTP status unless the product visibly uses that term and the reader
needs it.

## Page structure

Use only the sections that help the reader. A typical guide follows this structure:

```markdown
# Product area

## What this area is for
## Important words
## The normal journey
## Statuses and what they mean
## Actions you can take
## When something needs attention
## Common scenarios
## What happens next
## Related guides
```

For every status, explain:

- what has already happened;
- whether someone needs to act;
- what action normally comes next; and
- what causes the status to change.

For every important action, explain:

- when to use it;
- what information or confirmation is required;
- what changes after it succeeds; and
- what the person should do if it fails.

## Scenario format

Use a short situation followed by the safe response:

```markdown
### Payment was reversed before setup

The application returns to Needs attention and account setup is blocked. Open the application,
review the payment history, and resolve the payment problem before trying to create the organization.
```

Choose scenarios from real edge cases in the approved behavior. Do not create fictional product
capabilities to make a scenario easier.

## Organization

- `README.md` is the main manual index.
- `platform-owner/` covers the private Platform Owner control room.
- `contractor/` covers the contractor workspace.
- `customer/` covers customer-facing pages and actions.
- Each file covers one product area or one closely connected journey.
- Split a file when readers would normally visit its sections for different jobs.

Audience index pages list only guides that contain usable, verified instructions. A planned filename
is not listed as an available guide until its page is ready.

## Completion check

Before calling a manual page current, confirm that:

- a nontechnical reader can identify where the journey begins;
- every visible status and important action in scope is explained;
- common failure and recovery situations are covered;
- wording matches the real interface;
- links point to existing manual pages;
- no unfinished behavior is presented as available; and
- the page contains no implementation details or sensitive information.
