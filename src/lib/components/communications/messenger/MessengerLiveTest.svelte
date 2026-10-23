<script lang="ts">
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import MessengerMark from './MessengerMark.svelte';
	import {
		fetchMessengerTestArrival,
		messengerOverviewKey,
		messengerTestKey,
		type MessengerConnection
	} from '$lib/communications/messenger-settings';
	import accessPointIcon from '@tabler/icons/outline/access-point.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	// The live test (board `tEAXY`): listens while the business messages its own Page from a personal Facebook
	// account, and ticks off the moment the message reaches Conversations. Only messages sent after the test began
	// count, so an old conversation never passes for a working connection.
	let {
		connections,
		connectionId,
		since,
		onPick
	}: {
		connections: MessengerConnection[];
		connectionId: string;
		/** When this test began. */
		since: string;
		/** Choosing another Page starts a new test for it. */
		onPick: (connectionId: string) => void;
	} = $props();

	const queryClient = useQueryClient();
	const selected = $derived(connections.find((connection) => connection.id === connectionId));
	const options = $derived(
		connections.map((connection) => ({ value: connection.id, label: connection.page_name }))
	);

	const testQuery = createQuery(() => ({
		queryKey: messengerTestKey(connectionId, since),
		queryFn: () => fetchMessengerTestArrival(connectionId, since),
		enabled: Boolean(selected),
		refetchInterval: (query) => (query.state.data?.arrived ? false : 3_000),
		refetchIntervalInBackground: false
	}));

	const arrived = $derived(testQuery.data?.arrived ?? null);
	const timeFormat = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });

	// The Page's row turns to Receiving as soon as its first message lands.
	$effect(() => {
		if (arrived) void queryClient.invalidateQueries({ queryKey: messengerOverviewKey });
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -- trusted build-time Tabler icons -->
<section class="live-test" aria-labelledby="messenger-live-test-title">
	<div class="live-test__header">
		<IconTile icon={accessPointIcon} tone="informative" size={32} />
		<h2 id="messenger-live-test-title" class="live-test__title">Live test</h2>
		{#if arrived}
			<StatusBadge status="success">Arrived</StatusBadge>
		{:else}
			<StatusBadge status="informative">Listening</StatusBadge>
		{/if}
	</div>

	<Select
		id="messenger-live-test-page"
		label="Page to test"
		{options}
		value={connectionId}
		onchange={onPick}
	/>

	<div class="live-test__chat" aria-live="polite">
		<div class="live-test__chat-head">
			<MessengerMark size={20} />
			<span>You, messaging {selected?.page_name ?? 'your Page'}</span>
		</div>
		<div class="live-test__bubble-row">
			<span class="live-test__bubble">Hi, testing</span>
		</div>
		{#if arrived}
			<div class="live-test__arrived">
				<span class="live-test__tick" aria-hidden="true">{@html checkIcon}</span>
				Arrived {timeFormat.format(new Date(arrived.at))}
				{arrived.new_lead ? 'as a new lead' : `from ${arrived.client_name}`}
			</div>
		{:else}
			<div class="live-test__waiting">
				<span class="live-test__dots" aria-hidden="true"><i></i><i></i><i></i></span>
				Waiting for it to arrive…
			</div>
		{/if}
	</div>

	{#if arrived}
		<p class="live-test__how">It works. New messages to this Page now arrive in Conversations.</p>
		<Button
			variant="secondary"
			fullWidth
			href={`${resolve('/(app)/communications')}?client=${arrived.client_id}`}
		>
			<span aria-hidden="true">{@html inboxIcon}</span>
			Open the conversation
		</Button>
	{:else}
		<p class="live-test__how">
			Open Messenger with your own Facebook account, not the Page's, and send any message to the
			Page above. It ticks off here within seconds.
		</p>
		<Button
			variant="secondary"
			fullWidth
			href={selected ? `https://m.me/${selected.page_id}` : undefined}
			target="_blank"
			disabled={!selected}
		>
			<span aria-hidden="true">{@html externalLinkIcon}</span>
			Open Messenger
		</Button>
	{/if}
</section>

<style lang="scss">
	.live-test {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-medium);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__header {
			display: flex;
			align-items: center;
			gap: 10px;
		}
		&__title {
			flex: 1;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}
		&__chat {
			display: grid;
			gap: 10px;
			padding: var(--space-base);
			border-radius: var(--radius-tile-large);
			background: var(--color-surface--background--subtle);
		}
		&__chat-head {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
		}
		&__bubble-row {
			display: flex;
			justify-content: flex-end;
		}
		&__bubble {
			padding: var(--space-small) var(--space-slim);
			border-radius: var(--space-base) var(--space-base) var(--space-smaller) var(--space-base);
			color: var(--color-white);
			background: var(--color-messenger);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
		&__waiting,
		&__arrived {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding-top: 6px;
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}
		&__waiting {
			color: var(--color-text--secondary);
		}
		&__arrived {
			color: var(--color-success--onSurface);
			font-weight: 600;
		}
		&__tick {
			display: grid;
			place-items: center;
			width: 20px;
			height: 20px;
			border: 1px solid var(--color-success--surface-edge);
			border-radius: var(--radius-circle);
			color: var(--color-success);
			background: var(--color-success--surface);

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}
		&__dots {
			display: inline-flex;
			gap: var(--space-small);

			i {
				width: 6px;
				height: 6px;
				border-radius: var(--radius-circle);
				background: var(--color-border--interactive);
				animation: live-test-dot 1.2s infinite ease-in-out;
			}
			i:nth-child(2) {
				animation-delay: 0.2s;
			}
			i:nth-child(3) {
				animation-delay: 0.4s;
			}
		}
		&__how {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			line-height: var(--typography--lineHeight-large);
		}
	}

	@keyframes live-test-dot {
		0%,
		60%,
		100% {
			background: var(--color-border--interactive);
		}
		30% {
			background: var(--color-informative);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.live-test__dots i {
			animation: none;
		}
		.live-test__dots i:first-child {
			background: var(--color-informative);
		}
	}
</style>
