<script lang="ts">
	import Toast from './Toast.svelte';
	import type { ToastManager } from './ToastManager.svelte';

	let { manager }: { manager: ToastManager } = $props();

	let viewport: HTMLDivElement;
	// Where the keyboard was before F8 brought it here, so it can be put back once the toast has gone.
	let returnTo: HTMLElement | null = null;

	// Toasts sit at the very end of the page, dozens of Tab presses from wherever the person is working,
	// and they do not wait. F8 jumps straight to the newest one's button — Undo, or Dismiss — the same
	// shortcut Radix Toast uses for its notification region.
	function jumpToToasts(event: KeyboardEvent) {
		if (event.key !== 'F8' || event.defaultPrevented) return;
		const buttons = viewport.querySelectorAll<HTMLElement>('.toast:last-child button');
		if (buttons.length === 0) return;
		event.preventDefault();
		if (!viewport.contains(document.activeElement)) {
			returnTo = document.activeElement instanceof HTMLElement ? document.activeElement : null;
		}
		buttons[0].focus();
	}

	// A toast that closes while it holds focus would leave the keyboard nowhere. Hand focus back to where
	// it came from, unless something else has already taken it.
	function restoreFocus(event: FocusEvent) {
		if (event.relatedTarget !== null) return;
		const target = returnTo;
		queueMicrotask(() => {
			if (document.activeElement !== document.body) return;
			if (target?.isConnected) target.focus();
			returnTo = null;
		});
	}
</script>

<svelte:window onkeydown={jumpToToasts} />

<div
	bind:this={viewport}
	class="toast-viewport"
	role="region"
	aria-label="Notifications (F8)"
	onfocusout={restoreFocus}
>
	{#each manager.toasts as toast (toast.id)}
		<Toast
			open={true}
			variant={toast.variant}
			title={toast.title}
			message={toast.message}
			loading={toast.loading}
			dismissible={!toast.loading}
			action={toast.action}
			onDismiss={() => manager.dismiss(toast.id)}
			onPause={() => manager.pause(toast.id)}
			onResume={() => manager.resume(toast.id)}
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
