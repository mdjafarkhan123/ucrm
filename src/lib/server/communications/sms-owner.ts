// The Stage 2C SMS money and control commands each record a uuid `actor` for their own immutable
// ledger/event trail. The platform owner (Jafar) authenticates by email and has no Supabase user id,
// and these actor columns are free uuids with no foreign key, so we pass one stable non-user sentinel
// as the command actor. The real human identity of every owner action is captured separately in
// access_audit_events via recordOwnerAccessAudit — the same trail every other Jafar action uses.
export const PLATFORM_OWNER_ACTOR_ID = '00000000-0000-0000-0000-000000000000';
