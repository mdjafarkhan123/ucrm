<script lang="ts">
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import { OTHER_MAX_LENGTH, setupChoiceList } from '$lib/setup/answer-values';

	// A "tick several" setup answer (client onboarding A5d), laid out like Google Forms' checkboxes: every
	// choice as a checkbox, then "Other" with a box for the client's own words when the question offers it.
	// It reads and writes the answer as JSON text — the ticked values, then the typed words — so the page
	// saves it like any other answer. Nothing ticked is an empty answer.
	let {
		id,
		label,
		labelledby,
		options,
		allowOther = false,
		maxChoices,
		value = $bindable(''),
		invalid = false,
		onedit,
		oncommit
	}: {
		id: string;
		label: string;
		/** The id of the question shown above; the field then draws no legend of its own. */
		labelledby?: string;
		options: { value: string; label: string }[];
		allowOther?: boolean;
		maxChoices?: number;
		value?: string;
		invalid?: boolean;
		onedit: () => void;
		oncommit: () => void;
	} = $props();

	const saved = $derived(setupChoiceList(value) ?? []);
	const listed = $derived(new Set(options.map((option) => option.value)));
	const ticked = $derived(saved.filter((item) => listed.has(item)));
	const savedOther = $derived(saved.find((item) => !listed.has(item)));

	// "Other" can be ticked before anything is typed, so its tick lives here and not only in the answer.
	let otherTicked = $state(false);
	let otherText = $state('');
	$effect.pre(() => {
		if (savedOther !== undefined) {
			otherTicked = true;
			otherText = savedOther;
		}
	});

	const count = $derived(ticked.length + (otherTicked ? 1 : 0));
	const full = $derived(maxChoices !== undefined && count >= maxChoices);

	function write(nextTicked: string[]) {
		// Kept in the order the choices are listed, whatever order they were ticked in.
		const ordered = options.map((option) => option.value).filter((v) => nextTicked.includes(v));
		const other = otherTicked ? otherText.trim() : '';
		const next = other ? [...ordered, other] : ordered;
		value = next.length ? JSON.stringify(next) : '';
	}

	function tick(choice: string, checked: boolean) {
		write(checked ? [...ticked, choice] : ticked.filter((item) => item !== choice));
		oncommit();
	}

	function tickOther(checked: boolean) {
		otherTicked = checked;
		write(ticked);
		oncommit();
	}

	function typeOther(event: Event) {
		otherText = (event.currentTarget as HTMLInputElement).value;
		write(ticked);
		onedit();
	}
</script>

<fieldset class="setup-choices" aria-labelledby={labelledby}>
	{#if !labelledby}<legend class="setup-choices__label">{label}</legend>{/if}
	{#if maxChoices}
		<p class="setup-choices__limit">Tick up to {maxChoices}.</p>
	{/if}
	<div class="setup-choices__options">
		{#each options as option (option.value)}
			{@const checked = ticked.includes(option.value)}
			<Checkbox
				id={`${id}-${option.value}`}
				label={option.label}
				{checked}
				disabled={!checked && full}
				{invalid}
				onchange={(next) => tick(option.value, next)}
			/>
		{/each}
		{#if allowOther}
			<Checkbox
				id={`${id}-other`}
				label="Other"
				checked={otherTicked}
				disabled={!otherTicked && full}
				{invalid}
				onchange={tickOther}
			/>
		{/if}
	</div>
	{#if allowOther && otherTicked}
		<Input
			id={`${id}-other-text`}
			label="Tell us which"
			value={otherText}
			maxlength={OTHER_MAX_LENGTH}
			oninput={typeOther}
			onblur={oncommit}
		/>
	{/if}
</fieldset>

<style lang="scss">
	.setup-choices {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		min-width: 0;
		margin: 0;
		padding: 0;
		border: 0;

		&__label {
			margin-bottom: var(--space-small);
			padding: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__limit {
			margin: calc(var(--space-small) * -1) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__options {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
			gap: var(--space-small) var(--space-base);
		}
	}
</style>
