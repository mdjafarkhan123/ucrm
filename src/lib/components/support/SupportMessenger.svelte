<script lang="ts">
	import { tick } from 'svelte';
	import { createQuery, keepPreviousData, useQueryClient } from '@tanstack/svelte-query';
	import SupportConversation from './SupportConversation.svelte';
	import {
		SUPPORT_MAX_LOADED,
		SUPPORT_OPEN_REFRESH_MS,
		SUPPORT_PAGE_SIZE,
		fetchSupportThread,
		sendSupportMessage,
		supportThreadKey,
		supportThreadPageKey,
		type SupportThread
	} from '$lib/support/api';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	// The Uplift Support Messenger: a "Chat with Uplift" button in the bottom-right corner of every signed-in
	// screen, opening the person's own conversation with Uplift (plan §7; Intercom / Help Scout messenger
	// model). It is contractor-to-Uplift only and shares nothing with the customer inbox.
	//
	// Closed, it asks the server nothing: the conversation starts loading when the pointer or keyboard
	// reaches the button, and is cached so reopening is instant.
	let { userId }: { userId: string } = $props();

	const queryClient = useQueryClient();
	let open = $state(false);
	let limit = $state(SUPPORT_PAGE_SIZE);
	let launcherEl = $state<HTMLButtonElement | null>(null);
	let conversation = $state<ReturnType<typeof SupportConversation> | null>(null);

	const query = createQuery(() => ({
		queryKey: supportThreadPageKey(userId, limit),
		queryFn: () => fetchSupportThread(limit),
		enabled: open,
		placeholderData: keepPreviousData,
		// No live delivery yet (D2): an open conversation checks for Uplift's reply on a timer. TanStack
		// pauses the timer while the tab is in the background.
		refetchInterval: open ? SUPPORT_OPEN_REFRESH_MS : false
	}));

	function warm() {
		void queryClient.prefetchQuery({
			queryKey: supportThreadPageKey(userId, limit),
			queryFn: () => fetchSupportThread(limit),
			staleTime: 30_000
		});
	}

	async function openPanel() {
		open = true;
		await tick();
		conversation?.focusComposer();
	}

	async function closePanel() {
		open = false;
		await tick();
		launcherEl?.focus();
	}

	function handleKeydown(event: KeyboardEvent) {
		if (event.key !== 'Escape') return;
		event.stopPropagation();
		void closePanel();
	}

	async function send(input: { body: string; client_message_id: string }) {
		const message = await sendSupportMessage(input);
		// Every loaded page of this person's thread gains the stored message, so it shows at once.
		queryClient.setQueriesData<SupportThread>({ queryKey: supportThreadKey(userId) }, (current) =>
			!current || current.messages.some((existing) => existing.id === message.id)
				? current
				: { ...current, messages: [...current.messages, message] }
		);
	}

	const thread = $derived(query.data);
	const availability = $derived(thread?.availability_note ?? '');
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if open}
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -- Escape closes the panel from anywhere inside it. -->
	<div
		class="support-messenger"
		role="dialog"
		aria-modal="false"
		aria-labelledby="support-messenger-title"
		onkeydown={handleKeydown}
	>
		<header class="support-messenger__header">
			<span class="support-messenger__mark" aria-hidden="true">{@html messageIcon}</span>
			<div class="support-messenger__heading">
				<h2 id="support-messenger-title">Uplift Support</h2>
				<p>{availability || 'We reply here as soon as we can.'}</p>
			</div>
			<button
				class="support-messenger__close"
				type="button"
				aria-label="Close chat"
				title="Close chat"
				onclick={() => void closePanel()}
			>
				<span aria-hidden="true">{@html closeIcon}</span>
			</button>
		</header>

		<SupportConversation
			bind:this={conversation}
			viewer="member"
			messages={thread?.messages ?? []}
			loading={query.isPending}
			failed={query.isError && !thread}
			onRetry={() => void query.refetch()}
			hasEarlier={(thread?.has_earlier ?? false) && limit < SUPPORT_MAX_LOADED}
			loadingEarlier={query.isPlaceholderData}
			onLoadEarlier={() => (limit = Math.min(limit + SUPPORT_PAGE_SIZE, SUPPORT_MAX_LOADED))}
			onSend={send}
			placeholder="Write to Uplift…"
		>
			{#snippet empty()}
				<div class="support-messenger__welcome">
					<strong>How can we help?</strong>
					<p>
						Ask about your setup, website, Google profile, the CRM or billing. Your message goes to
						the Uplift team — never to your customers.
					</p>
				</div>
			{/snippet}
			{#snippet footnote()}
				Please never send passwords here.
			{/snippet}
		</SupportConversation>
	</div>
{:else}
	<button
		class="support-messenger__launcher"
		type="button"
		bind:this={launcherEl}
		aria-haspopup="dialog"
		onpointerenter={warm}
		onfocus={warm}
		onclick={() => void openPanel()}
	>
		<span class="support-messenger__launcher-icon" aria-hidden="true">{@html messageIcon}</span>
		<span class="support-messenger__launcher-label">Chat with Uplift</span>
	</button>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// Both sit in the bottom-right corner of the content area. `--support-launcher-clearance` is published
	// by a pinned action bar while one is on screen, so the button rises above it instead of covering Save.
	.support-messenger,
	.support-messenger__launcher {
		position: fixed;
		right: var(--shell-content-right, var(--space-large));
		bottom: calc(var(--shell-edge, var(--space-base)) + var(--space-small));
		z-index: calc(var(--elevation-menu) + 1);
	}

	.support-messenger__launcher {
		bottom: calc(
			var(--shell-edge, var(--space-base)) + var(--space-small) +
				var(--support-launcher-clearance, 0px)
		);
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		min-height: 44px;
		padding: 0 var(--space-base) 0 var(--space-slim);
		border: 0;
		border-radius: var(--radius-circle);
		color: var(--color-surface);
		font: inherit;
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		background: var(--color-interactive);
		box-shadow: var(--shadow-high);
		cursor: pointer;
		transition:
			background var(--timing-quick) ease,
			bottom var(--timing-base) ease-out;

		&:hover {
			background: var(--color-interactive--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.support-messenger__launcher-icon {
		display: inline-flex;

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.support-messenger {
		display: flex;
		flex-direction: column;
		width: min(380px, calc(100vw - (var(--space-base) * 2)));
		height: min(600px, calc(100dvh - 96px));
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-larger);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
		overflow: hidden;
	}

	.support-messenger__header {
		display: flex;
		flex: none;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-slim) var(--space-slim) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.support-messenger__mark {
		display: grid;
		flex: none;
		place-items: center;
		width: 36px;
		height: 36px;
		border-radius: var(--radius-circle);
		color: var(--color-surface);
		background: var(--color-interactive);

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.support-messenger__heading {
		flex: 1;
		min-width: 0;

		h2 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			line-height: var(--typography--lineHeight-tight);
		}

		p {
			margin: var(--space-smallest) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.support-messenger__close {
		display: grid;
		flex: none;
		place-items: center;
		width: 36px;
		height: 36px;
		padding: 0;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-icon);
		background: transparent;
		cursor: pointer;

		span {
			display: inline-flex;
		}

		:global(svg) {
			width: 20px;
			height: 20px;
		}

		&:hover {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.support-messenger__welcome {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);

		strong {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
		}

		p {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-base);
		}
	}

	// On a phone the conversation takes the whole screen, and the button shrinks to its icon so it covers
	// as little of the page as possible.
	@media (max-width: 767px) {
		.support-messenger {
			inset: 0;
			width: auto;
			height: auto;
			border: 0;
			border-radius: 0;
			z-index: var(--elevation-modal);
		}

		.support-messenger__launcher {
			right: var(--space-base);
			width: 48px;
			min-height: 48px;
			padding: 0;
			justify-content: center;
		}

		.support-messenger__launcher-label {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}
	}
</style>
