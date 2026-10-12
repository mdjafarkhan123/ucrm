<svelte:options css="injected" />

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
		--proof-accent: #2563eb;
		min-height: 100vh;
		overflow-wrap: anywhere;
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
		:global(a),
		:global(button) {
			display: inline-block;
			max-width: 100%;
			margin-top: 24px;
			color: #2563eb;
			padding: 8px;
			border-radius: 6px;
		}
		:global(button) {
			border: 1px solid var(--proof-accent);
			background: white;
			cursor: pointer;
		}
		:global(button:disabled) {
			opacity: 0.5;
			cursor: default;
		}
		:global(a:hover),
		:global(button:hover) {
			text-decoration: underline;
		}
		:global(a:focus-visible),
		:global(button:focus-visible) {
			outline: 3px solid #2563eb;
			outline-offset: 3px;
		}
	}
</style>
