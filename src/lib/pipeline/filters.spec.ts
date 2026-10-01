import { describe, expect, it } from 'vitest';
import {
	boardFilterKey,
	boardFilterParams,
	filtersAreDefault,
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
