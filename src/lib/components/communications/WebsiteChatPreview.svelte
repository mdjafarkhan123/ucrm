<script lang="ts">
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import messageCircleIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';

	type ChannelOption = {
		type: 'whatsapp' | 'messenger';
		destination: string;
	};

	let {
		businessName,
		brandColor = null,
		logoUrl = null,
		launcherPosition,
		teaserText,
		greetingText,
		contactRequirement,
		privacyPolicyUrl,
		channelOptions = []
	}: {
		businessName: string;
		brandColor?: string | null;
		logoUrl?: string | null;
		launcherPosition: string;
		teaserText: string;
		greetingText: string;
		contactRequirement: string;
		privacyPolicyUrl: string;
		channelOptions?: ChannelOption[];
	} = $props();

	const viewportOptions = [
		{ value: 'desktop', label: 'Desktop' },
		{ value: 'mobile', label: 'Mobile' }
	];

	let viewport = $state('desktop');
	let panelOpen = $state(true);
	let logoFailed = $state(false);

	const displayName = $derived(businessName.trim() || 'Your business');
	const displayGreeting = $derived(greetingText.trim() || 'Hi there! How can we help?');
	const displayTeaser = $derived(
		teaserText.trim() || 'Hi there. Have a question? Message us here.'
	);
	// The same words the live widget shows above its contact box.
	const replyHint = $derived(
		contactRequirement === 'phone'
			? 'Phone needed'
			: contactRequirement === 'email'
				? 'Email needed'
				: 'Phone or email'
	);
	const initials = $derived.by(() => {
		const parts = displayName.split(/\s+/).filter(Boolean);
		if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
		return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
	});
	const showLogo = $derived(Boolean(logoUrl) && !logoFailed);
</script>

{#snippet logoMark(size: 24 | 32)}
	<span
		class={['chat-preview__logo', `chat-preview__logo--${size}`, showLogo && 'chat-preview__logo--image']}
		aria-hidden="true"
	>
		{#if showLogo}
			<img src={logoUrl} alt="" onerror={() => (logoFailed = true)} />
		{:else}
			{initials}
		{/if}
	</span>
{/snippet}

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="chat-preview" aria-labelledby="website-chat-preview-title">
	<header class="chat-preview__header">
		<div>
			<h3 id="website-chat-preview-title">Preview</h3>
			<p>See the customer experience before you publish.</p>
		</div>
		<SegmentedControl
			bind:value={viewport}
			options={viewportOptions}
			label="Preview size"
			size="small"
		/>
	</header>

	<div
		class={['chat-preview__viewport', viewport === 'mobile' && 'chat-preview__viewport--mobile']}
		style:--chat-preview-brand={brandColor || 'var(--color-brand)'}
	>
		<div class="chat-preview__browser" aria-label={`${viewport} Website Chat preview`}>
			<div class="chat-preview__browser-bar" aria-hidden="true">
				<span></span><span></span><span></span>
			</div>
			<div class="chat-preview__site">
				<div
					class={[
						'chat-preview__widget',
						launcherPosition === 'bottom_left' && 'chat-preview__widget--left'
					]}
				>
					{#if panelOpen}
						<article class="chat-preview__panel">
							<div class="chat-preview__hero">
								<div class="chat-preview__hero-top">
									<span class="chat-preview__tile">{@render logoMark(32)}</span>
									<button
										type="button"
										class="chat-preview__close"
										aria-label="Collapse preview"
										onclick={() => (panelOpen = false)}
									>
										{@html xIcon}
									</button>
								</div>
								<p class="chat-preview__business">{displayName}</p>
								<h4 class="chat-preview__greeting">{displayGreeting}</h4>
							</div>

							<div class="chat-preview__card-space">
								<div class="chat-preview__card">
									<div class="chat-preview__group">
										<span class="chat-preview__label">Your message</span>
										<div class="chat-preview__box chat-preview__box--message">
											What can we help you with?
										</div>
									</div>

									<div class="chat-preview__group">
										<div class="chat-preview__group-head">
											<span class="chat-preview__label">How should we reply?</span>
											<small>{replyHint}</small>
										</div>
										<div class="chat-preview__box">
											<div class="chat-preview__row">{@html userIcon}Your name</div>
											<div class="chat-preview__row chat-preview__row--phone">
												<span class="chat-preview__country">+1 {@html chevronDownIcon}</span>
												{contactRequirement === 'email' ? 'Phone (optional)' : 'Phone number'}
											</div>
											<div class="chat-preview__row">
												{@html mailIcon}{contactRequirement === 'email' ? 'Email' : 'Email (optional)'}
											</div>
										</div>
									</div>

									{#if channelOptions.length}
										<div class="chat-preview__channels" aria-label="Configured contact options">
											<span>Website Chat</span>
											{#each channelOptions as option (option.type)}
												<span>{option.type === 'whatsapp' ? 'WhatsApp' : 'Messenger'}</span>
											{/each}
										</div>
									{/if}

									<span class="chat-preview__send">
										Send message
										<span class="chat-preview__send-well">{@html arrowRightIcon}</span>
									</span>
								</div>
							</div>

							<footer class="chat-preview__footer">
								{#if privacyPolicyUrl.trim()}
									{@html lockIcon}<strong>Privacy policy</strong><span aria-hidden="true">·</span>
								{/if}
								<span>Powered by {displayName}</span>
							</footer>
						</article>
					{:else}
						<div class="chat-preview__teaser">
							<span class="chat-preview__dismiss" aria-hidden="true">{@html xIcon}</span>
							<div class="chat-preview__bubble">
								<span class="chat-preview__who">{@render logoMark(24)}{displayName}</span>
								<span class="chat-preview__teaser-text">{displayTeaser}</span>
							</div>
						</div>
					{/if}

					<button
						type="button"
						class={['chat-preview__launcher', panelOpen && 'chat-preview__launcher--open']}
						aria-label={panelOpen ? 'Collapse preview' : 'Open preview'}
						onclick={() => (panelOpen = !panelOpen)}
					>
						{#if panelOpen}
							{@html chevronDownIcon}
						{:else}
							{@html messageCircleIcon}<span>Message us</span>
						{/if}
					</button>
				</div>
			</div>
		</div>
	</div>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.chat-preview {
		display: grid;
		gap: var(--space-base);
	}

	.chat-preview__header {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: var(--space-base);

		h3 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
		}

		p {
			margin: var(--space-smaller) 0 0;
			color: var(--color-text--secondary);
		}
	}

	.chat-preview__viewport {
		display: flex;
		justify-content: center;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}

	.chat-preview__browser {
		width: 100%;
		min-height: 690px;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		transition: width var(--timing-base) ease-out;
	}

	.chat-preview__viewport--mobile .chat-preview__browser {
		width: min(100%, 360px);
	}

	.chat-preview__browser-bar {
		display: flex;
		gap: var(--space-smaller);
		padding: var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background);

		span {
			width: var(--space-small);
			height: var(--space-small);
			border-radius: var(--radius-circle);
			background: var(--color-border);
		}
	}

	.chat-preview__site {
		position: relative;
		min-height: 656px;
		background:
			linear-gradient(var(--color-border), var(--color-border)) var(--space-large)
				var(--space-large) / 42% var(--space-small) no-repeat,
			linear-gradient(var(--color-border), var(--color-border)) var(--space-large)
				calc(var(--space-large) + var(--space-large)) / 64% var(--space-small) no-repeat,
			var(--color-surface--background--subtle);
	}

	/* The widget wears the business's colour and stays light on every website, in dark mode too
	   (layout.md § Website chat widget), so its preview keeps the light values rather than following
	   the app's theme. Mirrors the tokens `src/widget/website-chat.ts` copies. */
	.chat-preview__widget {
		--wc-surface: #ffffff;
		--wc-subtle: #f9f8f6;
		--wc-border: #dadfe2;
		--wc-heading: #032b3a;
		--wc-text: #233d48;
		--wc-quiet: #49646f;
		--wc-icon: #84979f;

		position: absolute;
		right: var(--space-base);
		bottom: var(--space-base);
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-base);
	}

	.chat-preview__widget--left {
		right: auto;
		left: var(--space-base);
		align-items: flex-start;
	}

	.chat-preview__panel {
		width: min(340px, calc(100vw - 96px));
		overflow: hidden;
		border: var(--border-base) solid var(--wc-border);
		border-radius: var(--radius-larger);
		background: var(--wc-subtle);
		box-shadow:
			0 20px 48px rgb(3 43 58 / 18%),
			0 2px 6px rgb(3 43 58 / 8%);
	}

	.chat-preview__hero {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		padding: var(--space-base) var(--space-base) calc(var(--space-largest) + var(--space-smaller))
			var(--space-medium);
		color: var(--color-white);
		background:
			radial-gradient(120% 160% at 95% 0%, rgb(255 255 255 / 20%), rgb(255 255 255 / 0%) 60%),
			linear-gradient(
				200deg,
				var(--chat-preview-brand),
				color-mix(in srgb, var(--chat-preview-brand) 78%, #000000)
			);
	}

	.chat-preview__hero-top {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		margin-bottom: var(--space-slim);
	}

	.chat-preview__tile {
		display: grid;
		width: 40px;
		height: 40px;
		place-items: center;
		border-radius: var(--radius-tile-large);
		background: var(--wc-surface);
	}

	.chat-preview__close {
		display: grid;
		width: 28px;
		height: 28px;
		place-items: center;
		border: 0;
		border-radius: var(--radius-tile-large);
		color: var(--color-white);
		background: rgb(255 255 255 / 15%);
		cursor: pointer;

		&:hover {
			background: rgb(255 255 255 / 25%);
		}

		&:focus-visible {
			outline: transparent;
			box-shadow: 0 0 0 2px var(--color-white);
		}

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.chat-preview__business {
		margin: 0;
		color: rgb(255 255 255 / 82%);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.chat-preview__greeting {
		color: var(--color-white);
		font-size: var(--typography--fontSize-larger);
		font-weight: 700;
		letter-spacing: -0.4px;
		line-height: 1.2;
		overflow-wrap: anywhere;
	}

	.chat-preview__logo {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		overflow: hidden;
		color: var(--color-white);
		background: var(--chat-preview-brand);
		font-weight: 700;

		img {
			width: 100%;
			height: 100%;
			object-fit: contain;
		}
	}

	.chat-preview__logo--image {
		background: var(--wc-surface);
	}

	.chat-preview__logo--24 {
		width: 24px;
		height: 24px;
		border-radius: var(--radius-tile-small);
		font-size: var(--typography--fontSize-smaller);
	}

	.chat-preview__logo--32 {
		width: 28px;
		height: 28px;
		border-radius: var(--radius-base);
		font-size: var(--typography--fontSize-smaller);
	}

	.chat-preview__card-space {
		margin-top: calc(-1 * var(--space-larger) - var(--space-small));
		padding: 0 var(--space-slim);
	}

	.chat-preview__card {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		padding: var(--space-base);
		border: var(--border-base) solid var(--wc-border);
		border-radius: var(--space-medium);
		background: var(--wc-surface);
		box-shadow: 0 4px 14px rgb(3 43 58 / 8%);
	}

	.chat-preview__group {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
	}

	.chat-preview__group-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-small);

		small {
			color: var(--wc-quiet);
			font-size: var(--typography--fontSize-smaller);
		}
	}

	.chat-preview__label {
		color: var(--wc-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.chat-preview__box {
		overflow: hidden;
		border: var(--border-base) solid var(--wc-border);
		border-radius: var(--radius-tile-large);
		color: var(--wc-quiet);
		background: var(--wc-surface);
		font-size: var(--typography--fontSize-small);
	}

	.chat-preview__box--message {
		min-height: 64px;
		padding: var(--space-small) var(--space-slim);
	}

	.chat-preview__row {
		display: flex;
		min-height: 38px;
		align-items: center;
		gap: var(--space-small);
		padding: 0 var(--space-slim);

		& + & {
			border-top: var(--border-base) solid var(--wc-border);
		}

		> :global(svg) {
			width: 15px;
			height: 15px;
			color: var(--wc-icon);
		}
	}

	.chat-preview__row--phone {
		padding-left: var(--space-smaller);
	}

	.chat-preview__country {
		display: inline-flex;
		height: 28px;
		align-items: center;
		gap: var(--space-smallest);
		padding: 0 var(--space-smaller) 0 var(--space-small);
		border-radius: var(--radius-base);
		color: var(--wc-heading);
		background: var(--wc-subtle);
		font-weight: 600;

		:global(svg) {
			width: 13px;
			height: 13px;
			color: var(--wc-icon);
		}
	}

	.chat-preview__channels {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-smaller);

		span {
			padding: var(--space-smallest) var(--space-small);
			border: var(--border-base) solid var(--wc-border);
			border-radius: var(--radius-circle);
			color: var(--wc-quiet);
			font-size: var(--typography--fontSize-smaller);
		}
	}

	.chat-preview__send {
		display: flex;
		min-height: 42px;
		align-items: center;
		justify-content: space-between;
		padding: 0 var(--space-smaller) 0 var(--space-base);
		border-radius: var(--radius-tile-large);
		color: var(--color-white);
		background: var(--chat-preview-brand);
		font-size: var(--typography--fontSize-large);
		font-weight: 600;
	}

	.chat-preview__send-well {
		display: grid;
		width: 30px;
		height: 30px;
		place-items: center;
		border-radius: var(--radius-base);
		background: rgb(255 255 255 / 18%);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.chat-preview__footer {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: center;
		gap: var(--space-smaller);
		padding: var(--space-slim) var(--space-base);
		color: var(--wc-quiet);
		font-size: var(--typography--fontSize-smaller);

		strong {
			color: var(--wc-text);
			text-decoration: underline;
		}

		:global(svg) {
			width: 12px;
			height: 12px;
			color: var(--wc-icon);
		}
	}

	.chat-preview__teaser {
		display: flex;
		width: min(280px, calc(100vw - 96px));
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-small);
	}

	.chat-preview__widget--left .chat-preview__teaser {
		align-items: flex-start;
	}

	.chat-preview__dismiss {
		display: grid;
		width: 26px;
		height: 26px;
		place-items: center;
		border-radius: var(--radius-circle);
		color: var(--wc-text);
		background: var(--wc-surface);
		box-shadow:
			0 2px 6px rgb(3 43 58 / 12%),
			0 0 0 1px var(--wc-border);

		:global(svg) {
			width: 13px;
			height: 13px;
		}
	}

	.chat-preview__bubble {
		display: flex;
		width: 100%;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base) var(--space-base);
		border-radius: var(--space-medium) var(--space-medium) var(--space-smaller) var(--space-medium);
		background: var(--wc-surface);
		box-shadow:
			0 12px 30px rgb(3 43 58 / 12%),
			0 0 0 1px var(--wc-border);
	}

	.chat-preview__widget--left .chat-preview__bubble {
		border-radius: var(--space-medium) var(--space-medium) var(--space-medium) var(--space-smaller);
	}

	.chat-preview__who {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		color: var(--wc-heading);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
	}

	.chat-preview__teaser-text {
		color: var(--wc-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 500;
		line-height: 1.4;
	}

	.chat-preview__launcher {
		display: inline-flex;
		height: 48px;
		align-items: center;
		gap: var(--space-small);
		padding: 0 var(--space-medium) 0 var(--space-base);
		border: 0;
		border-radius: var(--radius-circle);
		color: var(--color-white);
		background: var(--chat-preview-brand);
		box-shadow:
			0 8px 20px color-mix(in srgb, var(--chat-preview-brand) 35%, transparent),
			0 2px 4px rgb(0 0 0 / 10%);
		font-size: var(--typography--fontSize-large);
		font-weight: 600;
		cursor: pointer;

		&:hover {
			filter: brightness(1.05);
		}

		&:active {
			filter: brightness(0.95);
		}

		&:focus-visible {
			outline: transparent;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.chat-preview__launcher--open {
		width: 48px;
		justify-content: center;
		padding: 0;
	}

	@media (max-width: 639px) {
		.chat-preview__header {
			align-items: stretch;
			flex-direction: column;
		}

		.chat-preview__viewport {
			padding: var(--space-small);
		}

		.chat-preview__panel {
			width: min(320px, calc(100vw - 80px));
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.chat-preview__browser {
			transition: none;
		}
	}
</style>
