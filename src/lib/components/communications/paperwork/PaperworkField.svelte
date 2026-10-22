<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import { choiceLabel, type FormField } from '$lib/communications/number-paperwork';
	import { fieldHint, fieldPlaceholder } from './paperwork-ui';

	// One question the country asks, drawn from Twilio's live rules: a fixed list becomes a select, the rest a
	// box typed for what it holds (email, phone, date, web address).
	let {
		field,
		value,
		error,
		idPrefix,
		onchange
	}: {
		field: FormField;
		value: string;
		error?: string;
		idPrefix: string;
		onchange: (value: string) => void;
	} = $props();

	const id = $derived(`${idPrefix}-${field.name}`);
	const hint = $derived(fieldHint(field.name));
	const INPUT_TYPES: Record<FormField['kind'], string> = {
		text: 'text',
		email: 'email',
		phone: 'tel',
		url: 'url',
		date: 'date'
	};
</script>

<div class="paperwork-field">
	{#if field.choices}
		<Select
			{id}
			label={field.label}
			required={field.required}
			{value}
			options={field.choices.map(([choice, label]) => ({
				value: choice,
				label: choiceLabel(choice) === choice ? label : choiceLabel(choice)
			}))}
			placeholder="Choose one"
			errorMessage={error}
			onchange={(next) => onchange(next)}
		/>
	{:else}
		<Input
			{id}
			label={field.label}
			required={field.required}
			type={INPUT_TYPES[field.kind]}
			{value}
			placeholder={fieldPlaceholder(field)}
			autocomplete="off"
			errorMessage={error}
			oninput={(event: Event) => onchange((event.currentTarget as HTMLInputElement).value)}
		/>
	{/if}
	{#if hint && !error}<p class="paperwork-field__hint">{hint}</p>{/if}
</div>

<style lang="scss">
	.paperwork-field {
		display: flex;
		flex-direction: column;
		gap: 6px;
		min-width: 0;

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			line-height: var(--typography--lineHeight-large);
		}
	}
</style>
