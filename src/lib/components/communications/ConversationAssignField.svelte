<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { assignConversation } from '$lib/communications/inbox';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';
	import chevronIcon from '@tabler/icons/outline/chevron-down.svg?raw';

	// The one place the conversation assign menu is built, mirroring pipeline's OpportunityOwnerField:
	// team list, mutation, and eligible-member items live here once; the caller only supplies identity and
	// the current assignee.
	let {
		clientId,
		assignedToId,
		assignedToName,
		canManage
	}: {
		clientId: string;
		assignedToId: string | null;
		assignedToName: string | null;
		canManage: boolean;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		staleTime: 300_000,
		enabled: canManage
	}));
	const team = $derived(teamQuery.data ?? []);

	const assignMutation = createMutation(() => ({
		mutationFn: (userId: string | null) => assignConversation(clientId, userId),
		onSuccess: () => {
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] });
		},
		onError: (error: Error) => toast.error('Could not assign the conversation', error.message)
	}));

	const items = $derived([
		{
			label: 'Unassigned',
			onSelect: () => assignMutation.mutate(null),
			disabled: assignMutation.isPending
		},
		...team.map((member) => ({
			label: member.full_name ?? 'Unnamed teammate',
			onSelect: () => assignMutation.mutate(member.id),
			disabled: assignMutation.isPending
		}))
	]);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if canManage}
	<DropdownMenu
		{items}
		triggerClass="conversation-assign__trigger"
		align="start"
		triggerLabel={`Change assignee — currently ${assignedToName ?? 'Unassigned'}`}
	>
		{#snippet trigger()}
			{#if assignedToId}
				<Avatar id={assignedToId} name={assignedToName} size="small" />
			{/if}
			<span class="conversation-assign__label">{assignedToName ?? 'Unassigned'}</span>
			<span class="conversation-assign__chevron" aria-hidden="true">{@html chevronIcon}</span>
		{/snippet}
	</DropdownMenu>
{:else}
	<span class="conversation-assign__readonly">
		{#if assignedToId}
			<Avatar id={assignedToId} name={assignedToName} size="small" />
		{/if}
		{assignedToName ?? 'Unassigned'}
	</span>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.conversation-assign__trigger) {
		display: inline-flex;
		width: auto;
		height: auto;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-smaller) var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		background: var(--color-surface);
		cursor: pointer;

		&:hover:not(:disabled) {
			color: var(--color-text);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	:global(.conversation-assign__trigger[data-state='open']) {
		background: var(--color-surface--active);
	}

	.conversation-assign__chevron {
		display: inline-flex;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.conversation-assign__readonly {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
