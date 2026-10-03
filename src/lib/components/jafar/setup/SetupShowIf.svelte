<script lang="ts" module>
	let newRules = 0;
</script>

<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import RadioGroup from '$lib/components/ui/RadioGroup.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import TagSelect from '$lib/components/ui/TagSelect.svelte';
	import { COUNTRIES } from '$lib/settings/countries';
	import type { DraftCondition, SetupEditor, ShowIfSource } from '$lib/jafar/setup-editor';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// Client onboarding A5b (plan §2.1): "Show this question: Always / Only when…", the way SurveyJS and Jotform
	// show or hide a question from an earlier answer. Every rule must hold. A rule names an earlier pick-one,
	// yes/no or built-in choice question and the answers that reveal this one, or a service the client's
	// package must include. The database checks the rules again when the stage is saved and published.
	let {
		conditions = $bindable(),
		sources,
		services,
		idPrefix,
		error = ''
	}: {
		conditions: DraftCondition[];
		/** The questions this one can depend on, in setup order. */
		sources: ShowIfSource[];
		services: SetupEditor['services'];
		idPrefix: string;
		error?: string;
	} = $props();

	const MAX_RULES = 5;
	/** A list longer than this is picked from a search box rather than ticked. */
	const MAX_TICK_BOXES = 8;
	const SERVICE = 'service';

	const sourceById = $derived(new Map(sources.map((source) => [source.id, source])));
	const subjectOptions = $derived([
		...sources.map((source) => ({
			value: `answer:${source.id}`,
			label: source.stageTitle ? `${source.label} (${source.stageTitle})` : source.label
		})),
		{ value: SERVICE, label: "The client's package includes a service" }
	]);

	function serviceOptions(chosen: string | null) {
		return services
			.filter((service) => !service.archived || service.key === chosen)
			.map((service) => ({ value: service.key, label: service.name }));
	}

	function subject(condition: DraftCondition) {
		if (condition.type === 'service') return SERVICE;
		return condition.source ? `answer:${condition.source}` : '';
	}

	function addRule() {
		newRules += 1;
		conditions.push({ rowId: `new-rule-${newRules}`, type: 'answer', source: null, values: [] });
	}

	function setMode(mode: string) {
		if (mode === 'always') conditions.length = 0;
		else if (conditions.length === 0) addRule();
	}

	function setSubject(index: number, value: string) {
		const rowId = conditions[index].rowId;
		conditions[index] =
			value === SERVICE
				? { rowId, type: 'service', service_key: null }
				: { rowId, type: 'answer', source: value.slice('answer:'.length), values: [] };
	}

	function tick(condition: DraftCondition, value: string, checked: boolean) {
		if (condition.type !== 'answer') return;
		condition.values = checked
			? [...condition.values, value]
			: condition.values.filter((existing) => existing !== value);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="setup-show-if">
	<RadioGroup
		label="Show this question"
		name={`${idPrefix}-show-if`}
		options={[
			{ value: 'always', label: 'Always' },
			{ value: 'when', label: 'Only when…' }
		]}
		value={conditions.length ? 'when' : 'always'}
		onchange={setMode}
	/>

	{#if conditions.length}
		{#if conditions.length > 1}
			<p class="setup-show-if__hint">Every rule must be true for the client to see it.</p>
		{/if}
		<ol class="setup-show-if__rules">
			{#each conditions as condition, index (condition.rowId)}
				{@const source =
					condition.type === 'answer' && condition.source
						? sourceById.get(condition.source)
						: undefined}
				<li class="setup-show-if__rule">
					<div class="setup-show-if__subject">
						<Select
							id={`${idPrefix}-rule-${condition.rowId}`}
							label={index === 0 ? 'When' : 'And when'}
							placeholder="Choose an earlier question"
							options={subjectOptions}
							value={subject(condition)}
							onchange={(value: string) => setSubject(index, value)}
						/>
						<button
							type="button"
							class="setup-show-if__remove"
							aria-label={`Remove rule ${index + 1}`}
							onclick={() => conditions.splice(index, 1)}>{@html xIcon}</button
						>
					</div>

					{#if condition.type === 'service'}
						<div class="setup-show-if__answers">
							<Select
								id={`${idPrefix}-rule-${condition.rowId}-service`}
								label="Includes"
								placeholder="Choose a service"
								options={serviceOptions(condition.service_key)}
								bind:value={
									() => condition.service_key ?? '', (value) => (condition.service_key = value)
								}
							/>
						</div>
					{:else if source}
						<div class="setup-show-if__answers">
							{#if source.options === 'country' || source.options.length > MAX_TICK_BOXES}
								{@const catalog = (source.options === 'country' ? COUNTRIES : source.options).map(
									(option) => ({ id: option.value, name: option.label })
								)}
								<span class="setup-show-if__label">Is any of</span>
								<TagSelect
									bind:tagIds={condition.values}
									{catalog}
									noun="answer"
									addLabel={source.options === 'country' ? 'Add countries' : 'Add answers'}
									searchId={`${idPrefix}-rule-${condition.rowId}-search`}
								/>
							{:else}
								<fieldset class="setup-show-if__ticks">
									<legend class="setup-show-if__label">Is any of</legend>
									{#each source.options as option (option.value)}
										<Checkbox
											id={`${idPrefix}-rule-${condition.rowId}-${option.value}`}
											label={option.label}
											checked={condition.values.includes(option.value)}
											onchange={(checked) => tick(condition, option.value, checked)}
										/>
									{/each}
								</fieldset>
							{/if}
							{#if source.newChoices}
								<p class="setup-show-if__hint">New choices can be used here once you save.</p>
							{/if}
						</div>
					{:else if condition.type === 'answer' && condition.source}
						<p class="setup-show-if__warning">
							<span class="setup-show-if__icon" aria-hidden="true">{@html alertIcon}</span>
							The question this rule used is no longer above this one, or no longer pick-one or yes/no.
							Choose another, or move it back up.
						</p>
					{/if}
				</li>
			{/each}
		</ol>

		{#if error}
			<p class="setup-show-if__error" role="alert">{error}</p>
		{/if}

		<div>
			<Button
				size="small"
				variant="secondary"
				disabled={conditions.length >= MAX_RULES}
				onclick={addRule}
				><span class="setup-show-if__icon" aria-hidden="true">{@html plusIcon}</span>Add another
				rule</Button
			>
		</div>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-show-if {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&__rules {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__rule {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			max-width: 560px;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__subject {
			display: flex;
			align-items: flex-end;
			gap: var(--space-small);

			> :global(:first-child) {
				flex: 1 1 auto;
				min-width: 0;
			}
		}

		&__answers {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__ticks {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			border: 0;
		}

		&__label {
			margin-bottom: var(--space-smallest);
			padding: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__hint,
		&__warning,
		&__error {
			margin: 0;
			font-size: var(--typography--fontSize-small);
		}

		&__hint {
			color: var(--color-text--secondary);
		}

		&__warning {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			color: var(--color-warning--onSurface);
			font-weight: 600;
		}

		&__error {
			color: var(--color-critical--onSurface);
			font-weight: 600;
		}

		&__icon {
			display: inline-grid;
			flex: 0 0 auto;
			place-items: center;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__remove {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 40px;
			height: 40px;
			padding: 0;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: none;
			cursor: pointer;
			transition: all var(--timing-quick) ease-out;

			&:hover,
			&:focus-visible {
				border-color: var(--color-critical);
				color: var(--color-critical);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}
	}
</style>
