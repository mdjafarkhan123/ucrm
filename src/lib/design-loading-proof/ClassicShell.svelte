<script lang="ts">
	import type { Snippet } from 'svelte';
	let { children }: { children: Snippet } = $props();
</script>

<div class="proof-shell" data-proof-design="classic">
	<header class="proof-shell__header">
		<strong>classic</strong><span>Private loading proof · synthetic data</span>
	</header>
	<main class="proof-shell__content">
		<h1>One workspace, selected presentation</h1>
		<p>This tests delivery only. It is not the approved app redesign.</p>
		{@render children()}
	</main>
</div>

<style lang="scss">
	.proof-shell {
		min-height: 100vh;
		background: #f4f6f8;
		color: #172b4d;
		.proof-shell__header {
			display: flex;
			flex-wrap: wrap;
			gap: 16px;
			padding: 24px;
			border-bottom: 3px solid #2563eb;
		}
		.proof-shell__content {
			max-width: 960px;
			padding: 24px;
			margin: auto;
		}
		:global(a) {
			display: inline-block;
			margin-top: 24px;
			color: #2563eb;
			padding: 8px;
			border-radius: 6px;
		}
		:global(a:hover) {
			text-decoration: underline;
		}
		:global(a:focus-visible) {
			outline: 3px solid #2563eb;
			outline-offset: 3px;
		}
	}
</style>
