<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import JafarAuthCard from '$lib/components/jafar/JafarAuthCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';

	let { data } = $props();

	type FieldErrors = Partial<Record<'full_name' | 'password' | 'password_confirmation', string>>;

	let fullName = $state('');
	let password = $state('');
	let passwordConfirmation = $state('');
	let fieldErrors = $state<FieldErrors>({});
	let errorMessage = $state('');
	let isSubmitting = $state(false);

	async function join() {
		if (isSubmitting) return;
		isSubmitting = true;
		fieldErrors = {};
		errorMessage = '';

		try {
			const response = await fetch('/api/jafar/account/join', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					token: page.url.searchParams.get('token')?.trim() ?? '',
					full_name: fullName,
					password,
					password_confirmation: passwordConfirmation
				})
			});
			const result: { error?: string; field_errors?: FieldErrors } = await response
				.json()
				.catch(() => ({}));
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				errorMessage = result.error ?? 'Your account could not be set up. Try again.';
				return;
			}
			// Signed in already; the panel opens on this teammate's own first area.
			window.location.assign('/jafar');
		} catch {
			errorMessage = 'Your account could not be set up. Check your connection and try again.';
		} finally {
			isSubmitting = false;
		}
	}
</script>

<svelte:head>
	<title>Join the Uplift team</title>
	<meta name="robots" content="noindex, nofollow" />
	<meta name="referrer" content="no-referrer" />
</svelte:head>

{#if data.invitation}
	<JafarAuthCard
		eyebrow="Uplift team"
		title="Join the Uplift team"
		intro={`You're invited as ${data.invitation.roleLabel}, using ${data.invitation.emailHint}. Add your name and choose a password to sign in.`}
		titleId="jafar-join-title"
	>
		<form
			onsubmit={(event) => {
				event.preventDefault();
				void join();
			}}
		>
			<Input
				id="jafar-join-name"
				label="Your name"
				bind:value={fullName}
				autocomplete="name"
				maxlength="120"
				required
				invalid={Boolean(fieldErrors.full_name)}
				errorMessage={fieldErrors.full_name}
			/>
			<Input
				id="jafar-join-password"
				label="Password (8 characters or more)"
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
				id="jafar-join-password-confirmation"
				label="Confirm password"
				type="password"
				bind:value={passwordConfirmation}
				autocomplete="new-password"
				maxlength="72"
				required
				invalid={Boolean(fieldErrors.password_confirmation)}
				errorMessage={fieldErrors.password_confirmation}
			/>

			{#if errorMessage}<p class="jafar-join__error" role="alert">{errorMessage}</p>{/if}
			<Button type="submit" size="large" fullWidth loading={isSubmitting}>
				{isSubmitting ? 'Setting up…' : 'Join and sign in'}
			</Button>
		</form>
	</JafarAuthCard>
{:else}
	<JafarAuthCard
		eyebrow="Uplift team"
		title="This invitation is no longer available"
		intro="The link may have expired, been used already, or been replaced by a newer one. Ask Jafar to send you a new invitation."
		titleId="jafar-join-title"
	>
		<Button href={resolve('/jafar/login')} variant="secondary" size="large" fullWidth
			>Go to sign in</Button
		>
	</JafarAuthCard>
{/if}

<style lang="scss">
	.jafar-join__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
