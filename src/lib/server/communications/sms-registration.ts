// A2 launch scope: one SMS registration per organization, for US long-code (10DLC) operational messaging
// (Memory/campaigns/communications-activation ROADMAP "Approved Automation and SMS boundary" — launch scope
// is US-first, long_code is the two-way sender type the Conversations promise requires). Country and sender
// type become contractor choices only when a later stage adds multi-country/sender-type support; until then
// every organization's registration uses this same key, so the contractor never has to understand the
// underlying provider vocabulary.
export const SMS_REGISTRATION_COUNTRY_CODE = 'US';
export const SMS_REGISTRATION_SENDER_TYPE = 'long_code';
export const SMS_REGISTRATION_USE_CASE = 'Customer service messaging and appointment updates';

// The attestation wording a contractor agrees to when submitting a registration for review. Versioned so a
// wording change is recorded on each stored submission. Lives here (not in the +server route) because
// SvelteKit only allows HTTP-method exports from a +server.ts; the route and its test both import these.
export const SMS_REGISTRATION_ATTESTATION_VERSION = 'authorized-representative-v1';
export const SMS_REGISTRATION_ATTESTATION_TEXT =
	'I confirm that I am authorized to represent this business and that the information submitted is complete and truthful.';

// The safe, contractor-facing projection of a communication_sms_registrations row: no provider identifiers,
// no internal audit fields. Shared by the collection route (start/read current) and the [registrationId]
// route (read/save draft) so both expose the same shape.
export function safeSmsRegistration(row: Record<string, unknown>) {
	return {
		id: row.id,
		country_code: row.country_code,
		sender_type: row.sender_type,
		use_case: row.use_case,
		status: row.status,
		required_fixes: row.required_fixes,
		draft_questionnaire_version: row.draft_questionnaire_version,
		draft_answers: row.draft_answers,
		draft_revision: row.draft_revision,
		draft_updated_at: row.draft_updated_at,
		submitted_at: row.submitted_at,
		updated_at: row.updated_at
	};
}
