<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import alertCircleIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import Tooltip from '$lib/components/ui/Tooltip.svelte';
	import {
		fetchResolvedEmailSender,
		resolvedEmailSenderKey,
		type ResolvedEmailSenderKind
	} from '$lib/communications/senders';

	// The "From" value of an email preview: the real address the send will use, read the same way the
	// send itself chooses it. It mounts only inside an opened dialog or composer, so it loads on reveal.
	let { kind }: { kind: ResolvedEmailSenderKind } = $props();

	const senderQuery = createQuery(() => ({
		queryKey: resolvedEmailSenderKey(kind),
		queryFn: () => fetchResolvedEmailSender(kind),
		staleTime: 60_000
	}));
	const sender = $derived(senderQuery.data);

	// The chip stays on one line; when the address is cut off, hover or focus shows it in full.
	let cutOff = $state(false);

	function watchCutOff(element: HTMLElement) {
		const measure = () => (cutOff = element.scrollWidth > element.clientWidth + 1);
		measure();
		const observer = new ResizeObserver(measure);
		observer.observe(element);
		return () => observer.disconnect();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if senderQuery.isPending}
	<span class="email-sender-label__bone skeleton" role="status">
		<span class="email-sender-label__sr">Loading sender…</span>
	</span>
{:else if senderQuery.isError}
	<span class="email-sender-label email-sender-label--critical">
		<span class="email-sender-label__icon" aria-hidden="true">{@html alertCircleIcon}</span>
		<span class="email-sender-label__name">Sender could not be loaded</span>
	</span>
{:else if sender}
	<Tooltip text="{sender.display_name} · {sender.email_address}" disabled={!cutOff}>
		{#snippet children(props)}
			<span
				{...props}
				{@attach watchCutOff}
				class="email-sender-label"
				tabindex={cutOff ? 0 : undefined}
			>
				<span class="email-sender-label__icon" aria-hidden="true">{@html mailIcon}</span>
				<span class="email-sender-label__name">{sender.display_name}</span>
				<span class="email-sender-label__address">{sender.email_address}</span>
			</span>
		{/snippet}
	</Tooltip>
{:else}
	<span class="email-sender-label email-sender-label--warning">
		<span class="email-sender-label__icon" aria-hidden="true">{@html alertTriangleIcon}</span>
		<span class="email-sender-label__name">
			{kind === 'manual'
				? 'No email address is assigned to you yet'
				: 'No default business email address is set up yet'}
		</span>
	</span>
{/if}

<style lang="scss">
	.email-sender-label {
		display: inline-flex;
		max-width: 100%;
		min-width: 0;
		height: 28px;
		box-sizing: border-box;
		align-items: center;
		gap: 6px;
		padding: 0 var(--space-slim) 0 var(--space-small);
		overflow: hidden;
		border: var(--border-base) solid var(--color-conversation--surface-edge);
		border-radius: var(--radius-circle);
		background: var(--color-conversation--surface);
		font-size: var(--typography--fontSize-label);
		line-height: 1;
		vertical-align: middle;
		white-space: nowrap;

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&__icon {
			display: inline-flex;
			flex: 0 0 auto;
			color: var(--color-conversation);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__name {
			flex: 0 0 auto;
			color: var(--color-conversation--onSurface);
			font-weight: 600;
		}

		&__address {
			min-width: 0;
			overflow: hidden;
			color: var(--color-text--secondary);
			font-weight: 400;
			text-overflow: ellipsis;
		}

		&--critical {
			border-color: var(--color-critical--surface-edge);
			background: var(--color-critical--surface);

			.email-sender-label__icon {
				color: var(--color-critical);
			}

			.email-sender-label__name {
				flex: 0 1 auto;
				min-width: 0;
				overflow: hidden;
				color: var(--color-critical--onSurface);
				text-overflow: ellipsis;
			}
		}

		&--warning {
			border-color: var(--color-warning--surface-edge);
			background: var(--color-warning--surface);

			.email-sender-label__icon {
				color: var(--color-warning);
			}

			.email-sender-label__name {
				flex: 0 1 auto;
				min-width: 0;
				overflow: hidden;
				color: var(--color-warning--onSurface);
				text-overflow: ellipsis;
			}
		}

		&__bone {
			display: inline-block;
			width: 240px;
			max-width: 100%;
			height: 28px;
			min-height: 0;
			border-radius: var(--radius-circle);
			vertical-align: middle;
		}

		&__sr {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}
	}
</style>
