<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		fetchMessengerPageChoices,
		type MessengerConnectResult,
		type MessengerPageChoice
	} from '$lib/communications/messenger-settings';
	import messagesIcon from '@tabler/icons/outline/messages.svg?raw';
	import plugIcon from '@tabler/icons/outline/plug.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import loginIcon from '@tabler/icons/outline/login-2.svg?raw';

	// After Facebook's own window closes, the business ticks which Pages to connect (board `tEAXY`, Pop-ups).
	// Pages already on this business are greyed out; one that needs reconnecting can be ticked again. The button
	// counts the ticked Pages.
	let {
		sessionId,
		preselectPageId = null,
		connecting,
		failures,
		onConnect,
		onLoginAgain,
		onClose
	}: {
		sessionId: string;
		/** The Page whose Reconnect opened this, ticked from the start. */
		preselectPageId?: string | null;
		connecting: boolean;
		failures: MessengerConnectResult['failed'];
		onConnect: (pageIds: string[]) => void;
		onLoginAgain: () => void;
		onClose: () => void;
	} = $props();

	const choicesQuery = createQuery(() => ({
		queryKey: ['settings', 'communications', 'messenger', 'pages', sessionId],
		queryFn: () => fetchMessengerPageChoices(sessionId),
		staleTime: Infinity,
		retry: false
	}));

	const selectable = (page: MessengerPageChoice) =>
		page.state === 'available' || page.state === 'reconnect';

	let ticked = $state<string[] | null>(null);
	// Until the person touches a box: the Page being reconnected, or the only Page there is to pick.
	const initialTicks = $derived.by(() => {
		const pages = choicesQuery.data?.pages ?? [];
		if (preselectPageId && pages.some((page) => page.id === preselectPageId && selectable(page)))
			return [preselectPageId];
		const open = pages.filter(selectable);
		return open.length === 1 ? [open[0].id] : [];
	});
	const chosen = $derived(ticked ?? initialTicks);

	function toggle(pageId: string, checked: boolean) {
		const current = chosen.filter((id) => id !== pageId);
		ticked = checked ? [...current, pageId] : current;
	}

	const PILLS: Partial<Record<MessengerPageChoice['state'], string>> = {
		connected: 'Already connected',
		reconnect: 'Needs reconnecting',
		elsewhere: 'On another business',
		no_permission: "Can't manage messages"
	};

	function describe(page: MessengerPageChoice) {
		const followers =
			page.followers === null
				? null
				: `${new Intl.NumberFormat().format(page.followers)} ${page.followers === 1 ? 'follower' : 'followers'}`;
		return [page.category, followers].filter(Boolean).join(' · ');
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -- trusted build-time Tabler icons -->
<Dialog
	open
	title="Choose Pages to connect"
	subtitle={choicesQuery.data
		? `Pages you manage on Facebook as ${choicesQuery.data.facebook_user_name}`
		: 'Pages you manage on Facebook'}
	icon={messagesIcon}
	iconTone="conversation"
	closeDisabled={connecting}
	{onClose}
>
	{#if choicesQuery.isPending}
		<LoadingSkeleton rows={3} />
	{:else if choicesQuery.isError}
		<Banner type="error">
			{choicesQuery.error.message}
			{#snippet action()}
				<Button variant="secondary" size="small" onclick={onLoginAgain}>
					<span aria-hidden="true">{@html loginIcon}</span>
					Log in again
				</Button>
			{/snippet}
		</Banner>
	{:else}
		{#if failures.length}
			<div class="choose-pages__failures">
				<Banner type="error">
					<ul class="choose-pages__failure-list">
						{#each failures as failure (failure.page_id)}
							<li><strong>{failure.page_name}:</strong> {failure.message}</li>
						{/each}
					</ul>
				</Banner>
			</div>
		{/if}
		<ul class="choose-pages__list">
			{#each choicesQuery.data.pages as page (page.id)}
				{@const open = selectable(page)}
				{@const id = `messenger-page-${page.id}`}
				<li class={['choose-pages__row', !open && 'choose-pages__row--off']}>
					<Checkbox
						{id}
						label={page.name}
						hideLabel
						checked={open ? chosen.includes(page.id) : page.state === 'connected'}
						disabled={!open || connecting}
						onchange={(checked) => toggle(page.id, checked)}
					/>
					<label class="choose-pages__page" for={id}>
						<Avatar id={page.id} name={page.name} size="base" />
						<span class="choose-pages__text">
							<span class="choose-pages__name">{page.name}</span>
							{#if describe(page)}<span class="choose-pages__line">{describe(page)}</span>{/if}
						</span>
					</label>
					{#if PILLS[page.state]}
						<span class={['choose-pages__pill', `choose-pages__pill--${page.state}`]}>
							{PILLS[page.state]}
						</span>
					{/if}
				</li>
			{/each}
		</ul>
		<div class="choose-pages__hint">
			<span class="choose-pages__hint-icon" aria-hidden="true">{@html infoIcon}</span>
			<span class="choose-pages__hint-text">
				Missing a Page? You need to be its admin on Facebook, and it must be ticked in Facebook's
				window.
				<button type="button" class="choose-pages__again" onclick={onLoginAgain}>
					Choose Pages on Facebook again
				</button>
			</span>
		</div>
	{/if}

	{#snippet footer()}
		<Button variant="secondary" disabled={connecting} onclick={onClose}>Cancel</Button>
		<Button
			loading={connecting}
			disabled={chosen.length === 0 || !choicesQuery.isSuccess}
			onclick={() => onConnect(chosen)}
		>
			<span aria-hidden="true">{@html plugIcon}</span>
			Connect {chosen.length || ''}
			{chosen.length === 1 ? 'Page' : 'Pages'}
		</Button>
	{/snippet}
</Dialog>

<style lang="scss">
	.choose-pages {
		&__failures {
			margin-bottom: var(--space-slim);
		}
		&__failure-list {
			display: grid;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__list {
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__row {
			display: flex;
			align-items: center;
			gap: 14px;
			padding: 14px 0;

			& + & {
				border-top: 1px solid var(--color-border);
			}
		}
		&__page {
			display: flex;
			flex: 1;
			align-items: center;
			gap: 14px;
			min-width: 0;
			cursor: pointer;
		}
		&__row--off &__page {
			cursor: default;
			opacity: 0.6;
		}
		&__text {
			display: grid;
			gap: 2px;
			min-width: 0;
		}
		&__name {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__line {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}
		&__pill {
			flex: 0 0 auto;
			padding: 4px 10px;
			border-radius: var(--radius-circle);
			color: var(--color-inactive--onSurface);
			background: var(--color-inactive--surface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;

			&--reconnect {
				color: var(--color-critical--onSurface);
				background: var(--color-critical--surface);
			}
		}
		&__hint {
			display: flex;
			align-items: flex-start;
			gap: 10px;
			margin-top: var(--space-small);
			padding: 10px var(--space-slim);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}
		&__hint-icon {
			display: flex;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__hint-text {
			display: grid;
			gap: 2px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
			line-height: 1.45;
		}
		&__again {
			justify-self: start;
			padding: 0;
			border: 0;
			border-radius: var(--radius-small);
			color: var(--color-interactive);
			background: none;
			font: inherit;
			font-weight: 600;
			cursor: pointer;

			&:hover {
				text-decoration: underline;
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
	}
</style>
