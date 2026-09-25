-- Operational email SES Part 4: remove the pre-SES 12-argument record_communication_inbound_message.
--
-- 20260925150000 added a 13th parameter (target_provider, default 'brevo') with CREATE OR REPLACE, which in
-- Postgres creates a second overload instead of replacing the first. Every parameter of both overloads has a
-- default, so the Brevo inbound webhook's 12 named arguments match both equally and the call is ambiguous
-- (PostgREST PGRST203). Dropping the old overload leaves the one function 20260925150000 intended, which
-- records Brevo rows exactly as before through its 'brevo' default.

drop function if exists "public"."record_communication_inbound_message"(
    text, text, uuid, text, text, jsonb, jsonb, text, text, text, text, jsonb
);
