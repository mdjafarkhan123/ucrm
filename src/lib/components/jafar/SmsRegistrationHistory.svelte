<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';

	type RegistrationEvent = {
		id: string;
		registration_id: string;
		event_type:
			| 'started'
			| 'info_updated'
			| 'submitted'
			| 'resubmitted'
			| 'approved'
			| 'action_needed'
			| 'readiness_checked';
		from_status: string | null;
		to_status: string | null;
		detail: string | null;
		provider_outcome: string | null;
		created_at: string;
		country_code: string | null;
		sender_type: string | null;
		use_case: string | null;
	};
	type ListResponse = { events?: RegistrationEvent[]; error?: string };

	let { organizationId }: { organizationId: string } = $props();

	const listQuery = createQuery<ListResponse>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'sms', 'registration-events'],
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/registration-events`
			);
			const result = (await response.json()) as ListResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'SMS registration history could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	const eventLabels: Record<RegistrationEvent['event_type'], string> = {
		started: 'Registration started',
		info_updated: 'Information updated',
		submitted: 'Submitted to carrier',
		resubmitted: 'Resubmitted to carrier',
		approved: 'Approved',
		action_needed: 'Action needed',
		readiness_checked: 'Readiness checked'
	};
	const eventTone: Record<
		RegistrationEvent['event_type'],
		'success' | 'warning' | 'critical' | 'informative' | 'inactive'
	> = {
		started: 'inactive',
		info_updated: 'inactive',
		submitted: 'informative',
		resubmitted: 'informative',
		approved: 'success',
		action_needed: 'critical',
		readiness_checked: 'inactive'
	};

	function formatTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}

	function registrationLabel(registrationEvent: RegistrationEvent) {
		if (!registrationEvent.country_code) return 'Registration removed';
		return `${registrationEvent.country_code} · ${registrationEvent.sender_type} · ${registrationEvent.use_case}`;
	}
</script>

<div class="sms-registration-history">
	<div class="sms-registration-history__heading">
		<h3>SMS registration &amp; provider history</h3>
		<p>
			Every submission, readiness check and carrier decision, most recent first. Never includes
			provider secrets or message content.
		</p>
	</div>

	{#if listQuery.isPending}
		<LoadingSkeleton variant="table" rows={3} label="Loading SMS registration history" />
	{:else if listQuery.isError}
		<ErrorState
			title="SMS registration history could not be loaded"
			description={listQuery.error instanceof Error ? listQuery.error.message : 'Try again.'}
			retry={() => listQuery.refetch()}
		/>
	{:else if (listQuery.data?.events ?? []).length === 0}
		<EmptyState
			title="No registration activity yet"
			description="Starting or checking a registration will record its history here."
		/>
	{:else}
		<div class="sms-registration-history__table-wrap">
			<table>
				<caption>SMS registration &amp; provider history</caption>
				<thead>
					<tr>
						<th scope="col">Registration</th>
						<th scope="col">Event</th>
						<th scope="col">Status change</th>
						<th scope="col">Note</th>
						<th scope="col">When</th>
					</tr>
				</thead>
				<tbody>
					{#each listQuery.data?.events ?? [] as registrationEvent (registrationEvent.id)}
						<tr>
							<td>{registrationLabel(registrationEvent)}</td>
							<td>
								<Badge status={eventTone[registrationEvent.event_type]}>
									{eventLabels[registrationEvent.event_type]}
								</Badge>
							</td>
							<td>
								{#if registrationEvent.from_status || registrationEvent.to_status}
									{registrationEvent.from_status ?? 'new'} &rarr; {registrationEvent.to_status ??
										'unchanged'}
								{:else}
									&mdash;
								{/if}
							</td>
							<td>{registrationEvent.provider_outcome ?? registrationEvent.detail ?? '—'}</td>
							<td>{formatTime(registrationEvent.created_at)}</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	{/if}
</div>

<style lang="scss">
	.sms-registration-history {
		display: grid;
		gap: var(--space-base);
	}
	.sms-registration-history__heading h3 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.sms-registration-history__heading p {
		margin: var(--space-small) 0 0;
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.sms-registration-history__table-wrap {
		overflow-x: auto;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
		text-align: left;
	}
	caption {
		padding-bottom: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: left;
	}
	th,
	td {
		padding: var(--space-slim) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
		vertical-align: top;
	}
	th {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}
	td:first-child {
		color: var(--color-heading);
		font-weight: 700;
		text-transform: capitalize;
	}
</style>
