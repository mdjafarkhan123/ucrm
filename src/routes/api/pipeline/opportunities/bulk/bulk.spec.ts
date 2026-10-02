import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const cardA = '00000000-0000-4000-8000-000000000031';
const cardB = '00000000-0000-4000-8000-000000000032';
const personId = '00000000-0000-4000-8000-000000000041';
const stageId = '7b0c8f2e-0000-4000-8000-000000000001';

function event(body: unknown, rpc = vi.fn()) {
	return {
		params: {},
		request: new Request('http://localhost/api/pipeline/opportunities/bulk', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

const context = { auth: { user: { id: 'user-1' } }, access: {} } as never;
const ok = (results: unknown[]) => vi.fn().mockResolvedValue({ data: results, error: null });

describe('pipeline bulk API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('asks for permission to edit the pipeline and stops there when refused', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await POST(
			event({ action: 'owner', opportunity_ids: [cardA], owner_user_id: personId }, rpc)
		);

		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('offers no bulk change outside owner, Task, and custom stage', async () => {
		const rpc = vi.fn();
		for (const action of ['send', 'convert', 'lost', 'move', 'delete']) {
			const response = await POST(event({ action, opportunity_ids: [cardA] }, rpc));
			expect(response.status).toBe(422);
		}
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses no cards, more than 50, and a stage that is null before the database', async () => {
		const rpc = vi.fn();
		const many = Array.from(
			{ length: 51 },
			(_, index) => `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`
		);

		expect(
			(await POST(event({ action: 'owner', opportunity_ids: [], owner_user_id: null }, rpc))).status
		).toBe(422);
		expect(
			(await POST(event({ action: 'owner', opportunity_ids: many, owner_user_id: null }, rpc)))
				.status
		).toBe(422);
		expect(
			(await POST(event({ action: 'place', opportunity_ids: [cardA], custom_stage_id: null }, rpc)))
				.status
		).toBe(422);
		expect((await POST(event('not json', rpc))).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('reassigns every card and hands back each answer', async () => {
		const results = [
			{ id: cardA, status: 'done' },
			{ id: cardB, status: 'done' }
		];
		const rpc = ok(results);

		const response = await POST(
			event({ action: 'owner', opportunity_ids: [cardA, cardB], owner_user_id: personId }, rpc)
		);

		expect(rpc).toHaveBeenCalledWith('pipeline_bulk_update', {
			target_opportunity_ids: [cardA, cardB],
			bulk_action: 'owner',
			new_owner_user_id: personId
		});
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ results });
	});

	it('clears the owner by leaving it to the database default', async () => {
		const rpc = ok([{ id: cardA, status: 'done' }]);

		await POST(event({ action: 'owner', opportunity_ids: [cardA], owner_user_id: null }, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_bulk_update', {
			target_opportunity_ids: [cardA],
			bulk_action: 'owner'
		});
	});

	it('gives each card the same Task', async () => {
		const rpc = ok([{ id: cardA, status: 'done' }]);

		await POST(
			event(
				{
					action: 'task',
					opportunity_ids: [cardA],
					task: {
						title: '  Call back  ',
						instructions: '',
						assignee_user_id: null,
						due_on: '2026-10-09'
					}
				},
				rpc
			)
		);

		expect(rpc).toHaveBeenCalledWith('pipeline_bulk_update', {
			target_opportunity_ids: [cardA],
			bulk_action: 'task',
			new_title: 'Call back',
			new_due_on: '2026-10-09'
		});
	});

	it('passes a refused card through beside the ones that moved', async () => {
		const results = [
			{ id: cardA, status: 'done' },
			{
				id: cardB,
				status: 'refused',
				reason: 'Cards in “On hold” need a follow-up task with a future due date.',
				code: 'needs_future_task'
			}
		];
		const rpc = ok(results);

		const response = await POST(
			event({ action: 'place', opportunity_ids: [cardA, cardB], custom_stage_id: stageId }, rpc)
		);

		expect(rpc).toHaveBeenCalledWith('pipeline_bulk_update', {
			target_opportunity_ids: [cardA, cardB],
			bulk_action: 'place',
			target_custom_stage_id: stageId
		});
		expect(await response.json()).toEqual({ results });
	});

	it("passes on the database's own limit refusal and hides any other failure", async () => {
		const limited = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '54000', message: 'Change 50 cards or fewer at a time.' }
		});
		const broken = vi
			.fn()
			.mockResolvedValue({ data: null, error: { code: 'XX000', message: 'x' } });
		const body = { action: 'owner', opportunity_ids: [cardA], owner_user_id: null };

		const refused = await POST(event(body, limited));
		expect(refused.status).toBe(422);
		expect((await refused.json()).field_errors.form).toBe('Change 50 cards or fewer at a time.');
		expect((await POST(event(body, broken))).status).toBe(500);
	});
});
