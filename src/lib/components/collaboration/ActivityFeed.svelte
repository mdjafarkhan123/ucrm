<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import AuthorMeta from '$lib/components/collaboration/AuthorMeta.svelte';
	import { dayLabel } from '$lib/collaboration/format';
	import {
		activityKey,
		fetchActivity,
		fetchProfiles,
		profilesKey,
		type ActivityEvent,
		type EntityType
	} from '$lib/collaboration/api';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';
	import tagIcon from '@tabler/icons/outline/tag.svg?raw';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import userPlusIcon from '@tabler/icons/outline/user-plus.svg?raw';

	let {
		entityType,
		entityId,
		limit = 50,
		currentUserId
	}: {
		entityType: EntityType;
		entityId: string;
		limit?: number;
		currentUserId?: string;
	} = $props();

	const activityQuery = createQuery<ActivityEvent[]>(() => ({
		queryKey: activityKey(entityType, entityId),
		queryFn: () => fetchActivity(entityType, entityId, limit)
	}));
	const events = $derived(activityQuery.data ?? []);

	const actorIds = $derived([
		...new Set(events.map((event) => event.actor_user_id).filter((id): id is string => Boolean(id)))
	]);
	const profilesQuery = createQuery(() => ({
		queryKey: profilesKey(actorIds),
		queryFn: () => fetchProfiles(actorIds),
		enabled: actorIds.length > 0
	}));
	const profileById = $derived(
		new Map((profilesQuery.data ?? []).map((profile) => [profile.id, profile]))
	);

	const groups = $derived.by(() => {
		const map = new Map<string, ActivityEvent[]>();
		for (const event of events) {
			const label = dayLabel(event.created_at);
			const list = map.get(label);
			if (list) list.push(event);
			else map.set(label, [event]);
		}
		return [...map.entries()];
	});

	const eventIcons: Record<string, string> = {
		note_added: notesIcon,
		tag_assigned: tagIcon,
		attachment_added: paperclipIcon,
		property_contact_added: userPlusIcon
	};

	function iconFor(eventType: string) {
		return eventIcons[eventType] ?? historyIcon;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="activity-feed">
	{#if activityQuery.isPending}
		<p class="activity-feed__muted">Loading activity…</p>
	{:else if activityQuery.isError}
		<p class="activity-feed__error" role="alert">
			{activityQuery.error instanceof Error
				? activityQuery.error.message
				: 'Activity could not be loaded.'}
		</p>
	{:else if events.length === 0}
		<EmptyState
			title="No activity yet"
			description="Notes, tags, and files added here will show up as activity."
			icon={historyIcon}
		/>
	{:else}
		{#each groups as [label, groupEvents] (label)}
			<section class="activity-feed__group">
				<h3 class="activity-feed__group-label">{label}</h3>
				<ul class="activity-feed__list">
					{#each groupEvents as event (event.id)}
						<li class="activity-feed__item">
							<span class="activity-feed__item-icon" aria-hidden="true"
								>{@html iconFor(event.event_type)}</span
							>
							<div class="activity-feed__item-body">
								<p class="activity-feed__item-summary">{event.summary}</p>
								<AuthorMeta
									userId={event.actor_user_id}
									profile={event.actor_user_id ? profileById.get(event.actor_user_id) : undefined}
									{currentUserId}
									timestamp={event.created_at}
									size="small"
								/>
							</div>
						</li>
					{/each}
				</ul>
			</section>
		{/each}
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.activity-feed {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__group-label {
			margin-bottom: var(--space-small);
			padding-bottom: var(--space-smaller);
			border-bottom: var(--border-base) solid var(--color-border--section);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			text-transform: uppercase;
			letter-spacing: var(--typography--letterSpacing-loose);
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
		}

		&__item-icon {
			display: grid;
			width: 32px;
			height: 32px;
			flex: 0 0 auto;
			place-items: center;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
			color: var(--color-icon);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__item-body {
			display: flex;
			min-width: 0;
			flex-direction: column;
			gap: var(--space-smaller);
			padding-top: var(--space-smaller);
		}

		&__item-summary {
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-base);
		}
	}
</style>
