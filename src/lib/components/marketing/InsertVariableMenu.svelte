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
	triggerText="Variable"
	triggerLeadingIcon={plusIcon}
	triggerChevron={false}
	triggerSize="small"
	align="end"
/>
