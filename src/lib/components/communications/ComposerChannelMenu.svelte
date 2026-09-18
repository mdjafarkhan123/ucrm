<script lang="ts">
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import messagesIcon from '@tabler/icons/outline/messages.svg?raw';

	type ComposerChannel = 'email' | 'sms' | 'website_chat';

	let {
		channel,
		channels,
		onSelect
	}: {
		channel: ComposerChannel;
		channels: ComposerChannel[];
		onSelect: (channel: ComposerChannel) => void;
	} = $props();

	function channelDetails(value: ComposerChannel) {
		if (value === 'sms') return { label: 'SMS', icon: messageIcon };
		if (value === 'website_chat') return { label: 'Website chat', icon: messagesIcon };
		return { label: 'Email', icon: mailIcon };
	}

	const current = $derived(channelDetails(channel));
	const items = $derived(
		channels.map((value) => ({
			label: channelDetails(value).label,
			icon: channelDetails(value).icon,
			onSelect: () => onSelect(value)
		}))
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet trigger()}
	<span class="composer-channel-menu__icon" aria-hidden="true">{@html current.icon}</span>
	<span>{current.label}</span>
	<span class="composer-channel-menu__chevron" aria-hidden="true">{@html chevronDownIcon}</span>
{/snippet}

{#if channels.length > 1}
	<DropdownMenu
		{items}
		triggerLabel={`Change message channel, current: ${current.label}`}
		triggerClass="composer-channel-menu__trigger"
		{trigger}
		align="start"
	/>
{:else}
	<span class="composer-channel-menu__static">
		<span class="composer-channel-menu__icon" aria-hidden="true">{@html current.icon}</span>
		<span>{current.label}</span>
	</span>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.composer-channel-menu__trigger),
	.composer-channel-menu__static {
		display: inline-flex;
		min-height: 32px;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-smaller) var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		color: var(--color-text);
		background: var(--color-surface);
		font: inherit;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	:global(.composer-channel-menu__trigger) {
		cursor: pointer;
		transition:
			background-color var(--timing-quick),
			border-color var(--timing-quick);

		&:hover,
		&:focus-visible {
			border-color: var(--color-border--interactive);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	:global(.composer-channel-menu__trigger[data-state='open']) {
		border-color: var(--color-border--interactive);
		background: var(--color-surface--hover);
	}

	.composer-channel-menu__static {
		border-color: transparent;
	}

	.composer-channel-menu__icon,
	.composer-channel-menu__chevron {
		display: inline-grid;
		place-items: center;
		color: var(--color-icon--secondary);
	}

	.composer-channel-menu__icon :global(svg) {
		width: 16px;
		height: 16px;
	}

	.composer-channel-menu__chevron :global(svg) {
		width: 14px;
		height: 14px;
	}
</style>
