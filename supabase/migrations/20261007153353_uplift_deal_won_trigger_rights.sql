-- B5 fix: the deferred link trigger fires at commit, after the owner function that linked the Application has
-- returned, so it ran as the caller and was refused the private schema. The B5 triggers run with the owner's
-- rights, like the other cross-table triggers (search_path is already pinned).
alter function private.payment_confirmed_wins_deal() security definer;
alter function private.application_keeps_won_link() security definer;
alter function private.application_link_wins_deal() security definer;
