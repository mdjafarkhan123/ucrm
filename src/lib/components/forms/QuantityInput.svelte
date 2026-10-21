<script lang="ts">
	import minusIcon from '@tabler/icons/outline/minus.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	// Same shape as MoneyInput: free typing behind a plain text field, committed to the numeric value on
	// blur. A get/set bind straight to a number round-trips every keystroke through Number(), which strips
	// a trailing "." mid-type and resets the cursor — this is what avoids that.
	let {
		value = $bindable(1),
		id,
		label,
		size = 'base',
		disabled = false,
		placeholder = '0'
	}: {
		value?: number;
		id: string;
		label?: string;
		size?: 'small' | 'base' | 'large';
		disabled?: boolean;
		placeholder?: string;
	} = $props();

	function fromValue(quantity: number) {
		return String(quantity);
	}

	let draft = $state(fromValue(value));
	let focused = $state(false);

	// The external value only overwrites what is being typed once the field is not the one changing it —
	// otherwise a save elsewhere on the page would yank the cursor mid-keystroke.
	$effect(() => {
		if (!focused) draft = fromValue(value);
	});

	function commit() {
		focused = false;
		const parsed = Number(draft);
		if (!Number.isFinite(parsed) || parsed <= 0) {
			draft = fromValue(value);
			return;
		}
		// The column is numeric(12,3); round to what the database will actually store so the field never
		// shows a number it is about to silently change on save.
		value = Math.round(parsed * 1000) / 1000;
		draft = fromValue(value);
	}
	function step(delta: number) {
		if (disabled) return;
		commit();
		value = Math.round(Math.max(1, value + delta) * 1000) / 1000;
		draft = fromValue(value);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="quantity-input quantity-input--{size}">
	{#if label}<label for={id}>{label}</label>{/if}
	<div class="quantity-input__control" class:quantity-input__control--disabled={disabled}>
		<button
			type="button"
			aria-label="Decrease quantity"
			disabled={disabled || value <= 1}
			onclick={() => step(-1)}>{@html minusIcon}</button
		>
		<input
			{id}
			aria-label={label ?? 'Quantity'}
			{disabled}
			{placeholder}
			type="text"
			inputmode="decimal"
			bind:value={draft}
			onfocus={() => (focused = true)}
			onblur={commit}
			onkeydown={(event) => {
				if (event.key === 'Enter') event.currentTarget.blur();
			}}
		/>
		<button type="button" aria-label="Increase quantity" {disabled} onclick={() => step(1)}
			>{@html plusIcon}</button
		>
	</div>
</div>

<style lang="scss">
	.quantity-input {
		min-width: 0;
		label {
			display: block;
			margin-bottom: 6px;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}
		&__control {
			display: flex;
			align-items: center;
			gap: 2px;
			height: 36px;
			padding: 3px;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--field--fill, var(--color-surface--background));
			&:hover {
				border-color: var(--color-border--interactive--hover);
			}
			&:focus-within {
				box-shadow: var(--shadow-focus);
			}
		}
		input {
			min-width: 24px;
			width: 100%;
			padding: 0;
			border: 0;
			outline: 0;
			background: transparent;
			text-align: center;
			font: inherit;
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			color: var(--color-heading);
		}
		button {
			display: grid;
			place-items: center;
			flex: 0 0 28px;
			width: 28px;
			height: 28px;
			padding: 0;
			border: 0;
			border-radius: var(--radius-tile-small);
			background: var(--color-surface--hover);
			color: var(--color-icon);
			cursor: pointer;
			&:hover:not(:disabled),
			&:active:not(:disabled) {
				background: var(--color-surface--active);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			&:disabled {
				color: var(--color-disabled);
				cursor: not-allowed;
			}
			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
		&__control--disabled {
			background: var(--color-disabled--secondary);
			input {
				color: var(--color-disabled);
			}
		}
	}
</style>
