import { describe, expect, it } from 'vitest';
import {
	activeDirectoryFilterCount,
	directoryFilterParams,
	directoryFiltersAreComplete,
	EMPTY_DIRECTORY_FILTERS,
	readDirectoryFilters
} from './organization-directory-filters';

const PACKAGE_ID = '123e4567-e89b-12d3-a456-426614174000';

describe('organization directory filters in the URL', () => {
	it('reads an untouched address as no filters', () => {
		expect(readDirectoryFilters(new URLSearchParams())).toEqual(EMPTY_DIRECTORY_FILTERS);
	});

	it('round-trips every filter through the address', () => {
		const filters = {
			q: 'raad',
			attention: ['payment_overdue', 'renewal_due'] as const,
			lifecycle: ['active', 'suspended'] as const,
			packages: [PACKAGE_ID, 'none'],
			billing: 'year' as const,
			renews: '14' as const,
			team: 'large' as const,
			joined: 'custom' as const,
			from: '2026-01-05',
			to: '2026-01-31'
		};
		const read = readDirectoryFilters(
			directoryFilterParams({
				...filters,
				attention: [...filters.attention],
				lifecycle: [...filters.lifecycle]
			})
		);
		// Lists come back in the vocabulary's own order, so the same choice is always the same address.
		expect(read).toEqual({
			...filters,
			attention: ['payment_overdue', 'renewal_due'],
			lifecycle: ['active', 'suspended']
		});
	});

	it('leaves anything at rest out of the address', () => {
		expect(directoryFilterParams(EMPTY_DIRECTORY_FILTERS).toString()).toBe('');
	});

	it('falls back to no filter for whatever a stale or edited link got wrong', () => {
		const read = readDirectoryFilters(
			new URLSearchParams(
				`lifecycle=active,gone&billing=weekly&renews=90&team=huge&package=starter,${PACKAGE_ID}&joined=custom&from=bad&to=2026-02-01`
			)
		);
		expect(read.lifecycle).toEqual(['active']);
		expect(read.billing).toBe('');
		expect(read.renews).toBe('');
		expect(read.team).toBe('');
		expect(read.packages).toEqual([PACKAGE_ID]);
		expect(read.from).toBe('');
		expect(read.to).toBe('2026-02-01');
	});

	it('drops a date range once the joined choice is not custom', () => {
		const read = readDirectoryFilters(new URLSearchParams('joined=30&from=2026-01-01'));
		expect(read.joined).toBe('30');
		expect(read.from).toBe('');
	});

	it('does not ask the server about a custom range with no dates', () => {
		expect(directoryFiltersAreComplete({ ...EMPTY_DIRECTORY_FILTERS, joined: 'custom' })).toBe(
			false
		);
		expect(
			directoryFiltersAreComplete({
				...EMPTY_DIRECTORY_FILTERS,
				joined: 'custom',
				to: '2026-01-31'
			})
		).toBe(true);
	});

	it('counts the filters narrowing the list, leaving the search box out', () => {
		expect(activeDirectoryFilterCount({ ...EMPTY_DIRECTORY_FILTERS, q: 'raad' })).toBe(0);
		expect(
			activeDirectoryFilterCount({
				...EMPTY_DIRECTORY_FILTERS,
				attention: ['payment_overdue', 'renewal_due'],
				billing: 'month'
			})
		).toBe(2);
	});
});
