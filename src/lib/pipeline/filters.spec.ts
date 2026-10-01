import { describe, expect, it } from 'vitest';
import {
	DEFAULT_BOARD_FILTERS,
	boardFilterKey,
	boardFilterParams,
	filtersAreDefault,
	filtersFromSavedQuery,
	savedFilterQuery,
	readBoardFilters,
	searchTerm
} from './filters';

describe('the board search term', () => {
	it('is what was typed, trimmed', () => {
		expect(searchTerm('  Ada  ')).toBe('Ada');
	});

	it('is nothing until there are two characters to search with', () => {
		expect(searchTerm('')).toBeUndefined();
		expect(searchTerm(' a ')).toBeUndefined();
		expect(searchTerm(null)).toBeUndefined();
	});

	it('is nothing when it is longer than the API will take', () => {
		expect(searchTerm('a'.repeat(101))).toBeUndefined();
	});
});

describe('search and lead source in the URL', () => {
	it('reads both back from a link', () => {
		const filters = readBoardFilters(new URLSearchParams('q=555+0102&source=Google+search'));
		expect(filters.q).toBe('555 0102');
		expect(filters.source).toBe('Google search');
	});

	it('leaves them out of an untouched board entirely', () => {
		const filters = readBoardFilters(new URLSearchParams(''));
		expect('q' in filters).toBe(false);
		expect('source' in filters).toBe(false);
		expect(filtersAreDefault(filters)).toBe(true);
		expect(boardFilterParams(filters).toString()).toBe('');
	});

	it('drops a search too short to act on rather than putting an error on screen', () => {
		expect(readBoardFilters(new URLSearchParams('q=a')).q).toBeUndefined();
	});

	it('counts either one as a filtered board', () => {
		expect(filtersAreDefault(readBoardFilters(new URLSearchParams('q=Ada')))).toBe(false);
		expect(filtersAreDefault(readBoardFilters(new URLSearchParams('source=Referral')))).toBe(false);
	});

	it('gives a searched board its own cache entry', () => {
		const plain = readBoardFilters(new URLSearchParams(''));
		const searched = readBoardFilters(new URLSearchParams('q=Ada'));
		const sourced = readBoardFilters(new URLSearchParams('source=Referral'));
		expect(boardFilterKey(searched)).not.toBe(boardFilterKey(plain));
		expect(boardFilterKey(sourced)).not.toBe(boardFilterKey(searched));
	});
});

describe('what a saved filter keeps', () => {
	it('keeps every control but the search box, in a stable order', () => {
		const query = savedFilterQuery({
			sort: 'value',
			direction: 'asc',
			owner: 'unassigned',
			date: 'last_30_days',
			source: 'Google',
			q: 'Ada'
		});
		expect(query).toBe('date=last_30_days&direction=asc&owner=unassigned&sort=value&source=Google');
	});

	it('is empty for an untouched board, so there is nothing to save', () => {
		expect(savedFilterQuery({ ...DEFAULT_BOARD_FILTERS, q: 'Ada' })).toBe('');
	});

	it('puts the board back as saved, with the search box cleared', () => {
		const filters = filtersFromSavedQuery('owner=unassigned&source=Google&q=Ada');
		expect(filters).toEqual({ ...DEFAULT_BOARD_FILTERS, owner: 'unassigned', source: 'Google' });
	});

	it('reads a saved custom range back with both ends', () => {
		const filters = filtersFromSavedQuery('date=custom&from=2026-01-01&to=2026-03-31');
		expect(filters.from).toBe('2026-01-01');
		expect(filters.to).toBe('2026-03-31');
		expect(savedFilterQuery(filters)).toBe('date=custom&from=2026-01-01&to=2026-03-31');
	});
});
