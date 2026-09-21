-- A Paid invoice must be backed by recorded money. Keep the historical
-- marked_received_at/marked_received_by fields and reopen_invoice command so existing
-- status-only closures remain visible and correctable, but remove the command that can
-- create another one.
drop function if exists public.mark_invoice_received(uuid, uuid, text, text, text);

notify pgrst, 'reload schema';
