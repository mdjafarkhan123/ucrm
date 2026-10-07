<script lang="ts">
	import { resolve } from '$app/paths';
	import JafarAuthCard from '$lib/components/jafar/JafarAuthCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';

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
			errorMessage = 'We could not reach the sign-in service. Check your connection and try again.';
		} finally {
			isSubmitting = false;
		}
	}
</script>

<svelte:head><title>Sign in · Uplift team</title></svelte:head>

<JafarAuthCard
	eyebrow="Uplift team"
	title="Sign in to the control room"
	intro="Run Uplift's business and the platform from this private workspace."
	titleId="jafar-login-title"
>
	<form
		onsubmit={(event) => {
			event.preventDefault();
			void submit();
		}}
	>
		<Input
			id="jafar-login-email"
			label="Email"
			type="email"
			bind:value={email}
			autocomplete="username"
			required
			invalid={Boolean(fieldErrors.email)}
			errorMessage={fieldErrors.email}
		/>
		<Input
			id="jafar-login-password"
			label="Password"
			type="password"
			bind:value={password}
			autocomplete="current-password"
			required
			invalid={Boolean(fieldErrors.password)}
			errorMessage={fieldErrors.password}
		/>
		<a class="jafar-login__forgot" href={resolve('/jafar/forgot-password')}>Forgot password?</a>

		{#if errorMessage}<p class="jafar-login__error" role="alert">{errorMessage}</p>{/if}
		<Button type="submit" size="large" fullWidth loading={isSubmitting}>
			{isSubmitting ? 'Signing in…' : 'Sign in securely'}
		</Button>
	</form>
</JafarAuthCard>

<style lang="scss">
	.jafar-login__forgot {
		justify-self: end;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}

		&:focus-visible {
			outline: 2px solid var(--color-focus);
			outline-offset: 2px;
			border-radius: var(--radius-small);
		}
	}

	.jafar-login__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
