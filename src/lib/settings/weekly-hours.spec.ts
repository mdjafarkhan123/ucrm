import { describe, expect, it } from 'vitest';
import { timeFromString } from '$lib/components/ui/date-time';
import { blockLabel, dayBlocks } from './weekly-hours';

const period = (start?: string, end?: string) => ({
	start: start ? timeFromString(start) : undefined,
	end: end ? timeFromString(end) : undefined
});

describe('blockLabel', () => {
	it('spells a long day out in full', () => {
		expect(blockLabel(8 * 60, 17 * 60)).toBe('8:00 AM – 5:00 PM');
	});
	it('shortens a block within one half of the day', () => {
		expect(blockLabel(7 * 60, 11 * 60)).toBe('7–11 AM');
		expect(blockLabel(13 * 60, 17 * 60)).toBe('1–5 PM');
	});
	it('names both halves when a short block crosses noon', () => {
		expect(blockLabel(8 * 60, 12 * 60)).toBe('8 AM–12 PM');
	});
	it('keeps minutes that are not on the hour', () => {
		expect(blockLabel(7 * 60 + 30, 11 * 60)).toBe('7:30–11 AM');
	});
});

describe('dayBlocks', () => {
	it('draws nothing on a closed day', () => {
		expect(dayBlocks({ isOpen: false, is24h: false, periods: [] })).toEqual([]);
	});
	it('fills the bar for 24 hours', () => {
		expect(dayBlocks({ isOpen: true, is24h: true, periods: [] })).toEqual([
			{ left: 0, width: 100, label: 'Open 24 hours' }
		]);
	});
	it('places each valid period and skips one still being typed or ending first', () => {
		const blocks = dayBlocks({
			isOpen: true,
			is24h: false,
			periods: [period('06:00', '12:00'), period('13:00'), period('17:00', '09:00')]
		});
		expect(blocks).toEqual([{ left: 25, width: 25, label: '6:00 AM – 12:00 PM' }]);
	});
});
