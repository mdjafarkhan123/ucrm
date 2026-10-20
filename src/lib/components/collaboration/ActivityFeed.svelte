<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import { dayLabel, exactTime, relativeTime } from '$lib/collaboration/format';
	import userRoundIcon from '@tabler/icons/outline/user.svg?raw';
	import zapIcon from '@tabler/icons/outline/bolt.svg?raw';
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
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import googleIcon from '@tabler/icons/outline/brand-google.svg?raw';
	import feedbackIcon from '@tabler/icons/outline/message-heart.svg?raw';
	import cancelIcon from '@tabler/icons/outline/circle-x.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import restoreIcon from '@tabler/icons/outline/restore.svg?raw';
	import mergeIcon from '@tabler/icons/outline/arrow-merge.svg?raw';

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
		property_contact_added: userPlusIcon,
		'quote.viewed_by_client': eyeIcon,
		'quote.approved': checkIcon,
		'quote.changes_requested': messageIcon,
		'review.requested': starIcon,
		'review.opened': eyeIcon,
		'review.continued_to_google': googleIcon,
		'review.feedback_submitted': feedbackIcon,
		'review.cancelled': cancelIcon,
		'client.archived': archiveIcon,
		'client.restored': restoreIcon,
		'client.restored_by_new_work': restoreIcon,
		client_merged: mergeIcon
	};

	function iconFor(eventType: string) {
		return eventIcons[eventType] ?? historyIcon;
	}

	// Some things on this feed nobody on the team did. A customer opening their quote or answering it has
	// no user behind it, and "Unknown" — the right word for a teammate who has since left — would read as
	// something going wrong. These events say who it actually was.
	const CUSTOMER_EVENTS = new Set([
		'quote.viewed_by_client',
		'quote.approved',
		'quote.changes_requested',
		'review.opened',
		'review.continued_to_google',
		'review.feedback_submitted'
	]);

	// New work brings an archived client back on its own. When a teammate added that work they are named;
	// a website booking or an automation has nobody behind it.
	// The event's meaning colour (`notes.md` → Activity feed): what the event is about.
	function toneFor(eventType: string) {
		if (eventType.startsWith('quote.')) return 'quote';
		if (eventType.startsWith('review.')) return 'review';
		if (eventType.startsWith('client') || eventType === 'property_contact_added') return 'client';
		if (eventType === 'note_added') return 'conversation';
		return 'inactive';
	}

	function nameFor(event: ActivityEvent) {
		if (!event.actor_user_id) return fallbackNameFor(event.event_type);
		if (event.actor_user_id === currentUserId) return 'You';
		return profileById.get(event.actor_user_id)?.full_name ?? 'Team member';
	}

	function fallbackNameFor(eventType: string) {
		if (CUSTOMER_EVENTS.has(eventType)) return 'The client';
		return eventType === 'client.restored_by_new_work' ? 'Automatic' : 'Unknown';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="activity-feed">
	{#if activityQuery.isPending}
		<div class="activity-feed__loading" role="status" aria-label="Loading activity">
			<span class="skeleton activity-feed__bone-pill"></span>
			{#each [0, 1, 2] as bone (bone)}
				<div class="activity-feed__bone-row">
					<span class="skeleton activity-feed__bone-marker"></span>
					<span class="activity-feed__bone-lines">
						<span class="skeleton activity-feed__bone-line"></span>
						<span class="skeleton activity-feed__bone-line activity-feed__bone-line--short"></span>
					</span>
				</div>
			{/each}
		</div>
	{:else if activityQuery.isError}
		<ErrorState
			title="History didn't load"
			description="Check your connection, then try again."
			retry={() => activityQuery.refetch()}
		/>
	{:else if events.length === 0}
		<EmptyState
			title="No activity yet"
			description="Notes, tags, and files added here will show up as activity."
			icon={historyIcon}
			tone="client"
		/>
	{:else}
		{#each groups as [label, groupEvents] (label)}
			<section class="activity-feed__group">
				<h3 class="activity-feed__day"><span class="activity-feed__day-pill">{label}</span></h3>
				<ul class="activity-feed__list">
					{#each groupEvents as event (event.id)}
						{@const tone = toneFor(event.event_type)}
						<li class="activity-feed__item">
							<span
								class="activity-feed__marker"
								style={`--marker-surface: var(--color-${tone}--surface); --marker-edge: var(--color-${tone}--surface-edge); --marker-ink: var(--color-${tone});`}
								aria-hidden="true">{@html iconFor(event.event_type)}</span
							>
							<div class="activity-feed__item-body">
								<p class="activity-feed__item-summary">{event.summary}</p>
								<span class="activity-feed__author">
									{#if event.actor_user_id}
										<Avatar
											id={event.actor_user_id}
											name={profileById.get(event.actor_user_id)?.full_name}
											src={profileById.get(event.actor_user_id)?.avatar_url}
											size="small"
										/>
									{:else}
										<span
											class="activity-feed__system"
											class:activity-feed__system--client={CUSTOMER_EVENTS.has(event.event_type)}
											aria-hidden="true"
											>{@html CUSTOMER_EVENTS.has(event.event_type) ? userRoundIcon : zapIcon}</span
										>
									{/if}
									<span class="activity-feed__author-name">{nameFor(event)}</span>
									<span class="activity-feed__author-dot" aria-hidden="true">·</span>
									<time
										class="activity-feed__author-time"
										datetime={event.created_at}
										title={exactTime(event.created_at)}>{relativeTime(event.created_at)}</time
									>
								</span>
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
	// Activity feed (`notes.md`, board `gZ6rR` A · Timeline).
	.activity-feed {
		display: flex;
		flex-direction: column;
		gap: var(--space-medium);

		&__day {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0 0 10px;

			&::after {
				content: '';
				flex: 1 1 auto;
				height: 1px;
				background: var(--color-border);
			}
		}

		&__day-pill {
			padding: 3px var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}

		&__list {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			position: relative;
			display: flex;
			align-items: flex-start;
			gap: var(--space-slim);
			padding-bottom: var(--space-base);

			// The 2px line joining this marker to the next one in the same day.
			&:not(:last-child)::before {
				content: '';
				position: absolute;
				top: 28px;
				bottom: 0;
				left: 13px;
				width: 2px;
				background: var(--color-border);
			}

			&:last-child {
				padding-bottom: 0;
			}
		}

		&__marker {
			display: grid;
			width: 28px;
			height: 28px;
			box-sizing: border-box;
			flex: 0 0 auto;
			place-items: center;
			border: var(--border-base) solid var(--marker-edge);
			border-radius: var(--radius-circle);
			color: var(--marker-ink);
			background: var(--marker-surface);

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}

		&__item-body {
			display: flex;
			min-width: 0;
			flex-direction: column;
			gap: 6px;
			padding-top: 4px;
		}

		&__item-summary {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
			line-height: var(--typography--lineHeight-base);
		}

		&__author {
			display: inline-flex;
			min-width: 0;
			align-items: center;
			gap: 6px;
			font-size: var(--typography--fontSize-small);
		}

		&__system {
			display: grid;
			width: 24px;
			height: 24px;
			flex: 0 0 auto;
			place-items: center;
			border-radius: var(--radius-circle);
			color: var(--color-inactive);
			background: var(--color-inactive--surface);

			:global(svg) {
				width: 14px;
				height: 14px;
			}

			&--client {
				color: var(--color-client);
				background: var(--color-client--surface);
			}
		}

		&__author-name {
			overflow: hidden;
			color: var(--color-heading);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__author-dot,
		&__author-time {
			flex: 0 0 auto;
			color: var(--color-text--secondary);
		}

		&__loading {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__bone-pill {
			width: 72px;
			height: 22px;
			min-height: 0;
			border-radius: var(--radius-circle);
		}

		&__bone-row {
			display: flex;
			gap: var(--space-slim);
		}

		&__bone-marker {
			width: 28px;
			height: 28px;
			min-height: 0;
			flex: 0 0 auto;
			border-radius: var(--radius-circle);
		}

		&__bone-lines {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: var(--space-small);
			padding-top: 4px;
		}

		&__bone-line {
			width: 80%;
			height: 10px;
			min-height: 0;

			&--short {
				width: 45%;
			}
		}
	}
</style>
