<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import arrowsDiffIcon from '@tabler/icons/outline/arrows-diff.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { organizationAccessComparisonQuery } from '$lib/jafar/organization-experience-queries';
	import type { AccessChange, AccessComparisonMember } from '$lib/experience/types';

	// Multi-industry foundation B5: today's access beside the access the Organization would have once its
	// Industry experience takes part, for its real Package and each real member. Read-only: opening it
	// never changes who can do what. It loads when Uplift asks for it, not with the tab.
	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	let requested = $state(false);
	const comparison = createQuery(() => ({
		...organizationAccessComparisonQuery(organizationId),
		enabled: requested
	}));
	const data = $derived(comparison.data);

	function prefetch() {
		void queryClient.prefetchQuery(organizationAccessComparisonQuery(organizationId));
	}

	const differenceCount = (member: AccessComparisonMember) =>
		member.differences.features.length +
		member.differences.permissions.length +
		member.differences.navigation.length;

	const totalDifferences = $derived(
		data
			? data.organization.features.length +
					data.members.reduce((total, member) => total + differenceCount(member), 0)
			: 0
	);

	const memberName = (member: AccessComparisonMember) =>
		member.name ?? member.email ?? 'Unnamed member';

	const groups = (member: AccessComparisonMember): { title: string; items: AccessChange[] }[] =>
		[
			{ title: 'Capabilities', items: member.differences.features },
			{ title: 'Permissions', items: member.differences.permissions },
			{ title: 'Menu', items: member.differences.navigation }
		].filter((group) => group.items.length > 0);
</script>

<SectionBlock
	title="Access comparison"
	icon={arrowsDiffIcon}
	hint="Today’s access beside the access with the experience taking part. Nothing here changes who can do what."
>
	<div class="comparison">
		<div class="comparison__actions">
			{#if requested}
				<Button
					variant="secondary"
					variation="subtle"
					size="small"
					loading={comparison.isFetching}
					onclick={() => comparison.refetch()}>Run again</Button
				>
			{:else}
				<Button
					variant="secondary"
					size="small"
					onhover={prefetch}
					onclick={() => (requested = true)}>Compare access</Button
				>
			{/if}
		</div>
		{#if !requested}
			<p class="comparison__muted">
				Compares this business’s real Package and each team member before any switch, so a loss or
				gain can be investigated first.
			</p>
		{:else if comparison.isPending}
			<LoadingSkeleton variant="card" label="Comparing access" />
		{:else if comparison.isError && !data}
			<ErrorState
				title="Access could not be compared"
				description={comparison.error.message}
				retry={() => comparison.refetch()}
			/>
		{:else if data}
			<Banner type={data.basis.state === 'unavailable' ? 'warning' : 'notice'}>
				{data.basis.explanation}
			</Banner>

			{#if data.verdict !== 'unavailable'}
				<div class="comparison__verdict">
					{#if data.verdict === 'same'}
						<Badge status="success">Same access</Badge>
						<span class="comparison__muted"
							>Every capability, permission and menu item matches for {data.members.length}
							{data.members.length === 1 ? 'member' : 'members'}.</span
						>
					{:else}
						<Badge status="critical"
							>{totalDifferences}
							{totalDifferences === 1 ? 'difference' : 'differences'} to review</Badge
						>
						<span class="comparison__muted"
							>Do not switch this business until each one is explained.</span
						>
					{/if}
				</div>

				<dl class="comparison__facts">
					<div>
						<dt>Package</dt>
						<dd>{data.package_name ?? 'No package'}</dd>
					</div>
					<div>
						<dt>Capabilities on today</dt>
						<dd>{data.capabilities_today}</dd>
					</div>
					<div>
						<dt>With the experience</dt>
						<dd>{data.capabilities_with_experience}</dd>
					</div>
				</dl>

				{#if data.organization.features.length}
					<div class="comparison__block">
						<h3>Business capabilities</h3>
						{@render changeList(data.organization.features)}
					</div>
				{/if}

				{#if data.members.length === 0}
					<p class="comparison__muted">This business has no team members yet.</p>
				{:else}
					<ul class="comparison__members">
						{#each data.members as member (member.user_id)}
							{@const count = differenceCount(member)}
							<li class="comparison__member">
								<div class="comparison__member-top">
									<div class="comparison__who">
										<strong>{memberName(member)}</strong>
										<span class="comparison__muted"
											>{member.email && member.name ? `${member.email} · ` : ''}{member.role}</span
										>
									</div>
									<span class="comparison__counts"
										>{member.permissions_today} → {member.permissions_with_experience} permissions</span
									>
									{#if count === 0}
										<Badge status="success" size="small">Same</Badge>
									{:else}
										<Badge status="critical" size="small">{count} to review</Badge>
									{/if}
								</div>
								{#each groups(member) as group (group.title)}
									<div class="comparison__block">
										<h3>{group.title}</h3>
										{@render changeList(group.items)}
									</div>
								{/each}
							</li>
						{/each}
					</ul>
				{/if}
			{/if}
		{/if}
	</div>
</SectionBlock>

{#snippet changeList(items: AccessChange[])}
	<ul class="comparison__changes">
		{#each items as item (item.key)}
			<li>
				<Badge status={item.direction === 'lost' ? 'warning' : 'critical'} size="small"
					>{item.direction}</Badge
				>
				<div>
					<code>{item.key}</code>
					<p class="comparison__muted">{item.cause}</p>
				</div>
			</li>
		{/each}
	</ul>
{/snippet}

<style lang="scss">
	.comparison {
		display: grid;
		gap: var(--space-base);
		min-width: 0;

		&__actions {
			display: flex;
			justify-content: flex-start;
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__verdict {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__facts {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
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

		&__members {
			display: grid;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__member {
			display: grid;
			gap: var(--space-small);
			padding: var(--space-base) 0;
			border-bottom: var(--border-base) solid var(--color-border);

			&:first-child {
				padding-top: 0;
			}

			&:last-child {
				padding-bottom: 0;
				border-bottom: 0;
			}
		}

		&__member-top {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small) var(--space-base);
		}

		&__who {
			display: grid;
			flex: 1 1 14rem;
			min-width: 0;
			overflow-wrap: anywhere;

			strong {
				color: var(--color-heading);
			}
		}

		&__counts {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-variant-numeric: tabular-nums;
		}

		&__block {
			display: grid;
			gap: var(--space-small);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__changes {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				align-items: flex-start;
				gap: var(--space-small);
			}

			div {
				min-width: 0;
			}

			code {
				overflow-wrap: anywhere;
			}

			p {
				margin: var(--space-smallest) 0 0;
			}
		}
	}

	// The shared Badge capitalizes every word; these read as sentences.
	.comparison :global(.badge) {
		text-transform: none;
	}

	@media (max-width: 639px) {
		.comparison__facts {
			grid-template-columns: 1fr;
		}
	}
</style>
