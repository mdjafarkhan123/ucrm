<script lang="ts">
	import { parseDate, type CalendarDate } from '@internationalized/date';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import RadioGroup from '$lib/components/ui/RadioGroup.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import TimezonePicker from '$lib/components/ui/TimezonePicker.svelte';
	import SetupHoursField from '$lib/components/setup/SetupHoursField.svelte';
	import SetupHoursExceptions from '$lib/components/setup/SetupHoursExceptions.svelte';
	import SetupAmountField from '$lib/components/setup/SetupAmountField.svelte';
	import SetupChoicesField from '$lib/components/setup/SetupChoicesField.svelte';
	import SetupColoursField from '$lib/components/setup/SetupColoursField.svelte';
	import SetupFilesField from '$lib/components/setup/SetupFilesField.svelte';
	import SetupListField from '$lib/components/setup/SetupListField.svelte';
	import { COUNTRIES } from '$lib/settings/countries';
	import type { SetupAvailability, SetupFact } from '$lib/setup/catalogue';

	// One setup question. It only shows and collects: the page owns saving, so every question on a section
	// autosaves the same way. `onedit` fires while the person is still typing (the page waits a moment before
	// saving) and `oncommit` when they have plainly finished — left the field, or picked from a list.
	let {
		fact,
		value = $bindable(''),
		availability = $bindable('have'),
		note = $bindable(''),
		error = '',
		suggested = false,
		currency = null,
		country = null,
		userId = null,
		fileTarget,
		onedit,
		oncommit
	}: {
		fact: SetupFact;
		value?: string;
		availability?: SetupAvailability;
		note?: string;
		error?: string;
		/** The value was filled in from what is already known and nobody has confirmed it yet. */
		suggested?: boolean;
		/** The business's currency, for an amount of money. */
		currency?: string | null;
		/** The business's country, which suggests miles or kilometres. */
		country?: string | null;
		/** Who is signed in, for a photo or file answer's cached file list. */
		userId?: string | null;
		/** A5e: a box in a list's row uploads its file to the list question and that box. */
		fileTarget?: { factKey: string; fieldKey: string };
		onedit: () => void;
		oncommit: () => void;
	} = $props();

	const id = $derived(`setup-${fact.key.replace(/\./g, '-')}`);
	const inputType = $derived(
		fact.kind === 'email'
			? 'email'
			: fact.kind === 'phone'
				? 'tel'
				: fact.kind === 'url'
					? 'url'
					: 'text'
	);
	const autocomplete = $derived(
		fact.kind === 'email'
			? 'email'
			: fact.kind === 'phone'
				? 'tel'
				: fact.kind === 'url'
					? 'url'
					: 'off'
	);

	const AVAILABILITY_OPTIONS = [
		{ value: 'have', label: 'I have this' },
		{ value: 'not_yet', label: "I don't have this yet" },
		{ value: 'need_help', label: "I need Uplift's help" }
	];

	// A list-or-other answer is saved as the words themselves. Anything off the list is "Other" plus what
	// was typed.
	const OTHER = 'Other';
	const listed = $derived(
		fact.kind === 'choice_other' && fact.options?.some((option) => option.value === value)
	);
	const listChoice = $derived(value ? (listed ? value : OTHER) : '');
	const otherText = $derived(value && !listed ? value : '');

	function choose(next: string) {
		value = next;
		oncommit();
	}

	function typeOther(event: Event) {
		value = (event.currentTarget as HTMLInputElement).value || OTHER;
		onedit();
	}

	// Hours and dated exceptions are editors with a heading of their own rather than one labelled box.
	const isEditor = $derived(fact.kind === 'hours' || fact.kind === 'hours_exceptions');

	// A date answer is kept as YYYY-MM-DD; anything else (an old answer of another shape) shows as empty.
	const dateValue = $derived.by(() => {
		if (fact.kind !== 'date' || !value) return undefined;
		try {
			return parseDate(value);
		} catch {
			return undefined;
		}
	});

	function chooseDate(next: CalendarDate | undefined) {
		value = next?.toString() ?? '';
		oncommit();
	}

	function chooseAvailability(next: string) {
		availability = next as SetupAvailability;
		oncommit();
	}
</script>

<div class="setup-field" id={`${id}-field`}>
	{#if fact.canDefer}
		<RadioGroup
			label={fact.label}
			options={AVAILABILITY_OPTIONS}
			value={availability}
			onchange={chooseAvailability}
		/>
	{/if}

	{#if availability !== 'have'}
		<Input
			id={`${id}-note`}
			label="Note for Uplift (optional)"
			bind:value={note}
			maxlength={500}
			oninput={onedit}
			onblur={oncommit}
		/>
		<p class="setup-field__hint">
			{availability === 'need_help'
				? 'Uplift will pick this up and get in touch — you can carry on with the rest.'
				: 'No problem. You can come back and add it whenever you have it.'}
		</p>
	{:else if isEditor}
		<div class="setup-field__heading">
			<span class="setup-field__label">{fact.label}</span>
			{#if fact.hint}<p class="setup-field__hint">{fact.hint}</p>{/if}
		</div>
		{#if fact.kind === 'hours'}
			<SetupHoursField {id} bind:value onchange={onedit} />
		{:else}
			<SetupHoursExceptions {id} bind:value onchange={onedit} />
		{/if}
	{:else if fact.kind === 'multi_choice'}
		<SetupChoicesField
			{id}
			label={fact.label}
			options={fact.options ?? []}
			allowOther={fact.allowOther}
			maxChoices={fact.maxChoices}
			bind:value
			invalid={Boolean(error)}
			{onedit}
			{oncommit}
		/>
	{:else if fact.kind === 'number' || fact.kind === 'percentage' || fact.kind === 'money' || fact.kind === 'distance' || fact.kind === 'duration'}
		<SetupAmountField
			{id}
			label={fact.label}
			kind={fact.kind}
			bind:value
			{currency}
			{country}
			required={fact.required && !fact.canDefer}
			invalid={Boolean(error)}
			{onedit}
			{oncommit}
		/>
	{:else if fact.kind === 'list'}
		<SetupListField
			{id}
			factKey={fact.key}
			label={fact.label}
			fields={fact.listFields ?? []}
			maxRows={fact.maxRows ?? 1}
			bind:value
			{error}
			{currency}
			{country}
			{userId}
			{onedit}
			{oncommit}
		/>
	{:else if fact.kind === 'file'}
		<SetupFilesField
			{id}
			factKey={fileTarget?.factKey ?? fact.key}
			fieldKey={fileTarget?.fieldKey}
			label={fact.label}
			kinds={fact.fileKinds ?? ['photo']}
			maxFiles={fact.maxFiles ?? 1}
			{userId}
			bind:value
			invalid={Boolean(error)}
			{oncommit}
		/>
	{:else if fact.kind === 'colours'}
		<SetupColoursField
			{id}
			label={fact.label}
			bind:value
			invalid={Boolean(error)}
			{onedit}
			{oncommit}
		/>
	{:else if fact.kind === 'choice' && fact.layout === 'radio'}
		<RadioGroup label={fact.label} options={fact.options ?? []} {value} onchange={choose} />
	{:else if fact.kind === 'country'}
		<Select
			{id}
			label={fact.label}
			placeholder="Choose your country"
			options={COUNTRIES}
			bind:value
			required={fact.required}
			onchange={oncommit}
		/>
	{:else if fact.kind === 'date'}
		<CalendarPicker
			{id}
			label={fact.label}
			value={dateValue}
			required={fact.required && !fact.canDefer}
			invalid={Boolean(error)}
			onchange={chooseDate}
		/>
	{:else if fact.kind === 'timezone'}
		<TimezonePicker {id} bind:value required={fact.required} onchange={oncommit} />
	{:else if fact.kind === 'longtext'}
		<Textarea
			{id}
			label={fact.label}
			bind:value
			maxlength={fact.maxLength}
			oninput={onedit}
			onblur={oncommit}
		/>
	{:else if fact.kind === 'choice'}
		<Select
			{id}
			label={fact.label}
			placeholder="Choose one"
			options={fact.options ?? []}
			bind:value
			required={fact.required}
			onchange={oncommit}
		/>
	{:else if fact.kind === 'choice_other'}
		<Select
			{id}
			label={fact.label}
			placeholder="Choose one"
			options={fact.options ?? []}
			value={listChoice}
			required={fact.required}
			onchange={choose}
		/>
		{#if listChoice === OTHER}
			<Input
				id={`${id}-other`}
				label={fact.otherLabel ?? 'Tell us which'}
				value={otherText}
				maxlength={fact.maxLength}
				oninput={typeOther}
				onblur={oncommit}
			/>
		{/if}
	{:else}
		<Input
			{id}
			label={fact.canDefer ? undefined : fact.label}
			aria-label={fact.canDefer ? fact.label : undefined}
			placeholder={fact.canDefer ? fact.label : fact.kind === 'url' ? 'example.com' : undefined}
			type={inputType}
			inputmode={fact.kind === 'url' ? 'url' : undefined}
			{autocomplete}
			bind:value
			required={fact.required && !fact.canDefer}
			maxlength={fact.maxLength}
			invalid={Boolean(error)}
			oninput={onedit}
			onblur={oncommit}
		/>
	{/if}

	{#if error && fact.kind !== 'list'}
		<p class="setup-field__error" role="alert">{error}</p>
	{:else if suggested && availability === 'have'}
		<p class="setup-field__hint">Filled in for you — change it if it isn’t right.</p>
	{:else if fact.hint && availability === 'have' && !isEditor}
		<p class="setup-field__hint">{fact.hint}</p>
	{/if}
</div>

<style lang="scss">
	.setup-field {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		min-width: 0;
		// Room above the field when "Mark as done" scrolls an unanswered question into view.
		scroll-margin-top: var(--space-largest);

		&__heading {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__hint,
		&__error {
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__hint {
			color: var(--color-text--secondary);
		}

		&__error {
			color: var(--color-critical--onSurface);
			font-weight: 600;
		}
	}
</style>
