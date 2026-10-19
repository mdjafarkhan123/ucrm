import { page } from 'vitest/browser';
import { describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import TagSelect from './TagSelect.svelte';

describe('saved-colour tag picker', () => {
	it('shows saved colours but hides colour editing and creation from pick-only people', async () => {
		render(TagSelect, {
			searchId: 'pick-tags',
			catalog: [{ id: 'one', name: 'A very long customer tag name', color: '#556acb' }],
			tagIds: ['one']
		});
		await page.getByRole('button', { name: 'Add tag', exact: true }).click();
		await expect
			.element(
				page.getByRole('button', { name: 'Change colour for A very long customer tag name' })
			)
			.not.toBeInTheDocument();
		await page.getByRole('searchbox').fill('Snow');
		await expect.element(page.getByText('No matching tags.', { exact: true })).toBeVisible();
		await expect
			.element(page.getByRole('button', { name: 'Create tag “Snow”' }))
			.not.toBeInTheDocument();
	});
	it('shows loading while creating and passes the chosen palette colour', async () => {
		let finish!: (tag: { id: string; name: string; color: string }) => void;
		const onCreate = vi.fn(
			() =>
				new Promise<{ id: string; name: string; color: string }>((resolve) => (finish = resolve))
		);
		render(TagSelect, { searchId: 'create-tags', catalog: [], onCreate });
		await page.getByRole('button', { name: 'Add tag', exact: true }).click();
		await page.getByRole('searchbox').fill('Snow');
		await page.getByRole('button', { name: 'Indigo', exact: true }).click();
		await page.getByRole('button', { name: 'Create tag “Snow”' }).click();
		await expect.element(page.getByRole('button', { name: 'Create tag “Snow”' })).toBeDisabled();
		expect(onCreate).toHaveBeenCalledExactlyOnceWith('Snow', '#556acb');
		finish({ id: 'snow', name: 'Snow', color: '#556acb' });
	});
});
