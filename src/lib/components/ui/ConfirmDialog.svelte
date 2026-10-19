<script lang="ts">
	import { AlertDialog } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';

	// The "are you sure?" pop-up (`concept.pen` → Pop-ups): one decision before something happens. No ×;
	// Cancel or Escape backs out.
	let {
		open,
		title,
		icon,
		tone = 'default',
		confirmLabel = 'Confirm',
		cancelLabel = 'Cancel',
		destructive = false,
		loading = false,
		confirmDisabled = false,
		onConfirm,
		onClose,
		children
	}: {
		open: boolean;
		title: string;
		icon?: string;
		/** The tile's colour: `critical` for danger, `warning` when something is missing but you may carry
		 *  on, or the record you will end up with (`job`, `invoice`…). */
		tone?: 'default' | 'critical' | 'success' | 'warning' | (string & {});
		confirmLabel?: string;
		/** Null for a notice that only needs acknowledging: one button, no second choice. */
		cancelLabel?: string | null;
		destructive?: boolean;
		loading?: boolean;
		confirmDisabled?: boolean;
		onConfirm: () => void;
		onClose: () => void;
		children: Snippet;
	} = $props();

	let content = $state<HTMLElement | null>(null);

	const tileTone = $derived(tone === 'default' ? 'informative' : tone);
	const tileIcon = $derived(
		icon ??
			(tone === 'critical' || tone === 'warning'
				? alertIcon
				: tone === 'success'
					? checkIcon
					: infoIcon)
	);
</script>

<AlertDialog.Root
	{open}
	onOpenChange={(next) => {
		if (!next) onClose();
	}}
>
	<AlertDialog.Portal>
		<AlertDialog.Overlay class="confirm-dialog__overlay" />
		<AlertDialog.Content
			bind:ref={content}
			class="confirm-dialog__content"
			onOpenAutoFocus={(event) => {
				// Start on Cancel, so pressing Enter never confirms by accident.
				const cancel = content?.querySelector<HTMLElement>('[data-alert-dialog-cancel]');
				if (!cancel) return;
				event.preventDefault();
				cancel.focus();
			}}
		>
			<div class="confirm-dialog__heading">
				<IconTile icon={tileIcon} tone={tileTone} />
				<AlertDialog.Title level={2} class="confirm-dialog__title">{title}</AlertDialog.Title>
			</div>
			<div class="confirm-dialog__body">
				{@render children()}
			</div>
			<div class="confirm-dialog__actions">
				{#if cancelLabel !== null}
					<AlertDialog.Cancel>
						{#snippet child({ props })}
							<Button {...props} type="button" variant="secondary" disabled={loading}
								>{cancelLabel}</Button
							>
						{/snippet}
					</AlertDialog.Cancel>
				{/if}
				<Button
					type="button"
					variation={destructive ? 'destructive' : 'work'}
					disabled={confirmDisabled}
					{loading}
					onclick={onConfirm}>{confirmLabel}</Button
				>
			</div>
		</AlertDialog.Content>
	</AlertDialog.Portal>
</AlertDialog.Root>

<style lang="scss">
	:global(.confirm-dialog__overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: var(--color-overlay);
	}

	:global(.confirm-dialog__content) {
		position: fixed;
		top: 50%;
		left: 50%;
		z-index: var(--elevation-modal);
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		box-sizing: border-box;
		width: min(calc(100vw - var(--space-large) * 2), 480px);
		max-height: calc(100dvh - var(--space-large) * 2);
		overflow: auto;
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
		transform: translate(-50%, -50%);
	}

	.confirm-dialog__heading {
		display: flex;
		align-items: center;
		gap: 14px;
	}

	:global(.confirm-dialog__title) {
		flex: 1 1 auto;
		min-width: 0;
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		font-weight: 600;
		line-height: 1.3;
	}

	.confirm-dialog__body {
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-large);

		:global(strong) {
			color: var(--color-heading);
		}
	}

	.confirm-dialog__actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
		padding-top: var(--space-small);
	}
</style>
