import { page, userEvent } from 'vitest/browser';
import { describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import CountryPicker from './CountryPicker.svelte';

describe('CountryPicker', () => {
	it('finds a country by an everyday name and saves its code', async () => {
		const onchange = vi.fn();
		render(CountryPicker, { props: { id: 'country', label: 'Country', onchange } });

		const input = page.getByLabelText('Country');
		await input.click();
		await userEvent.keyboard('uk');
		await expect.element(page.getByRole('option').first()).toHaveTextContent('United Kingdom');
		await userEvent.keyboard('{Enter}');

		expect(onchange).toHaveBeenCalledWith('GB');
		await expect.element(input).toHaveValue('United Kingdom');
	});

	it('shows the saved country and the whole list when reopened', async () => {
		render(CountryPicker, { props: { id: 'country', label: 'Country', value: 'PK' } });

		const input = page.getByLabelText('Country');
		await expect.element(input).toHaveValue('Pakistan');
		await input.click();
		await expect
			.poll(() => document.querySelectorAll('[role="option"]').length)
			.toBeGreaterThan(240);
	});

	it('says so when nothing matches', async () => {
		render(CountryPicker, { props: { id: 'country', label: 'Country' } });

		await page.getByLabelText('Country').click();
		await userEvent.keyboard('zzqx');
		await expect.element(page.getByText('No countries match “zzqx”.')).toBeVisible();
	});

	it('lets arrow keys pick a match below the top one', async () => {
		const onchange = vi.fn();
		render(CountryPicker, { props: { id: 'country', label: 'Country', onchange } });

		await page.getByLabelText('Country').click();
		await userEvent.keyboard('ger');
		await expect.element(page.getByRole('option').first()).toHaveTextContent('Germany');
		await userEvent.keyboard('{ArrowDown}{Enter}');

		expect(onchange).toHaveBeenCalledTimes(1);
		expect(onchange.mock.calls[0][0]).not.toBe('DE');
	});
});
