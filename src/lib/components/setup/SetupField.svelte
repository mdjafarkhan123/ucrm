<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
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
		onedit,
		oncommit
	}: {
		fact: SetupFact;
		value?: string;
		availability?: SetupAvailability;
		note?: string;
		error?: string;
		/** The value came from what the CRM already knows and nobody has confirmed it yet. */
		suggested?: boolean;
		onedit: () => void;
		oncommit: () => void;
	} = $props();

	const id = $derived(`setup-${fact.key.replace(/\./g, '-')}`);
	const inputType = $derived(
		fact.kind === 'email' ? 'email' : fact.kind === 'phone' ? 'tel' : 'text'
	);
	const autocomplete = $derived(
		fact.kind === 'email' ? 'email' : fact.kind === 'phone' ? 'tel' : 'off'
	);

	const AVAILABILITY_OPTIONS = [
		{ value: 'have', label: 'I have this' },
		{ value: 'not_yet', label: "I don't have this yet" },
		{ value: 'need_help', label: "I need Uplift's help" }
	];

	// A trade is saved as the words themselves. Anything off the list is "Other" plus what was typed.
	const OTHER = 'Other';
	const listedTrade = $derived(
		fact.kind === 'trade' && fact.options?.some((option) => option.value === value)
	);
	const tradeChoice = $derived(value ? (listedTrade ? value : OTHER) : '');
	const tradeOther = $derived(value && !listedTrade ? value : '');

	function chooseTrade(next: string) {
		value = next;
		oncommit();
	}

	function typeOtherTrade(event: Event) {
		value = (event.currentTarget as HTMLInputElement).value || OTHER;
		onedit();
	}

	function chooseAvailability(next: string) {
		availability = next as SetupAvailability;
		oncommit();
	}
</script>

<div class="setup-field" id={`${id}-field`}>
	{#if fact.canDefer}
		<SegmentedControl
			label={fact.label}
			options={AVAILABILITY_OPTIONS}
			value={availability}
			size="small"
			onchange={chooseAvailability}
		/>
	{/if}

	{#if availability !== 'have'}
		<Input
			id={`${id}-note`}
			label="Anything Uplift should know? (optional)"
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
	{:else if fact.kind === 'trade'}
		<Select
			{id}
			label={fact.label}
			placeholder="Choose your trade"
			options={fact.options ?? []}
			value={tradeChoice}
			required={fact.required}
			onchange={chooseTrade}
		/>
		{#if tradeChoice === OTHER}
			<Input
				id={`${id}-other`}
				label="Your trade"
				value={tradeOther}
				maxlength={fact.maxLength}
				oninput={typeOtherTrade}
				onblur={oncommit}
			/>
		{/if}
	{:else}
		<Input
			{id}
			label={fact.canDefer ? undefined : fact.label}
			aria-label={fact.canDefer ? fact.label : undefined}
			placeholder={fact.canDefer ? fact.label : undefined}
			type={inputType}
			{autocomplete}
			bind:value
			required={fact.required && !fact.canDefer}
			maxlength={fact.maxLength}
			invalid={Boolean(error)}
			oninput={onedit}
			onblur={oncommit}
		/>
	{/if}

	{#if error}
		<p class="setup-field__error" role="alert">{error}</p>
	{:else if suggested && availability === 'have'}
		<p class="setup-field__hint">From your account — change it if it isn't right.</p>
	{:else if fact.hint && availability === 'have'}
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
