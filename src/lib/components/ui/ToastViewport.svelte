<script lang="ts">
	import Toast from './Toast.svelte';
	import type { ToastManager } from './ToastManager.svelte';

	let { manager }: { manager: ToastManager } = $props();
</script>

<div class="toast-viewport" aria-label="Notifications">
	{#each manager.toasts as toast (toast.id)}
		<Toast
			open={true}
			variant={toast.variant}
			title={toast.title}
			message={toast.message}
			onDismiss={() => manager.dismiss(toast.id)}
		/>
	{/each}
</div>

<style lang="scss">
	.toast-viewport {
		position: fixed;
		top: var(--space-base);
		right: var(--space-base);
		z-index: var(--elevation-toast);
		display: grid;
		gap: var(--space-small);
		width: min(calc(100vw - (var(--space-base) * 2)), 420px);
		pointer-events: none;

		:global(.toast) {
			pointer-events: auto;
		}
	}

	@media (max-width: 600px) {
		.toast-viewport {
			top: var(--space-small);
			right: var(--space-small);
			left: var(--space-small);
			width: auto;
		}
	}
</style>
