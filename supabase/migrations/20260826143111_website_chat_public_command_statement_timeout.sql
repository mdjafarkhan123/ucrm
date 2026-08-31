-- Website Chat WC4.2: a hard ceiling on how long a public command may run.
--
-- Both commands are reachable by anyone browsing a contractor's website, and
-- `accept_website_chat_first_message` takes a `for update` lock on the organization's capacity bucket --
-- the serialization point every concurrent visitor of that organization passes through. Without a
-- ceiling, one pathological call holding that lock stalls every other visitor of the same organization
-- behind it, and the pool fills with waiters. WC0.2's performance-review gate set the ceiling at 5s.
--
-- A function-level SET is the only place this can live: PostgREST gives the API route no way to issue
-- `SET LOCAL` inside the same transaction as the RPC. The effect is identical -- Postgres applies the
-- value for the duration of the call and restores the previous value on exit, including on error.
--
-- IMPORTANT: a later `create or replace function` on either command that does not repeat the SET clause
-- silently drops this ceiling. Repeat it in any future revision of these two functions.

alter function public.accept_website_chat_first_message(
  uuid, text, text, text, text, text, text, text, boolean, text, jsonb
) set statement_timeout = '5000';

alter function public.post_website_chat_message(text, text, text, text)
  set statement_timeout = '5000';
