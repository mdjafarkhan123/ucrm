# Part 1 — Welcome notice

**Campaign:** pilot-test · **Plan:** none — test campaign; agreed behavior (roadmap line 1): the pretend
customer receives exactly one welcome notice, never a second
**Code:** none — this part only sends a notice
**Done when:** the inbox holds exactly one welcome notice from this campaign

## Steps

- [x] Check the inbox before sending — it was empty, so nothing had been sent
- [ ] Send the welcome notice with ID `pilot-test-part1-welcome` (see Outside actions)
- [ ] Confirm the inbox holds exactly one line with that ID, then finish the part

## Next

Send the welcome notice — but first run its check below, because a session may have stopped just after
sending. Only if the check finds 0 lines, append exactly one line, `NOTICE pilot-test-part1-welcome welcome`,
to the inbox file. Then run the check again: it must find exactly 1.

## Outside actions

- Welcome notice `pilot-test-part1-welcome` to the pretend customer — check: in
  `/tmp/claude-1000/-home-jafar-khan-Documents-Projects-Ucrm/ede9fd5d-e41d-45c6-a3db-0b1b35d00a9e/scratchpad/pilot/test-outbox.log`,
  count the lines that read exactly `NOTICE pilot-test-part1-welcome welcome`: 0 = not sent, 1 = sent,
  2 or more = the customer got a duplicate. If the file is missing or holds 2 or more, stop and ask Jafar.
  The inbox has no duplicate protection of its own, so this check is the only guard — pending
