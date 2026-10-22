<script lang="ts">
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import { MARKETING_VARIABLES, MARKETING_VARIABLE_LABELS } from '$lib/marketing/campaign-content';
	import type { MarketingVariable } from '$lib/marketing/campaign-content';
	import bracesIcon from '@tabler/icons/outline/braces.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import buildingStoreIcon from '@tabler/icons/outline/building-store.svg?raw';

	// Every field the block editor lets carry a variable (blueprint §8 step 3: "approved customer/business
	// variables") offers the same fixed picker -- never a free-typed `{{token}}`, so a saved draft can never
	// contain a token the server's `rejectUnknownVariables` would refuse. The look is the design skill's
	// `layout.md` → New campaign · Email step: a 28 square button inside a one-line field, or a labelled one
	// under a paragraph box.
	let {
		onInsert,
		variant = 'icon',
		label = 'Insert a variable'
	}: {
		onInsert: (token: string) => void;
		variant?: 'icon' | 'labelled';
		/** Names the button to a screen reader; several fields on one page each need their own. */
		label?: string;
	} = $props();

	// A chosen variable goes into a field, which takes focus itself; the menu must not pull it back.
	let inserted = false;

	// The customer's own detail is a client thing (sand), the business's is the business's (heading ink).
	const iconColors: Record<MarketingVariable, string> = {
		customer_first_name: 'var(--color-client)',
		business_name: 'var(--color-icon)'
	};
	const icons: Record<MarketingVariable, string> = {
		customer_first_name: userIcon,
		business_name: buildingStoreIcon
	};

	const items = MARKETING_VARIABLES.map((variable) => ({
		label: MARKETING_VARIABLE_LABELS[variable],
		icon: icons[variable],
		iconColor: iconColors[variable],
		onSelect: () => {
			inserted = true;
			onInsert(`{{${variable}}}`);
		}
	}));

	function keepFocusInField(event: Event) {
		if (!inserted) return;
		inserted = false;
		event.preventDefault();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<DropdownMenu
	{items}
	triggerLabel={label}
	triggerClass={`variable-button variable-button--${variant}`}
	roomy
	wide
	align={variant === 'labelled' ? 'start' : 'end'}
	onCloseAutoFocus={keepFocusInField}
>
	{#snippet trigger()}
		{@html bracesIcon}{#if variant === 'labelled'}<span>Variable</span>{/if}
	{/snippet}
</DropdownMenu>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// The trigger is drawn inside the shared menu, so these reach it by class.
	:global(.variable-button) {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		gap: var(--space-smaller);
		height: 28px;
		border: var(--border-base) solid var(--color-border);
		border-radius: 6px;
		color: var(--color-growth);
		background: var(--color-surface--background--subtle);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		cursor: pointer;
		transition:
			background-color var(--timing-quick) ease-out,
			border-color var(--timing-quick) ease-out;

		:global(svg) {
			display: block;
			width: 14px;
			height: 14px;
		}

		&:hover {
			border-color: var(--color-growth--surface-edge);
			background: var(--color-growth--surface);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		// Open: the Marketing colour fills the button.
		&[data-state='open'] {
			border-color: var(--color-growth);
			color: var(--color-text--reverse);
			background: var(--color-growth);
		}
	}

	:global(.variable-button--icon) {
		width: 28px;
	}

	// Under a paragraph box the button says its word, in the soft Marketing tint.
	:global(.variable-button--labelled) {
		padding: 0 8px;
		border-color: var(--color-growth--surface-edge);
		color: var(--color-growth--onSurface);
		background: var(--color-growth--surface);

		:global(svg) {
			color: var(--color-growth);
		}
		&[data-state='open'] :global(svg) {
			color: inherit;
		}
	}
</style>
