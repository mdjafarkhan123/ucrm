import { describe, expect, it } from 'vitest';
import { tagColors, nextTagColor, tagColor } from './tag-colors';
import { tagColorUpdateSchema } from '../server/validation/collaboration.schema';
describe('tag colour palette', () => {
	it('chooses the next unused saved colour and falls back when all ten are used', () => {
		expect(nextTagColor([{ color: tagColors[0].hex }])).toEqual(tagColors[1]);
		expect(nextTagColor(tagColors.map((color) => ({ color: color.hex })))).toEqual(tagColors[0]);
	});
	it('maps saved colours to theme tokens and rejects arbitrary colours', () => {
		expect(tagColor('#556ACB').token).toBe('time');
		expect(tagColor(null).token).toBe('inactive');
		expect(tagColorUpdateSchema.safeParse({ color: '#123456' }).success).toBe(false);
		expect(tagColorUpdateSchema.safeParse({}).success).toBe(false);
		expect(tagColorUpdateSchema.safeParse({ color: '#556ACB' }).success).toBe(true);
	});
});
