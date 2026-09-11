<script lang="ts">
	import { createInfiniteQuery } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { fetchTeamActivity, teamActivityKey, type TeamActivityEntry } from '$lib/team/api';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';

	const actorUserId = $derived(page.data.user?.id ?? '');

	const activityQuery = createInfiniteQuery(() => ({
		queryKey: teamActivityKey(actorUserId),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) => fetchTeamActivity(pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined,
		staleTime: 30_000,
		enabled: Boolean(actorUserId)
	}));

	const entries = $derived(activityQuery.data?.pages.flatMap((p) => p.entries) ?? []);

	const ROLE_LABELS: Record<string, string> = {
		owner: 'Owner',
		admin: 'Administrator',
		office: 'Office staff',
		sales: 'Sales',
		field: 'Field employee',
		finance: 'Finance'
	};
	const PROFILE_FIELD_LABELS: Record<string, string> = {
		full_name: 'name',
		work_phone: 'work phone',
		job_title: 'job title',
		schedule_color: 'calendar color'
	};
	const CATEGORY_LABELS: Record<string, string> = {
		'invitation.sent': 'Invitation',
		'invitation.resent': 'Invitation',
		'invitation.cancelled': 'Invitation',
		'invitation.expired': 'Invitation',
		'invitation.accepted': 'Invitation',
		'member.role_changed': 'Permissions',
		'member.permissions_changed': 'Permissions',
		'member.profile_updated': 'Profile',
		'member.availability_updated': 'Profile',
		'member.deactivated': 'Status',
		'member.work_unassigned': 'Status',
		'member.restored': 'Status',
		'member.removed': 'Status',
		'member.identity_revoked': 'Status',
		'ownership.transfer_requested': 'Ownership',
		'ownership.transfer_accepted': 'Ownership',
		'ownership.transfer_declined': 'Ownership',
		'ownership.transfer_cancelled': 'Ownership'
	};

	function roleLabel(value: unknown) {
		const key = String(value);
		return ROLE_LABELS[key] ?? key;
	}

	function joinList(values: string[]) {
		if (values.length === 0) return '';
		if (values.length === 1) return values[0];
		if (values.length === 2) return `${values[0]} and ${values[1]}`;
		return `${values.slice(0, -1).join(', ')}, and ${values[values.length - 1]}`;
	}

	function stringList(value: unknown, labels?: Record<string, string>): string[] {
		if (!Array.isArray(value)) return [];
		return value
			.filter((item): item is string => typeof item === 'string')
			.map((item) => labels?.[item] ?? item);
	}

	// Every event type gets a plain-English sentence. Some fields in `summary` (previous_status,
	// transfer_id, …) are recorded for completeness but never need to appear in the one-line feed.
	function sentenceFor(entry: TeamActivityEntry): string {
		const actor = entry.actor_name;
		const subject = entry.subject_name ?? 'a team member';
		const email = entry.invited_email ?? 'the invitee';
		const summary = entry.summary;

		switch (entry.event_type) {
			case 'invitation.sent':
				return `${actor} invited ${email} to join as ${roleLabel(summary.role)}.`;
			case 'invitation.resent':
				return `${actor} resent the invitation to ${email}.`;
			case 'invitation.cancelled':
				return `${actor} cancelled the invitation to ${email}.`;
			case 'invitation.expired':
				return `The invitation to ${email} expired.`;
			case 'invitation.accepted':
				return `${email} accepted the invitation and joined as ${roleLabel(summary.role)}.`;
			case 'member.role_changed':
				return `${actor} changed ${subject}’s role from ${roleLabel(summary.previous_role)} to ${roleLabel(summary.new_role)}.`;
			case 'member.permissions_changed': {
				const added = stringList(summary.added_permissions);
				const removed = stringList(summary.removed_permissions);
				if (added.length && removed.length) {
					return `${actor} gave ${subject} access to ${joinList(added)}, and removed access to ${joinList(removed)}.`;
				}
				if (added.length) return `${actor} gave ${subject} access to ${joinList(added)}.`;
				if (removed.length) return `${actor} removed ${subject}’s access to ${joinList(removed)}.`;
				return `${actor} updated ${subject}’s permissions.`;
			}
			case 'member.profile_updated': {
				const fields = stringList(summary.changed_fields, PROFILE_FIELD_LABELS);
				return `${actor} updated ${subject}’s ${joinList(fields) || 'profile'}.`;
			}
			case 'member.availability_updated':
				return `${actor} updated ${subject}’s availability.`;
			case 'member.deactivated':
				return `${actor} deactivated ${subject}.`;
			case 'member.work_unassigned': {
				const counts: [unknown, string][] = [
					[summary.unassigned_assessments, 'assessment'],
					[summary.unassigned_visits, 'visit'],
					[summary.unassigned_tasks, 'task']
				];
				const parts = counts
					.map(([value, noun]) => [Number(value ?? 0), noun] as const)
					.filter(([count]) => count > 0)
					.map(([count, noun]) => `${count} ${noun}${count === 1 ? '' : 's'}`);
				return `Deactivating ${subject} freed up ${joinList(parts) || 'their assigned work'}.`;
			}
			case 'member.restored':
				return `${actor} restored ${subject} as ${roleLabel(summary.restored_role)}.`;
			case 'member.removed':
				return `${actor} removed ${subject} from the team.`;
			case 'member.identity_revoked':
				return `${actor} revoked ${subject}’s login access.`;
			case 'ownership.transfer_requested':
				return `${actor} requested to transfer ownership to ${subject}.`;
			case 'ownership.transfer_accepted':
				return `${actor} accepted ownership of the account from ${subject}.`;
			case 'ownership.transfer_declined':
				return `${actor} declined the ownership transfer from ${subject}.`;
			case 'ownership.transfer_cancelled':
				return `${actor} cancelled the ownership transfer to ${subject}.`;
			default:
				return `${actor} made a team change.`;
		}
	}

	function categoryFor(entry: TeamActivityEntry) {
		return CATEGORY_LABELS[entry.event_type] ?? 'Team';
	}

	function formatEventTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}
</script>

<svelte:head><title>Activity log · Team · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="fill">
		<PageHeader
			eyebrow="Team & access"
			title="Activity log"
			description="Every access and team change made in your business, newest first."
		/>

		{#if activityQuery.isPending}
			<LoadingSkeleton variant="card" rows={5} />
		{:else if activityQuery.isError}
			<ErrorState
				description="The activity log could not be loaded. Refresh and try again."
				retry={() => activityQuery.refetch()}
			/>
		{:else if entries.length === 0}
			<EmptyState
				icon={historyIcon}
				title="Nothing here yet"
				description="Invites, role changes, and other team updates will show up here as they happen."
			/>
		{:else}
			<ol class="activity">
				{#each entries as entry (entry.id)}
					<li class="activity__event">
						<p class="activity__sentence">{sentenceFor(entry)}</p>
						<p class="activity__meta">
							{categoryFor(entry)} · {formatEventTime(entry.created_at)}
						</p>
					</li>
				{/each}
			</ol>
			<ListLoadMore
				hasNextPage={activityQuery.hasNextPage}
				isFetchingNextPage={activityQuery.isFetchingNextPage}
				onLoadMore={() => void activityQuery.fetchNextPage()}
				endLabel="That’s the whole history."
			/>
		{/if}
	</PageContainer>
</div>

<style lang="scss">
	.activity {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;

		&__event {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__sentence {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
		}

		&__meta {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
