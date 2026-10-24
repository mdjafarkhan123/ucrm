import { page } from 'vitest/browser';
import { describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { today, getLocalTimeZone, getDayOfWeek } from '@internationalized/date';
import CalendarPicker from './CalendarPicker.svelte';

describe('CalendarPicker quick dates', () => {
	it('uses the next business week-start, including when today is the week-start', async () => {
		const current = today(getLocalTimeZone());
		const onchange = vi.fn();
		render(CalendarPicker, {
			props: { id: 'date', label: 'Date', weekStartsOn: getDayOfWeek(current, 'en-US') as 0 | 1 | 2 | 3 | 4 | 5 | 6, onchange }
		});
		await page.getByRole('button', { name: 'Open date calendar' }).click();
		await page.getByRole('button', { name: 'Next week', exact: true }).click();
		expect(onchange.mock.calls[0][0].toString()).toBe(current.add({ days: 7 }).toString());
	});
	it('keeps quick dates within caller limits and custom validation', async () => {
		const current = today(getLocalTimeZone());
		render(CalendarPicker, {
			props: {
				id: 'date',
				minValue: current.add({ days: 1 }),
				validate: (date) =>
					date.compare(current.add({ days: 1 })) === 0 ? 'Unavailable' : undefined
			}
		});
		await page.getByRole('button', { name: 'Open date calendar' }).click();
		await expect.element(page.getByRole('button', { name: 'Today', exact: true })).toBeDisabled();
		await expect
			.element(page.getByRole('button', { name: 'Tomorrow', exact: true }))
			.toBeDisabled();
	});
});
