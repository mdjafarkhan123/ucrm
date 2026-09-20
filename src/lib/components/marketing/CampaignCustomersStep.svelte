<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import Select from '$lib/components/ui/Select.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import CustomerGroupDialog from './CustomerGroupDialog.svelte';
	import CustomerGroupPreview from './CustomerGroupPreview.svelte';
	import { marketingCustomerGroupsKey } from '$lib/marketing/api';
	import type { MarketingCustomerGroup } from '$lib/marketing/customer-groups';
	import usersGroupIcon from '@tabler/icons/outline/users-group.svg?raw';
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

	function groupCreated(group: MarketingCustomerGroup) {
		creatingGroup = false;
		void queryClient.invalidateQueries({ queryKey: marketingCustomerGroupsKey });
		customerGroupId = group.id;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="panel">
	<header class="panel__head">
		<h2>Who should receive this?</h2>
		<p>Choose a saved customer group. Its count follows your customers and jobs automatically.</p>
	</header>

	<div class="panel__body">
		{#if isPending}
			<LoadingSkeleton variant="text" rows={2} label="Loading customer groups" />
		{:else if isError}
			<ErrorState description="Customer groups could not be loaded." retry={onRetry} />
		{:else if groups.length === 0}
			<EmptyState
				icon={usersGroupIcon}
				title="No customer groups yet"
				description="Save a rule set once and reuse it every time you email past customers."
			>
				{#snippet action()}
					<Button variant="secondary" onclick={() => (creatingGroup = true)}>New group</Button>
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
				<Button variant="secondary" size="small" onclick={() => (creatingGroup = true)}>
					New group
				</Button>
			</div>

			{#if selectedGroup}
				<CustomerGroupPreview rules={selectedGroup.rules} />
			{/if}
		{/if}

		{#if errorMessage}
			<p class="panel__error" role="alert">{errorMessage}</p>
		{/if}
	</div>

	<footer class="panel__foot">
		<Button variant="secondary" variation="subtle" onclick={onBack}>
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		<Button variant="primary" onclick={onContinue}>
			Continue <span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
	</footer>
</section>

{#if creatingGroup}
	<CustomerGroupDialog
		open={true}
		group={null}
		onSaved={groupCreated}
		onClose={() => (creatingGroup = false)}
	/>
{/if}

<style lang="scss">
	.panel {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-base);
		overflow: hidden;

		&__head {
			padding: var(--space-large) var(--space-large) var(--space-base);
			border-bottom: 1px solid var(--color-border);

			h2 {
				font-family: var(--typography--fontFamily-display);
				font-size: var(--typography--fontSize-larger);
				font-weight: 600;
				color: var(--color-heading);
				margin: 0;
			}
			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
			}
		}

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-large);
		}

		&__error {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-slim);
			padding: var(--space-base) var(--space-large);
			border-top: 1px solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}
	}

	.group-picker {
		display: flex;
		align-items: flex-end;
		gap: var(--space-small);

		:global(.select) {
			flex: 1;
		}
	}

	.btn-icon :global(svg) {
		width: 16px;
		height: 16px;
		display: block;
	}

	@media (max-width: 560px) {
		.panel__foot {
			flex-direction: column-reverse;
			align-items: stretch;
		}
		.group-picker {
			flex-direction: column;
			align-items: stretch;
		}
	}
</style>
