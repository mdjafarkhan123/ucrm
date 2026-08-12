<script lang="ts">
	import AppShell from '$lib/components/layout/AppShell.svelte';
	let { children } = $props();
</script>

<AppShell variant="owner">{@render children()}</AppShell>
