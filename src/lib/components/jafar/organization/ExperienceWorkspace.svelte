<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import compassIcon from '@tabler/icons/outline/compass.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ExperienceDecisionDialog from './ExperienceDecisionDialog.svelte';
	import { canUseJafarPath } from '$lib/jafar/team-access';
	import { organizationExperienceQuery } from '$lib/jafar/organization-experience-queries';
	import { jafarOrganizationExperienceKey } from '$lib/jafar/query-keys';
	import type { OrganizationDetailPreview } from '$lib/jafar/organization-detail-preview';
	import type { ExperienceTabResponse } from '$lib/experience/types';
	import { formatDateTime } from './format';

	// Multi-industry foundation B1 (plan "Organization experience profile"): which Industry experience the
	// business runs on, who confirmed it and why, and every earlier decision. A business without a
	// confirmed profile shows that plainly; nothing is assumed from its trade or its history.
	let {
		organizationId,
		preview
	}: {
		organizationId: string | undefined;
		preview: OrganizationDetailPreview | null;
	} = $props();

	const queryClient = useQueryClient();
	const experienceQuery = createQuery(() => ({
		...organizationExperienceQuery(organizationId ?? ''),
		enabled: !preview && Boolean(organizationId)
	}));
	const data = $derived(experienceQuery.data);
	const current = $derived(
		data?.history.find((entry) => entry.id === data.profile.decision_id) ?? null
	);
	const canDecide = $derived(
		Boolean(organizationId) &&
			canUseJafarPath(
				{ role: page.data.owner.role, access: page.data.owner.access },
				`/api/jafar/organizations/${organizationId}/experience`,
				'POST'
			)
	);

	let dialogOpen = $state(false);
	let idempotencyKey = $state('');
	let actionError = $state('');

	function openDialog() {
		idempotencyKey = crypto.randomUUID();
		actionError = '';
		dialogOpen = true;
	}

	const decide = createMutation(() => ({
		mutationFn: async (input: {
			experience_key: string;
			definition_version: number;
			business_type_key: string | null;
			service_shape: string;
			reason: string;
		}) => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/experience`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					...input,
					expected_previous_decision_id: data?.profile.decision_id ?? null,
					idempotency_key: idempotencyKey
				})
			});
			const result = (await response.json()) as ExperienceTabResponse & {
				field_errors?: Record<string, string>;
			};
			if (!response.ok) {
				throw new Error(
					Object.values(result.field_errors ?? {})[0] ??
						result.error ??
						'The decision could not be recorded. Try again.'
				);
			}
			return result;
		},
		onSuccess: (result) => {
			queryClient.setQueryData(jafarOrganizationExperienceKey(organizationId), result);
			dialogOpen = false;
		},
		onError: (error) => {
			actionError = error.message;
		},
		onSettled: () => {
			void queryClient.invalidateQueries({
				queryKey: jafarOrganizationExperienceKey(organizationId)
			});
		}
	}));

	const SOURCE_LABELS: Record<string, string> = {
		review: 'Uplift review',
		migration: 'Migration review',
		provisioning: 'Provisioning'
	};
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<TabPanel value="experience">
	<div class="experience">
		{#if preview}
			<EmptyState
				title="Experience is not part of this preview"
				description="Development scenarios do not include an experience profile."
			/>
		{:else if experienceQuery.isPending}
			<LoadingSkeleton variant="card" label="Loading experience profile" />
			<LoadingSkeleton variant="card" label="Loading decision history" />
		{:else if experienceQuery.isError && !data}
			<ErrorState
				title="Experience profile could not be loaded"
				description={experienceQuery.error.message}
				retry={() => experienceQuery.refetch()}
			/>
		{:else if data}
			<SectionBlock title="Profile" icon={compassIcon}>
				{#snippet actions()}
					{#if canDecide && data.profile.state !== 'unresolved' && data.profile.state !== 'unrecognized'}
						<Button
							variant={current ? 'secondary' : 'primary'}
							variation={current ? 'subtle' : undefined}
							size="small"
							onclick={openDialog}
							disabled={data.definitions.length === 0}
							>{current ? 'Review profile' : 'Confirm experience'}</Button
						>
					{/if}
				{/snippet}

				{#if data.profile.state === 'missing'}
					<Banner type="warning">
						<strong>No experience confirmed yet.</strong> Nothing is switched on from a guess. Its tools
						keep working as they do today until Uplift reviews this business.
					</Banner>
				{:else if data.profile.state === 'unrecognized'}
					<Banner type="error">
						<strong>This experience is not available in this version of Uplift.</strong> No experience
						is enabled from it. Fix the definition before recording another decision.
					</Banner>
				{:else if data.profile.state === 'unresolved'}
					<Banner type="error">
						<strong>The decision history could not be read as one chain.</strong> No experience is enabled
						until it is repaired.
					</Banner>
				{/if}

				{#if current}
					<div class="experience__profile">
						<div class="experience__heading">
							<h3>{current.experience_name ?? current.experience_key}</h3>
							{#if data.profile.state === 'confirmed'}
								<Badge status="success">Confirmed</Badge>
							{/if}
							<span class="experience__version">Definition v{current.definition_version}</span>
						</div>
						<dl class="experience__facts">
							<div>
								<dt>Business type</dt>
								<dd>
									{#if current.business_type_label}
										{current.business_type_label}
									{:else}
										<span class="experience__muted">Not yet confirmed</span>
									{/if}
								</dd>
							</div>
							<div>
								<dt>Agreement at decision</dt>
								<dd>{current.agreement?.package_name ?? 'No agreement in force'}</dd>
							</div>
							<div>
								<dt>Confirmed by</dt>
								<dd>{current.actor_email}</dd>
							</div>
							<div>
								<dt>Confirmed</dt>
								<dd>{formatDateTime(current.decided_at)}</dd>
							</div>
							<div class="experience__wide">
								<dt>Services reviewed</dt>
								<dd>{current.service_shape}</dd>
							</div>
							<div class="experience__wide">
								<dt>Reason</dt>
								<dd>{current.reason}</dd>
							</div>
						</dl>
					</div>
				{/if}
			</SectionBlock>

			<SectionBlock title="Decision history" icon={historyIcon}>
				{#if data.history.length === 0}
					<p class="experience__muted">No decisions recorded yet.</p>
				{:else}
					<ol class="experience__history">
						{#each data.history as entry (entry.id)}
							<li class="experience__entry">
								<div class="experience__entry-top">
									<strong
										>{entry.experience_name ?? entry.experience_key} · {entry.business_type_label ??
											'Business type not yet confirmed'}</strong
									>
									{#if entry.id === data.profile.decision_id}
										<Badge status="informative">Current</Badge>
									{/if}
								</div>
								<p class="experience__entry-meta">
									{formatDateTime(entry.decided_at)} · {entry.actor_email} · {SOURCE_LABELS[
										entry.source
									] ?? entry.source} · v{entry.definition_version}
								</p>
								<p>{entry.reason}</p>
								<p class="experience__muted">Services: {entry.service_shape}</p>
							</li>
						{/each}
					</ol>
				{/if}
			</SectionBlock>
		{/if}
	</div>
</TabPanel>
<!-- eslint-enable svelte/no-at-html-tags -->

{#if dialogOpen && data}
	<ExperienceDecisionDialog
		definitions={data.definitions}
		{current}
		agreement={data.current_agreement}
		pending={decide.isPending}
		error={actionError}
		onSubmit={(input) => decide.mutate(input)}
		onClose={() => (dialogOpen = false)}
	/>
{/if}

<style lang="scss">
	.experience {
		display: grid;
		gap: var(--space-large);
		min-width: 0;

		&__profile {
			display: grid;
			gap: var(--space-base);
		}

		&__heading {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
			}
		}

		&__version {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__facts {
			display: grid;
			grid-template-columns: repeat(4, minmax(0, 1fr));
			gap: var(--space-base);
			margin: 0;

			div {
				min-width: 0;
			}

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			dd {
				margin: var(--space-smallest) 0 0;
				color: var(--color-heading);
				overflow-wrap: anywhere;
			}
		}

		&__wide {
			grid-column: span 2;
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
		}

		&__history {
			display: grid;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__entry {
			display: grid;
			gap: var(--space-smaller);
			padding: var(--space-base) 0;
			border-bottom: var(--border-base) solid var(--color-border);

			&:first-child {
				padding-top: 0;
			}

			&:last-child {
				padding-bottom: 0;
				border-bottom: 0;
			}

			p {
				margin: 0;
				overflow-wrap: anywhere;
			}
		}

		&__entry-top {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-heading);
		}

		&__entry-meta {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	@media (max-width: 1100px) {
		.experience__facts {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 639px) {
		.experience__facts {
			grid-template-columns: 1fr;
		}

		.experience__wide {
			grid-column: auto;
		}
	}
</style>
