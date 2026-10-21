<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import ClientTagSelect from '$lib/components/clients/ClientTagSelect.svelte';
	import FreeTextChipInput from './FreeTextChipInput.svelte';
	import AsyncMultiPicker from './AsyncMultiPicker.svelte';
	import {
		searchCatalogItemsForRule,
		searchClientsForRule,
		type RuleLabel
	} from '$lib/marketing/api';
	import { LEAD_SOURCES } from '$lib/clients/lead-sources';
	import {
		incompleteGroupConditions,
		MARKETING_GROUP_RULE_CONDITIONS,
		type MarketingGroupRuleConditionKey,
		type MarketingGroupRules
	} from '$lib/marketing/customer-groups';
	import filterIcon from '@tabler/icons/outline/filter.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import circlePlusIcon from '@tabler/icons/outline/circle-plus.svg?raw';
	import { CONDITION_TILES } from './group-rule-tiles';

	// One AND-only condition list, the same "add a condition" shape as
	// `settings/automation/RecipeBuilder.svelte`'s If block: start empty, add only the checks this group
	// needs, remove one without hunting through nine always-visible fields.
	let {
		rules = $bindable<MarketingGroupRules>(),
		labels = { catalog_items: [], clients: [] },
		showIncomplete = false
	}: {
		rules?: MarketingGroupRules;
		/** Names for ids a reopened saved group already holds, so their chips show a name, not an id. */
		labels?: { catalog_items: RuleLabel[]; clients: RuleLabel[] };
		/** After a save attempt: an empty condition's hint turns into an error. */
		showIncomplete?: boolean;
	} = $props();

	const incompleteKeys = $derived(incompleteGroupConditions(rules));

	type ConditionKey = MarketingGroupRuleConditionKey;

	const CONDITIONS = MARKETING_GROUP_RULE_CONDITIONS;

	function conditionLabel(key: ConditionKey) {
		return CONDITIONS.find((entry) => entry.key === key)?.label ?? key;
	}

	const activeKeys = $derived(
		CONDITIONS.map((entry) => entry.key).filter((key) => rules[key] !== undefined)
	);
	const addableConditions = $derived(CONDITIONS.filter((entry) => !activeKeys.includes(entry.key)));

	function addCondition(key: string) {
		if (!key) return;
		switch (key as ConditionKey) {
			case 'lifecycle':
				rules.lifecycle = ['customer'];
				break;
			case 'tags':
				rules.tags = [];
				break;
			case 'cities':
				rules.cities = [];
				break;
			case 'lead_sources':
				rules.lead_sources = [];
				break;
			case 'services':
				rules.services = [];
				break;
			case 'work_type':
				rules.work_type = 'one_off';
				break;
			case 'last_completed_job':
				rules.last_completed_job = { mode: 'never' };
				break;
			case 'upcoming_work':
				rules.upcoming_work = true;
				break;
			case 'include_client_ids':
				rules.include_client_ids = [];
				break;
			case 'exclude_client_ids':
				rules.exclude_client_ids = [];
				break;
		}
	}

	function removeCondition(key: ConditionKey) {
		delete rules[key];
	}

	// A list-valued condition with nothing left in it can't be saved (the schema requires at least one
	// value), so clearing the last chip removes the whole condition instead of leaving an invalid row.
	function setListOrRemove(key: ConditionKey, next: string[]) {
		if (next.length === 0) {
			delete rules[key];
			return;
		}
		(rules as Record<string, unknown>)[key] = next;
	}

	function toggleLifecycle(value: 'lead' | 'customer', checked: boolean) {
		const current = rules.lifecycle ?? [];
		const next = checked ? [...current, value] : current.filter((entry) => entry !== value);
		setListOrRemove('lifecycle', next);
	}

	const lastCompletedMode = $derived(rules.last_completed_job?.mode ?? 'never');
	const lastCompletedDays = $derived(
		rules.last_completed_job && rules.last_completed_job.mode !== 'never'
			? rules.last_completed_job.days
			: 30
	);

	function setLastCompletedMode(mode: string) {
		if (mode === 'never') {
			rules.last_completed_job = { mode: 'never' };
		} else if (mode === 'within_days' || mode === 'before_days') {
			rules.last_completed_job = { mode, days: lastCompletedDays };
		}
	}

	function setLastCompletedDays(days: number) {
		if (!rules.last_completed_job || rules.last_completed_job.mode === 'never') return;
		rules.last_completed_job = { mode: rules.last_completed_job.mode, days };
	}

	const catalogLabelById = $derived(new Map(labels.catalog_items.map((item) => [item.id, item])));
	const clientLabelById = $derived(new Map(labels.clients.map((item) => [item.id, item])));
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="rule-builder" aria-labelledby="rule-builder-title">
	<header class="rule-builder__head">
		<h3 id="rule-builder-title" class="rule-builder__title">
			<span class="rule-builder__title-icon" aria-hidden="true">{@html filterIcon}</span>
			Match customers who
		</h3>
		<p class="rule-builder__hint">
			Add only the checks this group needs. A customer must pass every one.
		</p>
	</header>

	<div class="rule-builder__box">
		{#if activeKeys.length === 0}
			<p class="rule-builder__empty">
				<span class="rule-builder__empty-icon" aria-hidden="true">{@html usersIcon}</span>
				No conditions yet — this group matches every active customer.
			</p>
		{:else}
			<ul class="rule-builder__rows">
				{#each activeKeys as key (key)}
					<li class="rule-builder__row">
						<div class="rule-builder__row-head">
							<IconTile
								icon={CONDITION_TILES[key].icon}
								tone={CONDITION_TILES[key].tone}
								size={24}
							/>
							<span class="rule-builder__row-title">{conditionLabel(key)}</span>
						</div>
						<div class="rule-builder__row-controls">
							{#if key === 'lifecycle'}
								<div class="rule-builder__checks">
									<Checkbox
										id="rule-lifecycle-lead"
										label="Lead"
										checked={(rules.lifecycle ?? []).includes('lead')}
										onchange={(checked) => toggleLifecycle('lead', checked)}
									/>
									<Checkbox
										id="rule-lifecycle-customer"
										label="Customer"
										checked={(rules.lifecycle ?? []).includes('customer')}
										onchange={(checked) => toggleLifecycle('customer', checked)}
									/>
								</div>
							{:else if key === 'tags'}
								<ClientTagSelect
									tagIds={rules.tags ?? []}
									onChange={(next) => setListOrRemove('tags', next.slice(0, 50))}
								/>
							{:else if key === 'cities'}
								<FreeTextChipInput
									id="rule-cities"
									max={50}
									placeholder="Add a city"
									values={rules.cities ?? []}
									onChange={(next) => setListOrRemove('cities', next)}
								/>
							{:else if key === 'lead_sources'}
								<FreeTextChipInput
									id="rule-lead-sources"
									max={50}
									placeholder="Add a lead source"
									suggestions={LEAD_SOURCES}
									values={rules.lead_sources ?? []}
									onChange={(next) => setListOrRemove('lead_sources', next)}
								/>
							{:else if key === 'services'}
								<AsyncMultiPicker
									id="rule-services"
									max={50}
									placeholder="Search the price list"
									queryKey="services"
									search={searchCatalogItemsForRule}
									ids={rules.services ?? []}
									initialItems={(rules.services ?? [])
										.map((itemId) => catalogLabelById.get(itemId))
										.filter((item) => item !== undefined)}
									onChange={(next) => setListOrRemove('services', next)}
								/>
							{:else if key === 'work_type'}
								<Select
									id="rule-work-type"
									ariaLabel="One-off or recurring work"
									value={rules.work_type ?? 'one_off'}
									options={[
										{ value: 'one_off', label: 'One-off work' },
										{ value: 'recurring', label: 'Recurring work' }
									]}
									onchange={(value) => (rules.work_type = value as 'one_off' | 'recurring')}
								/>
							{:else if key === 'last_completed_job'}
								<div class="rule-builder__inline">
									<Select
										id="rule-last-completed-mode"
										ariaLabel="Last completed Job"
										value={lastCompletedMode}
										options={[
											{ value: 'never', label: 'Never completed a Job' },
											{ value: 'within_days', label: 'Completed within the last…' },
											{ value: 'before_days', label: 'Completed more than…' }
										]}
										onchange={setLastCompletedMode}
									/>
									{#if lastCompletedMode !== 'never'}
										<Input
											id="rule-last-completed-days"
											type="number"
											aria-label="Days"
											value={lastCompletedDays}
											min="1"
											max="3650"
											onchange={(event: Event) =>
												setLastCompletedDays(Number((event.target as HTMLInputElement).value) || 1)}
										/>
										<span class="rule-builder__inline-suffix">days ago</span>
									{/if}
								</div>
							{:else if key === 'upcoming_work'}
								<Select
									id="rule-upcoming-work"
									ariaLabel="Upcoming work"
									value={rules.upcoming_work ? 'yes' : 'no'}
									options={[
										{ value: 'yes', label: 'Has upcoming work scheduled' },
										{ value: 'no', label: 'Has no upcoming work scheduled' }
									]}
									onchange={(value) => (rules.upcoming_work = value === 'yes')}
								/>
							{:else if key === 'include_client_ids'}
								<AsyncMultiPicker
									id="rule-include-clients"
									max={500}
									placeholder="Search customers to always include"
									queryKey="include-clients"
									search={searchClientsForRule}
									ids={rules.include_client_ids ?? []}
									initialItems={(rules.include_client_ids ?? [])
										.map((clientId) => clientLabelById.get(clientId))
										.filter((item) => item !== undefined)}
									onChange={(next) => setListOrRemove('include_client_ids', next)}
								/>
							{:else if key === 'exclude_client_ids'}
								<AsyncMultiPicker
									id="rule-exclude-clients"
									max={500}
									placeholder="Search customers to always exclude"
									queryKey="exclude-clients"
									search={searchClientsForRule}
									ids={rules.exclude_client_ids ?? []}
									initialItems={(rules.exclude_client_ids ?? [])
										.map((clientId) => clientLabelById.get(clientId))
										.filter((item) => item !== undefined)}
									onChange={(next) => setListOrRemove('exclude_client_ids', next)}
								/>
							{/if}
							{#if incompleteKeys.includes(key)}
								<p
									id={`rule-${key}-incomplete`}
									class="rule-builder__incomplete"
									class:rule-builder__incomplete--error={showIncomplete}
									role={showIncomplete ? 'alert' : undefined}
								>
									Pick at least one, or remove this condition.
								</p>
							{/if}
						</div>
						<button
							type="button"
							class="rule-builder__remove"
							aria-label={`Remove condition: ${conditionLabel(key)}`}
							title="Remove condition"
							onclick={() => removeCondition(key)}
						>
							{@html trashIcon}
						</button>
					</li>
				{/each}
			</ul>
		{/if}

		{#if addableConditions.length > 0}
			<div class="rule-builder__add">
				<DropdownMenu
					triggerText="Add a condition…"
					triggerLeadingIcon={circlePlusIcon}
					triggerVariant="quiet"
					triggerSize="small"
					align="start"
					contentClass="rule-builder__menu"
					items={addableConditions.map((entry) => ({
						key: entry.key,
						label: entry.label,
						icon: CONDITION_TILES[entry.key].icon,
						tile: CONDITION_TILES[entry.key].tone,
						onSelect: () => addCondition(entry.key)
					}))}
				/>
			</div>
		{/if}
	</div>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.rule-builder__menu) {
		min-width: 320px;
	}

	.rule-builder {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
	}

	.rule-builder__title {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 600;
	}

	.rule-builder__title-icon {
		display: inline-flex;
		color: var(--color-growth);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.rule-builder__hint {
		margin: 2px 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.rule-builder__box {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: 12px;
		background: var(--color-surface);
	}

	.rule-builder__empty {
		display: flex;
		align-items: center;
		gap: 10px;
		margin: 0;
		padding: var(--space-base) 14px;
		border-bottom: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-label);
	}

	.rule-builder__empty-icon {
		display: inline-flex;
		color: var(--color-growth);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.rule-builder__rows {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.rule-builder__row {
		display: flex;
		align-items: flex-start;
		gap: var(--space-slim);
		padding: var(--space-slim) var(--space-small) var(--space-slim) 14px;
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.rule-builder__row-head {
		display: flex;
		flex: 0 0 172px;
		align-items: center;
		gap: 10px;
		min-height: 36px;
	}

	.rule-builder__row-title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
		line-height: 1.3;
	}

	.rule-builder__row-controls {
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
		justify-content: center;
		min-width: 0;
		min-height: 36px;

		:global(.select) {
			width: 100%;
		}
	}

	.rule-builder__remove {
		display: grid;
		flex: 0 0 32px;
		height: 32px;
		margin-top: 2px;
		place-items: center;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
		transition:
			color var(--timing-base) ease-out,
			background var(--timing-base) ease-out;

		:global(svg) {
			width: 16px;
			height: 16px;
		}

		&:hover {
			color: var(--color-critical);
			background: var(--color-critical--surface);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.rule-builder__checks {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-large);
		min-height: 36px;
	}

	.rule-builder__inline {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);

		:global(.select) {
			flex: 1 1 200px;
			width: auto;
		}

		:global(.input) {
			width: 72px;
		}
	}

	.rule-builder__inline-suffix {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-label);
	}

	.rule-builder__incomplete {
		margin: 6px 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--error {
			color: var(--color-critical);
		}
	}

	.rule-builder__add {
		padding: var(--space-small) var(--space-slim);
		background: var(--color-surface--background--subtle);

		:global(.button) {
			color: var(--color-interactive);
			font-weight: 600;
		}
	}
</style>
