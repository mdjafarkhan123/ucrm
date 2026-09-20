<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
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
	import type { MarketingGroupRules } from '$lib/marketing/customer-groups';
	import filterIcon from '@tabler/icons/outline/filter.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// One AND-only condition list, the same "add a condition" shape as
	// `settings/automation/RecipeBuilder.svelte`'s If block: start empty, add only the checks this group
	// needs, remove one without hunting through nine always-visible fields.
	let {
		rules = $bindable<MarketingGroupRules>(),
		labels = { catalog_items: [], clients: [] }
	}: {
		rules?: MarketingGroupRules;
		/** Names for ids a reopened saved group already holds, so their chips show a name, not an id. */
		labels?: { catalog_items: RuleLabel[]; clients: RuleLabel[] };
	} = $props();

	type ConditionKey = Exclude<keyof MarketingGroupRules, 'version'>;

	const CONDITIONS: { key: ConditionKey; label: string }[] = [
		{ key: 'lifecycle', label: 'Lead or customer status' },
		{ key: 'tags', label: 'Has any of these tags' },
		{ key: 'cities', label: 'City or service area' },
		{ key: 'lead_sources', label: 'Original lead source' },
		{ key: 'services', label: 'Used one of these services' },
		{ key: 'work_type', label: 'One-off or recurring work' },
		{ key: 'last_completed_job', label: 'Last completed Job' },
		{ key: 'upcoming_work', label: 'Upcoming work' },
		{ key: 'include_client_ids', label: 'Always include these customers' },
		{ key: 'exclude_client_ids', label: 'Always exclude these customers' }
	];

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

<SectionBlock
	title="Match customers who"
	icon={filterIcon}
	hint="Add only the checks this group needs. A customer must pass every one."
	form
>
	{#if activeKeys.length === 0}
		<p class="rule-builder__empty">No conditions yet — this group matches every active customer.</p>
	{:else}
		<ul class="rule-builder__rows">
			{#each activeKeys as key (key)}
				<li class="rule-builder__row">
					<div class="rule-builder__row-head">
						<span class="rule-builder__row-title">{conditionLabel(key)}</span>
						<button
							type="button"
							class="rule-builder__icon-button"
							aria-label={`Remove condition: ${conditionLabel(key)}`}
							onclick={() => removeCondition(key)}
						>
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							{@html trashIcon}
						</button>
					</div>

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
									label="Days"
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
				</li>
			{/each}
		</ul>
	{/if}

	{#if addableConditions.length > 0}
		<div class="rule-builder__add">
			<Select
				id="rule-add-condition"
				value=""
				options={[
					{ value: '', label: 'Add a condition…' },
					...addableConditions.map((entry) => ({ value: entry.key, label: entry.label }))
				]}
				ariaLabel="Add a condition"
				onchange={addCondition}
			/>
		</div>
	{/if}
</SectionBlock>

<style lang="scss">
	.rule-builder__empty {
		margin: 0;
		color: var(--color-text--secondary);
		font-style: italic;
	}

	.rule-builder__rows {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.rule-builder__row {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	.rule-builder__row-head {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.rule-builder__row-title {
		flex: 1 1 auto;
		color: var(--color-heading);
		font-weight: 600;
	}

	.rule-builder__icon-button {
		display: grid;
		width: 32px;
		height: 32px;
		flex: 0 0 auto;
		place-items: center;
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: none;
		cursor: pointer;

		&:hover {
			border-color: var(--color-border);
			color: var(--color-critical);
			background: var(--color-critical--surface);
		}

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	.rule-builder__checks {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-base);
	}

	.rule-builder__inline {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-end;
		gap: var(--space-small);

		:global(.select) {
			width: auto;
			min-width: 220px;
		}

		:global(.input) {
			width: 100px;
		}
	}

	.rule-builder__inline-suffix {
		padding-bottom: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.rule-builder__add {
		max-width: 320px;
	}
</style>
