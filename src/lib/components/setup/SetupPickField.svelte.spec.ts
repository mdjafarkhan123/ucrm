import { page } from 'vitest/browser';
import { describe, expect, it } from 'vitest';
import { render } from 'vitest-browser-svelte';
import Harness from './SetupPickField.harness.svelte';

// Client onboarding A5f: a client picks from the services they already listed and puts them in order
// (docs/client-onboarding-delivery-behavior-contract.md §2.1).

const rows = ['Boiler repair', 'Leak repair', 'Bathroom fitting'].map((name, index) => ({
	id: `row${index}`,
	values: { name }
}));

const saved = () =>
	JSON.parse(document.querySelector('[data-testid="value"]')?.textContent || '[]') as string[];

describe('SetupPickField', () => {
	it('lists only the entries the client added, and saves the picks in list order', async () => {
		render(Harness, { props: { rows } });
		await expect.element(page.getByText('Pick at least 2.')).toBeVisible();
		await page.getByText('Bathroom fitting').click();
		await page.getByText('Boiler repair').click();
		expect(saved()).toEqual(['row0', 'row2']);
		await page.getByText('Bathroom fitting').click();
		expect(saved()).toEqual(['row0']);
	});

	it('puts picks in the order ticked, and moves one up with the button keeping focus on it', async () => {
		render(Harness, { props: { rows, ordered: true } });
		await page.getByText('Leak repair').click();
		await page.getByText('Boiler repair').click();
		expect(saved()).toEqual(['row1', 'row0']);
		await expect.element(page.getByText('Your order')).toBeVisible();

		const up = page.getByRole('button', { name: 'Move Boiler repair up' });
		await up.click();
		expect(saved()).toEqual(['row0', 'row1']);
		// At the top, its Up button is off, so the cursor moves to its Down button.
		await expect
			.element(page.getByRole('button', { name: 'Move Boiler repair down' }))
			.toHaveFocus();
	});

	it('stops further ticks at the most, and drops a pick its list no longer holds', async () => {
		render(Harness, {
			props: { rows, maxChoices: 1, value: JSON.stringify(['gone', 'row2']) }
		});
		await expect.element(page.getByRole('checkbox', { name: 'Bathroom fitting' })).toBeChecked();
		await expect.element(page.getByRole('checkbox', { name: 'Boiler repair' })).toBeDisabled();
	});
});
