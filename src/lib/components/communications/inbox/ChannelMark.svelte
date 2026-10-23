<script lang="ts" module>
	export type InboxChannel = 'messenger' | 'email' | 'sms' | 'website_chat';

	export const CHANNEL_LABELS: Record<InboxChannel, string> = {
		messenger: 'Messenger',
		email: 'Email',
		sms: 'Text',
		website_chat: 'Website chat'
	};
</script>

<script lang="ts">
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import messagesIcon from '@tabler/icons/outline/messages.svg?raw';

	// Which channel a row, bubble or button belongs to (design skill inbox.md, Channel marks). Messenger, email
	// and text show their real logos, because customers recognise them; Website chat is a small app-style tile.
	// `inverse` is the all-white version that sits inside a green bubble.
	let {
		channel,
		size = 14,
		inverse = false,
		label
	}: {
		channel: InboxChannel;
		size?: 12 | 14 | 16;
		inverse?: boolean;
		/** Spoken name; leave out when words beside the mark already say the channel. */
		label?: string;
	} = $props();

	const glyphs: Record<Exclude<InboxChannel, 'messenger'>, string> = {
		email: mailIcon,
		sms: messageIcon,
		website_chat: messagesIcon
	};

	const logos: Partial<Record<InboxChannel, string>> = {
		messenger: '/assets/messenger.png',
		email: '/assets/mail.png',
		sms: '/assets/sms.png'
	};
	const logo = $derived(inverse ? undefined : logos[channel]);
</script>

<span
	class="channel-mark channel-mark--{size} channel-mark--{channel}"
	class:channel-mark--inverse={inverse}
	class:channel-mark--logo={Boolean(logo)}
	role={label ? 'img' : undefined}
	aria-label={label}
	aria-hidden={label ? undefined : 'true'}
>
	{#if logo}
		<img class="channel-mark__logo" src={logo} alt="" />
	{:else if channel === 'messenger'}
		<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
			<path
				fill-rule="evenodd"
				d="M0.001 11.639c0-6.69 5.24-11.639 12-11.639s11.999 4.95 11.999 11.639c0 6.689-5.24 11.638-12 11.638-1.21 0-2.38-0.16-3.47-0.46a0.96 0.96 0 0 0-0.64 0.05l-2.39 1.05a0.96 0.96 0 0 1-1.35-0.85l-0.07-2.14a0.97 0.97 0 0 0-0.32-0.68 11.39 11.389 0 0 1-3.758-8.607z m8.32-2.19l-3.52 5.6c-0.35 0.53 0.32 1.139 0.82 0.75l3.79-2.87c0.26-0.2 0.6-0.2 0.87 0l2.8 2.1c0.84 0.63 2.04 0.4 2.6-0.48l3.52-5.6c0.35-0.53-0.32-1.13-0.82-0.75l-3.79 2.87c-0.25 0.2-0.6 0.2-0.86 0l-2.8-2.1a1.8 1.8 0 0 0-2.61 0.48z"
			/>
		</svg>
	{:else}
		<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
		{@html glyphs[channel]}
	{/if}
</span>

<style lang="scss">
	.channel-mark {
		display: inline-grid;
		flex: 0 0 auto;
		place-items: center;
		border-radius: var(--radius-small);
		color: var(--color-white);

		:global(svg) {
			display: block;
			width: 62.5%;
			height: 62.5%;
			stroke-width: 2.4;
		}

		&--12 {
			width: 12px;
			height: 12px;
		}
		&--14 {
			width: 14px;
			height: 14px;
		}
		&--16 {
			width: 16px;
			height: 16px;
		}

		&--email {
			background: var(--color-channel-email);
		}
		&--sms {
			background: var(--color-channel-text);
		}
		&--website_chat {
			background: var(--color-channel-chat);
		}
		&--messenger {
			border-radius: 0;
			color: var(--color-messenger);

			:global(svg) {
				width: 100%;
				height: 100%;
			}
		}

		// A real logo carries its own shape and colour, so the tile steps back.
		&--logo {
			border-radius: 0;
			background: none;
		}

		&__logo {
			display: block;
			width: 100%;
			height: 100%;
		}

		// Inside a green bubble every mark is plain white, so the tile drops its colour and the glyph fills it.
		&--inverse {
			color: var(--color-surface);
			background: none;

			:global(svg) {
				width: 100%;
				height: 100%;
			}
		}
	}
</style>
