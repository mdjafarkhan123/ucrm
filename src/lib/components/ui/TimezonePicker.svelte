<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { Combobox } from 'bits-ui';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import exclamationCircleIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';
	import searchIcon from '@tabler/icons/outline/world.svg?raw';

	let {
		value = $bindable(''),
		id,
		invalid = false,
		errorMessage = '',
		required = false,
		labelledby,
		onchange
	}: {
		value?: string;
		id: string;
		invalid?: boolean;
		errorMessage?: string;
		required?: boolean;
		/** The id of a question already shown elsewhere; the picker then draws no "Time zone" label. */
		labelledby?: string;
		onchange?: (value: string) => void;
	} = $props();
	type IntlWithTimezones = typeof Intl & { supportedValuesOf?: (key: 'timeZone') => string[] };
	type TimezoneOption = {
		value: string;
		label: string;
		city: string;
		meta: string;
		offset: string;
		searchText: string;
	};
	const timezoneNames = (
		(Intl as IntlWithTimezones).supportedValuesOf?.('timeZone') ?? ['UTC']
	).sort();
	const timezoneOptions: TimezoneOption[] = timezoneNames
		.map(createTimezoneOption)
		.sort((a, b) => a.city.localeCompare(b.city));
	const comboboxItems = timezoneOptions.map(({ value: optionValue, label }) => ({
		value: optionValue,
		label
	}));
	let query = $state('');
	let open = $state(false);
	let selectedOption = $derived(timezoneOptions.find((timezone) => timezone.value === value));
	let inputValue = $derived(open ? query : (selectedOption?.label ?? friendlyTimezone(value)));
	let normalizedQuery = $derived(query === selectedOption?.label ? '' : query.trim().toLowerCase());
	let results = $derived(
		timezoneOptions
			.filter((timezone) => timezone.searchText.includes(normalizedQuery))
			.slice(0, 100)
	);
	let describedBy = $derived(errorMessage ? `${id}-error` : undefined);

	function friendlyTimezone(timezone: string) {
		return timezone.replaceAll('_', ' ');
	}

	function timezoneOffset(timezone: string) {
		try {
			const formatter = new Intl.DateTimeFormat('en-US', {
				timeZone: timezone,
				timeZoneName: 'longOffset',
				hour: '2-digit'
			});
			const name = formatter
				.formatToParts(new Date())
				.find((part) => part.type === 'timeZoneName')?.value;
			return name?.replace('GMT', 'UTC') ?? 'UTC';
		} catch {
			return 'UTC';
		}
	}

	function createTimezoneOption(timezone: string): TimezoneOption {
		const parts = friendlyTimezone(timezone).split('/');
		const city = parts.at(-1) ?? timezone;
		const region = parts.length > 1 ? parts.slice(0, -1).join(' / ') : 'Universal';
		const offset = timezoneOffset(timezone);
		const label = `${city} (${offset})`;
		return {
			value: timezone,
			label,
			city,
			meta: region,
			offset,
			searchText:
				`${timezone} ${friendlyTimezone(timezone)} ${city} ${region} ${offset}`.toLowerCase()
		};
	}

	function focusTimezone(input: HTMLInputElement) {
		query = selectedOption?.label ?? '';
		open = true;
		input.select();
	}

	function chooseTimezone(timezone: string) {
		lastCommitted = timezone;
		value = timezone;
		query =
			timezoneOptions.find((option) => option.value === timezone)?.label ??
			friendlyTimezone(timezone);
		open = false;
		onchange?.(timezone);
	}

	// bits-ui's Combobox keeps its own internal copy of the displayed text once the user picks an
	// option; it never re-reads our `inputValue` prop afterwards. An external revert (e.g. the
	// settings page's Cancel button restoring `value`) would then leave the stale label on screen.
	// Only remount the combobox for that external case — remounting on every selection would drop
	// focus and break keyboard tabbing to the next field.
	let lastCommitted = value;
	let resetKey = $state(0);
	$effect(() => {
		if (value !== lastCommitted) {
			lastCommitted = value;
			resetKey++;
		}
	});
	function matchParts(text: string) {
		const term = normalizedMatch.trim().toLowerCase();
		const index = term ? text.toLowerCase().indexOf(term) : -1;
		return index < 0
			? { before: text, match: '', after: '' }
			: {
					before: text.slice(0, index),
					match: text.slice(index, index + term.length),
					after: text.slice(index + term.length)
				};
	}
	let normalizedMatch = $derived(normalizedQuery);
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="timezone-picker" class:timezone-picker--invalid={invalid}>
	{#if !labelledby}
		<label for={id}
			>Time zone{#if required}
				<span aria-hidden="true">*</span>{/if}</label
		>
	{/if}
	{#key resetKey}
		<Combobox.Root
			type="single"
			bind:value
			bind:open
			{inputValue}
			items={comboboxItems}
			onValueChange={chooseTimezone}
		>
			<div class="timezone-picker__control">
				<IconTile icon={searchIcon} tone="time" size={24} class="timezone-picker__search" />
				<Combobox.Input
					{id}
					placeholder="Search by city or UTC offset"
					autocomplete="off"
					aria-labelledby={labelledby}
					aria-describedby={describedBy}
					aria-invalid={invalid}
					onfocus={(event) => focusTimezone(event.currentTarget)}
					onclick={() => (open = true)}
					oninput={(event) => {
						query = event.currentTarget.value;
						open = true;
					}}
				/>
				<Combobox.Trigger class="timezone-picker__trigger" aria-label="Show time zones">
					<span aria-hidden="true">{@html chevronDownIcon}</span>
				</Combobox.Trigger>
			</div>
			<Combobox.Portal>
				<Combobox.Content
					class="timezone-picker__menu"
					data-elevation="elevated"
					align="start"
					sideOffset={4}
					collisionPadding={8}
				>
					<Combobox.Viewport class="timezone-picker__viewport">
						{#each results as timezone (timezone.value)}
							{@const parts = matchParts(timezone.city)}
							<Combobox.Item
								value={timezone.value}
								label={timezone.label}
								class="timezone-picker__option"
							>
								<span class="timezone-picker__option-copy"
									><strong
										>{parts.before}{#if parts.match}<mark>{parts.match}</mark
											>{/if}{parts.after}</strong
									><small>{timezone.meta}</small></span
								>
								<span class="timezone-picker__offset">{timezone.offset}</span>
								{#if value === timezone.value}<span
										class="timezone-picker__check"
										aria-hidden="true">{@html checkIcon}</span
									>{/if}
							</Combobox.Item>
						{:else}<div class="timezone-picker__empty">
								No time zones match “{query}”.<small
									>Try a city, like Denver, or an offset, like UTC+5.</small
								>
							</div>{/each}
					</Combobox.Viewport>
				</Combobox.Content>
			</Combobox.Portal>
		</Combobox.Root>
	{/key}
	{#if errorMessage}<p class="timezone-picker__error" id={`${id}-error`} role="alert">
			<span aria-hidden="true">{@html exclamationCircleIcon}</span>{errorMessage}
		</p>{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.timezone-picker {
		width: 100%;
	}
	.timezone-picker > label {
		display: block;
		margin-bottom: 6px;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
	}
	.timezone-picker > label span {
		color: var(--color-critical);
	}
	.timezone-picker__control {
		position: relative;
		display: flex;
		min-height: 40px;
		align-items: center;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--field--fill, var(--color-surface--background));
	}
	.timezone-picker__control:focus-within {
		z-index: var(--elevation-base);
		box-shadow: var(--shadow-focus);
	}
	.timezone-picker--invalid .timezone-picker__control {
		border-color: var(--color-critical);
	}
	.timezone-picker__control :global(input) {
		width: 100%;
		min-width: 0;
		min-height: 38px;
		padding: var(--space-small) var(--space-largest);
		border: 0;
		outline: 0;
		color: var(--color-heading);
		background: transparent;
		font: inherit;
	}
	:global(.timezone-picker__trigger) {
		position: absolute;
		right: 0;
		display: grid;
		width: var(--space-largest);
		height: 100%;
		place-items: center;
		border: 0;
		border-radius: 0 var(--radius-base) var(--radius-base) 0;
		outline: 0;
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
	}
	:global(.timezone-picker__trigger:focus-visible) {
		box-shadow: var(--shadow-focus);
	}
	:global(.timezone-picker__trigger[data-state='open']) span {
		transform: rotate(180deg);
	}
	:global(.timezone-picker__trigger span) {
		display: grid;
		width: 18px;
		height: 18px;
		place-items: center;
		transition: transform var(--timing-quick);
	}
	:global(.timezone-picker__trigger svg),
	.timezone-picker__check :global(svg),
	.timezone-picker__error :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
	:global(.timezone-picker__menu) {
		z-index: var(--elevation-modal);
		width: var(--bits-floating-anchor-width);
		max-height: min(300px, var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	:global(.timezone-picker__viewport) {
		max-height: inherit;
		overflow-y: auto;
		padding: var(--space-small);
	}
	:global(.timezone-picker__option) {
		display: flex;
		width: 100%;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-small);
		outline: 0;
		color: var(--color-text);
		background: transparent;
		text-align: left;
		cursor: pointer;
		transition:
			color var(--timing-quick),
			background-color var(--timing-quick);
	}
	:global(.timezone-picker__option[data-highlighted]) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}
	.timezone-picker__option-copy {
		display: grid;
		min-width: 0;
		flex: 1;
		gap: 2px;
	}
	.timezone-picker__option-copy strong {
		overflow: hidden;
		color: inherit;
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.timezone-picker__option-copy small {
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.timezone-picker__check {
		display: grid;
		width: 16px;
		height: 16px;
		flex: 0 0 16px;
		place-items: center;
		color: var(--color-interactive);
	}
	.timezone-picker__empty {
		padding: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
	.timezone-picker__error {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		margin: var(--space-smaller) 0 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.timezone-picker__control:hover {
		border-color: var(--color-border--interactive--hover);
	}
	.timezone-picker__control :global(input) {
		font-size: var(--typography--fontSize-base);
	}
	.timezone-picker__control :global(input[aria-expanded='true']) {
		color: var(--color-interactive);
	}
	:global(.timezone-picker__option) {
		min-height: 40px;
		border-radius: var(--radius-base);
	}
	:global(.timezone-picker__option:active) {
		background: var(--color-surface--active);
	}
	.timezone-picker__empty small {
		display: block;
		margin-top: var(--space-small);
		line-height: 1.5;
	}
	mark {
		background: transparent;
		color: var(--color-interactive);
		font-weight: 700;
	}

	// The search tile sits inside the field, before the typed text.
	.timezone-picker__control :global(.timezone-picker__search) {
		position: absolute;
		left: var(--space-small);
		pointer-events: none;
	}
	.timezone-picker__offset {
		border-radius: var(--radius-circle);
		background: var(--color-surface--background--subtle);
		color: var(--color-text--secondary);
		padding: 2px var(--space-small);
		font-size: var(--typography--fontSize-small);
		white-space: nowrap;
	}
</style>
