<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// A binary on/off setting. Use Checkbox instead when the answer is "opt in", part of a multi-select
	// set, or only takes effect once a form is saved — a toggle reads as a switch that acts immediately.
	let {
		checked = $bindable(false),
		id,
		label,
		description = '',
		disabled = false,
		labelSide = 'end',
		onchange
	}: {
		checked?: boolean;
		id: string;
		label: string;
		description?: string;
		disabled?: boolean;
		/** 'end' puts the text after the switch, 'start' puts the switch on the far right of a settings row. */
		labelSide?: 'start' | 'end';
		onchange?: (checked: boolean) => void;
	} = $props();

	const describedBy = $derived(description ? `${id}-description` : undefined);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<label
	class="toggle"
	class:toggle--disabled={disabled}
	class:toggle--label-start={labelSide === 'start'}
	for={id}
>
	<input
		{id}
		type="checkbox"
		role="switch"
		bind:checked
		{disabled}
		aria-describedby={describedBy}
		onchange={(event) => onchange?.(event.currentTarget.checked)}
	/>

	<span class="toggle__track" aria-hidden="true">
		<span class="toggle__icon toggle__icon--on">{@html checkIcon}</span>
		<span class="toggle__icon toggle__icon--off">{@html xIcon}</span>
		<span class="toggle__pip"></span>
	</span>

	<span class="toggle__content">
		<span class="toggle__label">{label}</span>
		{#if description}
			<span class="toggle__description" id={`${id}-description`}>{description}</span>
		{/if}
	</span>
</label>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.toggle {
		--toggle--width: 48px;
		--toggle--height: 24px;
		--toggle--pip: 16px;
		--toggle--pip-off: 2px;
		--toggle--pip-on: 26px;

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

		&__track {
			position: relative;
			display: inline-block;
			box-sizing: border-box;
			width: var(--toggle--width);
			height: var(--toggle--height);
			flex: 0 0 var(--toggle--width);
			border: var(--border-thick) solid var(--color-border--interactive);
			border-radius: var(--toggle--pip);
			background: var(--color-inactive--surface);
			transition: all var(--timing-base) ease-in-out;
		}

		&__pip {
			position: absolute;
			top: 2px;
			left: 0;
			box-sizing: border-box;
			width: var(--toggle--pip);
			height: var(--toggle--pip);
			border-radius: var(--radius-circle);
			background: var(--color-inactive--onSurface);
			transform: translateX(var(--toggle--pip-off));
			transition: all var(--timing-base) ease-in-out;
		}

		// Each icon sits on the side the pip is not covering.
		&__icon {
			position: absolute;
			top: 2px;
			display: grid;
			width: var(--toggle--pip);
			height: var(--toggle--pip);
			place-items: center;
			opacity: 0;
			transition: opacity var(--timing-base) ease-in-out;

			:global(svg) {
				display: block;
				width: 12px;
				height: 12px;
			}

			&--on {
				left: 4px;
				color: var(--color-surface);
			}

			&--off {
				right: 4px;
				color: var(--color-inactive--onSurface);
				opacity: 1;
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

		&--label-start {
			width: 100%;
			align-items: center;
			justify-content: space-between;

			.toggle__content {
				order: -1;
			}
		}

		// --- States -------------------------------------------------------------------------------

		&:hover:not(.toggle--disabled) .toggle__track,
		&:has(input:focus-visible) .toggle__track {
			border-color: var(--color-interactive);
		}

		&:has(input:focus-visible) .toggle__track {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&:has(input:checked) {
			.toggle__track {
				background: var(--color-interactive);
			}

			.toggle__pip {
				background: var(--color-surface);
				transform: translateX(var(--toggle--pip-on));
			}

			.toggle__icon--on {
				opacity: 1;
			}

			.toggle__icon--off {
				opacity: 0;
			}
		}

		&:hover:not(.toggle--disabled):has(input:checked) .toggle__track {
			background: var(--color-interactive--hover);
		}

		&--disabled {
			color: var(--color-disabled);
			cursor: not-allowed;

			.toggle__track {
				border-color: var(--color-disabled);
				background: var(--color-surface);
			}

			.toggle__pip {
				border: var(--border-base) solid var(--color-disabled--secondary);
				background: var(--color-disabled);
			}

			.toggle__icon--off {
				color: var(--color-disabled);
			}

			.toggle__label,
			.toggle__description {
				color: var(--color-disabled);
			}
		}

		&--disabled:has(input:checked) {
			.toggle__track {
				background: var(--color-disabled);
			}

			.toggle__pip {
				border-color: var(--color-disabled--secondary);
				background: var(--color-surface);
			}
		}
	}
</style>
