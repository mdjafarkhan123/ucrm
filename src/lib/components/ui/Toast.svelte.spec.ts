import { page } from 'vitest/browser';
import { describe, expect, it } from 'vitest';
import { render } from 'vitest-browser-svelte';
import Toast from './Toast.svelte';

describe('Toast', () => {
	it('shows a non-dismissible busy status while work is saving', async () => {
		const screen = render(Toast, {
			props: {
				title: 'Saving change…',
				loading: true,
				dismissible: false
			}
		});

		const status = page.getByRole('status');
		await expect.element(status).toHaveAttribute('aria-busy', 'true');
		await expect.element(page.getByText('Saving change…')).toBeVisible();
		expect(screen.container.querySelector('.toast__spinner')).not.toBeNull();
		await expect
			.element(page.getByRole('button', { name: 'Dismiss notification' }))
			.not.toBeInTheDocument();
	});

	it('returns to ordinary dismissible feedback after saving', async () => {
		const screen = render(Toast, {
			props: {
				variant: 'success',
				title: 'Change saved.'
			}
		});

		await expect.element(page.getByRole('status')).toHaveAttribute('aria-busy', 'false');
		await expect.element(page.getByText('Change saved.')).toBeVisible();
		expect(screen.container.querySelector('.toast__spinner')).toBeNull();
		await expect.element(page.getByRole('button', { name: 'Dismiss notification' })).toBeVisible();
	});
});
