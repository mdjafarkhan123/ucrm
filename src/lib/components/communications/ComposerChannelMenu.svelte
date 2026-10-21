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
		if (value === 'sms') return { label: 'Text', icon: messageIcon };
		if (value === 'website_chat') return { label: 'Website chat', icon: messagesIcon };
		return { label: 'Email', icon: mailIcon };
	}

	const current = $derived(channelDetails(channel));
	const items = $derived(
		channels.map((value) => ({
			label: channelDetails(value).label,
			icon: channelDetails(value).icon,
			current: value === channel,
			onSelect: () => onSelect(value)
		}))
	);
</script>

<!-- The channel pill (design `chips.md`): white and raised when it opens a menu, a teal look-only pill when the
     conversation has one channel. -->
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
		contentClass="composer-channel-menu__content"
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
		box-sizing: border-box;
		height: 32px;
		align-items: center;
		gap: 6px;
		padding: 0 10px;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-circle);
		color: var(--color-heading);
		background: var(--color-surface);
		font: inherit;
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
		white-space: nowrap;
	}

	:global(.composer-channel-menu__trigger) {
		box-shadow: var(--shadow-button);
		cursor: pointer;
		transition:
			background-color var(--timing-quick),
			border-color var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			border-color: var(--color-interactive);
			box-shadow: 0 0 0 0.5px var(--color-interactive);
		}
	}

	:global(.composer-channel-menu__trigger[data-state='open']) {
		background: var(--color-surface--hover);
	}

	:global(.composer-channel-menu__trigger[data-state='open']) .composer-channel-menu__chevron {
		transform: rotate(180deg);
	}

	// One channel only: nothing to pick, so the pill is a tinted label.
	.composer-channel-menu__static {
		border-color: var(--color-conversation--surface-edge);
		background: var(--color-conversation--surface);
	}

	.composer-channel-menu__icon,
	.composer-channel-menu__chevron {
		display: inline-grid;
		place-items: center;
	}

	.composer-channel-menu__icon {
		color: var(--color-conversation);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.composer-channel-menu__chevron {
		color: var(--color-icon--secondary);
		transition: transform var(--timing-quick);

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	:global(.composer-channel-menu__content.dropdown-menu__content) {
		width: 216px;
	}

	:global(.composer-channel-menu__content .dropdown-menu__item-icon:first-child) {
		color: var(--color-conversation);
	}
</style>
