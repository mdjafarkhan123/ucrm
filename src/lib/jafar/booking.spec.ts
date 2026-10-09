import { describe, expect, it } from 'vitest';
import {
	dayKey,
	lengthWords,
	noticeWords,
	slotsByDay,
	slugify,
	timeWords,
	zoneCity
} from './booking';

describe('booking words', () => {
	it('names lengths and notice the way a person says them', () => {
		expect(lengthWords(30)).toBe('30 min');
		expect(lengthWords(60)).toBe('1 hr');
		expect(lengthWords(90)).toBe('1 hr 30 min');
		expect(noticeWords(0)).toBe('No notice');
		expect(noticeWords(240)).toBe('4 hours');
		expect(noticeWords(1440)).toBe('1 day');
		expect(noticeWords(10080)).toBe('1 week');
	});

	it('makes a link ending from any name', () => {
		expect(slugify('Discovery Call!')).toBe('discovery-call');
		expect(slugify('  Café  Chat  ')).toBe('cafe-chat');
		expect(slugify('a'.repeat(70))).toHaveLength(60);
	});

	it('shows a zone by its city', () => {
		expect(zoneCity('Asia/Dhaka')).toBe('Dhaka');
		expect(zoneCity('America/Argentina/Buenos_Aires')).toBe('Buenos Aires');
	});
});

describe('times in the visitor zone', () => {
	// 3pm in Dhaka is 9am UTC and 5am in New York, the same day; 1am in Dhaka is the evening before in London.
	it('puts each time on the day it falls in that zone', () => {
		expect(dayKey('2026-10-14T09:00:00Z', 'Asia/Dhaka')).toBe('2026-10-14');
		expect(dayKey('2026-10-13T19:00:00Z', 'Asia/Dhaka')).toBe('2026-10-14');
		expect(dayKey('2026-10-13T19:00:00Z', 'Europe/London')).toBe('2026-10-13');
		expect(timeWords('2026-10-14T09:00:00Z', 'Asia/Dhaka', 'en-US')).toBe('3:00 PM');
	});

	it('groups open times by day, in order', () => {
		const slots = [
			{ starts_at: '2026-10-13T19:00:00Z', ends_at: '2026-10-13T19:30:00Z' },
			{ starts_at: '2026-10-14T09:00:00Z', ends_at: '2026-10-14T09:30:00Z' },
			{ starts_at: '2026-10-15T09:00:00Z', ends_at: '2026-10-15T09:30:00Z' }
		];
		const days = slotsByDay(slots, 'Asia/Dhaka');
		expect([...days.keys()]).toEqual(['2026-10-14', '2026-10-15']);
		expect(days.get('2026-10-14')?.map((slot) => slot.starts_at)).toEqual([
			'2026-10-13T19:00:00Z',
			'2026-10-14T09:00:00Z'
		]);
	});
});
