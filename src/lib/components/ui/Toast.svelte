<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import exclamationCircleIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import infoCircleIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	let {
		open = $bindable(true),
		variant = 'info',
		title,
		message,
		loading = false,
		dismissible = true,
		action,
		onDismiss,
		onPause,
		onResume
	}: {
		open?: boolean;
		variant?: 'success' | 'error' | 'warning' | 'info';
		title: string;
		message?: string;
		loading?: boolean;
		dismissible?: boolean;
		// One follow-up the person can take, such as Undo. Choosing it closes the toast.
		action?: { label: string; onSelect: () => void };
		onDismiss?: () => void;
		// Hovering or focusing the toast holds it open, so its action can be reached in time.
		onPause?: () => void;
		onResume?: () => void;
	} = $props();

	const variantIcon = $derived(
		{
			success: checkIcon,
			error: exclamationCircleIcon,
			warning: alertTriangleIcon,
			info: infoCircleIcon
		}[variant]
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if open}
	<div
		class={`toast toast--${variant}`}
		role={variant === 'error' ? 'alert' : 'status'}
		aria-busy={loading}
		onmouseenter={onPause}
		onmouseleave={onResume}
		onfocusin={onPause}
		onfocusout={onResume}
	>
		{#if loading}
			<span class="toast__spinner" aria-hidden="true"></span>
		{:else}
			<span class="toast__icon" aria-hidden="true">{@html variantIcon}</span>
		{/if}
		<div class="toast__content">
			<strong>{title}</strong>
			{#if message}<p>{message}</p>{/if}
			{#if action}
				<button
					class="toast__action"
					type="button"
					onclick={() => {
						open = false;
						onDismiss?.();
						action.onSelect();
					}}
				>
					{action.label}
				</button>
			{/if}
		</div>
		{#if dismissible}
			<button
				class="toast__dismiss"
				type="button"
				aria-label="Dismiss notification"
				onclick={() => {
					open = false;
					onDismiss?.();
				}}
			>
				{@html closeIcon}
			</button>
		{/if}
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(:root:has(.app-shell[data-presentation='classic'])) .toast {
		align-items: center;
		gap: 10px;
		padding: 12px 14px;
		border: 1px solid var(--classic2-border);
		border-radius: 14px;
		color: var(--classic2-body);
		background: var(--classic2-surface-raised);
		box-shadow: 0 12px 32px var(--classic2-shadow-lift);
		font: 13px/1.5 var(--classic2-font);
		&--success {
			--toast-color: var(--classic2-green);
		}
		&--error {
			--toast-color: var(--classic2-rose);
		}
		&--warning {
			--toast-color: var(--classic2-amber);
		}
		&--info {
			--toast-color: var(--classic2-blue);
		}
		.toast__content {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: 4px 12px;
		}
		strong {
			flex: 1 1 auto;
			color: var(--classic2-ink);
			font-weight: 600;
			overflow-wrap: anywhere;
		}
		p {
			flex-basis: 100%;
			color: var(--classic2-muted);
			font-size: 12px;
		}
		.toast__icon :global(svg) {
			width: 17px;
			height: 17px;
		}
		.toast__spinner {
			width: 17px;
			height: 17px;
			color: var(--classic2-muted);
		}
		.toast__action {
			margin: 0;
			padding: 4px;
			border: 0;
			color: var(--classic2-green);
			background: transparent;
			font-size: 13px;
			font-weight: 700;
		}
		.toast__action:hover {
			background: var(--classic2-surface-soft);
		}
		.toast__dismiss {
			color: var(--classic2-muted);
		}
		.toast__dismiss:hover {
			color: var(--classic2-ink);
			background: var(--classic2-surface-soft);
		}
		.toast__action:focus-visible,
		.toast__dismiss:focus-visible {
			outline: 2px solid var(--classic2-green);
			outline-offset: 2px;
			box-shadow: none;
		}
	}

	.toast {
		animation: toast-enter 180ms ease-out;
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		width: min(100%, 420px);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-left: var(--border-thicker) solid var(--toast-color);
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
		will-change: transform, opacity;

		&--success {
			--toast-color: var(--color-success);
		}
		&--error {
			--toast-color: var(--color-critical);
		}
		&--warning {
			--toast-color: var(--color-warning);
		}
		&--info {
			--toast-color: var(--color-informative);
		}
		&__icon {
			flex: 0 0 auto;
			color: var(--toast-color);
		}
		&__icon :global(svg) {
			width: 22px;
			height: 22px;
		}
		&__spinner {
			flex: 0 0 auto;
			width: 20px;
			height: 20px;
			margin: 1px;
			border: 2px solid currentColor;
			border-right-color: transparent;
			border-radius: var(--radius-circle);
			color: var(--toast-color);
			animation: spinning var(--timing-loading) linear infinite;
		}
		&__content {
			flex: 1;
			min-width: 0;
		}
		strong {
			display: block;
			color: var(--color-heading);
			font-weight: 700;
		}
		p {
			margin-top: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-tighter);
		}
		&__action {
			margin-top: var(--space-small);
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-small);
			color: var(--color-heading);
			background: var(--color-surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;
			transition: background-color var(--timing-quick);
		}
		&__action:hover {
			background: var(--color-surface--hover);
		}
		&__action:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&__dismiss {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			padding: var(--space-smaller);
			border: 0;
			border-radius: var(--radius-small);
			color: var(--color-icon--secondary);
			background: transparent;
		}
		&__dismiss :global(svg) {
			width: 16px;
			height: 16px;
		}
		&__dismiss:hover {
			color: var(--color-heading);
			background: var(--color-surface--hover);
		}
		&__dismiss:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	@keyframes toast-enter {
		from {
			transform: translateY(-8px);
			opacity: 0;
		}
		to {
			transform: translateY(0);
			opacity: 1;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.toast {
			animation: none;

			&__spinner {
				animation: none;
			}
		}
	}
</style>
