import { describe, expect, it } from 'vitest';
import { encodeOutcomeCursor, readOutcomeCursor } from './outcomes-report';

describe('outcome cursor', () => {
	it('survives a round trip', () => {
		const cursor = {
			sort: 'created' as const,
			phase: 1 as const,
			value: '2026-08-19T04:00:00.000Z',
			id: '9c3f5a0e-1111-4222-8333-444455556666'
		};
		expect(readOutcomeCursor(encodeOutcomeCursor(cursor))).toEqual(cursor);
	});

	it('keeps a money value exactly as it was written', () => {
		const cursor = {
			sort: 'total' as const,
			phase: 1 as const,
			value: '15250.50',
			id: '9c3f5a0e-1111-4222-8333-444455556666'
		};
		expect(readOutcomeCursor(encodeOutcomeCursor(cursor))?.value).toBe('15250.50');
	});

	it('keeps a title with a colon or pipe in it intact', () => {
		const cursor = {
			sort: 'title' as const,
			phase: 1 as const,
			value: 'Fix: the pipe|leaked',
			id: '9c3f5a0e-1111-4222-8333-444455556666'
		};
		expect(readOutcomeCursor(encodeOutcomeCursor(cursor))).toEqual(cursor);
	});

	it('remembers which half of a Total sort it came from', () => {
		const unestimated = {
			sort: 'total' as const,
			phase: 2 as const,
			value: '',
			id: '9c3f5a0e-1111-4222-8333-444455556666'
		};
		expect(readOutcomeCursor(encodeOutcomeCursor(unestimated))?.phase).toBe(2);
	});

	it('refuses anything it did not write', () => {
		expect(readOutcomeCursor(null)).toBeNull();
		expect(readOutcomeCursor('')).toBeNull();
		expect(readOutcomeCursor('nonsense')).toBeNull();
		expect(readOutcomeCursor('value:1:abc|id')).toBeNull();
		expect(readOutcomeCursor('created:9:abc|id')).toBeNull();
		expect(readOutcomeCursor('created:1:abc|')).toBeNull();
	});
});
