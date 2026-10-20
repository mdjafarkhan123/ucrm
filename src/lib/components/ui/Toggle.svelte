<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

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
		<span class="toggle__pip">{@html checkIcon}</span>
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
		display: inline-flex;
		align-items: center;
		gap: 10px;
		cursor: pointer;
		user-select: none;
		input {
			position: absolute;
			width: 1px;
			height: 1px;
			clip-path: inset(50%);
			overflow: hidden;
			white-space: nowrap;
		}
		&__track {
			position: relative;
			display: inline-block;
			width: 44px;
			height: 24px;
			flex: 0 0 44px;
			border-radius: var(--radius-circle);
			background: var(--color-border--interactive);
			transition: background var(--timing-quick);
		}
		&__pip {
			position: absolute;
			top: 3px;
			left: 3px;
			display: grid;
			place-items: center;
			width: 18px;
			height: 18px;
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			color: var(--color-interactive);
			box-shadow:
				0 1px 2px color-mix(in srgb, var(--color-heading) 20%, transparent),
				0 2px 6px color-mix(in srgb, var(--color-heading) 10%, transparent);
			transition: transform var(--timing-quick);
			:global(svg) {
				width: 11px;
				height: 11px;
				opacity: 0;
			}
		}
		&__content {
			display: grid;
			gap: 2px;
		}
		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		&__description {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&--label-start {
			width: 100%;
			justify-content: space-between;
			.toggle__content {
				order: -1;
			}
		}
		&:hover:not(.toggle--disabled) .toggle__track {
			background: var(--color-border--interactive--hover);
		}
		&:has(input:checked) {
			.toggle__track {
				background: var(--color-interactive);
			}
			.toggle__pip {
				transform: translateX(20px);
				:global(svg) {
					opacity: 1;
				}
			}
		}
		&:hover:not(.toggle--disabled):has(input:checked) .toggle__track {
			background: var(--color-interactive--hover);
		}
		&:has(input:focus-visible) .toggle__track {
			outline: 2px solid var(--color-focus);
			outline-offset: 2px;
		}
		&:active:not(.toggle--disabled) .toggle__track {
			filter: brightness(0.95);
		}
		&--disabled {
			cursor: default;
			.toggle__track {
				background: var(--color-surface--background--subtle);
				box-shadow: inset 0 0 0 1px var(--color-border--interactive);
			}
			.toggle__pip {
				background: var(--color-disabled);
				box-shadow: none;
			}
			.toggle__label,
			.toggle__description {
				color: var(--color-disabled);
			}
		}
		&--disabled:has(input:checked) {
			.toggle__track {
				background: var(--color-disabled);
				box-shadow: none;
			}
			.toggle__pip {
				background: var(--color-surface--background);
				color: var(--color-disabled);
			}
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.toggle__pip,
		.toggle__track {
			transition: none;
		}
	}
</style>
