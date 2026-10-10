import { describe, expect, it, vi } from 'vitest';
import { isAreaOpenForOrganization, refuseIfAreaClosed } from './readiness';

function clientReturning(result: { data: unknown; error: unknown }) {
	return { rpc: vi.fn().mockResolvedValue(result) } as never;
}

const decision = (area: string, status: string, extra: object = {}) => ({
	area_key: area,
	status,
	source: 'review',
	checks: [],
	business_message: null,
	decided_at: '2026-10-10T00:00:00Z',
	...extra
});

describe('refuseIfAreaClosed', () => {
	it('lets an action through when the area is ready', async () => {
		const client = clientReturning({
			data: [decision('customer_billing', 'ready', { source: 'carried_over' })],
			error: null
		});
		expect(await refuseIfAreaClosed(client, 'org-1', 'customer_billing')).toBeNull();
	});

	it('refuses with the remaining tasks and their owners when the area is waiting', async () => {
		const client = clientReturning({
			data: [
				decision('customer_messaging', 'not_ready', {
					checks: [
						{ key: 'sender_email_verified', state: 'open' },
						{ key: 'text_number_registered', state: 'not_applicable' },
						{ key: 'contact_details_confirmed', state: 'done' }
					]
				})
			],
			error: null
		});
		const response = await refuseIfAreaClosed(client, 'org-1', 'customer_messaging');
		expect(response?.status).toBe(403);
		const body = await response!.json();
		expect(body.reason).toBe('not_ready');
		expect(body.area).toBe('customer_messaging');
		expect(body.tasks).toEqual([expect.objectContaining({ key: 'sender_email_verified' })]);
		expect(body.error).toContain('Uplift verifies the email address your messages are sent from');
	});

	it('refuses an area that has no decision at all', async () => {
		const response = await refuseIfAreaClosed(
			clientReturning({ data: [], error: null }),
			'org-1',
			'customer_billing'
		);
		expect(response?.status).toBe(403);
		expect((await response!.json()).error).toContain('Uplift has not reviewed this yet.');
	});

	it('refuses automation while customer messaging is not ready', async () => {
		const response = await refuseIfAreaClosed(
			clientReturning({ data: [decision('customer_automation', 'ready')], error: null }),
			'org-1',
			'customer_automation'
		);
		expect(response?.status).toBe(403);
	});

	it('never allows an action when readiness cannot be read', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const response = await refuseIfAreaClosed(
			clientReturning({ data: null, error: { message: 'down' } }),
			'org-1',
			'customer_billing'
		);
		expect(response?.status).toBe(503);
		spy.mockRestore();
	});
});

function tableReturning(result: { data: unknown; error: unknown }) {
	const query = { select: vi.fn(), eq: vi.fn() };
	query.select.mockReturnValue(query);
	query.eq.mockReturnValueOnce(query).mockResolvedValueOnce(result);
	return { from: vi.fn().mockReturnValue(query) } as never;
}

describe('isAreaOpenForOrganization', () => {
	it('is open when the latest decision is ready', async () => {
		const client = tableReturning({
			data: [
				{ id: 'a', status: 'not_ready', previous_decision_id: null },
				{ id: 'b', status: 'ready', previous_decision_id: 'a' }
			],
			error: null
		});
		expect(await isAreaOpenForOrganization(client, 'org-1', 'public_intake')).toBe(true);
	});

	it('is closed when a ready decision was replaced by a hold', async () => {
		const client = tableReturning({
			data: [
				{ id: 'a', status: 'ready', previous_decision_id: null },
				{ id: 'b', status: 'held', previous_decision_id: 'a' }
			],
			error: null
		});
		expect(await isAreaOpenForOrganization(client, 'org-1', 'public_intake')).toBe(false);
	});

	it('is closed with no decision, and when readiness cannot be read', async () => {
		expect(
			await isAreaOpenForOrganization(
				tableReturning({ data: [], error: null }),
				'org-1',
				'public_intake'
			)
		).toBe(false);
		expect(
			await isAreaOpenForOrganization(
				tableReturning({ data: null, error: { message: 'down' } }),
				'org-1',
				'public_intake'
			)
		).toBe(false);
	});
});
