import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as getUsage } from '../usage/+server';
import { GET as getTopups, POST as postTopup } from './+server';
import { PATCH as patchTopup } from './[requestId]/+server';
import { GET as getLedger } from '../ledger/+server';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationAdmin: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const organizationId = '123e4567-e89b-42d3-a456-426614174000';
const userId = '123e4567-e89b-42d3-a456-426614174001';
const requestId = '123e4567-e89b-42d3-a456-426614174002';

function event(url: string, method: string, params: Record<string, string> = {}, body?: unknown) {
	return {
		params,
		url: new URL(`http://localhost${url}`),
		request: new Request(`http://localhost${url}`, {
			method,
			headers: body === undefined ? undefined : { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		locals: {}
	} as never;
}

// A thenable query builder: every filter/order/range call returns itself, and awaiting it (or calling
// maybeSingle) resolves the supplied result -- enough to stand in for the owner Supabase client's read chains.
function tableBuilder(result: { data?: unknown; error: unknown; count?: number }) {
	const builder: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'neq', 'or', 'order', 'gte', 'lt', 'limit']) {
		builder[method] = vi.fn(() => builder);
	}
	builder.maybeSingle = vi.fn(() => Promise.resolve(result));
	builder.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve);
	return builder;
}

beforeEach(() => {
	vi.clearAllMocks();
	vi.mocked(requireOrganizationAdmin).mockResolvedValue({
		auth: {
			user: { id: userId, email: 'signed-in@ridgeway.example' },
			organization: { id: organizationId, name: 'Ridgeway', role: 'admin' }
		},
		access: { features: {}, limits: {}, permissions: {} }
	} as never);
});

describe('GET /api/settings/communications/sms/usage', () => {
	it('stops before database access when authorization is denied', async () => {
		vi.mocked(requireOrganizationAdmin).mockResolvedValue({
			response: new Response(null, { status: 403 })
		});

		const response = await getUsage(event('/api/settings/communications/sms/usage', 'GET'));

		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('shapes the balance, this month usage and lean health', async () => {
		const account = tableBuilder({
			data: { currency_code: 'USD', settled_balance_minor: 5000, reserved_balance_minor: 300 },
			error: null
		});
		const charges = tableBuilder({
			data: [{ amount_minor: -150 }, { amount_minor: -50 }],
			error: null
		});
		const adjustments = tableBuilder({ data: [{ amount_minor: 25 }], error: null });
		const reservations = tableBuilder({
			data: [{ segment_count: 1 }, { segment_count: 2 }],
			error: null
		});
		const messageEvents = tableBuilder({
			data: [{ event_kind: 'sent' }, { event_kind: 'sent' }, { event_kind: 'delivered' }],
			error: null
		});
		const from = vi.fn((table: string) => {
			if (table === 'communication_sms_credit_accounts') return account;
			if (table === 'communication_sms_credit_ledger_entries') {
				// Called twice: once for charges, once for adjustments. Distinguish by call order.
				return from.mock.calls.filter((c) => c[0] === 'communication_sms_credit_ledger_entries')
					.length === 1
					? charges
					: adjustments;
			}
			if (table === 'communication_sms_credit_reservations') return reservations;
			if (table === 'communication_message_events') return messageEvents;
			throw new Error(`Unexpected table ${table}`);
		});
		const rpc = vi.fn((name: string) => {
			if (name === 'communication_sms_promotional_balance')
				return Promise.resolve({ data: 200, error: null });
			if (name === 'communication_sms_spendable_balance')
				return Promise.resolve({ data: 4900, error: null });
			if (name === 'communication_sms_active_outbound_hold')
				return Promise.resolve({ data: [], error: null });
			if (name === 'communication_sms_opted_out_count')
				return Promise.resolve({ data: 1, error: null });
			throw new Error(`Unexpected rpc ${name}`);
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ from, rpc } as never);

		const response = await getUsage(event('/api/settings/communications/sms/usage', 'GET'));
		const payload = await response.json();

		expect(response.status).toBe(200);
		expect(payload.balance).toMatchObject({
			currency_code: 'USD',
			settled_balance_minor: 5000,
			reserved_balance_minor: 300,
			promotional_balance_minor: 200,
			spendable_balance_minor: 4900
		});
		expect(payload.availability).toEqual({ state: 'available', reason: null });
		expect(payload.usage_summary).toMatchObject({
			retail_charge_minor: 200,
			messages: 2,
			segments: 3,
			adjustments_count: 1,
			adjustments_amount_minor: 25
		});
		expect(payload.messaging_health).toMatchObject({
			sent: 2,
			delivered: 1,
			failed: 0,
			received: 0,
			opt_out_rate: 0.5
		});
	});

	it('reports a zero balance as the availability state even under an active hold', async () => {
		const account = tableBuilder({
			data: { currency_code: 'USD', settled_balance_minor: 0, reserved_balance_minor: 0 },
			error: null
		});
		const empty = tableBuilder({ data: [], error: null, count: 0 });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn((table: string) =>
				table === 'communication_sms_credit_accounts' ? account : empty
			),
			rpc: vi.fn((name: string) => {
				if (name === 'communication_sms_active_outbound_hold')
					return Promise.resolve({
						data: [{ scope: 'organization', reason: 'balance' }],
						error: null
					});
				return Promise.resolve({ data: 0, error: null });
			})
		} as never);

		const response = await getUsage(event('/api/settings/communications/sms/usage', 'GET'));
		const payload = await response.json();

		expect(payload.availability).toEqual({ state: 'zero_balance', reason: null });
	});
});

describe('GET/POST /api/settings/communications/sms/credit-topups', () => {
	it('lists the organization own requests scoped and safely shaped', async () => {
		const table = tableBuilder({
			data: [
				{
					id: requestId,
					requested_amount_minor: 2000,
					currency_code: 'USD',
					offsite_reference: 'zelle-1',
					note: null,
					status: 'awaiting_confirmation',
					requested_at: '2026-09-01T00:00:00Z',
					decided_at: null,
					decision_reason: null,
					settled_amount_minor: null
				}
			],
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn().mockReturnValue(table)
		} as never);

		const response = await getTopups(
			event('/api/settings/communications/sms/credit-topups', 'GET')
		);
		const payload = await response.json();

		expect(response.status).toBe(200);
		expect(table.eq).toHaveBeenCalledWith('organization_id', organizationId);
		expect(payload.requests[0]).toMatchObject({ id: requestId, status: 'awaiting_confirmation' });
	});

	it('validates the request body before database access', async () => {
		const response = await postTopup(
			event(
				'/api/settings/communications/sms/credit-topups',
				'POST',
				{},
				{ requested_amount_minor: -5 }
			)
		);

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('submits a request through the command with session organization and actor', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: {
				id: requestId,
				requested_amount_minor: 2000,
				currency_code: 'USD',
				offsite_reference: 'zelle-1',
				note: 'Paid via Zelle',
				status: 'awaiting_confirmation',
				requested_at: '2026-09-01T00:00:00Z',
				decided_at: null,
				decision_reason: null,
				settled_amount_minor: null
			},
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);

		const response = await postTopup(
			event(
				'/api/settings/communications/sms/credit-topups',
				'POST',
				{},
				{
					requested_amount_minor: 2000,
					offsite_reference: '  zelle-1  ',
					note: '  Paid via Zelle  '
				}
			)
		);
		const payload = await response.json();

		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith(
			'communication_sms_request_credit_topup',
			expect.objectContaining({
				p_organization_id: organizationId,
				p_requested_by: userId,
				p_requested_amount_minor: 2000,
				p_offsite_reference: 'zelle-1',
				p_note: 'Paid via Zelle'
			})
		);
		expect(payload.request.id).toBe(requestId);
	});
});

describe('PATCH /api/settings/communications/sms/credit-topups/[requestId]', () => {
	it('rejects an unsupported action before database access', async () => {
		const response = await patchTopup(
			event(
				`/api/settings/communications/sms/credit-topups/${requestId}`,
				'PATCH',
				{ requestId },
				{ action: 'confirm' }
			)
		);

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the request belongs to a different organization', async () => {
		const lookup = tableBuilder({
			data: { id: requestId, organization_id: 'someone-elses-org' },
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn().mockReturnValue(lookup)
		} as never);

		const response = await patchTopup(
			event(
				`/api/settings/communications/sms/credit-topups/${requestId}`,
				'PATCH',
				{ requestId },
				{ action: 'cancel' }
			)
		);

		expect(response.status).toBe(404);
	});

	it('cancels through the command once ownership is confirmed', async () => {
		const lookup = tableBuilder({
			data: { id: requestId, organization_id: organizationId },
			error: null
		});
		const rpc = vi.fn().mockResolvedValue({
			data: {
				id: requestId,
				requested_amount_minor: 2000,
				currency_code: 'USD',
				offsite_reference: null,
				note: null,
				status: 'cancelled',
				requested_at: '2026-09-01T00:00:00Z',
				decided_at: '2026-09-02T00:00:00Z',
				decision_reason: null,
				settled_amount_minor: null
			},
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn().mockReturnValue(lookup),
			rpc
		} as never);

		const response = await patchTopup(
			event(
				`/api/settings/communications/sms/credit-topups/${requestId}`,
				'PATCH',
				{ requestId },
				{ action: 'cancel' }
			)
		);
		const payload = await response.json();

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('communication_sms_cancel_credit_topup', {
			p_request_id: requestId,
			p_cancelled_by: userId
		});
		expect(payload.request.status).toBe('cancelled');
	});

	it('maps a guarded command error to 409', async () => {
		const lookup = tableBuilder({
			data: { id: requestId, organization_id: organizationId },
			error: null
		});
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: {
				code: 'P0001',
				message: 'top-up request is confirmed and can no longer be cancelled'
			}
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn().mockReturnValue(lookup),
			rpc
		} as never);

		const response = await patchTopup(
			event(
				`/api/settings/communications/sms/credit-topups/${requestId}`,
				'PATCH',
				{ requestId },
				{ action: 'cancel' }
			)
		);

		expect(response.status).toBe(409);
	});
});

describe('GET /api/settings/communications/sms/ledger', () => {
	it('rejects an unresolvable cursor', async () => {
		const response = await getLedger(
			event('/api/settings/communications/sms/ledger?cursor=not-a-cursor', 'GET')
		);

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('lists entries scoped to the organization, safely shaped, with no next page', async () => {
		const table = tableBuilder({
			data: [
				{
					id: 'l1',
					source_key: 'topup:abc',
					entry_kind: 'credit',
					amount_minor: 2000,
					balance_after_minor: 2000,
					occurred_at: '2026-09-01T00:00:00Z',
					reason: null
				}
			],
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn().mockReturnValue(table)
		} as never);

		const response = await getLedger(event('/api/settings/communications/sms/ledger', 'GET'));
		const payload = await response.json();

		expect(response.status).toBe(200);
		expect(table.eq).toHaveBeenCalledWith('organization_id', organizationId);
		expect(payload.entries[0]).toMatchObject({
			id: 'l1',
			reference: 'topup:abc',
			bucket: 'purchased',
			entry_kind: 'credit'
		});
		expect(payload.next_cursor).toBeNull();
	});

	it('filters by entry kind when requested', async () => {
		const table = tableBuilder({ data: [], error: null });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn().mockReturnValue(table)
		} as never);

		await getLedger(event('/api/settings/communications/sms/ledger?entry_kind=charge', 'GET'));

		expect(table.eq).toHaveBeenCalledWith('entry_kind', 'charge');
	});
});
