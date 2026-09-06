import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { createInvoiceEmailAccessLink } from '$lib/server/communications/invoice-email';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { batchDeliverInvoicesSchema } from '$lib/server/validation/invoices.schema';

// Batch Deliver (Part 8b-2). Sends many invoices to their clients in one action, reusing the exact single-send
// path per invoice: issue a draft, then queue one email through the durable outbox. Nothing new sends here --
// the outbox worker still meters delivery, retries, and reconciles the email allowance.
//
// Three rules the single send does not have to carry, all met by reusing existing machinery:
//   * Rate limit -- each invoice draws one token from the SAME 20-per-5-minute per-user bucket single-send
//     uses, checked BEFORE issuing. Batch and manual sends therefore share one window; a batch cannot exceed
//     it. On the first denial we stop and leave every remaining invoice untouched, because a denied check
//     still counts against the window -- spending the rest would only push the wait out.
//   * Safe retries -- every command is idempotent on the caller's stable per-invoice key, so re-sending the
//     batch (or a subset, after an uncertain response) returns the first result rather than sending twice. A
//     deliberate fresh send uses new keys.
//   * Honest reporting -- each invoice comes back as queued, rate_limited, skipped, or failed-with-a-reason.
//     "Queued" means accepted into the outbox; the sent/failed delivery fact is the worker's, shown per
//     invoice afterward exactly as it is for a single send.

type DbError = { code?: string; message?: string };

// Per-invoice failure reasons, worded the same way the single-send mappers word them so the batch and the one
// send never disagree about why a bill could not go.
function sendFailureReason(error: DbError): string {
	const message = error.message ?? '';
	if (error.code === '55000') {
		return message.includes('No automated email sender')
			? 'No sending email is set up for your business yet. Add and verify one in Settings before sending by email.'
			: message || 'This invoice needs a customer email address before it can be sent.';
	}
	if (error.code === '42501') return 'You do not have access to send this invoice.';
	if (error.code === 'P0404') return message || 'That invoice could not be found.';
	if (error.code === 'P0409') return message || 'Someone changed this invoice. Reload and try again.';
	if (error.code === '23514' || error.code === '23503')
		return message || 'This invoice cannot be sent as it stands.';
	return 'This invoice could not be sent. Please try again.';
}

type Outcome =
	| { invoice_id: string; outcome: 'queued'; intent_id: string; status: string }
	| { invoice_id: string; outcome: 'rate_limited'; retry_after_seconds: number }
	| { invoice_id: string; outcome: 'skipped' }
	| { invoice_id: string; outcome: 'failed'; reason: string };

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.send');
	if ('response' in check) return check.response;

	// Sending an invoice by email also opens a customer conversation, exactly as the single email route does.
	if (!hasPermission(check.access, 'conversations.send')) {
		return json(
			{ error: 'You do not have access to do that.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = batchDeliverInvoicesSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = check.auth.organization.id;
	const userId = check.auth.user.id;
	const userClient = event.locals.supabase;
	const ownerClient = getOwnerSupabaseClient();
	const items = parsed.data.invoices;

	// Authoritative draft-ness for the whole batch in one read: only a draft is issued on send; an already
	// issued bill (awaiting payment or past due) is only queued. Scoped to this organization so a stray id
	// from another tenant simply is not found.
	const { data: statusRows, error: statusError } = await userClient
		.from('invoices')
		.select('id, issued_at')
		.eq('organization_id', organizationId)
		.in(
			'id',
			items.map((item) => item.invoice_id)
		);
	if (statusError) {
		return json(
			{ error: 'The invoices could not be read.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
	const issuedAt = new Map((statusRows ?? []).map((row) => [row.id, row.issued_at]));

	const results: Outcome[] = [];

	for (let index = 0; index < items.length; index += 1) {
		const item = items[index];

		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communication_invoice_email:${organizationId}:${userId}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) {
			results.push({
				invoice_id: item.invoice_id,
				outcome: 'rate_limited',
				retry_after_seconds: limit.retryAfterSeconds
			});
			for (let rest = index + 1; rest < items.length; rest += 1) {
				results.push({ invoice_id: items[rest].invoice_id, outcome: 'skipped' });
			}
			break;
		}

		if (!issuedAt.has(item.invoice_id)) {
			results.push({
				invoice_id: item.invoice_id,
				outcome: 'failed',
				reason: 'That invoice could not be found.'
			});
			continue;
		}

		// Issue a draft first, as single-send does. The same key replays the first issue on a retry; a bill
		// already issued (by us earlier, or concurrently since our read) is not re-issued -- we fall through
		// to sending it.
		if (issuedAt.get(item.invoice_id) === null) {
			const { error: issueError } = await userClient.rpc('issue_invoice', {
				target_organization_id: organizationId,
				target_invoice_id: item.invoice_id,
				expected_revision: item.expected_revision,
				new_issue_method: 'sent',
				new_idempotency_key: item.idempotency_key,
				new_request_hash: item.idempotency_key
			});
			if (issueError && !(issueError.message ?? '').includes('already been issued')) {
				results.push({
					invoice_id: item.invoice_id,
					outcome: 'failed',
					reason: sendFailureReason(issueError)
				});
				continue;
			}
		}

		try {
			const link = createInvoiceEmailAccessLink();
			const { data: intent, error: enqueueError } = await ownerClient.rpc(
				'enqueue_invoice_communication_email',
				{
					target_organization_id: organizationId,
					target_actor_user_id: userId,
					target_invoice_id: item.invoice_id,
					target_logical_send_key: item.idempotency_key,
					target_invoice_url: link.url,
					target_invoice_token_hash: link.tokenHash
				}
			);
			if (enqueueError) {
				results.push({
					invoice_id: item.invoice_id,
					outcome: 'failed',
					reason: sendFailureReason(enqueueError)
				});
				continue;
			}
			results.push({
				invoice_id: item.invoice_id,
				outcome: 'queued',
				intent_id: intent.id,
				status: intent.status
			});
		} catch (error) {
			console.error('Could not queue an invoice email in a batch.', error);
			results.push({
				invoice_id: item.invoice_id,
				outcome: 'failed',
				reason: 'This invoice could not be sent. Please try again.'
			});
		}
	}

	const summary = {
		total: items.length,
		queued: results.filter((row) => row.outcome === 'queued').length,
		failed: results.filter((row) => row.outcome === 'failed').length,
		rate_limited: results.filter((row) => row.outcome === 'rate_limited').length,
		skipped: results.filter((row) => row.outcome === 'skipped').length
	};

	return json({ results, summary }, { status: 201, headers: NO_STORE_HEADERS });
};
