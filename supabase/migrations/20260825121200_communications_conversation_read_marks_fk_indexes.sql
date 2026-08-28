-- Cover both foreign keys on communication_conversation_read_marks so a client or user delete does not
-- force a sequential scan of this table to find rows to cascade. Neither is a leading-column match on the
-- (organization_id, user_id, client_id) primary key.
create index communication_conversation_read_marks_client_idx
  on public.communication_conversation_read_marks (organization_id, client_id);
create index communication_conversation_read_marks_user_idx
  on public.communication_conversation_read_marks (user_id);
