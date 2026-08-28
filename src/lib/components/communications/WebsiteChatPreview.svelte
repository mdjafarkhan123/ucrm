<script lang="ts">
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import messageCircleIcon from '@tabler/icons/outline/message-circle.svg?raw';

	type ChannelOption = {
		type: 'whatsapp' | 'messenger';
		destination: string;
	};

	let {
		businessName,
		brandColor = null,
		launcherPosition,
		teaserText,
		greetingText,
		contactRequirement,
		privacyPolicyUrl,
		channelOptions = []
	}: {
		businessName: string;
		brandColor?: string | null;
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

	const displayName = $derived(businessName.trim() || 'Your business');
	const displayGreeting = $derived(greetingText.trim() || 'How can we help?');
	const displayTeaser = $derived(
		teaserText.trim() || 'Hi there. Have a question? Message us here.'
	);
	const identityHint = $derived(
		contactRequirement === 'phone'
			? 'Phone required'
			: contactRequirement === 'email'
				? 'Email required'
				: 'Phone or email required'
	);
</script>

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
							<header class="chat-preview__panel-header">
								<div class="chat-preview__avatar" aria-hidden="true">
									{@html messageCircleIcon}
								</div>
								<div>
									<strong>{displayName}</strong>
									<span>Leave a message anytime</span>
								</div>
								<button
									type="button"
									aria-label="Collapse preview"
									onclick={() => (panelOpen = false)}
								>
									{@html chevronDownIcon}
								</button>
							</header>

							<div class="chat-preview__panel-body">
								<h4>{displayGreeting}</h4>
								<p>Tell us how we can help and our team will follow up.</p>

								{#if channelOptions.length}
									<div class="chat-preview__channels" aria-label="Configured contact options">
										<span>Website Chat</span>
										{#each channelOptions as option (option.type)}
											<span>{option.type === 'whatsapp' ? 'WhatsApp' : 'Messenger'}</span>
										{/each}
									</div>
								{/if}

								<div class="chat-preview__field"><span>Name</span></div>
								<div class="chat-preview__field"><span>Phone or email</span></div>
								<div class="chat-preview__field chat-preview__field--message">
									<span>Message</span>
								</div>
								<small>{identityHint}</small>
								<span class="chat-preview__send">Start conversation</span>
								{#if privacyPolicyUrl.trim()}
									<small>By chatting, the customer agrees to your privacy policy.</small>
								{/if}
							</div>

							<footer>Powered by <strong>{displayName}</strong></footer>
						</article>
					{:else}
						<div class="chat-preview__teaser">
							<span>{displayTeaser}</span>
							<button type="button" aria-label="Dismiss preview teaser">×</button>
						</div>
					{/if}

					<button
						type="button"
						class="chat-preview__launcher"
						aria-label={panelOpen ? 'Collapse preview' : 'Open preview'}
						onclick={() => (panelOpen = !panelOpen)}
					>
						{@html panelOpen ? chevronDownIcon : messageCircleIcon}
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
		min-height: 520px;
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
		min-height: 486px;
		background:
			linear-gradient(var(--color-border), var(--color-border)) var(--space-large)
				var(--space-large) / 42% var(--space-small) no-repeat,
			linear-gradient(var(--color-border), var(--color-border)) var(--space-large)
				calc(var(--space-large) + var(--space-large)) / 64% var(--space-small) no-repeat,
			var(--color-surface--background--subtle);
	}

	.chat-preview__widget {
		position: absolute;
		right: var(--space-base);
		bottom: var(--space-base);
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-small);
	}
	.chat-preview__widget--left {
		right: auto;
		left: var(--space-base);
		align-items: flex-start;
	}

	.chat-preview__panel {
		width: min(330px, calc(100vw - 96px));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
	}

	.chat-preview__panel-header {
		display: grid;
		grid-template-columns: auto 1fr auto;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-slim);
		color: var(--color-surface);
		background: var(--chat-preview-brand);

		strong,
		span {
			display: block;
		}

		span {
			margin-top: var(--space-smallest);
			font-size: var(--typography--fontSize-small);
		}

		button {
			display: grid;
			width: var(--space-larger);
			height: var(--space-larger);
			place-items: center;
			border: 0;
			border-radius: var(--radius-small);
			color: inherit;
			background: transparent;
			cursor: pointer;

			&:hover {
				background: var(--color-overlay--dimmed);
			}

			&:focus-visible {
				outline: transparent;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}
	}

	.chat-preview__avatar {
		display: grid;
		width: 36px;
		height: 36px;
		place-items: center;
		border-radius: var(--radius-circle);
		color: var(--chat-preview-brand);
		background: var(--color-surface);

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.chat-preview__panel-body {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);

		h4 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
		}

		p,
		small {
			margin: 0;
			color: var(--color-text--secondary);
		}

		small {
			font-size: var(--typography--fontSize-small);
		}
	}

	.chat-preview__channels {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-smaller);

		span {
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.chat-preview__field {
		display: flex;
		min-height: 40px;
		align-items: center;
		padding: 0 var(--space-slim);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-small);
	}
	.chat-preview__field--message {
		min-height: 64px;
		align-items: flex-start;
		padding-top: var(--space-slim);
	}

	.chat-preview__send {
		display: grid;
		min-height: 40px;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-surface);
		background: var(--chat-preview-brand);
		font-weight: 600;
	}

	.chat-preview__panel footer {
		padding: var(--space-small) var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}

	.chat-preview__teaser {
		display: flex;
		max-width: 280px;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-slim);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);

		button {
			padding: 0;
			border: 0;
			color: var(--color-text--secondary);
			background: transparent;
			font-size: var(--typography--fontSize-large);
			cursor: default;
		}
	}

	.chat-preview__launcher {
		display: grid;
		width: var(--space-largest);
		height: var(--space-largest);
		place-items: center;
		border: 0;
		border-radius: var(--radius-circle);
		color: var(--color-surface);
		background: var(--chat-preview-brand);
		box-shadow: var(--shadow-base);
		cursor: pointer;

		&:hover {
			filter: brightness(0.94);
		}

		&:focus-visible {
			outline: transparent;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			width: 22px;
			height: 22px;
		}
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
			width: min(310px, calc(100vw - 80px));
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.chat-preview__browser {
			transition: none;
		}
	}
</style>
