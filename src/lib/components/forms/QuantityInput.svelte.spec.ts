import { page, userEvent } from 'vitest/browser';
import { describe, expect, it } from 'vitest';
import { render } from 'vitest-browser-svelte';
import QuantityInput from './QuantityInput.svelte';

describe('approved quantity stepper', () => {
	it('stops decrementing at one and keeps decimal typing', async () => {
		render(QuantityInput, { id: 'quantity', value: 1 });
		await expect.element(page.getByRole('button', { name: 'Decrease quantity' })).toBeDisabled();
		await page.getByRole('button', { name: 'Increase quantity' }).click();
		await expect.element(page.getByRole('textbox')).toHaveValue('2');
		await page.getByRole('textbox').fill('2.5678');
		await userEvent.keyboard('{Tab}');
		await expect.element(page.getByRole('textbox')).toHaveValue('2.568');
		await page.getByRole('button', { name: 'Decrease quantity' }).click();
		await expect.element(page.getByRole('textbox')).toHaveValue('1.568');
	});
});
