import { describe, expect, it } from 'vitest';
import { withOptOutTasks } from './sms-opt-out-tasks';

type Rows = Record<string, unknown[]>;

// A tiny stand-in for the owner client: each table answers with fixed rows, whatever the filters.
function fakeClient(rows: Rows) {
	return {
		from(table: string) {
			const result = { data: rows[table] ?? [], error: null };
			const chain: Record<string, unknown> = {};
			for (const method of ['select', 'in', 'neq', 'order', 'gt', 'eq']) {
				chain[method] = () => chain;
			}
			chain.then = (resolve: (value: typeof result) => unknown) => resolve(result);
			return chain;
		}
	} as never;
}

const task = (id: string, organization: string, country: string, requestedAt: string) => ({
	id,
	organization_id: organization,
	organization_name: organization === 'org-a' ? 'Road LTD' : 'Raad LTD',
	country,
	is_home: false,
	requested_at: requestedAt,
	requested_by: null,
	account_sid: null,
	price: { segment: null, mms: null },
	history: []
});

const queue = (tasks: ReturnType<typeof task>[]) => ({
	summary: {
		to_do: tasks.length,
		oldest_at: tasks[0]?.requested_at ?? null,
		waiting_on_twilio: 0,
		countries_live: 0,
		businesses_live: 0,
		countries_without_price: []
	},
	recently_finished: [],
	tasks
});

describe('withOptOutTasks', () => {
	it('makes one task per business and language, shared by its countries', async () => {
		const result = await withOptOutTasks(
			fakeClient({
				communication_twilio_accounts: [{ organization_id: 'org-a', messaging_service_sid: 'MG1' }]
			}),
			queue([
				task('d1', 'org-a', 'MX', '2026-10-20T00:00:00Z'),
				task('d2', 'org-a', 'ES', '2026-10-21T00:00:00Z'),
				task('d3', 'org-a', 'GB', '2026-10-22T00:00:00Z')
			])
		);
		expect(result.opt_out_tasks).toEqual([
			{
				id: 'opt-out:org-a:es',
				organization_id: 'org-a',
				organization_name: 'Road LTD',
				language: 'es',
				countries: ['MX', 'ES'],
				requested_at: '2026-10-20T00:00:00Z',
				messaging_service_sid: 'MG1'
			}
		]);
		expect(result.tasks.map((row) => row.opt_out_missing)).toEqual([['es'], ['es'], []]);
		expect(result.summary.to_do).toBe(4);
	});

	it('asks nothing for a language the business already has', async () => {
		const result = await withOptOutTasks(
			fakeClient({
				communication_sms_opt_out_languages: [
					{ organization_id: 'org-a', language: 'es', added_at: '2026-10-23T00:00:00Z' }
				]
			}),
			queue([task('d1', 'org-a', 'MX', '2026-10-20T00:00:00Z')])
		);
		expect(result.opt_out_tasks).toEqual([]);
		expect(result.tasks[0].opt_out_missing).toEqual([]);
		expect(result.summary.to_do).toBe(1);
		expect(result.recently_finished).toEqual([
			{ id: 'opt-out:org-a:es', kind: 'opt_out_added', at: '2026-10-23T00:00:00Z', who: undefined }
		]);
	});
});
