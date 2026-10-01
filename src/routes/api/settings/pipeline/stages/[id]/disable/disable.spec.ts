import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { GET } from '../+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));
vi.mock('$lib/server/security/rate-limit', () => ({
	checkRateLimit: vi.fn(),
	rateLimitedResponse: () => new Response(null, { status: 429 })
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedLimit = vi.mocked(checkRateLimit);
const organizationId = '00000000-0000-4000-8000-000000000001';
const stageId = '7b0c8f2e-0000-4000-8000-000000000001';
const otherStageId = '7b0c8f2e-0000-4000-8000-000000000002';

function event(body: unknown, rpc = vi.fn(), id = stageId) {
	return {
		params: { id },
		request: new Request(`http://localhost/api/settings/pipeline/stages/${id}/disable`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

const context = {
	auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
	access: {}
} as never;

describe('switching a custom stage off', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedLimit.mockResolvedValue({ allowed: true } as never);
	});

	it('asks for permission to change business settings and stops there when refused', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await POST(event({ expected_revision: 2, destination: null }, rpc));

		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'settings.business.edit');
		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a bad destination, a missing revision, and a body that is not JSON before the database', async () => {
		const rpc = vi.fn();

		expect(
			(await POST(event({ expected_revision: 2, destination: 'somewhere' }, rpc))).status
		).toBe(422);
		expect((await POST(event({ destination: null }, rpc))).status).toBe(422);
		expect((await POST(event({ expected_revision: 2 }, rpc))).status).toBe(422);
		expect((await POST(event('not json', rpc))).status).toBe(422);
		expect(
			(await POST(event({ expected_revision: 2, destination: null }, rpc, 'waiting'))).status
		).toBe(404);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('switches an empty stage off without naming a destination', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { status: 'disabled', pipeline_revision: 3, moved_count: 0 },
			error: null
		});

		const response = await POST(event({ expected_revision: 2, destination: null }, rpc));

		expect(rpc).toHaveBeenCalledWith('disable_pipeline_custom_stage', {
			target_organization_id: organizationId,
			target_stage_id: stageId,
			expected_revision: 2,
			move_cards_to_stage_id: undefined,
			move_cards_to_built_in: false
		});
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			status: 'disabled',
			pipeline_revision: 3,
			moved_count: 0
		});
	});

	it('sends the cards to another custom stage', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { status: 'disabled', pipeline_revision: 3, moved_count: 3 },
			error: null
		});

		await POST(event({ expected_revision: 2, destination: otherStageId }, rpc));

		expect(rpc).toHaveBeenCalledWith(
			'disable_pipeline_custom_stage',
			expect.objectContaining({
				move_cards_to_stage_id: otherStageId,
				move_cards_to_built_in: false
			})
		);
	});

	it('sends the cards back to their built-in stages', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { status: 'disabled', pipeline_revision: 3, moved_count: 3 },
			error: null
		});

		await POST(event({ expected_revision: 2, destination: 'built_in' }, rpc));

		expect(rpc).toHaveBeenCalledWith(
			'disable_pipeline_custom_stage',
			expect.objectContaining({
				move_cards_to_stage_id: undefined,
				move_cards_to_built_in: true
			})
		);
	});

	it('asks where the cards go when the stage holds some and nobody said', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { status: 'needs_destination', card_count: 3 },
			error: null
		});

		const response = await POST(event({ expected_revision: 2, destination: null }, rpc));

		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({ reason: 'needs_destination', card_count: 3 });
	});

	it('says who saved first when the settings changed underneath', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { status: 'stale', editor_name: 'Raad', edited_at: '2026-10-01T10:00:00Z' },
			error: null
		});

		const response = await POST(event({ expected_revision: 1, destination: null }, rpc));

		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({ reason: 'stale', editor_name: 'Raad' });
	});

	it("passes the database's own refusal on as the message a person reads", async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'Cards can only move to a stage in the same section.' }
		});

		const response = await POST(event({ expected_revision: 2, destination: otherStageId }, rpc));

		expect(response.status).toBe(422);
		expect(await response.json()).toMatchObject({
			field_errors: { form: 'Cards can only move to a stage in the same section.' }
		});
	});

	it('stops when the organization is saving too fast', async () => {
		mockedLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 } as never);
		const rpc = vi.fn();

		const response = await POST(event({ expected_revision: 2, destination: null }, rpc));

		expect(response.status).toBe(429);
		expect(rpc).not.toHaveBeenCalled();
	});
});

describe('counting the cards in a custom stage', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	function readEvent(rpc = vi.fn(), id = stageId) {
		return { params: { id }, locals: { supabase: { rpc } } } as unknown as Parameters<
			typeof GET
		>[0];
	}

	it('is only for people who may change business settings', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		expect((await GET(readEvent(rpc))).status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'settings.business.edit');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('returns how many cards the stage holds', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: 3, error: null });

		const response = await GET(readEvent(rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_custom_stage_card_count', {
			target_organization_id: organizationId,
			target_stage_id: stageId
		});
		expect(await response.json()).toEqual({ card_count: 3 });
	});

	it('does not ask the database about something that is not a stage id', async () => {
		const rpc = vi.fn();

		expect((await GET(readEvent(rpc, 'waiting'))).status).toBe(404);
		expect(rpc).not.toHaveBeenCalled();
	});
});
