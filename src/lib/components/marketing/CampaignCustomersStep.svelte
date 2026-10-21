<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Select from '$lib/components/ui/Select.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import CampaignAudience from './CampaignAudience.svelte';
	import CustomerGroupDialog from './CustomerGroupDialog.svelte';
	import { CONDITION_TILES } from './group-rule-tiles';
	import {
		fetchGroupPreviewCounts,
		fetchRuleLabels,
		marketingCustomerGroupsKey
	} from '$lib/marketing/api';
	import {
		marketingGroupPreviewKey,
		type MarketingCustomerGroup
	} from '$lib/marketing/customer-groups';
	import { groupRuleChips } from '$lib/marketing/group-rule-chips';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import usersGroupIcon from '@tabler/icons/outline/users-group.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// Step 2 (blueprint §8 step 2): who receives this campaign. A campaign always points at a saved
	// customer group, never an ad hoc rule set of its own -- Customer groups (M2) already owns building and
	// re-running rules, so this step only chooses one and shows its live count.
	let {
		customerGroupId = $bindable(),
		groups,
		isPending,
		isError,
		errorMessage = '',
		onRetry,
		onBack,
		onContinue
	}: {
		customerGroupId: string | null;
		groups: MarketingCustomerGroup[];
		isPending: boolean;
		isError: boolean;
		errorMessage?: string;
		onRetry: () => void;
		onBack: () => void;
		onContinue: () => void;
	} = $props();

	const queryClient = useQueryClient();

	let creatingGroup = $state(false);

	const groupOptions = $derived(groups.map((group) => ({ value: group.id, label: group.name })));
	const selectedGroup = $derived(groups.find((group) => group.id === customerGroupId) ?? null);

	// The same count the Delivery and Review steps ask for, so its cache is shared with theirs. The step owns
	// it because the footer says the number too.
	const countsQuery = createQuery(() => ({
		queryKey: marketingGroupPreviewKey(selectedGroup?.rules ?? { version: '1' }),
		queryFn: () => fetchGroupPreviewCounts(selectedGroup!.rules),
		enabled: selectedGroup !== null,
		staleTime: 10_000
	}));
	const counts = $derived(countsQuery.data);

	// Names for the services a group's rules hold, so its chip says "Used Boiler repair" and not a count.
	const serviceIds = $derived(selectedGroup?.rules.services ?? []);
	const labelsQuery = createQuery(() => ({
		queryKey: ['marketing', 'rule-labels', serviceIds],
		queryFn: () => fetchRuleLabels(serviceIds, []),
		enabled: serviceIds.length > 0,
		staleTime: 60_000
	}));
	const chips = $derived(
		selectedGroup
			? groupRuleChips(
					selectedGroup.rules,
					Object.fromEntries(
						(labelsQuery.data?.catalog_items ?? []).map((item) => [item.id, item.label])
					)
				)
			: []
	);

	const hint = $derived(
		!selectedGroup || countsQuery.isError
			? ''
			: countsQuery.isPending
				? 'Counting who will get this email…'
				: counts
					? `${counts.eligible} ${counts.eligible === 1 ? 'customer' : 'customers'} will get this email.`
					: ''
	);

	function groupCreated(group: MarketingCustomerGroup) {
		creatingGroup = false;
		void queryClient.invalidateQueries({ queryKey: marketingCustomerGroupsKey });
		customerGroupId = group.id;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SetupStepCard
	title="Who should receive this?"
	hint="Choose a saved customer group. Its count follows your customers and jobs automatically."
	icon={usersIcon}
	tone="growth"
>
	<div class="customers-body">
		{#if isPending}
			<div
				class="customers-bones"
				role="status"
				aria-label="Loading customer groups"
				aria-busy="true"
			>
				<span class="skeleton customers-bones__label"></span>
				<div class="customers-bones__row">
					<span class="skeleton customers-bones__select"></span>
					<span class="skeleton customers-bones__button"></span>
				</div>
				<div class="customers-bones__row">
					<span class="skeleton customers-bones__label"></span>
					<span class="skeleton customers-bones__chip"></span>
					<span class="skeleton customers-bones__chip"></span>
					<span class="skeleton customers-bones__chip"></span>
				</div>
				<span class="skeleton customers-bones__meter"></span>
				<span class="skeleton customers-bones__label"></span>
				<div class="customers-bones__list">
					{#each [0, 1, 2] as row (row)}
						<div class="customers-bones__item">
							<span class="skeleton customers-bones__tile"></span>
							<span class="customers-bones__lines">
								<span class="skeleton customers-bones__line"></span>
								<span class="skeleton customers-bones__line customers-bones__line--short"></span>
							</span>
							<span class="skeleton customers-bones__count"></span>
						</div>
					{/each}
				</div>
			</div>
		{:else if isError}
			<ErrorState description="Customer groups could not be loaded." retry={onRetry} />
		{:else if groups.length === 0}
			<EmptyState
				icon={usersGroupIcon}
				tone="growth"
				title="No customer groups yet"
				description="Save a rule set once and reuse it every time you email past customers."
			>
				{#snippet action()}
					<Button variant="primary" onclick={() => (creatingGroup = true)}>New group</Button>
				{/snippet}
			</EmptyState>
		{:else}
			<div class="group-picker">
				<Select
					id="campaign-customer-group"
					label="Customer group"
					value={customerGroupId ?? ''}
					options={groupOptions}
					placeholder="Choose a customer group"
					onchange={(value) => (customerGroupId = value)}
				/>
				<Button variant="secondary" onclick={() => (creatingGroup = true)}>
					<span class="btn-icon" aria-hidden="true">{@html plusIcon}</span> New group
				</Button>
			</div>

			{#if selectedGroup}
				{#if chips.length > 0}
					<div class="group-rules">
						<span class="group-rules__lead">Matches customers who</span>
						{#each chips as chip (chip.key)}
							<span class="group-rules__chip">
								<span
									class="group-rules__icon"
									style:color={`var(--color-${CONDITION_TILES[chip.key].tone})`}
									aria-hidden="true">{@html CONDITION_TILES[chip.key].icon}</span
								>
								{chip.text}
							</span>
						{/each}
					</div>
				{:else}
					<p class="group-rules__none">
						No conditions set. This group matches every active customer.
					</p>
				{/if}

				{#key selectedGroup.id}
					<CampaignAudience
						rules={selectedGroup.rules}
						{counts}
						isPending={countsQuery.isPending}
						isError={countsQuery.isError}
						onRetry={() => countsQuery.refetch()}
					/>
				{/key}
			{/if}
		{/if}

		{#if errorMessage}
			<p class="customers-body__error" role="alert">{errorMessage}</p>
		{/if}
	</div>

	{#snippet footer()}
		<Button variant="secondary" onclick={onBack}>
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		<span class="foot-hint" role="status">{hint}</span>
		<Button variant="primary" onclick={onContinue}>
			Continue <span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
	{/snippet}
</SetupStepCard>

{#if creatingGroup}
	<CustomerGroupDialog
		open={true}
		group={null}
		onSaved={groupCreated}
		onClose={() => (creatingGroup = false)}
	/>
{/if}

<style lang="scss">
	.customers-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-medium);

		&__error {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}
	}

	.group-picker {
		display: flex;
		align-items: flex-end;
		gap: var(--space-slim);

		:global(.select) {
			flex: 1;
		}
	}

	// What the group does, one chip per condition (the icon takes the colour of what it checks).
	.group-rules {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);

		&__lead {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}

		&__chip {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			height: 28px;
			padding: 0 10px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}

		&__icon {
			display: inline-flex;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__none {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.foot-hint {
		flex: 1;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: right;
	}

	.btn-icon {
		display: inline-flex;
	}

	.btn-icon :global(svg) {
		width: 16px;
		height: 16px;
		display: block;
	}

	// The step before the groups arrive: grey shapes where each block will be.
	.customers-bones {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}
		&__label {
			width: 90px;
			height: 12px;
		}
		&__select {
			flex: 1;
			height: 40px;
			border-radius: var(--radius-base);
		}
		&__button {
			width: 126px;
			height: 36px;
			border-radius: var(--radius-base);
		}
		&__chip {
			width: 120px;
			height: 28px;
			border-radius: var(--radius-base);
		}
		&__meter {
			height: 134px;
			border-radius: var(--radius-large);
		}
		&__list {
			display: flex;
			flex-direction: column;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: 12px;
		}
		&__item {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) var(--space-base);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}
		&__tile {
			flex: none;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);
		}
		&__lines {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);
		}
		&__line {
			width: 180px;
			height: 12px;

			&--short {
				width: 260px;
				height: 10px;
			}
		}
		&__count {
			width: 20px;
			height: 12px;
		}
	}
</style>
