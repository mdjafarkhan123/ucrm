-- Communications A2 / Stage 9A follow-up: the Trust Hub ledger is missing a resource role.
--
-- Found while researching Stage 9B against Twilio's actual ISV onboarding guide
-- (docs/messaging/compliance/a2p-10dlc/onboarding-isv-api, "Standard and Low-Volume Standard" path): the A2P
-- Trust Product bundle requires its own EndUser resource, type `us_a2p_messaging_profile_information`
-- (company_type, and stock_exchange/stock_ticker for public companies) -- a mandatory step (guide step 2.2),
-- not the same object as `end_user_business_information` and not optional. The original migration only
-- enumerated 7 resource roles and has no slot for it. Widen both check constraints that list the 7 roles to
-- add the 8th; no data exists yet (Stage 9B, which would populate it, has not been built), so this is a pure
-- constraint widening with no backfill.

alter table public.communication_sms_trust_hub_resources
  drop constraint communication_sms_trust_hub_resources_role_check,
  add constraint communication_sms_trust_hub_resources_role_check
    check (resource_role in (
      'customer_profile', 'end_user_business_information', 'end_user_authorized_representative',
      'supporting_document_address', 'end_user_a2p_messaging_profile', 'a2p_trust_product',
      'brand_registration', 'campaign'
    ));

alter table public.communication_sms_trust_hub_events
  drop constraint communication_sms_trust_hub_events_role_check,
  add constraint communication_sms_trust_hub_events_role_check
    check (resource_role is null or resource_role in (
      'customer_profile', 'end_user_business_information', 'end_user_authorized_representative',
      'supporting_document_address', 'end_user_a2p_messaging_profile', 'a2p_trust_product',
      'brand_registration', 'campaign'
    ));
