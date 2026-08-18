<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import minusIcon from '@tabler/icons/outline/minus.svg?raw';
	let {
		checked = $bindable(false),
		indeterminate = false,
		id,
		label,
		description = '',
		disabled = false,
		invalid = false,
		name,
		value = 'on',
		onchange
	}: {
		checked?: boolean;
		indeterminate?: boolean;
		id: string;
		label: string;
		description?: string;
		disabled?: boolean;
		invalid?: boolean;
		name?: string;
		value?: string;
		/** For a list of checkboxes whose state lives in one array rather than a variable each. */
		onchange?: (checked: boolean) => void;
	} = $props();

	let inputElement = $state<HTMLInputElement>();
	let describedBy = $derived(description ? `${id}-description` : undefined);

	$effect(() => {
		if (inputElement) inputElement.indeterminate = indeterminate;
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<label
	class="checkbox"
	class:checkbox--disabled={disabled}
	class:checkbox--invalid={invalid}
	for={id}
>
	<input
		bind:this={inputElement}
		{id}
		{name}
		{value}
		type="checkbox"
		bind:checked
		onchange={(event) => onchange?.(event.currentTarget.checked)}
		{disabled}
		aria-invalid={invalid}
		aria-describedby={describedBy}
	/>
	<span class="checkbox__box" aria-hidden="true">{@html indeterminate ? minusIcon : checkIcon}</span
	>
	<span class="checkbox__content">
		<span class="checkbox__label">{label}</span>
		{#if description}<span class="checkbox__description" id={`${id}-description`}
				>{description}</span
			>{/if}
	</span>
</label>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.checkbox {
		display: inline-flex;
		align-items: flex-start;
		gap: var(--space-small);
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
		cursor: pointer;
		user-select: none;

		input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}

		&__box {
			display: inline-grid;
			flex: 0 0 20px;
			place-items: center;
			width: 20px;
			height: 20px;
			margin-top: var(--space-smallest);
			border: var(--border-thick) solid var(--color-border--interactive);
			border-radius: var(--radius-small);
			color: var(--color-surface);
			background: var(--color-surface);
			transition: all var(--timing-quick) ease-out;

			:global(svg) {
				width: 14px;
				height: 14px;
				opacity: 0;
			}
		}

		&__content {
			display: grid;
			gap: var(--space-smaller);
		}
		&__label {
			color: var(--color-text);
		}
		&__description {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&:hover:not(.checkbox--disabled) .checkbox__box {
			border-color: var(--color-interactive);
		}
		&:has(input:checked) .checkbox__box,
		&:has(input:indeterminate) .checkbox__box {
			border-color: var(--color-interactive);
			background: var(--color-interactive);
			:global(svg) {
				opacity: 1;
			}
		}
		&:has(input:focus-visible) .checkbox__box {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&--invalid .checkbox__box {
			border-color: var(--color-critical);
		}
		&--invalid:has(input:checked) .checkbox__box {
			background: var(--color-critical);
		}
		&--disabled {
			color: var(--color-disabled);
			cursor: not-allowed;
		}
		&--disabled .checkbox__box {
			border-color: var(--color-disabled--secondary);
			background: var(--color-disabled--secondary);
		}
		&--disabled .checkbox__label,
		&--disabled .checkbox__description {
			color: var(--color-disabled);
		}
		&--disabled:has(input:checked) .checkbox__box {
			border-color: var(--color-disabled);
			background: var(--color-disabled);
		}
	}
</style>
