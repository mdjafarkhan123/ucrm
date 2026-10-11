<script lang="ts">
	import type { ComponentProps } from 'svelte';
	import SharedAppShell from './SharedAppShell.svelte';
	import ClassicFrame from './presentations/ClassicFrame.svelte';
	let props: Omit<ComponentProps<typeof SharedAppShell>, 'Frame'> = $props();
</script>

<SharedAppShell Frame={ClassicFrame} {...props} />
