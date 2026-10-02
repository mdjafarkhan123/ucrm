import { page } from 'vitest/browser';
import { describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import OpportunityContactActions from './OpportunityContactActions.svelte';

// The three quick actions on a card's Brief. Each shows only when it can work, and Call never claims a call
// happened -- it only tells the Brief to offer the "How did it go?" bar.

const email = { id: 'm1', kind: 'email' as const, value: 'sam@example.test', is_primary: true };
const phone = { id: 'm2', kind: 'phone' as const, value: '+15550100', is_primary: true };

function renderActions(props: Partial<Record<string, unknown>> = {}) {
	return render(OpportunityContactActions, {
		props: {
			clientId: 'client-1',
			clientName: 'Sam Rivera',
			contacts: [email, phone],
			canMessage: true,
			onCall: vi.fn(),
			...props
		} as never
	});
}

describe('OpportunityContactActions', () => {
	it('shows Email, Text and Call when the client has both details and the member may message', async () => {
		renderActions();

		await expect.element(page.getByRole('link', { name: 'Email' })).toBeVisible();
		await expect.element(page.getByRole('link', { name: 'Text' })).toBeVisible();
		await expect.element(page.getByRole('button', { name: 'Call' })).toBeVisible();
	});

	it('shows no Text or Call for a client with no phone', async () => {
		renderActions({ contacts: [email] });

		await expect.element(page.getByRole('link', { name: 'Email' })).toBeVisible();
		await expect.element(page.getByRole('link', { name: 'Text' })).not.toBeInTheDocument();
		await expect.element(page.getByRole('button', { name: 'Call' })).not.toBeInTheDocument();
	});

	it('shows no Email for a client with no email address', async () => {
		renderActions({ contacts: [phone] });

		await expect.element(page.getByRole('link', { name: 'Email' })).not.toBeInTheDocument();
		await expect.element(page.getByRole('link', { name: 'Text' })).toBeVisible();
	});

	it('hides Email and Text, but not Call, from a member who may not message', async () => {
		renderActions({ canMessage: false });

		await expect.element(page.getByRole('link', { name: 'Email' })).not.toBeInTheDocument();
		await expect.element(page.getByRole('link', { name: 'Text' })).not.toBeInTheDocument();
		await expect.element(page.getByRole('button', { name: 'Call' })).toBeVisible();
	});

	it('shows nothing for a client with no contact details at all', async () => {
		renderActions({ contacts: [] });

		await expect.element(page.getByRole('group')).not.toBeInTheDocument();
	});

	it('opens a chooser when the client has several numbers, and offers the bar only after one is picked', async () => {
		const onCall = vi.fn();
		const second = { id: 'm3', kind: 'phone' as const, value: '+15550111', is_primary: false };
		renderActions({ contacts: [email, phone, second], onCall });

		await page.getByRole('button', { name: 'Call Sam Rivera' }).click();
		expect(onCall).not.toHaveBeenCalled();
		await expect.element(page.getByRole('menuitem', { name: /\+15550100/ })).toBeVisible();
		await expect.element(page.getByRole('menuitem', { name: /\+15550111/ })).toBeVisible();
	});
});
