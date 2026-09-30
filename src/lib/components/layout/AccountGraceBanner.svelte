<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import { PLATFORM_CONTACT_EMAIL, formatCalendarDay } from '$lib/account/standing';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// Shown to owners and admins during the seven-day grace week after the last covered day. It stays until
	// payment is confirmed — there is nothing to dismiss, because the pause is still coming.
	let { lastAccessDay }: { lastAccessDay: string } = $props();

	const day = $derived(formatCalendarDay(lastAccessDay));
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="grace-banner" role="status">
	<span class="grace-banner__icon" aria-hidden="true">{@html alertIcon}</span>
	<p class="grace-banner__message">
		Payment is overdue. Your team keeps full access through <strong>{day}</strong>, then the account
		pauses until payment is confirmed.
	</p>
	<Button
		variant="secondary"
		variation="subtle"
		size="small"
		href={`mailto:${PLATFORM_CONTACT_EMAIL}?subject=${encodeURIComponent('Account payment')}`}
		class="grace-banner__action">Contact us to pay</Button
	>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.grace-banner {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin-block-start: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
	}
	.grace-banner__icon {
		display: inline-flex;
		flex: 0 0 auto;
		padding: var(--space-smaller);
		border-radius: var(--radius-circle);
		background: var(--color-warning);
		color: var(--color-surface);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
	.grace-banner__message {
		flex: 1;
		margin: 0;
		font-size: var(--typography--fontSize-base);
	}
	.grace-banner :global(.grace-banner__action) {
		flex: 0 0 auto;
	}
	@media (max-width: 767px) {
		.grace-banner {
			flex-wrap: wrap;
			margin-inline-end: var(--space-base);
		}
	}
</style>
