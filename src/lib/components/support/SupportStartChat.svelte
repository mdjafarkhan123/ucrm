<script lang="ts">
	import { createQuery, keepPreviousData } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import SupportConversation from '$lib/components/support/SupportConversation.svelte';
	import SupportTopicPicker from '$lib/components/support/SupportTopicPicker.svelte';
	import {
		fetchSupportRecipients,
		jafarSupportFileUrls,
		jafarSupportKey,
		jafarSupportRecipientsKey,
		presignSupportStartAttachment,
		startSupportInboxThread,
		type SupportOutgoingMessage,
		type SupportTopic
	} from '$lib/support/api';
	import buildingIcon from '@tabler/icons/outline/building-store.svg?raw';

	// Uplift writes first (D5a; Intercom's outbound message): choose the business, the team member the chat
	// is for — the owner unless someone else is picked — and a topic, then write. The chat becomes that
	// member's, exactly as if they had started it.
	let {
		organizationId,
		onOrganizationChange,
		onStarted,
		blockedReason = '',
		footnoteText = '',
		context = null
	}: {
		/** The business, when it is already known (from its page, or once picked here). */
		organizationId: string | null;
		onOrganizationChange: (organizationId: string | null) => void;
		/** The first message is saved; the new chat can be opened. */
		onStarted: (threadId: string) => void;
		blockedReason?: string;
		/** The line under the box: how clients see Uplift's name. */
		footnoteText?: string;
		/** C3: the setup task the chat is about, from "Ask a question" on a client's Setup tab. */
		context?: { section: string; title: string } | null;
	} = $props();

	type DirectoryRow = { id: string; name: string; member_count: number };

	const uid = $props.id();

	// Searching the business directory, a moment after typing stops.
	let search = $state('');
	let debouncedSearch = $state('');
	$effect(() => {
		const term = search.trim();
		const handle = setTimeout(() => (debouncedSearch = term), 250);
		return () => clearTimeout(handle);
	});

	const directory = createQuery(() => ({
		queryKey: [...jafarSupportKey, 'start-directory', debouncedSearch] as const,
		queryFn: async (): Promise<DirectoryRow[]> => {
			const params = new URLSearchParams(
				debouncedSearch ? { limit: '8', search: debouncedSearch } : { limit: '8' }
			);
			const response = await fetch(`/api/jafar/organizations?${params}`);
			if (!response.ok) throw new Error('The businesses could not be loaded.');
			return (await response.json()).organizations;
		},
		enabled: organizationId === null,
		placeholderData: keepPreviousData
	}));

	const recipients = createQuery(() => ({
		queryKey: jafarSupportRecipientsKey(organizationId),
		queryFn: () => fetchSupportRecipients(organizationId as string),
		enabled: organizationId !== null
	}));

	// The owner comes first in the list, so they are chosen until Jafar picks someone else.
	let chosenUserId = $state('');
	const members = $derived(recipients.data?.members ?? []);
	const userId = $derived(
		members.some((member) => member.user_id === chosenUserId)
			? chosenUserId
			: (members[0]?.user_id ?? '')
	);
	// The role beside each name tells apart members who have not added their name yet.
	const memberOptions = $derived(
		members.map((member) => ({
			value: member.user_id,
			label: `${member.name} · ${member.role.charAt(0).toUpperCase()}${member.role.slice(1)}`
		}))
	);
	// svelte-ignore state_referenced_locally
	let topic = $state<SupportTopic>(context ? 'setup' : 'other');

	async function start(input: SupportOutgoingMessage) {
		if (!organizationId || !userId) throw new Error('Choose who to write to.');
		const message = await startSupportInboxThread({
			...input,
			organization_id: organizationId,
			user_id: userId,
			topic,
			...(context ? { context_section: context.section } : {})
		});
		onStarted(message.thread_id);
	}

	const blocked = $derived(
		blockedReason ||
			(recipients.isSuccess && members.length === 0 ? 'This business has no active team yet.' : '')
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if organizationId === null}
	<div class="support-start-chat__pick">
		<SearchInput
			id={`${uid}-search`}
			bind:value={search}
			label="Business"
			placeholder="Search businesses"
			ariaLabel="Search businesses"
		/>
		{#if directory.isPending}
			<LoadingSkeleton variant="text" rows={4} label="Loading businesses" />
		{:else if directory.isError && !directory.data}
			<ErrorState
				description="The businesses could not be loaded."
				retry={() => void directory.refetch()}
			/>
		{:else if (directory.data ?? []).length === 0}
			<EmptyState
				icon={buildingIcon}
				title="No matching business"
				description="Try another name."
			/>
		{:else}
			<ul class="support-start-chat__results" aria-label="Businesses">
				{#each directory.data ?? [] as business (business.id)}
					<li>
						<button
							type="button"
							class="support-start-chat__result"
							onclick={() => onOrganizationChange(business.id)}
						>
							<span class="support-start-chat__result-icon" aria-hidden="true"
								>{@html buildingIcon}</span
							>
							<span class="support-start-chat__result-text">
								<strong>{business.name}</strong>
								<span
									>{business.member_count}
									{business.member_count === 1 ? 'team member' : 'team members'}</span
								>
							</span>
						</button>
					</li>
				{/each}
			</ul>
		{/if}
	</div>
{:else}
	<div class="support-start-chat__to">
		<div class="support-start-chat__business">
			<span class="support-start-chat__label">Business</span>
			{#if recipients.data}
				<strong>{recipients.data.organization.name}</strong>
			{:else}
				<LoadingSkeleton variant="text" rows={1} label="Loading business" />
			{/if}
			<Button variant="tertiary" size="small" onclick={() => onOrganizationChange(null)}
				>Change</Button
			>
		</div>
		{#if recipients.isError && !recipients.data}
			<ErrorState
				description="This business's team could not be loaded."
				retry={() => void recipients.refetch()}
			/>
		{:else}
			<Select
				id={`${uid}-to`}
				label="To"
				value={userId}
				options={memberOptions}
				placeholder={recipients.isPending ? 'Loading team…' : 'No active team members'}
				disabled={memberOptions.length === 0}
				onchange={(value) => (chosenUserId = value)}
			/>
		{/if}
	</div>
	<div class="support-start-chat__body">
		<SupportConversation
			viewer="uplift"
			conversationKey={`new:${organizationId}`}
			messages={[]}
			onSend={start}
			presignAttachment={(file) => presignSupportStartAttachment(organizationId ?? '', file)}
			fileUrls={jafarSupportFileUrls}
			placeholder="Write your message…"
			blockedReason={blocked}
		>
			{#snippet empty()}
				<div class="support-start-chat__intro">
					<strong>Start a chat</strong>
					<p>It appears in their Chat with Uplift, as if they had asked you.</p>
					{#if context}
						<p class="support-start-chat__about">About their setup task “{context.title}”</p>
					{/if}
				</div>
				<SupportTopicPicker bind:value={topic} />
			{/snippet}
			{#snippet footnote()}
				{footnoteText}
			{/snippet}
		</SupportConversation>
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.support-start-chat {
		&__pick {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-base);
			min-height: 0;
			padding: var(--space-base);
			overflow-y: auto;
		}

		&__results {
			margin: 0;
			padding: 0;
			list-style: none;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);

			li + li {
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__result {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			width: 100%;
			padding: var(--space-small) var(--space-base);
			border: 0;
			color: inherit;
			background: transparent;
			font: inherit;
			text-align: left;
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: inset var(--shadow-focus);
			}
		}

		&__result-icon {
			display: inline-flex;
			flex: none;
			color: var(--color-icon);

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}

		&__result-text {
			display: flex;
			flex-direction: column;
			min-width: 0;

			strong {
				overflow: hidden;
				color: var(--color-heading);
				text-overflow: ellipsis;
				white-space: nowrap;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__to {
			display: flex;
			flex: none;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-base) var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);
		}

		&__business {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-height: 36px;

			strong {
				flex: 1;
				min-width: 0;
				overflow: hidden;
				color: var(--color-heading);
				text-overflow: ellipsis;
				white-space: nowrap;
			}
		}

		&__label {
			flex: none;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__body {
			display: flex;
			flex: 1;
			flex-direction: column;
			min-height: 0;
		}

		&__intro {
			margin-bottom: var(--space-base);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
			}

			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
			}
		}

		&__about {
			color: var(--color-heading);
			font-weight: 600;
		}
	}
</style>
