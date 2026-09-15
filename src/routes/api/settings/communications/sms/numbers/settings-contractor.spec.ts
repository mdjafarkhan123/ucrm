import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as getNumbers } from './+server';
import { PATCH as patchNumber } from './[senderId]/+server';
import { GET as getCompliance, PATCH as patchCompliance } from '../compliance/+server';
import { GET as getHolds } from '../holds/+server';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationAdmin: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const organizationId = '123e4567-e89b-42d3-a456-426614174000';
const userId = '123e4567-e89b-42d3-a456-426614174001';
const senderId = '123e4567-e89b-42d3-a456-426614174002';

function event(url: string, method: string, params: Record<string, string> = {}, body?: unknown) {
	return {
		params,
		request: new Request(`http://localhost${url}`, {
			method,
			headers: body === undefined ? undefined : { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		locals: {}
	} as never;
}

// A thenable query builder: every filter/order returns itself, and awaiting it (or calling maybeSingle) resolves
// the supplied result -- enough to stand in for the owner Supabase client's read chains.
function tableBuilder(result: { data?: unknown; error: unknown; count?: number }) {
	const builder: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'neq', 'or', 'order']) {
		builder[method] = vi.fn(() => builder);
	}
	builder.maybeSingle = vi.fn(() => Promise.resolve(result));
	builder.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve);
	return builder;
}

function rpcClient(result: { data: unknown; error: unknown }) {
	return { rpc: vi.fn().mockResolvedValue(result) };
}

const senderRow = {
	id: senderId,
	phone_number: '+15125550100',
	display_name: 'Front desk',
	country_code: 'US',
	sender_type: 'local',
	lifecycle_state: 'ready',
	capable_sms: true,
	capable_mms: true,
	capable_voice: true,
	allows_manual: true,
	allows_automated: true,
	registration_id: null,
	is_default_sender: true
};

describe('contractor SMS settings API', () => {
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

	it('stops before database access when authorization is denied', async () => {
		vi.mocked(requireOrganizationAdmin).mockResolvedValue({
			response: new Response(null, { status: 403 })
		});

		const response = await getNumbers(event('/api/settings/communications/sms/numbers', 'GET'));

		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('lists the organization numbers scoped and safely shaped', async () => {
		const table = tableBuilder({ data: [senderRow], error: null });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn().mockReturnValue(table)
		} as never);

		const response = await getNumbers(event('/api/settings/communications/sms/numbers', 'GET'));
		const payload = await response.json();

		expect(response.status).toBe(200);
		expect(table.eq).toHaveBeenCalledWith('organization_id', organizationId);
		expect(payload.numbers[0]).toMatchObject({
			id: senderId,
			capabilities: { sms: true, mms: true, voice: true },
			is_default_sender: true,
			can_be_default: true
		});
		// Raw capability columns must not leak; only the shaped fields are exposed.
		expect(payload.numbers[0].capable_sms).toBeUndefined();
	});

	it('renames a number through the command with session organization and actor', async () => {
		const client = rpcClient({ data: { ...senderRow, display_name: 'Dispatch' }, error: null });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await patchNumber(
			event(
				`/api/settings/communications/sms/numbers/${senderId}`,
				'PATCH',
				{ senderId },
				{ action: 'rename', display_name: '  Dispatch  ' }
			)
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_rename_sender',
			expect.objectContaining({
				p_organization_id: organizationId,
				p_sender_id: senderId,
				p_display_name: 'Dispatch',
				p_actor: userId
			})
		);
	});

	it('makes a number the default through the set-default command', async () => {
		const client = rpcClient({ data: senderRow, error: null });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await patchNumber(
			event(
				`/api/settings/communications/sms/numbers/${senderId}`,
				'PATCH',
				{ senderId },
				{ action: 'set_default' }
			)
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_set_default_sender',
			expect.objectContaining({ p_organization_id: organizationId, p_sender_id: senderId })
		);
	});

	it('rejects an unknown number action before database access', async () => {
		const response = await patchNumber(
			event(
				`/api/settings/communications/sms/numbers/${senderId}`,
				'PATCH',
				{ senderId },
				{ action: 'release' }
			)
		);

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('maps a not-found command error to 404 and a guarded state to 409', async () => {
		const notFound = rpcClient({
			data: null,
			error: { code: 'P0001', message: 'number not found' }
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(notFound as never);
		const notFoundResponse = await patchNumber(
			event(
				`/api/settings/communications/sms/numbers/${senderId}`,
				'PATCH',
				{ senderId },
				{ action: 'set_default' }
			)
		);
		expect(notFoundResponse.status).toBe(404);

		const notReady = rpcClient({
			data: null,
			error: {
				code: 'P0001',
				message: 'only a ready number can be made the default sending number'
			}
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(notReady as never);
		const conflictResponse = await patchNumber(
			event(
				`/api/settings/communications/sms/numbers/${senderId}`,
				'PATCH',
				{ senderId },
				{ action: 'set_default' }
			)
		);
		expect(conflictResponse.status).toBe(409);
	});

	it('returns system defaults when the organization has no compliance row', async () => {
		const table = tableBuilder({ data: null, error: null });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn().mockReturnValue(table)
		} as never);

		const response = await getCompliance(
			event('/api/settings/communications/sms/compliance', 'GET')
		);
		const payload = await response.json();

		expect(response.status).toBe(200);
		expect(payload.compliance).toMatchObject({
			opt_out_enabled: true,
			sender_info_enabled: true,
			periodic_reinsert_days: 30,
			is_default: true
		});
	});

	it('validates compliance input before database access', async () => {
		const response = await patchCompliance(
			event(
				'/api/settings/communications/sms/compliance',
				'PATCH',
				{},
				{
					opt_out_enabled: true,
					opt_out_text: null,
					sender_info_enabled: true,
					sender_info_text: null,
					periodic_reinsert_days: 90
				}
			)
		);

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('saves compliance settings through the upsert command', async () => {
		const client = rpcClient({
			data: {
				opt_out_enabled: false,
				opt_out_text: 'Reply STOP to opt out',
				sender_info_enabled: true,
				sender_info_text: null,
				periodic_reinsert_days: 14,
				updated_at: '2026-09-14T00:00:00Z'
			},
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await patchCompliance(
			event(
				'/api/settings/communications/sms/compliance',
				'PATCH',
				{},
				{
					opt_out_enabled: false,
					opt_out_text: '  Reply STOP to opt out  ',
					sender_info_enabled: true,
					sender_info_text: '   ',
					periodic_reinsert_days: 14
				}
			)
		);
		const payload = await response.json();

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_set_compliance_settings',
			expect.objectContaining({
				p_organization_id: organizationId,
				p_opt_out_enabled: false,
				p_opt_out_text: 'Reply STOP to opt out',
				// Blank custom text goes to the command as '' -- its nullif() clears it back to the default.
				p_sender_info_text: '',
				p_periodic_reinsert_days: 14,
				p_actor: userId
			})
		);
		expect(payload.compliance.is_default).toBe(false);
	});

	it('returns active holds and an opt-out count', async () => {
		const holds = tableBuilder({
			data: [
				{ id: 'h1', scope: 'organization', reason: 'balance', status: 'active', placed_at: 'x' }
			],
			error: null
		});
		const from = vi.fn(() => holds);
		const rpc = vi.fn(() => Promise.resolve({ data: 7, error: null }));
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ from, rpc } as never);

		const response = await getHolds(event('/api/settings/communications/sms/holds', 'GET'));
		const payload = await response.json();

		expect(response.status).toBe(200);
		expect(payload.holds[0]).toMatchObject({
			source: 'organization',
			releasable_by_contractor: false
		});
		expect(payload.opt_outs).toEqual({ total: 7 });
		expect(holds.eq).toHaveBeenCalledWith('status', 'active');
	});
});
