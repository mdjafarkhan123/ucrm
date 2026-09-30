<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import { PLATFORM_CONTACT_EMAIL, type AccountStanding } from '$lib/account/standing';
	import pauseIcon from '@tabler/icons/outline/player-pause.svg?raw';

	// Replaces the whole workspace while the organization is paused. Owners and admins learn whether it is
	// about payment and whom to contact; other staff are sent to their business owner (package plan, Jafar
	// 2026-09-30). Every record is kept, so each message says so.
	let { standing }: { standing: Extract<AccountStanding, { state: 'paused' }> } = $props();

	const queryClient = useQueryClient();
	let isSigningOut = $state(false);
	let signOutError = $state('');

	const contactHref = `mailto:${PLATFORM_CONTACT_EMAIL}?subject=${encodeURIComponent('Restore account access')}`;

	async function signOut() {
		isSigningOut = true;
		signOutError = '';
		try {
			const response = await fetch('/api/auth/session', { method: 'DELETE' });
			if (!response.ok) throw new Error('Sign out request failed.');
			queryClient.clear();
			await goto(resolve('/login'));
		} catch (error) {
			console.error('Could not sign out.', error);
			signOutError = 'Could not sign out. Please try again.';
		} finally {
			isSigningOut = false;
		}
	}
</script>

<svelte:head><title>Account paused · Contractor CRM</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="paused-account">
	<section class="paused-account__card" aria-labelledby="paused-account-title">
		<span class="paused-account__icon" aria-hidden="true">{@html pauseIcon}</span>
		<p class="paused-account__business">{standing.organization_name}</p>
		<h1 id="paused-account-title">
			{standing.reason === 'payment' ? 'Your account is paused' : 'This account is paused'}
		</h1>
		{#if standing.reason === 'payment'}
			<p>
				Payment is overdue, so access is paused for everyone on your team. Nothing has been deleted.
				Your clients, jobs, and invoices come back as soon as payment is confirmed.
			</p>
		{:else if standing.can_manage}
			<p>
				Access is paused for everyone on your team. Nothing has been deleted. Contact us to find out
				why and to restore access.
			</p>
		{:else}
			<p>
				Access to your business's account is paused. Nothing has been deleted. Please speak to your
				business owner.
			</p>
		{/if}
		<div class="paused-account__actions">
			{#if standing.can_manage}
				<Button href={contactHref}>
					{standing.reason === 'payment' ? 'Contact us to pay' : 'Contact us'}
				</Button>
			{/if}
			<Button variant="secondary" loading={isSigningOut} onclick={() => void signOut()}>
				Sign out
			</Button>
		</div>
		{#if signOutError}<p class="paused-account__error" role="alert">{signOutError}</p>{/if}
	</section>
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.paused-account {
		display: grid;
		place-items: center;
		min-height: 100dvh;
		padding: var(--space-base);
		background: var(--color-surface--background);
	}
	.paused-account__card {
		display: grid;
		justify-items: center;
		gap: var(--space-small);
		width: 100%;
		max-width: 480px;
		padding: var(--space-extravagant) var(--space-larger);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-larger);
		background: var(--color-surface);
		text-align: center;

		h1 {
			margin: 0;
			font-size: var(--typography--fontSize-larger);
			color: var(--color-heading);
		}
		p {
			margin: 0;
			color: var(--color-text--secondary);
		}
	}
	.paused-account__icon {
		display: inline-flex;
		margin-block-end: var(--space-small);
		padding: var(--space-slim);
		border-radius: var(--radius-circle);
		background: var(--color-warning--surface);
		color: var(--color-warning--onSurface);

		:global(svg) {
			width: 28px;
			height: 28px;
		}
	}
	.paused-account__card .paused-account__business {
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		color: var(--color-text);
	}
	.paused-account__actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-small);
		margin-block-start: var(--space-base);
	}
	.paused-account__card .paused-account__error {
		color: var(--color-critical);
	}
	@media (max-width: 767px) {
		.paused-account__card {
			padding: var(--space-larger) var(--space-base);
		}
	}
</style>
