-- Explicitly remove PostgreSQL's default PUBLIC execute privilege. The foundation command checks
-- the caller internally, but anonymous callers should never reach it at all.
revoke execute on function public.enqueue_communication_email(uuid, uuid, uuid, text, text, text, text, text)
  from public, anon;
grant execute on function public.enqueue_communication_email(uuid, uuid, uuid, text, text, text, text, text)
  to authenticated;
