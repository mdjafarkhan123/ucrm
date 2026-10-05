import { page } from 'vitest/browser';
import { describe, expect, it } from 'vitest';
import { render } from 'vitest-browser-svelte';
import Harness from './SetupReuseField.harness.svelte';

// Client onboarding A5g: a client confirms an answer they already gave, or gives a different one for this
// question only (docs/client-onboarding-delivery-behavior-contract.md §2.1).

const saved = () => document.querySelector('[data-testid="value"]')?.textContent ?? '';
const reuse = {
	lines: ['01632 960123'],
	where: 'You told us in Your business',
	href: '/setup/business'
};

describe('a reuse question', () => {
	it('shows the earlier answer and saves "Yes, use this" as the same answer, not a copy', async () => {
		render(Harness, { props: { reuse } });
		await expect.element(page.getByText('You told us in Your business')).toBeVisible();
		await expect.element(page.getByText('01632 960123')).toBeVisible();
		await expect
			.element(page.getByRole('link', { name: 'Change' }))
			.toHaveAttribute('href', '/setup/business');
		await page.getByText('Yes, use this').click();
		expect(JSON.parse(saved())).toEqual({ same_as: 'business.public_phone' });
		await expect.element(page.getByRole('textbox')).not.toBeInTheDocument();
	});

	it('opens a box of its own for a different answer', async () => {
		render(Harness, { props: { reuse } });
		await page.getByText('Yes, use this').click();
		await page.getByText('Use a different one here').click();
		expect(saved()).toBe('');
		const box = page.getByRole('textbox', { name: 'Which phone should the website show?' });
		await box.fill('01632 960999');
		expect(saved()).toBe('01632 960999');
		await expect
			.element(page.getByRole('radio', { name: 'Use a different one here' }))
			.toBeChecked();
	});

	it('is a plain question when there is nothing to reuse', async () => {
		render(Harness, { props: { reuse: null } });
		await expect.element(page.getByText('Yes, use this')).not.toBeInTheDocument();
		await expect
			.element(page.getByRole('textbox', { name: 'Which phone should the website show?' }))
			.toBeVisible();
	});
});
