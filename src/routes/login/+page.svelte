<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';

	let email = $state('');
	let password = $state('');
	let errorMessage = $state('');
	let isSubmitting = $state(false);

	async function submit() {
		isSubmitting = true;
		errorMessage = '';
		const response = await fetch('/api/auth/session', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ email, password })
		});
		const result: { error?: string } = await response.json().catch(() => ({}));
		isSubmitting = false;
		if (!response.ok) {
			errorMessage = result.error ?? 'We could not sign you in. Please try again.';
			return;
		}
		await goto(resolve('/dashboard'));
	}
</script>

<svelte:head><title>Sign in · Contractor CRM</title></svelte:head>

<main class="auth-page">
	<section class="auth-card" aria-labelledby="login-title">
		<div class="auth-card__eyebrow">Contractor CRM</div>
		<h1 id="login-title">Run the work. Grow the business.</h1>
		<p class="auth-card__intro">
			Sign in to manage customers, properties, and incoming work requests.
		</p>
		<form
			onsubmit={(event) => {
				event.preventDefault();
				void submit();
			}}
		>
			<label
				><span>Email</span><input
					type="email"
					bind:value={email}
					autocomplete="email"
					required
				/></label
			>
			<label
				><span>Password</span><input
					type="password"
					bind:value={password}
					autocomplete="current-password"
					required
				/></label
			>
			<a class="auth-card__link" href="/forgot-password">Forgot your password?</a>
			{#if errorMessage}<p class="form-error" role="alert">{errorMessage}</p>{/if}
			<button type="submit" disabled={isSubmitting}
				>{isSubmitting ? 'Signing in…' : 'Sign in'}</button
			>
		</form>
	</section>
</main>

<style lang="scss">
	.auth-page {
		min-height: 100vh;
		display: grid;
		place-items: center;
		padding: var(--space-large);
		background: var(--color-surface--background);
	}
	.auth-card {
		width: min(100%, 440px);
		padding: var(--space-largest);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	.auth-card__eyebrow {
		margin-bottom: var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
	}
	h1 {
		margin-bottom: var(--space-small);
		color: var(--color-heading);
		font-size: clamp(28px, 5vw, 40px);
		line-height: 1.1;
	}
	.auth-card__intro {
		margin-bottom: var(--space-large);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-larger);
	}
	form {
		display: grid;
		gap: var(--space-base);
	}
	label {
		display: grid;
		gap: var(--space-smaller);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}
	input {
		width: 100%;
		padding: 12px 14px;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-small);
		color: var(--color-text);
		background: var(--color-surface);
	}
	button {
		padding: 12px 16px;
		border: 0;
		border-radius: var(--radius-small);
		color: var(--color-text--reverse);
		background: var(--color-interactive);
		font-weight: 700;
	}
	button:hover {
		background: var(--color-interactive--hover);
	}
	button:disabled {
		opacity: 0.6;
	}
	.form-error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.auth-card__link {
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		text-decoration: underline;
		text-underline-offset: var(--space-smaller);
	}
	.auth-card__link:focus-visible { outline: none; box-shadow: var(--shadow-focus); }
</style>
