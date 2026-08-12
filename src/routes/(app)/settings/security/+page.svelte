<script lang="ts">
	let currentPassword = $state('');
	let password = $state('');
	let passwordConfirmation = $state('');
	let errorMessage = $state('');
	let successMessage = $state('');
	let isSubmitting = $state(false);

	async function submit() {
		isSubmitting = true;
		errorMessage = '';
		successMessage = '';
		const response = await fetch('/api/auth/password-reset', {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				current_password: currentPassword,
				password,
				password_confirmation: passwordConfirmation
			})
		});
		const result: { error?: string } = await response.json().catch(() => ({}));
		isSubmitting = false;
		if (!response.ok) {
			errorMessage = result.error ?? 'We could not update your password.';
			return;
		}
		currentPassword = '';
		password = '';
		passwordConfirmation = '';
		successMessage = 'Your password was updated.';
	}
</script>

<svelte:head><title>Password and security · Contractor CRM</title></svelte:head>

<section class="security-page" aria-labelledby="security-title">
	<div class="security-page__header">
		<div>
			<p class="security-page__eyebrow">Account settings</p>
			<h1 id="security-title">Password and security</h1>
			<p>Keep your contractor account protected with a unique password.</p>
		</div>
	</div>
	<section class="security-card" aria-labelledby="password-title">
		<h2 id="password-title">Change password</h2>
		<p class="security-card__intro">Confirm your current password, then choose a new one.</p>
		<form onsubmit={(event) => { event.preventDefault(); void submit(); }}>
			<label for="current-password">Current password</label>
			<input id="current-password" type="password" bind:value={currentPassword} autocomplete="current-password" required />
			<label for="new-password">New password</label>
			<input id="new-password" type="password" bind:value={password} autocomplete="new-password" minlength="8" required />
			<label for="new-password-confirmation">Confirm new password</label>
			<input id="new-password-confirmation" type="password" bind:value={passwordConfirmation} autocomplete="new-password" minlength="8" required />
			{#if errorMessage}<p class="form-error" role="alert">{errorMessage}</p>{/if}
			{#if successMessage}<p class="form-success" role="status">{successMessage}</p>{/if}
			<button type="submit" disabled={isSubmitting}>{isSubmitting ? 'Updating…' : 'Update password'}</button>
		</form>
	</section>
</section>

<style lang="scss">
	.security-page { width: min(100%, 720px); }
	.security-page__header { margin-bottom: var(--space-large); }
	.security-page__eyebrow { margin-bottom: var(--space-small); color: var(--color-text--secondary); font-size: var(--typography--fontSize-small); letter-spacing: 0.08em; text-transform: uppercase; }
	h1 { margin-bottom: var(--space-small); color: var(--color-heading); font-size: var(--typography--fontSize-jumbo); line-height: var(--typography--lineHeight-minuscule); }
	.security-page__header > div > p:last-child { color: var(--color-text--secondary); line-height: var(--typography--lineHeight-large); }
	.security-card { width: min(100%, 480px); padding: var(--space-large); border: var(--border-base) solid var(--color-border); border-radius: var(--radius-base); background: var(--color-surface); box-shadow: var(--shadow-low); }
	h2 { margin-bottom: var(--space-small); color: var(--color-heading); font-size: var(--typography--fontSize-larger); }
	.security-card__intro { margin-bottom: var(--space-large); color: var(--color-text--secondary); }
	form { display: grid; gap: var(--space-base); }
	label { color: var(--color-heading); font-size: var(--typography--fontSize-base); }
	input { width: 100%; padding: var(--space-small) var(--space-slim); border: var(--border-base) solid var(--color-border--interactive); border-radius: var(--radius-base); color: var(--color-text); background: var(--color-surface); }
	input:focus-visible, button:focus-visible { outline: none; box-shadow: var(--shadow-focus); }
	button { padding: var(--space-small) var(--space-base); border: 0; border-radius: var(--radius-base); color: var(--color-surface); background: var(--color-interactive); font-weight: 700; }
	button:hover:not(:disabled) { background: var(--color-interactive--hover); }
	button:disabled { opacity: 0.6; cursor: not-allowed; }
	.form-error { color: var(--color-critical); font-size: var(--typography--fontSize-small); }
	.form-success { color: var(--color-success); font-size: var(--typography--fontSize-small); }
</style>
