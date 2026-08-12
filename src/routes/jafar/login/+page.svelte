<script lang="ts">
	import shieldLockIcon from '@tabler/icons/outline/shield-lock.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';

	let email = $state('');
	let password = $state('');
	let errorMessage = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let isSubmitting = $state(false);

	async function submit() {
		isSubmitting = true;
		errorMessage = '';
		fieldErrors = {};

		try {
			const response = await fetch('/api/jafar/session', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ email, password })
			});
			const result = (await response.json()) as {
				error?: string;
				field_errors?: Record<string, string>;
			};

			if (!response.ok) {
				errorMessage = result.error ?? 'We could not sign you in.';
				fieldErrors = result.field_errors ?? {};
				return;
			}

			window.location.assign('/jafar');
		} catch {
			errorMessage = 'We could not reach the platform owner service.';
		} finally {
			isSubmitting = false;
		}
	}
</script>

<svelte:head><title>Platform owner sign in · Contractor CRM</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="owner-auth-page">
	<section class="owner-auth-card" aria-labelledby="owner-login-title">
		<div class="owner-auth-card__eyebrow">
			<span aria-hidden="true">{@html shieldLockIcon}</span>
			Platform owner
		</div>
		<h1 id="owner-login-title">Sign in to the control room</h1>
		<p class="owner-auth-card__intro">
			Manage contractor organizations and platform setup from this private workspace.
		</p>

		<form
			onsubmit={(event) => {
				event.preventDefault();
				void submit();
			}}
		>
			<label for="owner-email">Email</label>
			<input
				id="owner-email"
				class={fieldErrors.email ? 'error' : ''}
				type="email"
				bind:value={email}
				autocomplete="username"
				aria-describedby={fieldErrors.email ? 'owner-email-error' : undefined}
				required
			/>
			{#if fieldErrors.email}<p id="owner-email-error" class="owner-auth-card__field-error">
					{fieldErrors.email}
				</p>{/if}

			<label for="owner-password">Password</label>
			<input
				id="owner-password"
				class={fieldErrors.password ? 'error' : ''}
				type="password"
				bind:value={password}
				autocomplete="current-password"
				aria-describedby={fieldErrors.password ? 'owner-password-error' : undefined}
				required
			/>
			{#if fieldErrors.password}<p id="owner-password-error" class="owner-auth-card__field-error">
					{fieldErrors.password}
				</p>{/if}

			{#if errorMessage}<p class="owner-auth-card__error" role="alert">{errorMessage}</p>{/if}
			<button type="submit" disabled={isSubmitting}>
				<span aria-hidden="true">{@html lockIcon}</span>
				{isSubmitting ? 'Signing in…' : 'Sign in securely'}
			</button>
		</form>
	</section>
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.owner-auth-page {
		min-height: 100vh;
		display: grid;
		place-items: center;
		padding: var(--space-large);
		background:
			radial-gradient(
				circle at 15% 10%,
				var(--color-interactive--background--subtle--hover),
				transparent 30%
			),
			var(--color-surface--background);
	}

	.owner-auth-card {
		width: min(100%, 440px);
		padding: var(--space-largest);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);

		.owner-auth-card__eyebrow {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin-bottom: var(--space-small);
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			letter-spacing: var(--typography--letterSpacing-loose);
			text-transform: uppercase;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		h1 {
			margin-bottom: var(--space-small);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-jumbo);
			line-height: var(--typography--lineHeight-minuscule);
		}

		.owner-auth-card__intro {
			margin-bottom: var(--space-large);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-large);
			line-height: var(--typography--lineHeight-large);
		}

		form {
			display: grid;
			gap: var(--space-small);
		}

		label {
			margin-top: var(--space-small);
			color: var(--color-heading);
			font-weight: 600;
		}

		input {
			width: 100%;
			min-height: 44px;
			padding: var(--space-small) var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text);
			background: var(--color-surface);

			&:focus {
				border-color: var(--color-border--interactive);
			}

			&.error {
				border-color: var(--color-critical);
			}
		}

		button {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			gap: var(--space-small);
			min-height: 44px;
			margin-top: var(--space-base);
			padding: var(--space-small) var(--space-base);
			border: 0;
			border-radius: var(--radius-base);
			color: var(--color-text--reverse);
			background: var(--color-interactive);
			font-weight: 700;
			transition: background var(--timing-quick) ease;

			&:hover:not(:disabled) {
				background: var(--color-interactive--hover);
			}

			&:disabled {
				opacity: 0.6;
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		.owner-auth-card__error,
		.owner-auth-card__field-error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}

	@media (max-width: 639px) {
		.owner-auth-card {
			padding: var(--space-large);

			h1 {
				font-size: 28px;
			}
		}
	}
</style>
