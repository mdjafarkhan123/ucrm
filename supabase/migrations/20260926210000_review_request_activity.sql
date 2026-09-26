-- Google review campaign Part 5B: review request activity on the client's and the job's history.
--
-- Product truth: docs/google-review-campaign-owner-brief.md (§ Reviews workspace and activity): "The same
-- request activity appears in the client history and completed-job history."
--
-- One trigger on review_requests records each milestone once, whichever path caused it (manual send, the
-- automatic ask, a reminder, the customer's own taps, a cancel), so no send/track/cancel function needs to
-- change. Each milestone becomes one row for the client and, when the request belongs to a job, one for the
-- job, in the shared activity_events feed those histories already read. A summary never carries the customer's
-- private words; it says only that they left feedback. Additive; rolling back is dropping the trigger and
-- function.

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
    summary_text := case
      when new.origin = 'automation' then 'A review request was sent automatically'
      else 'A review request was sent' end
      || case when new.channel = 'sms' then ' by text message.' else ' by email.' end;
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

revoke all on function private.log_review_request_activity() from public, anon, authenticated;

create trigger review_requests_activity_insert
  after insert on public.review_requests
  for each row execute function private.log_review_request_activity();

-- Several milestones can land in one update (a customer who opens the page and taps Google in the same
-- statement), so only the first matching one is recorded per update; the customer's own taps arrive as
-- separate calls in practice.
create trigger review_requests_activity_update
  after update of first_opened_at, continued_to_google_at, feedback_submitted_at, cancelled_at
  on public.review_requests
  for each row execute function private.log_review_request_activity();
