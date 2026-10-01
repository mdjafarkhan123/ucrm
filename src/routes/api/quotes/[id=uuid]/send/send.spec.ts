import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { sendDraftQuoteByEmail } from '$lib/server/quotes/send';

vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	enforceOrganizationWriteRateLimit: vi.fn(async () => null)
}));
vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn(),
	hasPermission: vi.fn()
}));
vi.mock('$lib/server/quotes/send', () => ({ sendDraftQuoteByEmail: vi.fn() }));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedHasPermission = vi.mocked(hasPermission);
const mockedSendEmail = vi.mocked(sendDraftQuoteByEmail);
const quoteId = '00000000-0000-4000-8000-000000000071';
const idempotencyKey = '00000000-0000-4000-8000-000000000072';

const context = {
	auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
	access: {}
} as never;

function event(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: quoteId },
		request: new Request(`http://localhost/api/quotes/${quoteId}/send`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

describe('sending a draft quote from its own page', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedHasPermission.mockReturnValue(true);
		mockedSendEmail.mockResolvedValue(null);
	});

	it('needs the send permission', async () => {
		await POST(
			event({ idempotency_key: idempotencyKey, send: { method: 'email', expected_revision: 1 } })
		);

		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'quotes.send');
	});

	it('will not send without saying how', async () => {
		const response = await POST(event({ idempotency_key: idempotencyKey }));

		expect(response.status).toBe(422);
		expect(mockedSendEmail).not.toHaveBeenCalled();
	});

	it('emails the reviewed draft', async () => {
		const response = await POST(
			event({ idempotency_key: idempotencyKey, send: { method: 'email', expected_revision: 4 } })
		);

		expect(mockedSendEmail).toHaveBeenCalledWith({
			organizationId: 'org-1',
			actorUserId: 'user-1',
			quoteId,
			expectedRevision: 4,
			idempotencyKey
		});
		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toContain('no-store');
	});

	it('hands back the email refusal', async () => {
		mockedSendEmail.mockResolvedValue(new Response(null, { status: 422 }));

		const response = await POST(
			event({ idempotency_key: idempotencyKey, send: { method: 'email', expected_revision: 4 } })
		);

		expect(response.status).toBe(422);
	});

	it('will not email for someone who may send quotes but not email customers', async () => {
		mockedHasPermission.mockReturnValue(false);

		const response = await POST(
			event({ idempotency_key: idempotencyKey, send: { method: 'email', expected_revision: 4 } })
		);

		expect(response.status).toBe(403);
		expect(mockedSendEmail).not.toHaveBeenCalled();
	});

	it('records a quote the person sent themselves, with its channel and note', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { quote_id: quoteId }, error: null });

		const response = await POST(
			event(
				{
					idempotency_key: idempotencyKey,
					send: {
						method: 'external',
						expected_revision: 2,
						channel: 'phone',
						note: '  Read it out  '
					}
				},
				rpc
			)
		);

		expect(rpc).toHaveBeenCalledWith('mark_quote_sent_externally', {
			target_quote_id: quoteId,
			expected_revision: 2,
			send_channel: 'phone',
			send_note: 'Read it out'
		});
		expect(mockedSendEmail).not.toHaveBeenCalled();
		expect(response.status).toBe(200);
	});

	it('rejects a channel outside the known list', async () => {
		const response = await POST(
			event({
				idempotency_key: idempotencyKey,
				send: { method: 'external', expected_revision: 2, channel: 'carrier_pigeon' }
			})
		);

		expect(response.status).toBe(422);
	});

	it('turns a refusal to mark the quote sent into a form error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'Add at least one line before sending this quote.' }
		});

		const response = await POST(
			event(
				{
					idempotency_key: idempotencyKey,
					send: { method: 'external', expected_revision: 1, channel: 'in_person' }
				},
				rpc
			)
		);

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toBe(
			'Add at least one line before sending this quote.'
		);
	});
});
