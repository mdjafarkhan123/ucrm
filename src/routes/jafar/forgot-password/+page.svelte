<script lang="ts">
	import { resolve } from '$app/paths';
	import JafarAuthCard from '$lib/components/jafar/JafarAuthCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';

	let email = $state('');
	let fieldErrors = $state<Partial<Record<'email', string>>>({});
	let errorMessage = $state('');
	let isSubmitting = $state(false);
	let sent = $state(false);

	async function requestLink() {
		if (isSubmitting) return;
		isSubmitting = true;
		fieldErrors = {};
		errorMessage = '';

		try {
			const response = await fetch('/api/jafar/account/password-reset', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ email })
			});
			const result: { error?: string; field_errors?: Partial<Record<'email', string>> } =
				await response.json().catch(() => ({}));
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				errorMessage = result.error ?? 'The reset link could not be sent. Try again.';
				return;
			}
			sent = true;
		} catch {
			errorMessage = 'The reset link could not be sent. Check your connection and try again.';
		} finally {
			isSubmitting = false;
		}
	}
</script>

<svelte:head>
	<title>Reset your password · Uplift team</title>
	<meta name="robots" content="noindex, nofollow" />
</svelte:head>

{#if sent}
	<JafarAuthCard
		eyebrow="Uplift team"
		title="Check your email"
		intro={`If ${email.trim()} belongs to an Uplift teammate, a link to choose a new password is on its way. It works once and expires in one hour.`}
		titleId="jafar-forgot-title"
	>
		<Button href={resolve('/jafar/login')} variant="secondary" size="large" fullWidth
			>Back to sign in</Button
		>
	</JafarAuthCard>
{:else}
	<JafarAuthCard
		eyebrow="Uplift team"
		title="Forgot your password?"
		intro="Enter the email you sign in with and we'll send you a link to choose a new password."
		titleId="jafar-forgot-title"
	>
		<form
			onsubmit={(event) => {
				event.preventDefault();
				void requestLink();
			}}
		>
			<Input
				id="jafar-forgot-email"
				label="Email"
				type="email"
				bind:value={email}
				autocomplete="username"
				required
				invalid={Boolean(fieldErrors.email)}
				errorMessage={fieldErrors.email}
			/>
			{#if errorMessage}<p class="jafar-forgot__error" role="alert">{errorMessage}</p>{/if}
			<Button type="submit" size="large" fullWidth loading={isSubmitting}>
				{isSubmitting ? 'Sending…' : 'Send reset link'}
			</Button>
			<Button href={resolve('/jafar/login')} variant="tertiary" fullWidth>Back to sign in</Button>
		</form>
	</JafarAuthCard>
{/if}

<style lang="scss">
	.jafar-forgot__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
