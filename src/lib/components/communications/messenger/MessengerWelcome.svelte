<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import MessengerMark from './MessengerMark.svelte';
	import loginIcon from '@tabler/icons/outline/login-2.svg?raw';
	import listCheckIcon from '@tabler/icons/outline/list-check.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';

	// A business with no Page sees this in place of the banner and the list (board `tEAXY`, Every state). While
	// Facebook's window is open the button shows its loading look and can't be pressed twice.
	let {
		loggingIn,
		disabled = false,
		onLogin
	}: { loggingIn: boolean; disabled?: boolean; onLogin: () => void } = $props();

	const steps = [
		{
			icon: loginIcon,
			title: 'Log in with Facebook',
			line: 'Facebook opens its own small window.'
		},
		{ icon: listCheckIcon, title: 'Choose your Pages', line: 'Tick one Page or several.' },
		{ icon: sendIcon, title: 'Send yourself a test', line: 'Message the Page and watch it arrive.' }
	];
</script>

<!-- eslint-disable svelte/no-at-html-tags -- trusted build-time Tabler icons -->
<section class="messenger-welcome" aria-labelledby="messenger-welcome-title">
	<div class="messenger-welcome__main">
		<MessengerMark size={72} />
		<h2 id="messenger-welcome-title" class="messenger-welcome__title">
			Answer Facebook messages from Conversations
		</h2>
		<p class="messenger-welcome__text">
			Connect your business's Facebook Page. When a customer messages it, the chat lands in
			Conversations next to texts and emails, under the right client or a new lead.
		</p>
		<div class="messenger-welcome__action">
			<Button size="large" loading={loggingIn} {disabled} onclick={onLogin}>
				<span aria-hidden="true">{@html loginIcon}</span>
				Log in with Facebook
			</Button>
			<span class="messenger-welcome__hint">You need to be an admin of the Page on Facebook.</span>
		</div>
	</div>
	<div class="messenger-welcome__how">
		<h3 class="messenger-welcome__label">How it works · about 2 minutes</h3>
		{#each steps as step (step.title)}
			<div class="messenger-welcome__step">
				<span class="messenger-welcome__step-icon" aria-hidden="true">{@html step.icon}</span>
				<span class="messenger-welcome__step-text">
					<strong>{step.title}</strong>
					<span>{step.line}</span>
				</span>
			</div>
		{/each}
	</div>
</section>

<style lang="scss">
	.messenger-welcome {
		display: flex;
		align-items: center;
		gap: var(--space-larger);
		padding: var(--space-larger);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__main {
			display: grid;
			flex: 1;
			justify-items: start;
			gap: var(--space-base);
			min-width: 0;
		}
		&__title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
			letter-spacing: -0.5px;
			line-height: 1.2;
		}
		&__text {
			max-width: 60ch;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-large);
		}
		&__action {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-base);
			padding-top: var(--space-smaller);
		}
		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}
		&__how {
			display: grid;
			flex: 0 0 380px;
			gap: var(--space-slim);
			padding: var(--space-medium);
			border-radius: var(--radius-large);
			background: var(--color-surface--background--subtle);
		}
		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-overline);
			font-weight: 700;
			letter-spacing: 0.4px;
			text-transform: uppercase;
		}
		&__step {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}
		&__step-icon {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 32px;
			height: 32px;
			border: 1px solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-conversation);
			background: var(--color-surface);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__step-text {
			display: grid;
			gap: 2px;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}
			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}
		}
	}
</style>
