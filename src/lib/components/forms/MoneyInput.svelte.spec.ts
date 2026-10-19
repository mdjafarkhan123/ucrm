import { page, userEvent } from 'vitest/browser';
import { describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import MoneyInput from './MoneyInput.svelte';
vi.mock('$app/state', () => ({ page: { data: { currencyCode: 'GBP' } } }));
describe('approved money field', () => {
	it('uses the business currency, removes commas for typing, and restores invalid amounts', async () => {
		render(MoneyInput, { id: 'amount', label: 'Amount', value: 125000 });
		await expect.element(page.getByText('£', { exact: true })).toBeVisible();
		await expect.element(page.getByRole('textbox')).toHaveValue('1,250.00');
		await page.getByRole('textbox').click();
		await expect.element(page.getByRole('textbox')).toHaveValue('1250.00');
		await page.getByRole('textbox').fill('12345.678');
		await userEvent.keyboard('{Tab}');
		await expect.element(page.getByRole('textbox')).toHaveValue('12,345.68');
		await page.getByRole('textbox').fill('-2');
		await userEvent.keyboard('{Tab}');
		await expect.element(page.getByRole('textbox')).toHaveValue('12,345.68');
	});
});
