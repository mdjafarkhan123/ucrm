-- Open inboxes refresh when a send is first recorded, not only when its status later changes. A reply typed in
-- the Page's own Facebook inbox arrives as an already-sent row (record_communication_messenger_echo), so the
-- update-only trigger never fired and staff saw it only after a reload. Teammates' sends from UCRM now also
-- appear live in every other open inbox. Same ids-only broadcast and function as the update trigger.
-- Automated sends are left out: a bulk send inserts thousands of rows at once, and each one already broadcasts
-- moments later when the worker changes its status.

create trigger communication_delivery_intents_publish_new_activity
after insert on public.communication_delivery_intents
for each row
when (new.send_kind <> 'automated')
execute function private.publish_communication_delivery_activity();
