<script lang="ts">
	import { Select as SelectPrimitive } from 'bits-ui';
	import alertIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import chevronUpIcon from '@tabler/icons/outline/chevron-up.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';

	type SelectOption = {
		value: string;
		label: string;
		disabled?: boolean;
		tone?: string;
		reason?: string;
	};

	let {
		value = $bindable(''),
		options,
		id,
		label,
		ariaLabel,
		ariaLabelledby,
		placeholder = 'Select an option',
		disabled = false,
		required = false,
		invalid = false,
		errorMessage = '',
		name,
		class: className = '',
		contentClass = '',
		prefix,
		icon,
		fitOptions = false,
		locked = false,
		onchange
	}: {
		value?: string;
		options: SelectOption[];
		id: string;
		label?: string;
		ariaLabel?: string;
		/** The id of a question already shown elsewhere, naming the select instead of a label. */
		ariaLabelledby?: string;
		placeholder?: string;
		disabled?: boolean;
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		name?: string;
		class?: string;
		/** Extra class for the floating options list, e.g. to out-rank a popover this Select is nested in. */
		contentClass?: string;
		/** A fixed word drawn inside the trigger ahead of the value, e.g. a filter's name. */
		prefix?: string;
		/** A Tabler icon (raw SVG) drawn at the start of the trigger, ahead of the prefix. */
		icon?: string;
		/** The open list is as wide as its longest option (never narrower than the trigger) instead of matching the trigger. */
		fitOptions?: boolean;
		/** Only one choice exists, so the box shows a lock where the chevron would be. */
		locked?: boolean;
		onchange?: (value: string) => void;
	} = $props();

	let selectedLabel = $derived(
		options.find((option) => option.value === value)?.label ?? placeholder
	);
	let selectedTone = $derived(options.find((option) => option.value === value)?.tone);
	let isInvalid = $derived(invalid || Boolean(errorMessage));
	let labelId = $derived(label ? `${id}-label` : undefined);

	function handleValueChange(nextValue: string) {
		value = nextValue;
		onchange?.(nextValue);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div
	class={['select', label && 'select--labelled', isInvalid && 'select--invalid', className]}
	data-disabled={disabled || undefined}
>
	{#if label}
		<span class="select__label" id={labelId}
			>{label}{#if required}<span class="field-required" aria-hidden="true">*</span>{/if}</span
		>
	{/if}
	<SelectPrimitive.Root
		type="single"
		{value}
		items={options}
		{disabled}
		{required}
		{name}
		onValueChange={handleValueChange}
	>
		<SelectPrimitive.Trigger
			{id}
			class="select__trigger"
			aria-invalid={isInvalid}
			aria-describedby={errorMessage ? `${id}-error` : undefined}
			data-placeholder={!value || undefined}
			aria-label={label ? undefined : ariaLabel}
			aria-labelledby={labelId ?? ariaLabelledby}
		>
			{#if icon}<span class="select__icon" aria-hidden="true">{@html icon}</span>{/if}
			{#if prefix}<span class="select__prefix">{prefix}</span>{/if}
			{#if selectedTone}<span
					class="select__status-tile"
					style:--status-tone={`var(--color-${selectedTone})`}
					style:--status-surface={`var(--color-${selectedTone}--surface)`}
					style:--status-edge={`var(--color-${selectedTone}--surface-edge)`}
					aria-hidden="true"><span></span></span
				>{/if}
			<span class="select__value">{selectedLabel}</span>
			<span class={['select__chevron', locked && 'select__chevron--locked']} aria-hidden="true"
				>{@html locked ? lockIcon : chevronDownIcon}<span class="select__chevron-up"
					>{@html chevronUpIcon}</span
				></span
			>
		</SelectPrimitive.Trigger>

		<SelectPrimitive.Portal>
			<SelectPrimitive.Content
				class={['select__content', fitOptions && 'select__content--fit', contentClass]}
				data-elevation="elevated"
				align="start"
				sideOffset={4}
				collisionPadding={8}
			>
				<SelectPrimitive.Viewport class="select__viewport">
					{#each options as option (option.value)}
						<SelectPrimitive.Item
							class="select__option"
							value={option.value}
							label={option.label}
							disabled={option.disabled}
						>
							{#snippet children({ selected })}
								<span
									class={['select__radio', selected && 'select__radio--selected']}
									aria-hidden="true"
								></span>
								<span class="select__option-label"
									>{#if option.tone}<span
											class="select__option-dot"
											style:background={`var(--color-${option.tone})`}
										></span>{/if}{option.label}</span
								>
								{#if option.reason}<span class="select__option-reason">{option.reason}</span>{/if}
							{/snippet}
						</SelectPrimitive.Item>
					{/each}
				</SelectPrimitive.Viewport>
			</SelectPrimitive.Content>
		</SelectPrimitive.Portal>
	</SelectPrimitive.Root>
	{#if errorMessage}<p class="select__error" id={`${id}-error`} role="alert">
			<span aria-hidden="true">{@html alertIcon}</span>{errorMessage}
		</p>{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.select {
		position: relative;
		width: 100%;
		color: var(--color-heading);
		// The trigger inherits its font, so the box's value is 14 like every other field, not the page's 16.
		font-size: var(--typography--fontSize-base);

		.select__label {
			display: block;
			margin-bottom: 6px;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}
		.select__error {
			display: flex;
			align-items: flex-start;
			gap: 6px;
			padding-top: var(--space-smaller);
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
		.select__error span {
			display: inline-flex;
			flex: 0 0 auto;
		}
		.select__error :global(svg) {
			width: 14px;
			height: 14px;
		}

		:global(.select__trigger) {
			display: flex;
			width: 100%;
			min-height: calc(var(--space-larger) + var(--space-small));
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			padding: 0 calc(var(--space-smaller) + var(--space-minuscule)) 0 var(--space-slim);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			outline: none;
			color: inherit;
			background: var(--color-surface);
			font: inherit;
			line-height: var(--typography--lineHeight-base);
			text-align: left;
			cursor: pointer;
		}

		:global(.select__trigger:hover:not(:disabled)) {
			border-color: var(--color-border--interactive--hover);
		}
		:global(.select__trigger:active:not(:disabled)) {
			background: var(--color-surface--active);
		}
		:global(.select__trigger[data-state='open']) {
			border: 1.5px solid var(--color-interactive);
			box-shadow: var(--shadow-focus);
		}
		&.select--invalid :global(.select__trigger) {
			border: 1.5px solid var(--color-critical);
		}
		:global(.select__trigger[data-placeholder]) {
			color: var(--color-text--secondary);
		}
		:global(.select__trigger:disabled) :global(.select__chevron),
		:global(.select__trigger:disabled) :global(.select__icon),
		:global(.select__trigger:disabled) :global(.select__prefix) {
			color: var(--color-disabled);
		}

		:global(.select__trigger:focus-visible) {
			position: relative;
			z-index: var(--elevation-base);
			box-shadow: var(--shadow-focus);
		}

		:global(.select__trigger:disabled) {
			border-color: var(--color-border);
			color: var(--color-disabled);
			background: var(--color-disabled--secondary);
			cursor: not-allowed;
		}

		:global(.select__icon) {
			display: inline-flex;
			flex: 0 0 auto;
			color: var(--color-icon--secondary);
		}

		:global(.select__icon svg) {
			display: block;
			width: 16px;
			height: 16px;
		}

		:global(.select__prefix) {
			flex: 0 0 auto;
			color: var(--color-text--secondary);
			white-space: nowrap;
		}

		:global(.select__value) {
			flex: 1 1 auto;
			min-width: 0;
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		:global(.select__chevron) {
			display: grid;
			width: calc(var(--space-larger) - var(--space-smallest));
			height: calc(var(--space-larger) - var(--space-smallest));
			flex: 0 0 auto;
			place-items: center;
			border-radius: var(--radius-tile-small);
			color: var(--color-icon);
			background: var(--color-surface--background--subtle);
		}

		:global(.select__trigger[data-state='open']) :global(.select__chevron) {
			color: var(--color-surface);
			background: var(--color-interactive);
		}

		:global(.select__trigger:disabled) :global(.select__chevron) {
			background: var(--color-disabled--secondary);
		}
	}

	:global(.select__chevron svg) {
		display: block;
		width: 14px;
		height: 14px;
	}
	:global(.select__chevron-up) {
		display: none;
	}
	:global(
		.select__trigger[data-state='open'] .select__chevron:not(.select__chevron--locked) > svg
	) {
		display: none;
	}
	:global(
		.select__trigger[data-state='open']
			.select__chevron:not(.select__chevron--locked)
			.select__chevron-up
	) {
		display: contents;
	}
	:global(.select__status-tile) {
		display: grid;
		width: var(--space-large);
		height: var(--space-large);
		flex: 0 0 auto;
		place-items: center;
		border: var(--border-base) solid var(--status-edge);
		border-radius: var(--radius-tile-small);
		background: var(--status-surface);
	}
	:global(.select__status-tile span) {
		width: var(--space-small);
		height: var(--space-small);
		border-radius: var(--radius-circle);
		background: var(--status-tone);
	}

	:global(.select__content) {
		z-index: var(--elevation-modal);
		width: var(--bits-floating-anchor-width);
		max-height: min(calc(var(--space-extravagant) * 3), var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	// A trigger that hugs its value is narrower than its longest option, so the list sizes itself instead.
	:global(.select__content.select__content--fit) {
		width: max-content;
		min-width: max(var(--bits-floating-anchor-width), calc(var(--space-extravagant) * 2.5));
		max-width: min(calc(var(--space-extravagant) * 5), var(--bits-floating-available-width));
	}

	:global(.select__viewport) {
		max-height: inherit;
		overflow-y: auto;
		padding: calc(var(--space-smaller) + var(--space-smallest));
	}

	:global(.select__option) {
		display: flex;
		width: 100%;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		min-height: calc(var(--space-largest) - var(--space-small));
		margin-bottom: 2px;
		padding: 0 10px;
		border: 1.5px solid transparent;
		border-radius: var(--radius-tile-large);
		outline: none;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 400;
		line-height: var(--typography--lineHeight-base);
		cursor: pointer;
		transition:
			color var(--timing-quick),
			background-color var(--timing-quick);
	}

	:global(.select__option[data-highlighted]) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}

	:global(.select__option[data-selected]) {
		color: var(--color-heading);
		font-weight: 600;
		border-color: var(--color-interactive);
		background: var(--color-surface);
	}

	:global(.select__option:active:not([data-disabled])) {
		background: var(--color-surface--active);
	}

	:global(.select__option[data-disabled]) {
		color: var(--color-disabled);
		cursor: not-allowed;
	}

	.select__option-label {
		flex: 1 1 auto;
		min-width: 0;
		overflow: hidden;
		white-space: normal;
		overflow-wrap: anywhere;
	}

	:global(.select__radio) {
		width: 18px;
		height: 18px;
		flex: 0 0 auto;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-circle);
		background: var(--color-surface);
	}
	:global(.select__radio--selected) {
		border: 5px solid var(--color-interactive);
	}
	:global(.select__option[data-disabled] .select__radio) {
		border-color: var(--color-disabled--secondary);
	}
	:global(.select__option-reason) {
		color: var(--color-disabled);
		font-size: var(--typography--fontSize-smaller);
	}
	.select__option-label {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
	}
	.select__option-dot {
		width: 8px;
		height: 8px;
		border-radius: var(--radius-circle);
		flex: 0 0 8px;
	}
</style>
