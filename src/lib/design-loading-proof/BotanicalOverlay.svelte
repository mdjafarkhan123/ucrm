<svelte:options css="injected" />

<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	let { open, onClose }: { open: boolean; onClose: () => void } = $props();
</script>

<Dialog {open} {onClose} title="Read-only delivery example" size="small">
	<section class="proof-overlay" data-proof-overlay="botanical">
		<p>Fictional garden maintenance record</p>
		<p>This private example cannot save business records.</p>
	</section>
</Dialog>

<style lang="scss">
	/* This content is portalled outside the shell. Its exclusive style owns its own scope. */
	.proof-overlay {
		--proof-accent: #286b49;
		padding: 16px;
		border: 2px solid var(--proof-accent);
		border-radius: 12px;
		background: #f5f4ef;
		color: #172b4d;
	}
</style>
