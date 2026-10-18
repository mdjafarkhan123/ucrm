<script lang="ts">
	import Avatar from './Avatar.svelte';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import circlePlusIcon from '@tabler/icons/outline/circle-plus.svg?raw';

	// One person in a "Who is going" row (New job `zUFDO`): a round chip with their avatar and name that is
	// ticked on and off like a checkbox. Picked, it turns brand green with a check; not picked, it is a plain
	// white chip with a plus.
	let {
		id,
		personId,
		name,
		checked = false,
		disabled = false,
		onchange
	}: {
		/** The checkbox's id. */
		id: string;
		/** The person's id, for their avatar colour. */
		personId: string;
		name: string;
		checked?: boolean;
		disabled?: boolean;
		onchange?: (checked: boolean) => void;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<label
	class={['person-chip', checked && 'person-chip--checked', disabled && 'person-chip--disabled']}
	for={id}
>
	<input
		{id}
		type="checkbox"
		{checked}
		{disabled}
		onchange={(event) => onchange?.(event.currentTarget.checked)}
	/>
	<Avatar id={personId} {name} size="small" />
	<span class="person-chip__name">{name}</span>
	<span class="person-chip__state" aria-hidden="true"
		>{@html checked ? circleCheckIcon : circlePlusIcon}</span
	>
</label>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.person-chip {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		height: 36px;
		padding: 0 var(--space-slim) 0 6px;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-circle);
		color: var(--color-heading);
		background: var(--color-surface);
		box-shadow: var(--shadow-button);
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
		cursor: pointer;
		user-select: none;
		transition:
			background-color var(--timing-quick),
			border-color var(--timing-quick);

		input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}

		:global(.avatar) {
			box-shadow: 0 0 0 2px var(--color-surface);
		}

		&__state {
			display: inline-flex;
			color: var(--color-icon--secondary);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&:hover:not(.person-chip--disabled) {
			border-color: var(--color-border--interactive--hover);
			background: var(--color-surface--hover);
		}
		&:active:not(.person-chip--disabled) {
			background: var(--color-surface--active);
		}
		&:has(input:focus-visible) {
			box-shadow: var(--shadow-focus);
		}

		// Picked: a 1.5 brand-green edge, and the name and check in brand green.
		&--checked {
			border-color: var(--color-interactive);
			color: var(--color-interactive);
			box-shadow: inset 0 0 0 0.5px var(--color-interactive);

			.person-chip__state {
				color: var(--color-interactive);
			}

			&:hover:not(.person-chip--disabled) {
				border-color: var(--color-interactive--hover);
				color: var(--color-interactive--hover);
			}
		}

		&--disabled {
			border-color: var(--color-disabled--secondary);
			color: var(--color-disabled);
			background: var(--color-disabled--secondary);
			box-shadow: none;
			cursor: not-allowed;
		}
	}
</style>
