import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';

type DatabaseError = { code?: string; message?: string };

// Both the quote and invoice email-enqueue commands refuse an unready send with errcode
// object_not_in_prerequisite_state (55000), carrying the real reason in the message: either the client has no
// active email address, or the business has no verified sending identity yet. Without this, the shared quote/
// invoice write-error mappers have no 55000 case and fall through to a generic 500 — the office sees "We could
// not save that record. Please try again." and learns nothing. Here the database's own reason reaches the
// reader as a clean, actionable 422; the sender case is reworded to also say what to do next (setting the
// sender up is a later task, tracked in Memory/deferred/email-sender-setup-flow.md). Returns null when the
// error is not a send-prerequisite refusal, so the caller falls back to its normal mapper.
export function emailSendPrerequisiteResponse(error: DatabaseError) {
	if (error.code !== '55000') return null;
	const noSender = error.message?.includes('No automated email sender');
	return json(
		{
			error: noSender
				? 'No sending email is set up for your business yet. Add and verify one in Settings before sending by email.'
				: (error.message ?? 'This cannot be emailed yet.'),
			reason: 'not_ready'
		},
		{ status: 422, headers: NO_STORE_HEADERS }
	);
}
