<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';

	type LinkStatus = 'checking' | 'invalid' | 'form' | 'success';

	let status = $state<LinkStatus>('checking');
	let emailHint = $state('');
	let email = $state('');
	let password = $state('');
	let passwordConfirmation = $state('');
	let errorMessage = $state('');
	let isSubmitting = $state(false);

	const token = $derived(page.url.searchParams.get('token') ?? '');

	$effect(() => {
		const currentToken = token;
		if (!currentToken) {
			status = 'invalid';
			return;
		}
		status = 'checking';
		fetch(`/api/setup-password?token=${encodeURIComponent(currentToken)}`)
			.then((response) => response.json())
			.then((result: { valid: boolean; email_hint?: string }) => {
				if (!result.valid) {
					status = 'invalid';
					return;
				}
				emailHint = result.email_hint ?? '';
				status = 'form';
			})
			.catch(() => (status = 'invalid'));
	});

	async function submit() {
		isSubmitting = true;
		errorMessage = '';
		const response = await fetch('/api/setup-password', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				token,
				email,
				password,
				password_confirmation: passwordConfirmation
			})
		});
		const result: { error?: string } = await response.json().catch(() => ({}));
		isSubmitting = false;
		if (!response.ok) {
			errorMessage = result.error ?? 'We could not set your password.';
			return;
		}
		status = 'success';
		setTimeout(() => void goto(resolve('/login')), 1500);
	}
</script>

<svelte:head><title>Set up your account · UpliftContractor</title></svelte:head>

<main class="auth-page">
	<section class="auth-card" aria-labelledby="setup-title">
		<div class="auth-card__eyebrow">UpliftContractor</div>
		<h1 id="setup-title">Set up your account</h1>
		{#if status === 'checking'}
			<p class="auth-card__intro">Checking your setup link…</p>
		{:else if status === 'invalid'}
			<p class="form-error" role="alert">
				This setup link is invalid or has expired. Ask the Platform Owner to resend it.
			</p>
		{:else if status === 'success'}
			<p class="form-success" role="status">Your password was set. Taking you to sign in…</p>
		{:else}
			<p class="auth-card__intro">
				Confirm your email{emailHint ? ` (${emailHint})` : ''} and choose a password to activate your
				administrator account.
			</p>
			<form
				onsubmit={(event) => {
					event.preventDefault();
					void submit();
				}}
			>
				<label for="email">Email</label>
				<input id="email" type="email" bind:value={email} autocomplete="email" required />
				<label for="password">Password</label>
				<input
					id="password"
					type="password"
					bind:value={password}
					autocomplete="new-password"
					minlength="8"
					required
				/>
				<label for="password-confirmation">Confirm password</label>
				<input
					id="password-confirmation"
					type="password"
					bind:value={passwordConfirmation}
					autocomplete="new-password"
					minlength="8"
					required
				/>
				{#if errorMessage}<p class="form-error" role="alert">{errorMessage}</p>{/if}
				<button type="submit" disabled={isSubmitting}
					>{isSubmitting ? 'Setting up…' : 'Set password'}</button
				>
			</form>
		{/if}
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
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
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
		font-size: var(--typography--fontSize-jumbo);
		line-height: var(--typography--lineHeight-minuscule);
	}
	.auth-card__intro {
		margin-bottom: var(--space-large);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
	}
	form {
		display: grid;
		gap: var(--space-base);
		margin-bottom: var(--space-base);
	}
	label {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	input {
		width: 100%;
		padding: var(--space-small) var(--space-slim);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: var(--color-surface);
	}
	input:focus-visible,
	button:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	button {
		padding: var(--space-small) var(--space-base);
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-surface);
		background: var(--color-interactive);
		font-weight: 700;
	}
	button:hover:not(:disabled) {
		background: var(--color-interactive--hover);
	}
	button:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}
	.form-error {
		margin-bottom: var(--space-base);
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.form-success {
		margin-bottom: var(--space-base);
		color: var(--color-success);
		font-size: var(--typography--fontSize-base);
	}
</style>
