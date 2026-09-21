<script lang="ts">
	import { Tabs as TabsPrimitive } from 'bits-ui';
	import { useQueryClient, type CreateQueryResult } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConversationAssignField from '$lib/components/communications/ConversationAssignField.svelte';
	import ConversationContextSection from '$lib/components/communications/ConversationContextSection.svelte';
	import InquiryAutomationCard from '$lib/components/automation/InquiryAutomationCard.svelte';
	import { AUTOMATION_JOURNEY_READY } from '$lib/automation/journey';
	import {
		conversationContextSectionKey,
		conversationCustomerEmail,
		fetchConversationContextSection,
		type ConversationContext,
		type ConversationGroup
	} from '$lib/communications/inbox';
	import {
		CONTEXT_SECTION_LABELS,
		CONTEXT_SECTIONS,
		type ContextSection
	} from '$lib/communications/context-sections';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import requestsIcon from '@tabler/icons/outline/clipboard-list.svg?raw';
	import quotesIcon from '@tabler/icons/outline/file-text.svg?raw';
	import jobsIcon from '@tabler/icons/outline/tool.svg?raw';
	import invoicesIcon from '@tabler/icons/outline/file-invoice.svg?raw';
	import pipelineIcon from '@tabler/icons/outline/layout-kanban.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import starFilledIcon from '@tabler/icons/filled/star.svg?raw';

	// The customer context beside a conversation: who this is, and what work the business has with them,
	// one tab per kind of record. Every tab but Contact loads only when it is reached for -- hovering its
	// icon warms it, so the click usually finds it ready.
	//
	// A conversation with no client yet (an unlinked sender, an unresolved chat visitor) has no records to
	// show, so it gets the plain identity panel and no tabs rather than empty ones.
	let {
		group,
		context,
		canManageAssignment,
		followPending,
		onToggleFollow
	}: {
		group: ConversationGroup;
		context: CreateQueryResult<ConversationContext, Error>;
		canManageAssignment: boolean;
		followPending: boolean;
		onToggleFollow: () => void;
	} = $props();

	const queryClient = useQueryClient();

	type Tab = 'contact' | ContextSection;

	const ICONS: Record<Tab, string> = {
		contact: userIcon,
		properties: mapPinIcon,
		requests: requestsIcon,
		quotes: quotesIcon,
		jobs: jobsIcon,
		invoices: invoicesIcon,
		pipeline: pipelineIcon
	};

	// Kept while the member moves between conversations: someone scanning quotes across customers should
	// not be sent back to Contact every time.
	let selected = $state<Tab>('contact');

	// The tabs this member may see, in the order of the customer's journey. Until the client has loaded
	// there is nothing to say which those are, so the strip waits rather than flashing tabs that then vanish.
	const visibleSections = $derived(
		context.data
			? CONTEXT_SECTIONS.filter((section) => context.data?.sections.includes(section))
			: []
	);
	const tabs = $derived<{ value: Tab; label: string }[]>([
		{ value: 'contact', label: 'Contact' },
		...visibleSections.map((section) => ({
			value: section,
			label: CONTEXT_SECTION_LABELS[section]
		}))
	]);
	const active = $derived<Tab>(tabs.some((tab) => tab.value === selected) ? selected : 'contact');
	const activeLabel = $derived(tabs.find((tab) => tab.value === active)?.label ?? 'Contact');

	function warm(clientId: string, tab: Tab) {
		if (tab === 'contact') return;
		queryClient.prefetchQuery({
			queryKey: conversationContextSectionKey(clientId, tab),
			queryFn: () => fetchConversationContextSection(clientId, tab),
			staleTime: 30_000
		});
	}
</script>

{#snippet automation()}
	{#if AUTOMATION_JOURNEY_READY && group.chatSession}
		<div class="context-rail__automation">
			<InquiryAutomationCard record={{ kind: 'chat_session', id: group.chatSession.id }} />
		</div>
	{/if}
{/snippet}

{#snippet detail(label: string, value: string)}
	<div class="context-rail__detail">
		<dt>{label}</dt>
		<dd>{value}</dd>
	</div>
{/snippet}

{#if group.clientId}
	{@const clientId = group.clientId}
	<TabsPrimitive.Root
		class="context-rail"
		orientation="vertical"
		activationMode="manual"
		value={active}
		onValueChange={(next) => (selected = next as Tab)}
	>
		<div class="context-rail__panel">
			<header class="context-rail__identity">
				<Avatar id={clientId} name={group.name} size="medium" />
				<div class="context-rail__who">
					<h2>{group.name}</h2>
					<a
						class="context-rail__client-link"
						href={resolve('/(app)/clients/[id=uuid]', { id: clientId })}
					>
						View client
						<span class="context-rail__link-icon" aria-hidden="true">{@html externalLinkIcon}</span>
					</a>
				</div>
			</header>

			<h3 class="context-rail__title">{activeLabel}</h3>

			{#each tabs as tab (tab.value)}
				<TabsPrimitive.Content value={tab.value} class="context-rail__content">
					{#if active === tab.value}
						{#if tab.value === 'contact'}
							<div class="context-rail__group">
								<p class="context-rail__label">Owner</p>
								<div class="context-rail__actions">
									<ConversationAssignField
										{clientId}
										assignedToId={group.assignedTo}
										assignedToName={group.assignedToName}
										canManage={canManageAssignment}
									/>
									<Button
										size="small"
										variant={group.isFollowing ? 'primary' : 'secondary'}
										disabled={followPending}
										onclick={onToggleFollow}
									>
										<span class="context-rail__follow-icon" aria-hidden="true"
											>{@html group.isFollowing ? starFilledIcon : starIcon}</span
										>
										{group.isFollowing ? 'Following' : 'Follow'}
									</Button>
								</div>
							</div>
							<dl class="context-rail__details">
								{@render detail(
									'Email',
									context.data?.client.email ?? conversationCustomerEmail(group)
								)}
								{#if context.data?.client.phone}
									{@render detail('Phone', context.data.client.phone)}
								{/if}
								{#if context.data?.client.company_name}
									{@render detail('Company', context.data.client.company_name)}
								{/if}
							</dl>
							{@render automation()}
						{:else}
							<ConversationContextSection {clientId} section={tab.value} />
						{/if}
					{/if}
				</TabsPrimitive.Content>
			{/each}
		</div>

		<TabsPrimitive.List class="context-rail__strip" aria-label="Customer context sections">
			{#if context.isPending}
				{#each { length: 5 } as _, index (index)}
					<span class="context-rail__ghost" aria-hidden="true"></span>
				{/each}
			{:else}
				{#each tabs as tab (tab.value)}
					<TabsPrimitive.Trigger
						value={tab.value}
						class="context-rail__tab"
						aria-label={tab.label}
						title={tab.label}
						onmouseenter={() => warm(clientId, tab.value)}
						onfocus={() => warm(clientId, tab.value)}
					>
						<span class="context-rail__tab-icon" aria-hidden="true">{@html ICONS[tab.value]}</span>
					</TabsPrimitive.Trigger>
				{/each}
			{/if}
		</TabsPrimitive.List>
	</TabsPrimitive.Root>
{:else}
	<div class="context-rail context-rail--plain">
		<div class="context-rail__panel">
			<header class="context-rail__identity">
				<Avatar id={group.avatarId} name={group.name} size="medium" />
				<div class="context-rail__who"><h2>{group.name}</h2></div>
			</header>
			{#if group.chatSession}
				<p class="context-rail__note">
					This visitor's phone and email matched two different clients. UCRM never guesses --
					resolve identity to bring this conversation into one client's history.
				</p>
				<dl class="context-rail__details">
					{#if group.chatSession.visitor_email}
						{@render detail('Email', group.chatSession.visitor_email)}
					{/if}
					{#if group.chatSession.visitor_phone}
						{@render detail('Phone', group.chatSession.visitor_phone)}
					{/if}
				</dl>
			{:else}
				<p class="context-rail__note">
					This sender is not yet linked to a customer. It stays out of the customer's conversation
					until reviewed.
				</p>
				<dl class="context-rail__details">
					{@render detail('Email', group.avatarId)}
				</dl>
			{/if}
			{@render automation()}
		</div>
	</div>
{/if}

<style lang="scss">
	:global(.context-rail) {
		display: flex;
		height: 100%;
		min-height: 0;
	}

	.context-rail__panel {
		display: flex;
		flex: 1;
		min-width: 0;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-large) var(--space-base) var(--space-large) var(--space-large);
		overflow-y: auto;
	}

	.context-rail__identity {
		display: flex;
		align-items: center;
		gap: var(--space-slim, 12px);
		padding-bottom: var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.context-rail__who {
		display: grid;
		min-width: 0;
		gap: 2px;

		h2 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			line-height: 1.25;
			overflow-wrap: anywhere;
		}
	}

	.context-rail__client-link {
		display: inline-flex;
		width: fit-content;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-interactive--subtle);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}
	}

	.context-rail__link-icon,
	.context-rail__follow-icon {
		display: inline-flex;

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.context-rail__follow-icon :global(svg) {
		width: 16px;
		height: 16px;
	}

	.context-rail__title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
	}

	:global(.context-rail__content) {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	:global(.context-rail__content[hidden]) {
		display: none;
	}

	.context-rail__group {
		display: grid;
		gap: var(--space-smaller);
	}

	.context-rail__label,
	.context-rail__detail dt {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.context-rail__actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}

	.context-rail__details {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	.context-rail__detail {
		display: grid;
		gap: 2px;

		dd {
			margin: 0;
			color: var(--color-text);
			overflow-wrap: anywhere;
		}
	}

	.context-rail__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.context-rail__automation {
		margin-top: var(--space-smaller);
	}

	/* The strip: a slim rail of icons down the right edge. The active icon sits in a soft tile with a bar on
	   the strip's outer edge, so the open tab reads at a glance without a label. */
	:global(.context-rail__strip) {
		display: flex;
		flex: 0 0 auto;
		width: 52px;
		flex-direction: column;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-base) 0;
		border-left: var(--border-base) solid var(--color-border);
		background: var(--color-surface);
		overflow-x: hidden;
		overflow-y: auto;
	}

	:global(.context-rail__tab) {
		position: relative;
		display: inline-flex;
		width: 36px;
		height: 36px;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		padding: 0;
		border: 0;
		border-radius: var(--radius-base);
		background: transparent;
		color: var(--color-text--secondary);
		cursor: pointer;
		transition:
			background var(--timing-base) ease-out,
			color var(--timing-base) ease-out;

		&:hover {
			background: var(--color-surface--hover);
			color: var(--color-heading);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	:global(.context-rail__tab[data-state='active']) {
		background: var(--color-surface--active);
		color: var(--color-interactive);
	}

	:global(.context-rail__tab[data-state='active']::after) {
		content: '';
		position: absolute;
		top: 8px;
		right: -7px;
		bottom: 8px;
		width: 3px;
		border-radius: 3px 0 0 3px;
		background: var(--color-interactive);
	}

	.context-rail__tab-icon {
		display: inline-flex;

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.context-rail__ghost {
		width: 36px;
		height: 36px;
		border-radius: var(--radius-base);
		background: var(--color-surface--hover);
		opacity: 0.6;
	}
</style>
