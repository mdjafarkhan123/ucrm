<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import type { Snippet } from 'svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { assignOpportunityOwner, invalidatePipeline } from '$lib/pipeline/api';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';

	// The one place the owner-assign menu is built: team list, mutation, and the eligible-member items.
	// The card and the Brief show it differently — an icon-only avatar versus an avatar-and-name row — so
	// only the trigger's content is theirs; everything that decides who can be picked and what happens on
	// selection lives here once.
	let {
		opportunityId,
		ownerName,
		canEdit,
		trigger,
		triggerClass = 'dropdown-menu__trigger',
		align = 'end',
		onAssigned
	}: {
		opportunityId: string;
		ownerName: string;
		canEdit: boolean;
		trigger: Snippet;
		triggerClass?: string;
		align?: 'start' | 'center' | 'end';
		// Told the full member record a caller resolved from this component's own team list — the PATCH
		// itself only returns an id. Optional: the card doesn't need it, since it always renders from the
		// live column query; the Brief does, since it holds a snapshot the board's own refetch never
		// reaches.
		onAssigned?: (
			owner: { id: string; full_name: string | null; avatar_url: string | null } | null
		) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// The Salesperson filter loads this same list as soon as the board renders, so an editor opening this
	// menu almost always finds it already warm.
	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		staleTime: 300_000,
		enabled: canEdit
	}));
	const team = $derived(teamQuery.data ?? []);

	const ownerMutation = createMutation(() => ({
		mutationFn: (ownerUserId: string | null) => assignOpportunityOwner(opportunityId, ownerUserId),
		onSuccess: (_data, ownerUserId) => {
			invalidatePipeline(queryClient);
			onAssigned?.(ownerUserId ? (team.find((member) => member.id === ownerUserId) ?? null) : null);
		},
		onError: (error: Error) => toast.error('Could not change the owner', error.message)
	}));

	const items = $derived([
		{
			label: 'Unassigned',
			onSelect: () => ownerMutation.mutate(null),
			disabled: ownerMutation.isPending
		},
		...team.map((member) => ({
			label: member.full_name ?? 'Unnamed teammate',
			onSelect: () => ownerMutation.mutate(member.id),
			disabled: ownerMutation.isPending
		}))
	]);
</script>

<DropdownMenu
	{items}
	{trigger}
	{triggerClass}
	{align}
	triggerLabel={`Change owner — currently ${ownerName}`}
/>
