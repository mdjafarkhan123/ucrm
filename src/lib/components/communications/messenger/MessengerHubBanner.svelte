<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import MessengerMark from './MessengerMark.svelte';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	// The green banner at the top of Settings → Messenger (board `tEAXY`): whether Messenger is on, for how many
	// Pages, anything that needs the business, and which Facebook account connected them.
	let {
		pageCount,
		needsYou,
		newThisWeek,
		facebookUserName,
		loggingIn,
		onConnect
	}: {
		pageCount: number;
		needsYou: number;
		newThisWeek: number;
		facebookUserName: string | null;
		loggingIn: boolean;
		onConnect: () => void;
	} = $props();

	const initials = $derived(
		(facebookUserName ?? '')
			.split(/\s+/)
			.filter(Boolean)
			.slice(0, 2)
			.map((part) => part[0]?.toUpperCase())
			.join('')
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -- trusted build-time Tabler icons -->
<section class="messenger-hub" aria-label="Messenger">
	<MessengerMark size={56} />
	<div class="messenger-hub__text">
		<div class="messenger-hub__title-line">
			<h2 class="messenger-hub__title">
				Messenger is on for {pageCount}
				{pageCount === 1 ? 'Page' : 'Pages'}
			</h2>
			{#if needsYou > 0}
				<span class="messenger-hub__needs">
					<span class="messenger-hub__dot" aria-hidden="true"></span>
					{needsYou} needs you
				</span>
			{/if}
		</div>
		<p class="messenger-hub__line">
			Customers' Facebook messages land in Conversations next to texts and emails.
			{newThisWeek === 0
				? 'No new conversations this week yet.'
				: `${newThisWeek} new ${newThisWeek === 1 ? 'conversation' : 'conversations'} this week.`}
		</p>
		{#if facebookUserName}
			<div class="messenger-hub__account">
				<span class="messenger-hub__avatar" aria-hidden="true">{initials}</span>
				<span>Logged in to Facebook as {facebookUserName}</span>
				<button
					type="button"
					class="messenger-hub__switch"
					disabled={loggingIn}
					onclick={onConnect}
				>
					· Switch account
				</button>
			</div>
		{/if}
	</div>
	<Button variant="secondary" loading={loggingIn} onclick={onConnect}>
		<span aria-hidden="true">{@html plusIcon}</span>
		Connect a Page
	</Button>
</section>

<style lang="scss">
	.messenger-hub {
		display: flex;
		align-items: center;
		gap: var(--space-large);
		padding: var(--space-large) var(--space-larger) var(--space-large) var(--space-large);
		border-radius: var(--radius-large);
		color: var(--color-feature--text);
		background:
			radial-gradient(
				90% 220% at 85% 0%,
				var(--color-feature--glow),
				var(--color-feature--glow-end)
			),
			linear-gradient(200deg, var(--color-feature--start), var(--color-feature--end));

		&__text {
			display: grid;
			flex: 1;
			min-width: 0;
			gap: 6px;
		}
		&__title-line {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: 10px;
		}
		&__title {
			color: var(--color-feature--text);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			line-height: 1.2;
		}
		&__needs {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			padding: 4px 10px;
			border-radius: var(--radius-circle);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
		}
		&__dot {
			width: 6px;
			height: 6px;
			border-radius: var(--radius-circle);
			background: var(--color-critical);
		}
		&__line {
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			line-height: var(--typography--lineHeight-large);
		}
		&__account {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			padding-top: var(--space-smaller);
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}
		&__avatar {
			display: grid;
			place-items: center;
			width: 22px;
			height: 22px;
			border-radius: var(--radius-circle);
			color: var(--color-feature--text);
			background: var(--color-feature--subtle);
			font-size: var(--typography--fontSize-overline);
			font-weight: 700;
		}
		&__switch {
			padding: 0;
			border: 0;
			border-radius: var(--radius-small);
			color: var(--color-feature--text);
			background: none;
			font: inherit;
			font-weight: 600;
			cursor: pointer;

			&:hover:not(:disabled) {
				text-decoration: underline;
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			&:disabled {
				cursor: default;
				opacity: 0.6;
			}
		}
	}
</style>
