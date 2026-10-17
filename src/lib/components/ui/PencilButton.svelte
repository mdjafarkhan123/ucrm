<script lang="ts">
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import Button from './Button.svelte';

	// The small square edit affordance that sits beside a heading or at the end of a row: the shared icon
	// button holding a pencil. It carries no label, so `label` is required and becomes both the accessible
	// name and the hover title. Pass `href` to go to an edit page, or `onclick` to open an editor in place.
	let {
		label,
		href,
		onclick,
		onhover,
		size = 'small',
		disabled = false
	}: {
		/** What this pencil edits, e.g. "Edit Riverbend Diner". Read out loud by a screen reader. */
		label: string;
		href?: string;
		onclick?: (event: MouseEvent) => void;
		/** Fires when the pointer or keyboard reaches the button, before it is pressed. Use it to start
		 *  loading whatever pressing it will reveal, so the editor is already there on the click. */
		onhover?: () => void;
		size?: 'small' | 'base';
		disabled?: boolean;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Button variant="secondary" iconOnly {size} {label} {href} {disabled} {onclick} {onhover}>
	{@html pencilIcon}
</Button>
<!-- eslint-enable svelte/no-at-html-tags -->
