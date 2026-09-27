-- Review request history no longer says "sent" when the request is only queued.
--
-- The insert milestone was written as "A review request was sent by email." but at insert time the message
-- is only queued: a request scheduled for tomorrow morning has not gone out, and even an immediate one can
-- still fail delivery. The scheduled time lives on the outbox row written after this insert, so the trigger
-- cannot tell the two apart; the summary is reworded to be true for both. Rows already written keep their
-- wording. Only the function body changes; both triggers keep pointing at it.

create or replace function private.log_review_request_activity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  milestone text;
  summary_text text;
  who uuid := (select auth.uid());
begin
  if tg_op = 'INSERT' then
    milestone := 'review.requested';
    summary_text := case when new.origin = 'automation' then 'An automatic review request' else 'A review request' end
      || case when new.channel = 'sms' then ' by text message' else ' by email' end
      || ' was queued to go out.';
    who := coalesce(new.created_by, who);
  elsif old.cancelled_at is null and new.cancelled_at is not null then
    milestone := 'review.cancelled';
    summary_text := 'The review request was cancelled.';
    who := coalesce(new.cancelled_by, who);
  elsif old.feedback_submitted_at is null and new.feedback_submitted_at is not null then
    milestone := 'review.feedback_submitted';
    summary_text := 'The customer left private feedback'
      || case when new.rating is not null then ' (' || new.rating || case when new.rating = 1 then ' star).' else ' stars).' end
         else '.' end;
    who := null;
  elsif old.continued_to_google_at is null and new.continued_to_google_at is not null then
    milestone := 'review.continued_to_google';
    summary_text := 'The customer continued to Google to leave a review.';
    who := null;
  elsif old.first_opened_at is null and new.first_opened_at is not null then
    milestone := 'review.opened';
    summary_text := 'The customer opened the review page.';
    who := null;
  else
    return new;
  end if;

  insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata)
  values (new.organization_id, 'client', new.client_id, milestone, summary_text, who,
          jsonb_build_object('review_request_id', new.id));
  if new.job_id is not null then
    insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata)
    values (new.organization_id, 'job', new.job_id, milestone, summary_text, who,
            jsonb_build_object('review_request_id', new.id));
  end if;
  return new;
end;
$$;
