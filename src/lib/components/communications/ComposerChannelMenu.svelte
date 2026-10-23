<script lang="ts">
	import type { Snippet } from 'svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ChannelMark, {
		CHANNEL_LABELS,
		type InboxChannel
	} from '$lib/components/communications/inbox/ChannelMark.svelte';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';

	type ComposerChannel = InboxChannel;
	type ChannelDetail = {
		/** Where the reply goes: the customer's email or number, or the Page for Messenger. */
		address?: string;
		/** Why this channel can't send right now; the line is greyed and can't be picked. */
		unavailable?: string | null;
	};

	let {
		channel,
		channels,
		details = {},
		pageName = null,
		onSelect
	}: {
		channel: ComposerChannel;
		channels: ComposerChannel[];
		details?: Partial<Record<ComposerChannel, ChannelDetail>>;
		/** Messenger's pill names the Page it answers from. */
		pageName?: string | null;
		onSelect: (channel: ComposerChannel) => void;
	} = $props();

	const marks: Record<ComposerChannel, Snippet> = {
		messenger: messengerMark,
		email: emailMark,
		sms: smsMark,
		website_chat: chatMark
	};
	const label = $derived(CHANNEL_LABELS[channel]);
	const items = $derived(
		channels.map((value) => {
			const detail = details[value];
			return {
				key: value,
				label: CHANNEL_LABELS[value],
				leading: marks[value],
				hint: detail?.unavailable ?? detail?.address,
				hintCritical: Boolean(detail?.unavailable),
				disabled: Boolean(detail?.unavailable) && value !== channel,
				current: value === channel,
				onSelect: () => onSelect(value)
			};
		})
	);
	const detailed = $derived(channels.some((value) => details[value]));
</script>

<!-- The channel pill (design `chips.md`, Channel pill): the channel's mark and name, for Messenger the Page, and a
     chevron when it opens the channel menu (`inbox.md`, Channel menu); a tinted look-only pill when the
     conversation has one channel. -->
<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet messengerMark()}<ChannelMark channel="messenger" size={16} />{/snippet}
{#snippet emailMark()}<ChannelMark channel="email" size={16} />{/snippet}
{#snippet smsMark()}<ChannelMark channel="sms" size={16} />{/snippet}
{#snippet chatMark()}<ChannelMark channel="website_chat" size={16} />{/snippet}

{#snippet pillBody()}
	<ChannelMark {channel} size={16} />
	<span>{label}</span>
	{#if channel === 'messenger' && pageName}
		<span class="composer-channel-menu__page">· {pageName} Page</span>
	{/if}
{/snippet}

{#if channels.length > 1}
	<DropdownMenu
		{items}
		triggerLabel={`Change message channel, current: ${label}`}
		triggerClass="composer-channel-menu__trigger"
		contentClass={detailed
			? 'composer-channel-menu__content composer-channel-menu__content--detailed'
			: 'composer-channel-menu__content'}
		align="start"
	>
		{#snippet trigger()}
			{@render pillBody()}
			<span class="composer-channel-menu__chevron" aria-hidden="true">{@html chevronDownIcon}</span>
		{/snippet}
	</DropdownMenu>
{:else}
	<span class="composer-channel-menu__static">{@render pillBody()}</span>
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

	.composer-channel-menu__chevron {
		display: inline-grid;
		place-items: center;
	}

	// Messenger's pill names the Page it answers from; it gives way first when the reply box is narrow.
	.composer-channel-menu__page {
		min-width: 0;
		overflow: hidden;
		color: var(--color-text--secondary);
		font-weight: 400;
		text-overflow: ellipsis;
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

	@container inbox-chat (max-width: 640px) {
		.composer-channel-menu__page {
			display: none;
		}
	}

	// The inbox's channel menu lists where each channel goes, so it is wider (`inbox.md`, Channel menu).
	:global(.composer-channel-menu__content--detailed.dropdown-menu__content) {
		width: 300px;
	}
</style>
