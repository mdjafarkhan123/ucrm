<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';

	let password = $state('');
	let passwordConfirmation = $state('');
	let errorMessage = $state('');
	let isSubmitting = $state(false);
	let updated = $state(false);

	async function submit() {
		isSubmitting = true;
		errorMessage = '';
		const response = await fetch('/api/auth/password-reset', {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ password, password_confirmation: passwordConfirmation })
		});
		const result: { error?: string } = await response.json().catch(() => ({}));
		isSubmitting = false;
		if (!response.ok) {
			errorMessage = result.error ?? 'We could not update your password.';
			return;
		}
		updated = true;
		setTimeout(() => void goto('/login'), 1200);
	}
</script>

<svelte:head><title>Choose a new password · Contractor CRM</title></svelte:head>

<main class="auth-page">
	<section class="auth-card" aria-labelledby="reset-title">
		<div class="auth-card__eyebrow">Contractor CRM</div>
		<h1 id="reset-title">Choose a new password</h1>
		{#if page.url.searchParams.get('error') === 'invalid-link'}
			<p class="form-error" role="alert">This reset link is invalid or has expired. Request a new one to continue.</p>
		{:else if updated}
			<p class="form-success" role="status">Your password was updated. Returning to sign in…</p>
		{:else}
			<p class="auth-card__intro">Use a strong password you do not reuse elsewhere.</p>
			<form onsubmit={(event) => { event.preventDefault(); void submit(); }}>
				<label for="password">New password</label>
				<input id="password" type="password" bind:value={password} autocomplete="new-password" minlength="8" required />
				<label for="password-confirmation">Confirm new password</label>
				<input id="password-confirmation" type="password" bind:value={passwordConfirmation} autocomplete="new-password" minlength="8" required />
				{#if errorMessage}<p class="form-error" role="alert">{errorMessage}</p>{/if}
				<button type="submit" disabled={isSubmitting}>{isSubmitting ? 'Updating…' : 'Update password'}</button>
			</form>
		{/if}
		<a class="auth-card__link" href="/login">Return to sign in</a>
	</section>
</main>

<style lang="scss">
	.auth-page { min-height: 100vh; display: grid; place-items: center; padding: var(--space-large); background: var(--color-surface--background); }
	.auth-card { width: min(100%, 440px); padding: var(--space-largest); border: var(--border-base) solid var(--color-border); border-radius: var(--radius-base); background: var(--color-surface); box-shadow: var(--shadow-base); }
	.auth-card__eyebrow { margin-bottom: var(--space-small); color: var(--color-interactive); font-size: var(--typography--fontSize-small); font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; }
	h1 { margin-bottom: var(--space-small); color: var(--color-heading); font-size: var(--typography--fontSize-jumbo); line-height: var(--typography--lineHeight-minuscule); }
	.auth-card__intro { margin-bottom: var(--space-large); color: var(--color-text--secondary); line-height: var(--typography--lineHeight-large); }
	form { display: grid; gap: var(--space-base); margin-bottom: var(--space-base); }
	label { color: var(--color-heading); font-size: var(--typography--fontSize-base); }
	input { width: 100%; padding: var(--space-small) var(--space-slim); border: var(--border-base) solid var(--color-border--interactive); border-radius: var(--radius-base); color: var(--color-text); background: var(--color-surface); }
	input:focus-visible, button:focus-visible, .auth-card__link:focus-visible { outline: none; box-shadow: var(--shadow-focus); }
	button { padding: var(--space-small) var(--space-base); border: 0; border-radius: var(--radius-base); color: var(--color-surface); background: var(--color-interactive); font-weight: 700; }
	button:hover:not(:disabled) { background: var(--color-interactive--hover); }
	button:disabled { opacity: 0.6; cursor: not-allowed; }
	.form-error { margin-bottom: var(--space-base); color: var(--color-critical); font-size: var(--typography--fontSize-small); }
	.form-success { margin-bottom: var(--space-base); color: var(--color-success); font-size: var(--typography--fontSize-base); }
	.auth-card__link { color: var(--color-interactive); text-decoration: underline; text-underline-offset: var(--space-smaller); }
</style>
