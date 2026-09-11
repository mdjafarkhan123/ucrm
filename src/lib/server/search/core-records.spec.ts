import { describe, expect, it } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { searchCoreRecords } from './core-records';

type Call = { table: string; method: string; args: unknown[] };

function queryClient(rows: Record<string, unknown[]> = {}) {
	const calls: Call[] = [];
	const tableReads = new Map<string, number>();

	const from = (table: string) => {
		const read = tableReads.get(table) ?? 0;
		tableReads.set(table, read + 1);
		const data = rows[`${table}:${read}`] ?? rows[table] ?? [];
		const builder: Record<string, unknown> = {};

		for (const method of ['select', 'eq', 'neq', 'is', 'or', 'order', 'limit', 'ilike', 'in']) {
			builder[method] = (...args: unknown[]) => {
				calls.push({ table, method, args });
				return builder;
			};
		}
		builder.then = (resolve: (value: { data: unknown[]; error: null }) => unknown) =>
			Promise.resolve(resolve({ data, error: null }));
		return builder;
	};

	return { client: { from } as unknown as SupabaseClient<Database>, calls };
}

describe('searchCoreRecords query boundaries', () => {
	it('scopes every permitted database read to the organization and five rows', async () => {
		const { client, calls } = queryClient();

		await searchCoreRecords(client, 'org-1', 'roof', {
			clients: true,
			requests: true,
			quotes: true,
			jobs: true,
			invoices: true
		});

		const reads = calls.filter(({ method }) => method === 'select');
		expect(reads.map(({ table }) => table)).toEqual([
			'clients',
			'client_contact_methods',
			'requests',
			'quotes',
			'job_list_rows',
			'invoices'
		]);

		for (const { table } of reads) {
			expect(calls).toContainEqual({ table, method: 'eq', args: ['organization_id', 'org-1'] });
			expect(calls).toContainEqual({ table, method: 'limit', args: [5] });
		}
	});

	it('keeps the follow-up client lookup organization-scoped and bounded', async () => {
		const { client, calls } = queryClient({
			clients: [
				{
					id: 'client-name',
					display_name: 'Roof Name',
					company_name: null,
					updated_at: '2026-01-01'
				}
			],
			client_contact_methods: [{ client_id: 'client-name' }, { client_id: 'client-contact' }],
			'clients:1': [
				{
					id: 'client-contact',
					display_name: 'Contact Match',
					company_name: null,
					updated_at: '2025-01-01'
				}
			]
		});

		const result = await searchCoreRecords(client, 'org-2', '555', {
			clients: true,
			requests: false,
			quotes: false,
			jobs: false,
			invoices: false
		});

		const clientReads = calls.filter(
			({ table, method }) => table === 'clients' && method === 'select'
		);
		expect(clientReads).toHaveLength(2);
		expect(
			calls.filter(
				({ table, method, args }) =>
					table === 'clients' && method === 'eq' && args[0] === 'organization_id'
			)
		).toEqual([
			{ table: 'clients', method: 'eq', args: ['organization_id', 'org-2'] },
			{ table: 'clients', method: 'eq', args: ['organization_id', 'org-2'] }
		]);
		expect(calls.filter(({ table, method }) => table === 'clients' && method === 'limit')).toEqual([
			{ table: 'clients', method: 'limit', args: [5] },
			{ table: 'clients', method: 'limit', args: [5] }
		]);
		expect(result.clients).toHaveLength(2);
	});

	it('does not issue reads for groups without permission', async () => {
		const { client, calls } = queryClient();

		await searchCoreRecords(client, 'org-1', 'roof', {
			clients: false,
			requests: false,
			quotes: false,
			jobs: true,
			invoices: false
		});

		expect(calls.filter(({ method }) => method === 'select').map(({ table }) => table)).toEqual([
			'job_list_rows'
		]);
	});
});
