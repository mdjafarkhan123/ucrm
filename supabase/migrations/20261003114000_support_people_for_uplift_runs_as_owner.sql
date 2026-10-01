-- Client onboarding D3 follow-up: Uplift's people functions reach the shared private helpers.
-- public.support_thread_people_for_uplift and public.set_support_thread_participant_by_uplift ran as the
-- caller, the service role, which has no access to the private schema, so the /jafar People panel failed.
-- They now run as their owner, like the member versions. Execution stays granted to the service role only.
alter function public.support_thread_people_for_uplift(uuid) security definer;
alter function public.set_support_thread_participant_by_uplift(uuid, uuid, boolean) security definer;
