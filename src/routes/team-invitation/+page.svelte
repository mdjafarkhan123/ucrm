<script lang="ts">
	import { page } from '$app/state';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import { onMount } from 'svelte';

	type InspectionState = 'loading' | 'ready' | 'invalid';
	type FieldErrors = Partial<Record<'email' | 'password' | 'password_confirmation', string>>;

	let inspectionState = $state<InspectionState>('loading');
	let emailHint = $state('');
	let companyName = $state('');
	let email = $state('');
	let password = $state('');
	let passwordConfirmation = $state('');
	let fieldErrors = $state<FieldErrors>({});
	let errorMessage = $state('');
	let isSubmitting = $state(false);
	let accepted = $state(false);

	const token = page.url.searchParams.get('token')?.trim() ?? '';

	onMount(() => {
		const controller = new AbortController();

		void fetch(`/api/team/invitations/accept?token=${encodeURIComponent(token)}`, {
			signal: controller.signal,
			cache: 'no-store'
		})
			.then(async (response) => {
				const result: { valid?: boolean; email_hint?: string; company_name?: string } =
					await response.json().catch(() => ({}));
				if (!response.ok || !result.valid || !result.email_hint) {
					inspectionState = 'invalid';
					return;
				}
				emailHint = result.email_hint;
				companyName = result.company_name ?? '';
				inspectionState = 'ready';
			})
			.catch((error: unknown) => {
				if (error instanceof DOMException && error.name === 'AbortError') return;
				inspectionState = 'invalid';
			});

		return () => controller.abort();
	});

	async function acceptInvitation() {
		if (isSubmitting) return;

		isSubmitting = true;
		fieldErrors = {};
		errorMessage = '';

		try {
			const response = await fetch('/api/team/invitations/accept', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					token,
					email,
					password,
					password_confirmation: passwordConfirmation
				})
			});
			const result: { error?: string; field_errors?: FieldErrors } = await response
				.json()
				.catch(() => ({}));

			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				errorMessage = result.error ?? 'We could not set up your account. Please try again.';
				return;
			}

			accepted = true;
			password = '';
			passwordConfirmation = '';
		} catch {
			errorMessage = 'We could not set up your account. Check your connection and try again.';
		} finally {
			isSubmitting = false;
		}
	}
</script>

<svelte:head>
	<title>{accepted ? 'Account ready' : 'Join your team'} · UpliftContractor</title>
	<meta name="robots" content="noindex, nofollow" />
	<meta name="referrer" content="no-referrer" />
</svelte:head>

<main class="invitation-page">
	<section
		class="invitation-card"
		aria-labelledby="invitation-title"
		aria-busy={inspectionState === 'loading'}
	>
		<p class="invitation-card__eyebrow">{companyName || 'UpliftContractor'}</p>

		{#if inspectionState === 'loading'}
			<div class="invitation-card__loading" role="status">
				<span class="invitation-card__spinner" aria-hidden="true"></span>
				<span>Checking your invitation…</span>
			</div>
		{:else if inspectionState === 'invalid'}
			<h1 id="invitation-title">This invitation is no longer available</h1>
			<p class="invitation-card__intro">
				The link may have expired, been cancelled, or been replaced. Ask the person who invited you
				to send a new one.
			</p>
		{:else if accepted}
			<h1 id="invitation-title">Your account is ready</h1>
			<p class="invitation-card__intro">
				Your invitation has been accepted. Sign in with the email and password you just entered.
			</p>
			<Button href="/login" size="large" fullWidth>Sign In</Button>
		{:else}
			<h1 id="invitation-title">Join your team</h1>
			<p class="invitation-card__intro">
				Set up your account using the invited email address ({emailHint}) and choose a password.
			</p>

			<form
				onsubmit={(event) => {
					event.preventDefault();
					void acceptInvitation();
				}}
			>
				<Input
					id="invitation-email"
					label="Email"
					type="email"
					bind:value={email}
					autocomplete="email"
					required
					invalid={Boolean(fieldErrors.email)}
					errorMessage={fieldErrors.email}
				/>
				<Input
					id="invitation-password"
					label="New password"
					type="password"
					bind:value={password}
					autocomplete="new-password"
					minlength="8"
					required
					invalid={Boolean(fieldErrors.password)}
					errorMessage={fieldErrors.password}
				/>
				<Input
					id="invitation-password-confirmation"
					label="Confirm password"
					type="password"
					bind:value={passwordConfirmation}
					autocomplete="new-password"
					minlength="8"
					required
					invalid={Boolean(fieldErrors.password_confirmation)}
					errorMessage={fieldErrors.password_confirmation}
				/>

				{#if errorMessage}<p class="invitation-card__error" role="alert">{errorMessage}</p>{/if}

				<Button type="submit" size="large" fullWidth loading={isSubmitting}>
					{isSubmitting ? 'Setting Up Account…' : 'Set Up Account'}
				</Button>
			</form>
		{/if}
	</section>
</main>

<style lang="scss">
	.invitation-page {
		display: grid;
		place-items: center;
		min-height: 100vh;
		padding: var(--space-large);
		background: var(--color-surface--background);
	}

	.invitation-card {
		display: grid;
		gap: var(--space-base);
		width: min(100%, 440px);
		padding: var(--space-largest);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	.invitation-card__eyebrow {
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}

	.invitation-card__intro {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	.invitation-card__loading {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		min-height: 160px;
		color: var(--color-text);
	}

	.invitation-card__spinner {
		width: var(--space-large);
		height: var(--space-large);
		border: 2px solid var(--color-border);
		border-top-color: var(--color-interactive);
		border-radius: var(--radius-circle);
		animation: spinning var(--timing-loading) linear infinite;
	}

	.invitation-card__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}

	h1 {
		margin: 0;
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}

	form {
		display: grid;
		gap: var(--space-base);
	}

	@media (max-width: 639px) {
		.invitation-page {
			align-items: start;
			padding: var(--space-base);
		}

		.invitation-card {
			margin-top: var(--space-largest);
			padding: var(--space-large);
		}

		h1 {
			font-size: 28px;
		}
	}
</style>
