-- Jafar business management B3 fix: logging an outbound contact failed with "permission denied for function
-- website_host". The first-contact trigger ran as the inserting role (service_role); clearing the next action
-- updates the Lead row, which recomputes the stored `website_host` column through private.website_host --
-- a helper only the owner may run. The trigger now runs as its owner, like the other Lead functions.

alter function private.platform_business_history_first_contact_done() security definer;
