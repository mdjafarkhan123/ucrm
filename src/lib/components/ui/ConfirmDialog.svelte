<script lang="ts">
	import { AlertDialog } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';

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
		tone?: 'default' | 'critical' | 'success';
		confirmLabel?: string;
		cancelLabel?: string;
		destructive?: boolean;
		loading?: boolean;
		confirmDisabled?: boolean;
		onConfirm: () => void;
		onClose: () => void;
		children: Snippet;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<AlertDialog.Root
	{open}
	onOpenChange={(next) => {
		if (!next) onClose();
	}}
>
	<AlertDialog.Portal>
		<AlertDialog.Overlay class="confirm-dialog__overlay" />
		<AlertDialog.Content class="confirm-dialog__content confirm-dialog__content--{tone}">
			<div class="confirm-dialog__heading">
				{#if icon}<span class="confirm-dialog__icon" aria-hidden="true">{@html icon}</span>{/if}
				<AlertDialog.Title level={2}>{title}</AlertDialog.Title>
			</div>
			<div class="confirm-dialog__body">
				{@render children()}
			</div>
			<div class="confirm-dialog__actions">
				<AlertDialog.Cancel>
					{#snippet child({ props })}
						<Button
							{...props}
							type="button"
							variant="secondary"
							variation="subtle"
							disabled={loading}>{cancelLabel}</Button
						>
					{/snippet}
				</AlertDialog.Cancel>
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

<!-- eslint-enable svelte/no-at-html-tags -->

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
		box-sizing: border-box;
		width: min(calc(100vw - var(--space-large) * 2), 480px);
		max-height: calc(100dvh - var(--space-large) * 2);
		overflow: auto;
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
		transform: translate(-50%, -50%);
	}

	:global(.confirm-dialog__content--critical) {
		border-color: var(--color-critical);
	}

	:global(.confirm-dialog__content--success) {
		border-color: var(--color-success);
	}

	:global(.confirm-dialog__content [data-slot='alert-dialog-title']) {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tightest);
	}

	.confirm-dialog__heading {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.confirm-dialog__icon {
		display: grid;
		width: 24px;
		height: 24px;
		flex: 0 0 24px;
		place-items: center;
		color: var(--color-icon--secondary);

		:global(svg) {
			display: block;
			width: 20px;
			height: 20px;
		}
	}

	:global(.confirm-dialog__content--critical) .confirm-dialog__icon {
		color: var(--color-critical);
	}

	:global(.confirm-dialog__content--success) .confirm-dialog__icon {
		color: var(--color-success);
	}

	.confirm-dialog__body {
		margin-top: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
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
		margin-top: var(--space-large);
	}
</style>
