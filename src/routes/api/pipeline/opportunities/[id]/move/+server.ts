import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { dragOpportunitySchema } from '$lib/server/validation/pipeline.schema';
import type { OpportunityStage } from '$lib/pipeline/stages';
import { dragActionFor } from '$lib/pipeline/transitions';
import { convertRequestError, quoteWriteError } from '$lib/server/quotes/errors';
import { sendDraftQuoteByEmail } from '$lib/server/quotes/send';

function sendNotAllowed(message: string) {
	return json(
		{ error: message, reason: 'permission_denied' },
		{ status: 403, headers: NO_STORE_HEADERS }
	);
}

const NOT_FOUND = 'That opportunity could not be found.';

// The drag endpoint: dropping a card onto a column performs that column's real domain command first, and
// the card moves only because the command succeeded -- `opportunity_apply_stage` picks the new stage up
// on its own once the underlying record changes. `pipeline_drag_opportunity` is the one place that knows
// a card's current stage and which record backs it (the table grants no other read), and it is also the
// authoritative gate: `dragActionFor` here only decides which write to perform, never whether the move is
// allowed -- a client that disagreed with the database would simply have its move refused.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = dragOpportunitySchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const supabase = event.locals.supabase;
	const { data: gate, error: gateError } = await supabase.rpc('pipeline_drag_opportunity', {
		target_opportunity_id: event.params.id,
		to_stage: parsed.data.to_stage
	});

	if (gateError) {
		if (gateError.code === '42501') return notFound(NOT_FOUND);
		if (gateError.code === '23514')
			return validationError({ form: gateError.message ?? 'That card cannot be moved there.' });
		return databaseError();
	}

	const fromStage = gate.from_stage as OpportunityStage;
	const action = dragActionFor(fromStage, parsed.data.to_stage);

	// The database already agreed this move is allowed; a null here means this route has not caught up
	// with a transition the gate now permits, not that the move should be refused a second time.
	if (!action) return databaseError();

	if (action === 'assessment_require' || action === 'assessment_schedule') {
		if (action === 'assessment_schedule' && (!parsed.data.starts_at || !parsed.data.ends_at)) {
			return validationError({ starts_at: 'Pick a start and end time for the assessment.' });
		}

		// Independent writes to independent tables -- run together rather than paying two round trips in
		// sequence. Booking (or turning on) an assessment for a brand new request is what moves it out of
		// "new", mirroring the assessment panel's own side effect; the guard means this is a no-op update
		// when the request has already left "new", not a race with the upsert above it.
		const [{ error: upsertError }, { error: statusError }] = await Promise.all([
			supabase.from('assessments').upsert(
				{
					organization_id: gate.organization_id,
					request_id: gate.request_id,
					starts_at: action === 'assessment_schedule' ? parsed.data.starts_at : null,
					ends_at: action === 'assessment_schedule' ? parsed.data.ends_at : null
				},
				{ onConflict: 'request_id' }
			),
			supabase
				.from('requests')
				.update({ status: 'unscheduled' })
				.eq('organization_id', gate.organization_id)
				.eq('id', gate.request_id)
				.eq('status', 'new')
		]);
		if (upsertError || statusError) return databaseError();
	} else if (action === 'assessment_complete') {
		const { data: assessment, error: completeError } = await supabase
			.from('assessments')
			.update({ completed_at: new Date().toISOString() })
			.eq('organization_id', gate.organization_id)
			.eq('request_id', gate.request_id)
			.select('id')
			.maybeSingle();
		if (completeError) return databaseError();
		if (!assessment) return notFound('That request has no assessment to complete.');

		const { error: statusError } = await supabase
			.from('requests')
			.update({ status: 'assessment_completed' })
			.eq('organization_id', gate.organization_id)
			.eq('id', gate.request_id)
			.in('status', ['new', 'unscheduled']);
		if (statusError) return databaseError();
	} else if (action === 'quote_convert') {
		if (!parsed.data.idempotency_key) {
			return validationError({ form: 'Start this conversion again.' });
		}

		// `convert_request_to_quote` wants a fingerprint of what the person was looking at when they
		// decided. On the Request page that is the pricing they had on screen; on the board there is no
		// pricing on screen at all -- somebody dragged a card and confirmed a dialog naming the client and
		// the request. So the fingerprint says exactly that, and stays the same across a retry of the same
		// drag. Copying the Request page's `rev-N:lines-N` here would be a claim about a screen nobody saw.
		//
		// Permission is checked twice on purpose and they are not the same question: `pipeline.edit` is
		// whether this person may move cards, `quotes.create` is whether they may make a quote. The command
		// below answers the second one itself.
		const { data, error } = await supabase.rpc('convert_request_to_quote', {
			target_request_id: gate.request_id,
			idempotency_key: parsed.data.idempotency_key,
			request_hash: `board-drag:${event.params.id}`
		});
		if (error) return convertRequestError(error);

		// The new Quote's number, so the toast can name it. The card does not move here -- the Request
		// card leaves the board and a Quote card appears in Draft because the stage derivation followed
		// the records, which is the same thing every other drop relies on.
		return json(
			{ id: event.params.id, from_stage: fromStage, to_stage: parsed.data.to_stage, quote: data },
			{ headers: NO_STORE_HEADERS }
		);
	} else {
		// Draft -> Awaiting response. A drop alone never claims the customer received anything: the board's
		// send window says how the quote is going out, and the card moves only because that really happened.
		// Moving cards and sending quotes are separate permissions, so both are answered here in words rather
		// than left to the command's "not found".
		const send = parsed.data.send;
		if (!send) return validationError({ form: 'Choose how this quote is being sent.' });
		if (!hasPermission(check.access, 'quotes.send')) {
			return sendNotAllowed('You do not have permission to send quotes.');
		}

		if (send.method === 'email') {
			if (!parsed.data.idempotency_key) {
				return validationError({ form: 'Start this send again.' });
			}
			// The email also opens a customer conversation, so it needs that permission as well.
			if (!hasPermission(check.access, 'conversations.send')) {
				return sendNotAllowed('You do not have permission to email customers.');
			}
			const refusal = await sendDraftQuoteByEmail({
				organizationId: gate.organization_id,
				actorUserId: check.auth.user.id,
				quoteId: gate.quote_id,
				expectedRevision: send.expected_revision,
				idempotencyKey: parsed.data.idempotency_key
			});
			if (refusal) return refusal;
		} else {
			const { error: sentError } = await supabase.rpc('mark_quote_sent_externally', {
				target_quote_id: gate.quote_id,
				expected_revision: send.expected_revision,
				send_channel: send.channel,
				send_note: send.note ?? undefined
			});
			if (sentError) return quoteWriteError(sentError);
		}
	}

	return json(
		{ id: event.params.id, from_stage: fromStage, to_stage: parsed.data.to_stage },
		{
			headers: NO_STORE_HEADERS
		}
	);
};
