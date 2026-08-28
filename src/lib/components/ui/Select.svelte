<script lang="ts">
	import { Select as SelectPrimitive } from 'bits-ui';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';

	type SelectOption = {
		value: string;
		label: string;
		disabled?: boolean;
	};

	let {
		value = $bindable(''),
		options,
		id,
		label,
		ariaLabel,
		placeholder = 'Select an option',
		disabled = false,
		required = false,
		name,
		class: className = '',
		onchange
	}: {
		value?: string;
		options: SelectOption[];
		id: string;
		label?: string;
		ariaLabel?: string;
		placeholder?: string;
		disabled?: boolean;
		required?: boolean;
		name?: string;
		class?: string;
		onchange?: (value: string) => void;
	} = $props();

	let selectedLabel = $derived(
		options.find((option) => option.value === value)?.label ?? placeholder
	);
	let labelId = $derived(label ? `${id}-label` : undefined);

	function handleValueChange(nextValue: string) {
		value = nextValue;
		onchange?.(nextValue);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div
	class={['select', label && 'select--labelled', className]}
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
			aria-label={label ? undefined : ariaLabel}
			aria-labelledby={labelId}
		>
			<span class="select__value">{selectedLabel}</span>
			<span class="select__chevron" aria-hidden="true">{@html chevronDownIcon}</span>
		</SelectPrimitive.Trigger>

		<SelectPrimitive.Portal>
			<SelectPrimitive.Content
				class="select__content"
				data-elevation="elevated"
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
								<span class="select__option-label">{option.label}</span>
								{#if selected}
									<span class="select__check" aria-hidden="true">{@html checkIcon}</span>
								{/if}
							{/snippet}
						</SelectPrimitive.Item>
					{/each}
				</SelectPrimitive.Viewport>
			</SelectPrimitive.Content>
		</SelectPrimitive.Portal>
	</SelectPrimitive.Root>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.select {
		position: relative;
		width: 100%;
		color: var(--color-heading);

		&.select--labelled {
			padding-top: var(--space-small);
		}

		.select__label {
			position: absolute;
			z-index: var(--elevation-base);
			top: 0;
			left: var(--space-slim);
			max-width: calc(100% - var(--space-large));
			padding: 0 var(--space-smaller);
			overflow: hidden;
			color: var(--color-text--secondary);
			background: var(--color-surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			line-height: var(--space-base);
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		:global(.select__trigger) {
			display: flex;
			width: 100%;
			min-height: calc(var(--space-larger) + var(--space-small));
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			padding: 0 var(--space-small);
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

		:global(.select__value) {
			min-width: 0;
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		:global(.select__chevron) {
			display: grid;
			width: 16px;
			height: 16px;
			flex: 0 0 auto;
			place-items: center;
			color: var(--color-icon--secondary);
			transition: transform var(--timing-quick);
		}

		:global(.select__trigger[data-state='open']) :global(.select__chevron) {
			transform: rotate(180deg);
		}
	}

	:global(.select__chevron svg),
	:global(.select__check svg) {
		display: block;
		width: 16px;
		height: 16px;
	}

	:global(.select__content) {
		z-index: var(--elevation-modal);
		width: var(--bits-floating-anchor-width);
		max-height: min(calc(var(--space-extravagant) * 3), var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	:global(.select__viewport) {
		max-height: inherit;
		overflow-y: auto;
		padding: var(--space-small);
	}

	:global(.select__option) {
		display: flex;
		width: 100%;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-small);
		border-radius: var(--radius-small);
		outline: none;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
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
		background: var(--color-surface--active);
	}

	:global(.select__option[data-disabled]) {
		color: var(--color-disabled);
		cursor: not-allowed;
	}

	.select__option-label {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.select__check {
		display: grid;
		width: 16px;
		height: 16px;
		flex: 0 0 auto;
		place-items: center;
		color: var(--color-interactive);
	}
</style>
