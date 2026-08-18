<script lang="ts">
	import Sidebar, { type NavGroup } from './Sidebar.svelte';

	let {
		open = $bindable(false),
		groups,
		brand,
		eyebrow,
		onnavigate
	}: {
		open?: boolean;
		groups: NavGroup[];
		brand?: string;
		eyebrow?: string;
		onnavigate?: () => void;
	} = $props();

	let panelEl = $state<HTMLDivElement>();
	let lastFocused: HTMLElement | null = null;

	function focusableElements(): HTMLElement[] {
		if (!panelEl) return [];
		return Array.from(
			panelEl.querySelectorAll<HTMLElement>(
				'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'
			)
		);
	}

	function close() {
		open = false;
	}

	function onkeydown(event: KeyboardEvent) {
		if (event.key === 'Escape') {
			event.preventDefault();
			close();
			return;
		}
		if (event.key !== 'Tab') return;
		const focusable = focusableElements();
		if (focusable.length === 0) return;
		const first = focusable[0];
		const last = focusable[focusable.length - 1];
		if (event.shiftKey && document.activeElement === first) {
			event.preventDefault();
			last.focus();
		} else if (!event.shiftKey && document.activeElement === last) {
			event.preventDefault();
			first.focus();
		}
	}

	$effect(() => {
		if (open) {
			lastFocused = document.activeElement as HTMLElement | null;
			(focusableElements()[0] ?? panelEl)?.focus();
		} else {
			lastFocused?.focus();
			lastFocused = null;
		}
	});
</script>

{#if open}
	<div class="mobile-nav">
		<button class="mobile-nav__backdrop" type="button" aria-label="Close navigation" onclick={close}
		></button>
		<div
			class="mobile-nav__panel"
			bind:this={panelEl}
			role="dialog"
			aria-modal="true"
			aria-label="Navigation"
			tabindex="-1"
			{onkeydown}
		>
			<Sidebar
				{groups}
				{brand}
				{eyebrow}
				collapsible={false}
				onnavigate={() => {
					open = false;
					onnavigate?.();
				}}
			/>
		</div>
	</div>
{/if}

<style lang="scss">
	.mobile-nav {
		position: fixed;
		z-index: var(--elevation-modal);
		inset: 0;
		display: flex;
	}
	.mobile-nav__backdrop {
		position: absolute;
		inset: 0;
		border: 0;
		background: var(--color-overlay);
	}
	.mobile-nav__panel {
		position: relative;
		z-index: var(--elevation-modal);
		width: min(86vw, 320px);
		background: var(--color-surface--background);
		box-shadow: var(--shadow-overlay);

		&:focus-visible {
			outline: none;
		}
	}
	.mobile-nav__panel :global(.sidebar) {
		display: flex;
		width: 100%;
		min-height: 100%;
		border: 0;
	}
</style>
