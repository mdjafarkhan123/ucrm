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
		dismissible = true,
		onDismiss
	}: {
		open?: boolean;
		variant?: 'success' | 'error' | 'warning' | 'info';
		title: string;
		message?: string;
		dismissible?: boolean;
		onDismiss?: () => void;
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
	<div class={`toast toast--${variant}`} role={variant === 'error' ? 'alert' : 'status'}>
		<span class="toast__icon" aria-hidden="true">{@html variantIcon}</span>
		<div class="toast__content">
			<strong>{title}</strong>
			{#if message}<p>{message}</p>{/if}
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
		}
	}
</style>
