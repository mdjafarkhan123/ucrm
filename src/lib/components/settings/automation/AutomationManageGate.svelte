<script lang="ts">
	import type { Snippet } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import { automationSettingsKey, fetchAutomationSettings } from '$lib/settings/automation';
	import robotOffIcon from '@tabler/icons/outline/robot-off.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// The one place the create/edit surfaces check that this contractor may actually change automations, so
	// the builder and the preset library share exactly the same honest refusals instead of each reinventing
	// them. It renders its children only when the feature is included, the viewer can manage, and authority is
	// enabled and not read-only; every other state is a specific, non-leaking shell (matches the home page's
	// access handling and the server's requireAutomationAccess('manage') gate).
	let { children }: { children: Snippet } = $props();

	const query = createQuery(() => ({
		queryKey: automationSettingsKey,
		queryFn: fetchAutomationSettings
	}));
</script>

{#if query.isPending}
	<LoadingSkeleton variant="card" rows={2} />
{:else if query.isError}
	<ErrorState description="Automation could not be loaded." retry={() => query.refetch()} />
{:else if query.data.status === 'denied'}
	{#if query.data.reason === 'not_included'}
		<EmptyState
			icon={robotOffIcon}
			title="Automation isn’t part of your plan"
			description="Automation isn’t included in your current plan. Talk to us if you’d like to add it."
		/>
	{:else}
		<EmptyState
			icon={lockIcon}
			title="You don’t have access to Automation"
			description="Ask an owner or administrator if you need to work with automations."
		/>
	{/if}
{:else if !query.data.access.can_manage}
	<EmptyState
		icon={lockIcon}
		title="You can view automations, but not change them"
		description="Ask an owner or administrator to build or edit automations for your business."
	/>
{:else if query.data.access.read_only || query.data.access.authority_state !== 'enabled'}
	<EmptyState
		icon={alertTriangleIcon}
		title="Automations can’t be changed right now"
		description={query.data.access.authority_state === 'security_suspended'
			? 'Automation is suspended for your business, so nothing can be created or edited.'
			: 'Automation is temporarily unavailable, so nothing can be created or edited right now.'}
	/>
{:else}
	{@render children()}
{/if}
