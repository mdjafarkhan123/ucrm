<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import JafarAuthCard from '$lib/components/jafar/JafarAuthCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';

	type FieldErrors = Partial<Record<'token' | 'password' | 'password_confirmation', string>>;

	let password = $state('');
	let passwordConfirmation = $state('');
	let fieldErrors = $state<FieldErrors>({});
	let errorMessage = $state('');
	let isSubmitting = $state(false);
	let done = $state(false);
	let linkExpired = $state(false);

	async function resetPassword() {
		if (isSubmitting) return;
		isSubmitting = true;
		fieldErrors = {};
		errorMessage = '';

		try {
			const response = await fetch('/api/jafar/account/password-reset/complete', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					token: page.url.searchParams.get('token')?.trim() ?? '',
					password,
					password_confirmation: passwordConfirmation
				})
			});
			const result: { error?: string; field_errors?: FieldErrors } = await response
				.json()
				.catch(() => ({}));
			if (response.status === 410 || result.field_errors?.token) {
				linkExpired = true;
				return;
			}
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				errorMessage = result.error ?? 'Your password could not be changed. Try again.';
				return;
			}
			done = true;
			password = '';
			passwordConfirmation = '';
		} catch {
			errorMessage = 'Your password could not be changed. Check your connection and try again.';
		} finally {
			isSubmitting = false;
		}
	}
</script>

<svelte:head>
	<title>Choose a new password · Uplift team</title>
	<meta name="robots" content="noindex, nofollow" />
	<meta name="referrer" content="no-referrer" />
</svelte:head>

{#if done}
	<JafarAuthCard
		eyebrow="Uplift team"
		title="Your password is changed"
		intro="Sign in with your new password. Anywhere else you were signed in has been signed out."
		titleId="jafar-reset-title"
	>
		<Button href={resolve('/jafar/login')} size="large" fullWidth>Sign in</Button>
	</JafarAuthCard>
{:else if linkExpired}
	<JafarAuthCard
		eyebrow="Uplift team"
		title="This reset link no longer works"
		intro="Reset links work once and expire after one hour. Ask for a new one and use the newest email."
		titleId="jafar-reset-title"
	>
		<Button href={resolve('/jafar/forgot-password')} size="large" fullWidth>Send a new link</Button>
	</JafarAuthCard>
{:else}
	<JafarAuthCard
		eyebrow="Uplift team"
		title="Choose a new password"
		intro="Use 8 characters or more."
		titleId="jafar-reset-title"
	>
		<form
			onsubmit={(event) => {
				event.preventDefault();
				void resetPassword();
			}}
		>
			<Input
				id="jafar-reset-password"
				label="New password"
				type="password"
				bind:value={password}
				autocomplete="new-password"
				minlength="8"
				maxlength="72"
				required
				invalid={Boolean(fieldErrors.password)}
				errorMessage={fieldErrors.password}
			/>
			<Input
				id="jafar-reset-password-confirmation"
				label="Confirm new password"
				type="password"
				bind:value={passwordConfirmation}
				autocomplete="new-password"
				maxlength="72"
				required
				invalid={Boolean(fieldErrors.password_confirmation)}
				errorMessage={fieldErrors.password_confirmation}
			/>
			{#if errorMessage}<p class="jafar-reset__error" role="alert">{errorMessage}</p>{/if}
			<Button type="submit" size="large" fullWidth loading={isSubmitting}>
				{isSubmitting ? 'Saving…' : 'Save new password'}
			</Button>
		</form>
	</JafarAuthCard>
{/if}

<style lang="scss">
	.jafar-reset__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
