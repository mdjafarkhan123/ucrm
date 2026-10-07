<script lang="ts">
	import { parseDate, type CalendarDate } from '@internationalized/date';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
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
	import SetupPickField from '$lib/components/setup/SetupPickField.svelte';
	import type { SetupHelpAnswer } from '$lib/setup/help';
	import type { SetupListRow } from '$lib/setup/lists';
	import { PROTECTED_FILE_KINDS } from '$lib/setup/files';
	import type { SetupAvailability, SetupFact } from '$lib/setup/catalogue';
	import { setupReuseSource, setupReuseValue } from '$lib/setup/reuse';
	import flagIcon from '@tabler/icons/outline/flag.svg?raw';

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
		pickRows = [],
		reuse = null,
		flagged = false,
		helpAnswer = null,
		nested = false,
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
		/** A5f: a pick's list rows as they stand now. */
		pickRows?: SetupListRow[];
		/**
		 * A5g: the earlier answer this question reuses, in words, with where it was given and a link back to it.
		 * Null asks the question as a plain one: nothing to reuse yet, or not a reuse.
		 */
		reuse?: { lines: string[]; where: string; href: string } | null;
		/** C3b: Uplift sent this task back and asked for this question to change. */
		flagged?: boolean;
		/** C3c: what Uplift filled in, shown while the client still has "I need Uplift's help". */
		helpAnswer?: SetupHelpAnswer | null;
		/** A box inside a list's entry: its question reads as a smaller label. */
		nested?: boolean;
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

	// A5g: "Yes, use this" is the answer itself; "Use a different one here" opens the question's own box.
	let pickedDifferent = $state(false);
	const reuseChoice = $derived(
		setupReuseSource(value) ? 'same' : value || pickedDifferent ? 'different' : ''
	);
	const REUSE_OPTIONS = [
		{ value: 'same', label: 'Yes, use this' },
		{ value: 'different', label: 'Use a different one here' }
	];

	function chooseReuse(next: string) {
		pickedDifferent = next === 'different';
		value = next === 'same' && fact.reuseFrom ? setupReuseValue(fact.reuseFrom) : '';
		oncommit();
	}

	// Every question is shown once, above its answer, and names the answer for screen readers.
	const label = $derived(fact.label);
	const questionId = $derived(`${id}-question`);

	function chooseAvailability(next: string) {
		availability = next as SetupAvailability;
		oncommit();
	}
</script>

{#snippet control()}
	{#if fact.kind === 'hours'}
		<SetupHoursField {id} bind:value onchange={onedit} />
	{:else if fact.kind === 'hours_exceptions'}
		<SetupHoursExceptions {id} bind:value onchange={onedit} />
	{:else if fact.kind === 'multi_choice'}
		<SetupChoicesField
			{id}
			{label}
			labelledby={questionId}
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
			{label}
			labelledby={questionId}
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
			{label}
			labelledby={questionId}
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
	{:else if fact.kind === 'pick'}
		<SetupPickField
			{id}
			{label}
			labelledby={questionId}
			rows={pickRows}
			nameKey={fact.pickNameKey}
			minChoices={fact.minChoices}
			maxChoices={fact.maxChoices}
			ordered={fact.ordered}
			bind:value
			invalid={Boolean(error)}
			{oncommit}
		/>
	{:else if fact.kind === 'file' || fact.kind === 'protected_file'}
		<SetupFilesField
			{id}
			factKey={fact.kind === 'file' ? (fileTarget?.factKey ?? fact.key) : fact.key}
			fieldKey={fact.kind === 'file' ? fileTarget?.fieldKey : undefined}
			{label}
			labelledby={questionId}
			kinds={fact.fileKinds ?? (fact.kind === 'file' ? ['photo'] : PROTECTED_FILE_KINDS)}
			maxFiles={fact.maxFiles ?? 1}
			{userId}
			bind:value
			invalid={Boolean(error)}
			secure={fact.kind === 'protected_file'}
			{oncommit}
		/>
	{:else if fact.kind === 'colours'}
		<SetupColoursField
			{id}
			{label}
			labelledby={questionId}
			bind:value
			invalid={Boolean(error)}
			{onedit}
			{oncommit}
		/>
	{:else if fact.kind === 'choice' && fact.layout === 'radio'}
		<RadioGroup
			{label}
			labelledby={questionId}
			variant="cards"
			options={fact.options ?? []}
			{value}
			onchange={choose}
		/>
	{:else if fact.kind === 'country'}
		<CountryPicker
			{id}
			ariaLabelledby={questionId}
			placeholder="Search for your country"
			bind:value
			required={fact.required}
			onchange={oncommit}
		/>
	{:else if fact.kind === 'date'}
		<CalendarPicker
			{id}
			{label}
			hideLabel
			value={dateValue}
			required={fact.required && !fact.canDefer}
			invalid={Boolean(error)}
			onchange={chooseDate}
		/>
	{:else if fact.kind === 'timezone'}
		<TimezonePicker
			{id}
			labelledby={questionId}
			bind:value
			required={fact.required}
			onchange={oncommit}
		/>
	{:else if fact.kind === 'longtext'}
		<Textarea
			{id}
			aria-labelledby={questionId}
			bind:value
			maxlength={fact.maxLength}
			oninput={onedit}
			onblur={oncommit}
		/>
	{:else if fact.kind === 'choice' || fact.kind === 'choice_other'}
		<Select
			{id}
			ariaLabelledby={questionId}
			placeholder="Choose one"
			options={fact.options ?? []}
			value={fact.kind === 'choice' ? value : listChoice}
			required={fact.required}
			onchange={choose}
		/>
		{#if fact.kind === 'choice_other' && listChoice === OTHER}
			<div class="setup-field__sub">
				<label class="setup-field__sublabel" for={`${id}-other`}
					>{fact.otherLabel ?? 'Tell us which'}</label
				>
				<Input
					id={`${id}-other`}
					value={otherText}
					maxlength={fact.maxLength}
					oninput={typeOther}
					onblur={oncommit}
				/>
			</div>
		{/if}
	{:else}
		<Input
			{id}
			aria-labelledby={questionId}
			placeholder={fact.kind === 'url' ? 'example.com' : undefined}
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
{/snippet}

<div
	class="setup-field"
	class:setup-field--nested={nested}
	class:setup-field--flagged={flagged}
	class:setup-field--invalid={Boolean(error) && fact.kind !== 'list'}
	id={`${id}-field`}
>
	{#if flagged}
		<span class="setup-field__flag">
			<!-- eslint-disable-next-line svelte/no-at-html-tags -->
			<span class="setup-field__flag-icon" aria-hidden="true">{@html flagIcon}</span>
			Uplift asked you to change this
		</span>
	{/if}

	<div class="setup-field__heading">
		<span class="setup-field__question" id={questionId}
			>{label}{#if !fact.required}<span class="setup-field__optional">(optional)</span>{/if}</span
		>
		{#if fact.hint && availability === 'have'}<p class="setup-field__hint">{fact.hint}</p>{/if}
	</div>

	{#if error && fact.kind !== 'list'}
		<p class="setup-field__error" role="alert">{error}</p>
	{/if}

	{#if fact.canDefer}
		<RadioGroup
			label={fact.label}
			labelledby={questionId}
			variant="cards"
			options={AVAILABILITY_OPTIONS}
			value={availability}
			onchange={chooseAvailability}
		/>
	{/if}

	{#if availability !== 'have'}
		<div class="setup-field__sub">
			<label class="setup-field__sublabel" for={`${id}-note`}>Note for Uplift (optional)</label>
			<Input
				id={`${id}-note`}
				bind:value={note}
				maxlength={500}
				oninput={onedit}
				onblur={oncommit}
			/>
		</div>
		{#if availability === 'need_help' && helpAnswer}
			<div class="setup-field__help">
				<span class="setup-field__help-label">Uplift filled this in</span>
				{#each helpAnswer.lines as line, index (index)}
					<span>{line}</span>
				{/each}
				{#if helpAnswer.note}<span>{helpAnswer.note}</span>{/if}
				<span class="setup-field__hint">
					Not right? Tell Uplift in Support, or pick “I have this” and give your own answer.
				</span>
			</div>
		{:else}
			<p class="setup-field__hint">
				{availability === 'need_help'
					? 'Uplift will pick this up and get in touch — you can carry on with the rest.'
					: 'No problem. You can come back and add it whenever you have it.'}
			</p>
		{/if}
	{:else if reuse}
		<div class="setup-field__reuse">
			<span class="setup-field__reuse-where">{reuse.where}</span>
			{#each reuse.lines as line, index (index)}
				<span class="setup-field__reuse-line">{line}</span>
			{/each}
			<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- the page passes a resolve()d path or an in-page anchor -->
			<a class="setup-field__reuse-change" href={reuse.href}>Change</a>
		</div>
		<RadioGroup
			label={fact.label}
			labelledby={questionId}
			variant="cards"
			options={REUSE_OPTIONS}
			value={reuseChoice}
			onchange={chooseReuse}
		/>
		{#if reuseChoice === 'different'}
			{@render control()}
		{/if}
	{:else}
		{@render control()}
	{/if}

	{#if suggested && availability === 'have' && !error}
		<p class="setup-field__suggested">Filled in for you — change it if it isn’t right.</p>
	{/if}
</div>

<style lang="scss">
	.setup-field {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		min-width: 0;
		// Room above the question when "Mark as done" or a "Question to change" link brings it into view.
		scroll-margin-top: var(--space-largest);

		// C3b: the same warning tint Jafar's page gives a question he sent back.
		&--flagged {
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-warning--surface);
		}

		// A question still needing attention carries a red bar down its side, as GOV.UK's error pattern does.
		&--invalid {
			padding-left: var(--space-base);
			border-left: 3px solid var(--color-critical);
		}

		&__flag {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__flag-icon {
			display: inline-flex;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__heading {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
		}

		&__question {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
			line-height: 1.4;
			overflow-wrap: anywhere;
		}

		&__optional {
			margin-left: var(--space-smaller);
			color: var(--color-text--secondary);
			font-weight: 400;
		}

		&--nested &__question {
			font-size: var(--typography--fontSize-base);
		}

		&__hint,
		&__suggested,
		&__error {
			margin: 0;
			font-size: var(--typography--fontSize-base);
			line-height: 1.5;
		}

		&__hint {
			color: var(--color-text--secondary);
		}

		&__suggested {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			color: var(--color-critical--onSurface);
			font-weight: 600;
		}

		// A select sits at the same height and inset as a text box, so a screen of answers lines up.
		:global(.select__trigger) {
			min-height: var(--space-largest);
			padding-inline: var(--space-base);
			font-size: var(--typography--fontSize-base);
		}

		&__sub {
			margin-top: var(--space-smaller);
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__sublabel {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
		}

		&__help {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			padding: var(--space-small) var(--space-base);
			border-left: 3px solid var(--color-success);
			border-radius: var(--radius-base);
			background: var(--color-success--surface);
			color: var(--color-text);
			overflow-wrap: anywhere;
			white-space: pre-line;
		}

		&__help-label {
			color: var(--color-success--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__reuse {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__reuse-where {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__reuse-line {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			overflow-wrap: anywhere;
		}

		&__reuse-change {
			align-self: flex-start;
			margin-top: var(--space-smallest);
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
	}
</style>
