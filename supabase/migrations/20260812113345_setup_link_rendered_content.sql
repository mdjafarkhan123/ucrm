-- Stores the exact rendered subject/body of the last password-setup email actually sent,
-- so Jafar can always see what an administrator received even after the message-template
-- editor's published wording later changes.
alter table public.platform_onboarding_application_setup_links
  add column rendered_subject text,
  add column rendered_body text;
