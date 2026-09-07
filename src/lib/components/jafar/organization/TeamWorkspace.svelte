<script lang="ts">
	import type { EffectiveAccess, TeamResponse } from '$lib/components/jafar/organization/types';
	import type { CreateQueryResult } from '@tanstack/svelte-query';
	import type { OrganizationDetailPreview } from '$lib/jafar/organization-detail-preview';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import TeamAccessActions from '$lib/components/jafar/TeamAccessActions.svelte';

	let {
		access,
		preview,
		teamQuery
	}: {
		access: EffectiveAccess | null;
		preview: OrganizationDetailPreview | null;
		teamQuery: CreateQueryResult<TeamResponse, Error>;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<TabPanel value="team">
	<div class="organization-workspace">
		{#if preview}
			<section class="organization-detail__section" aria-labelledby="team-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Team access</p>
					<h2 id="team-title">Read-only access review</h2>
					<p>
						Contractor owners and administrators manage their team. Jafar can inspect effective
						access and recovery readiness without silently changing a role.
					</p>
				</div>
				<Card class="organization-detail__team-card">
					<div class="organization-detail__table-wrap">
						<table>
							<caption>Development-only team access preview</caption>
							<thead
								><tr
									><th scope="col">Team member</th><th scope="col">Role</th><th scope="col"
										>Effective access</th
									><th scope="col">Access note</th></tr
								></thead
							>
							<tbody
								>{#each preview?.team ?? [] as member (member.name)}<tr
										><td>{member.name}</td><td>{member.role}</td><td>{member.access}</td><td
											>{member.note}</td
										></tr
									>{/each}</tbody
							>
						</table>
					</div>
					<div class="organization-detail__recovery-note">
						<span class="organization-detail__card-icon organization-detail__card-icon--warning"
							>{@html alertIcon}</span
						>
						<div>
							<h3>Administrator recovery</h3>
							<p>
								Email recovery will require independent verification and identity reconfirmation
								when its secure workflow is built. Passwords and setup links are never shown here.
							</p>
						</div>
						<Badge status={preview?.setup.tone}>{preview?.setup.state}</Badge>
					</div>
				</Card>
			</section>
		{:else if access}
			<section class="organization-detail__section" aria-labelledby="team-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Team access</p>
					<h2 id="team-title">Read-only access review</h2>
					<p>
						Contractor owners and administrators manage their team. Jafar can inspect roles and
						administrator readiness, fix a support-case profile correction, and recover a locked-out
						administrator's login without silently changing permissions.
					</p>
				</div>
				<Card class="organization-detail__team-card">
					{#if teamQuery.isPending}
						<LoadingSkeleton variant="table" label="Loading team members" />
					{:else if teamQuery.isError}
						<ErrorState
							title="Team members could not be loaded"
							description={teamQuery.error instanceof Error
								? teamQuery.error.message
								: 'Team members could not be loaded. Try again.'}
							retry={() => teamQuery.refetch()}
						/>
					{:else}
						<TeamAccessActions
							organizationId={access.organization.id}
							members={teamQuery.data?.members ?? []}
						/>
						<div class="organization-detail__recovery-note">
							<span
								class="organization-detail__card-icon organization-detail__card-icon--{teamQuery
									.data?.has_administrator
									? 'success'
									: 'warning'}"
								>{@html teamQuery.data?.has_administrator ? checkIcon : alertIcon}</span
							>
							<div>
								<h3>Administrator readiness</h3>
								<p>
									{teamQuery.data?.has_administrator
										? 'At least one owner or admin can manage this organization.'
										: 'No owner or admin exists for this organization. Recovery is not built yet — coordinate with the contractor directly.'}
								</p>
							</div>
							<Badge status={teamQuery.data?.has_administrator ? 'success' : 'warning'}
								>{teamQuery.data?.has_administrator ? 'Ready' : 'Needs attention'}</Badge
							>
						</div>
					{/if}
				</Card>
			</section>
		{/if}
	</div>
</TabPanel>

<!-- eslint-enable svelte/no-at-html-tags -->
<style lang="scss">
	.organization-workspace {
		display: grid;
		gap: var(--space-larger);
		min-width: 0;
	}
	.organization-detail__eyebrow {
		margin: 0 0 var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h2,
	h3,
	p {
		margin: 0;
	}
	h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}
	h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		line-height: var(--typography--lineHeight-tight);
	}
	.organization-detail__section-heading > p:last-child {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}
	.organization-detail__section {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: var(--space-base);
		min-width: 0;
	}
	.organization-detail__section > * {
		min-width: 0;
	}
	.organization-detail__card-icon {
		display: grid;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.organization-detail__card-icon {
		width: 36px;
		height: 36px;
	}
	.organization-detail__card-icon :global(svg) {
		width: 20px;
		height: 20px;
	}
	.organization-detail__card-icon--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.organization-detail__card-icon--warning {
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.organization-workspace :global(.organization-detail__team-card) {
		display: grid;
		gap: var(--space-large);
	}
	.organization-detail__table-wrap {
		overflow-x: auto;
	}
	.organization-workspace table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
		text-align: left;
	}
	.organization-workspace caption {
		padding-bottom: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: left;
	}
	.organization-workspace th,
	.organization-workspace td {
		padding: var(--space-slim) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
		vertical-align: top;
	}
	.organization-workspace th {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}
	.organization-workspace td:first-child {
		color: var(--color-heading);
		font-weight: 700;
	}
	.organization-detail__recovery-note {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-base);
		border-radius: var(--radius-small);
		background: var(--color-surface--background--subtle);
	}
	.organization-detail__recovery-note > div {
		flex: 1;
		min-width: 0;
	}
	.organization-detail__recovery-note h3 {
		font-size: var(--typography--fontSize-base);
	}
	.organization-detail__recovery-note p {
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}
	@media (max-width: 639px) {
		.organization-detail__recovery-note {
			flex-direction: column;
		}
	}
</style>
