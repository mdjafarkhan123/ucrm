import { describe, expect, it } from 'vitest';
import { compareInventories, type Inventory } from './migration';

function inventory(overrides: Partial<Inventory> = {}): Inventory {
	return {
		taken_at: '2026-10-10T10:00:00Z',
		summary: {
			organization: { id: 'org-1', slug: 'raad', lifecycle_status: 'active' },
			current_agreement_id: 'agreement-1',
			members: { owner: 1, field: 1 },
			customer_links: { quote: { issued: 3, usable: 2 }, invoice: { issued: 1, usable: 1 } },
			forms: { total: 2, live: 2 },
			open_areas: ['public_intake', 'customer_billing'],
			experience_path: 'experience'
		},
		tables: {
			'public.clients': { rows: 2, ids: 'c-ids', content: 'c-content' },
			'public.jobs': { rows: 4, ids: 'j-ids', content: 'j-content' }
		},
		...overrides
	};
}

describe('compareInventories', () => {
	it('says same when nothing differs', () => {
		const result = compareInventories(inventory(), inventory());
		expect(result.verdict).toBe('same');
		expect(result.records).toEqual([]);
		expect(result.facts).toEqual([]);
		expect(result.rows_before).toBe(6);
	});

	it('stops when a record is lost or replaced', () => {
		const lost = inventory({
			tables: {
				'public.clients': { rows: 1, ids: 'x', content: 'y' },
				'public.jobs': { rows: 4, ids: 'j-ids', content: 'j-content' }
			}
		});
		expect(compareInventories(inventory(), lost).records).toEqual([
			{ table: 'public.clients', kind: 'lost', before: 2, after: 1 }
		]);
		expect(compareInventories(inventory(), lost).verdict).toBe('stop');

		const replaced = inventory({
			tables: {
				'public.clients': { rows: 2, ids: 'other', content: 'c-content' },
				'public.jobs': { rows: 4, ids: 'j-ids', content: 'j-content' }
			}
		});
		expect(compareInventories(inventory(), replaced).records[0].kind).toBe('replaced');

		const vanished = inventory({
			tables: { 'public.clients': { rows: 2, ids: 'c-ids', content: 'c-content' } }
		});
		expect(compareInventories(inventory(), vanished).records[0]).toMatchObject({
			table: 'public.jobs',
			kind: 'lost'
		});
	});

	it('reports ordinary work without stopping', () => {
		const grown = inventory({
			tables: {
				'public.clients': { rows: 3, ids: 'new', content: 'new' },
				'public.jobs': { rows: 4, ids: 'j-ids', content: 'edited' },
				'public.notes': { rows: 1, ids: 'n', content: 'n' }
			}
		});
		const result = compareInventories(inventory(), grown);
		expect(result.verdict).toBe('changed');
		expect(result.records.map((change) => change.kind)).toEqual(['added', 'edited', 'added']);
	});

	it('stops when a usable customer link, a live form or an open area goes away', () => {
		const after = inventory();
		after.summary.customer_links.quote.usable = 1;
		after.summary.forms.live = 1;
		after.summary.open_areas = ['customer_billing'];
		const result = compareInventories(inventory(), after);
		expect(result.verdict).toBe('stop');
		expect(result.facts.filter((fact) => fact.stops).map((fact) => fact.fact)).toEqual([
			'Usable quote links',
			'Live forms',
			'Open areas'
		]);
	});

	it('stops when the agreement, status or team changes', () => {
		const after = inventory();
		after.summary.current_agreement_id = 'agreement-2';
		after.summary.organization = { id: 'org-1', slug: 'raad', lifecycle_status: 'suspended' };
		after.summary.members = { owner: 1 };
		const result = compareInventories(inventory(), after);
		expect(result.facts.map((fact) => fact.fact)).toEqual([
			'Account status',
			'Agreement in force',
			'Active team members'
		]);
		expect(result.verdict).toBe('stop');
	});

	it('reports a change of path without stopping', () => {
		const after = inventory();
		after.summary.experience_path = 'previous_contractor';
		const result = compareInventories(inventory(), after);
		expect(result.verdict).toBe('changed');
		expect(result.facts).toEqual([
			{ fact: 'Access path', before: 'experience', after: 'previous_contractor', stops: false }
		]);
	});
});
