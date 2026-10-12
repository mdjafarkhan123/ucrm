<script lang="ts">
	import ProofWorkspace from '$lib/design-loading-proof/ProofWorkspace.svelte';
	import type { PageProps } from './$types';
	let { data }: PageProps = $props();
</script>

<svelte:head>
	<title>Selected design loading proof</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<!-- A deliberate test-design navigation gets its own local state. No cookie, storage or public preference. -->
{#key data.design}
	<ProofWorkspace design={data.design} surface={data.surface} Shell={data.Shell} />
{/key}
