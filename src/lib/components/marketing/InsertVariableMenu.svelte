<script lang="ts">
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import { MARKETING_VARIABLES, MARKETING_VARIABLE_LABELS } from '$lib/marketing/campaign-content';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	// Every field the block editor lets carry a variable (blueprint §8 step 3: "approved customer/business
	// variables") offers the same fixed picker -- never a free-typed `{{token}}`, so a saved draft can never
	// contain a token the server's `rejectUnknownVariables` would refuse.
	let { onInsert }: { onInsert: (token: string) => void } = $props();

	const items = MARKETING_VARIABLES.map((variable) => ({
		label: MARKETING_VARIABLE_LABELS[variable],
		onSelect: () => onInsert(`{{${variable}}}`)
	}));
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<DropdownMenu
	{items}
	triggerLabel="Insert a variable"
	triggerClass="insert-variable__trigger"
	align="end"
>
	{#snippet trigger()}
		<span class="insert-variable__icon" aria-hidden="true">{@html plusIcon}</span>
		Variable
	{/snippet}
</DropdownMenu>

<style lang="scss">
	:global(.insert-variable__trigger) {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		height: var(--space-largest);
		padding: 0 var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		white-space: nowrap;
		cursor: pointer;
		transition: all var(--timing-quick) ease-out;
	}
	:global(.insert-variable__trigger:hover:not(:disabled)) {
		border-color: var(--color-border--interactive);
		color: var(--color-interactive);
	}
	:global(.insert-variable__trigger:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.insert-variable__icon :global(svg) {
		width: 14px;
		height: 14px;
		display: block;
	}
</style>
