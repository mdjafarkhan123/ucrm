-- Adds the four contractor-facing closure notices (closure started, 14-day
-- reminder, 3-day reminder, closure completed) to the existing message
-- template editor from 20260812104126_platform_message_templates, seeded
-- with real copy and already published so the closure cron (which skips a
-- notice it cannot find published) works end-to-end without Jafar having to
-- author these first. Jafar can still edit and republish them like any
-- other template.

alter table public.platform_message_templates
  drop constraint platform_message_templates_template_key_check;

alter table public.platform_message_templates
  add constraint platform_message_templates_template_key_check check (
    template_key in (
      'received_page', 'application_receipt', 'password_setup', 'account_created_contact',
      'organization_closure_started', 'organization_closure_fourteen_day_reminder',
      'organization_closure_three_day_reminder', 'organization_closure_completed'
    )
  );

insert into public.platform_message_templates (
  template_key, subject_draft, body_draft, subject_published, body_published,
  published_version, published_at, published_by_owner_email
) values
  (
    'organization_closure_started',
    'Your {{business_name}} account is closing',
    '<p>Your UpliftContractor account for <strong>{{business_name}}</strong> is now closing.</p><p>Your team''s access has been turned off. All of your data is still safe and nothing is deleted yet.</p><p>If this was a mistake or you''d like to keep your account, contact us right away and we can restore it within the next 30 days. After that, your account and all of its data will be permanently deleted.</p>',
    'Your {{business_name}} account is closing',
    '<p>Your UpliftContractor account for <strong>{{business_name}}</strong> is now closing.</p><p>Your team''s access has been turned off. All of your data is still safe and nothing is deleted yet.</p><p>If this was a mistake or you''d like to keep your account, contact us right away and we can restore it within the next 30 days. After that, your account and all of its data will be permanently deleted.</p>',
    1, now(), 'system'
  ),
  (
    'organization_closure_fourteen_day_reminder',
    '14 days left to restore your {{business_name}} account',
    '<p>This is a reminder that your UpliftContractor account for <strong>{{business_name}}</strong> is closing.</p><p>You have until <strong>{{closure_deadline_at}}</strong> to contact us and restore your account. After that date, your account and all of its data will be permanently deleted and cannot be recovered.</p>',
    '14 days left to restore your {{business_name}} account',
    '<p>This is a reminder that your UpliftContractor account for <strong>{{business_name}}</strong> is closing.</p><p>You have until <strong>{{closure_deadline_at}}</strong> to contact us and restore your account. After that date, your account and all of its data will be permanently deleted and cannot be recovered.</p>',
    1, now(), 'system'
  ),
  (
    'organization_closure_three_day_reminder',
    '3 days left to restore your {{business_name}} account',
    '<p>Your UpliftContractor account for <strong>{{business_name}}</strong> will be permanently deleted on <strong>{{closure_deadline_at}}</strong> unless you contact us before then.</p><p>Once your account is deleted, none of your data can be recovered.</p>',
    '3 days left to restore your {{business_name}} account',
    '<p>Your UpliftContractor account for <strong>{{business_name}}</strong> will be permanently deleted on <strong>{{closure_deadline_at}}</strong> unless you contact us before then.</p><p>Once your account is deleted, none of your data can be recovered.</p>',
    1, now(), 'system'
  ),
  (
    'organization_closure_completed',
    'Your {{business_name}} account has been deleted',
    '<p>Your UpliftContractor account for <strong>{{business_name}}</strong> and all of its data have now been permanently deleted.</p><p>If you''d like to use UpliftContractor again in the future, you''re welcome to sign up as a new account.</p>',
    'Your {{business_name}} account has been deleted',
    '<p>Your UpliftContractor account for <strong>{{business_name}}</strong> and all of its data have now been permanently deleted.</p><p>If you''d like to use UpliftContractor again in the future, you''re welcome to sign up as a new account.</p>',
    1, now(), 'system'
  );

insert into public.platform_message_template_versions (
  template_key, version, subject, body, published_by_owner_email
)
select template_key, published_version, subject_published, body_published, published_by_owner_email
from public.platform_message_templates
where template_key in (
  'organization_closure_started', 'organization_closure_fourteen_day_reminder',
  'organization_closure_three_day_reminder', 'organization_closure_completed'
);
