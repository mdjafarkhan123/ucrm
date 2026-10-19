<script lang="ts">
	import BusinessSettingsPresentation from '$lib/components/settings/SettingsPresentation.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import shieldIcon from '@tabler/icons/outline/shield-lock.svg?raw';
	import keyIcon from '@tabler/icons/outline/key.svg?raw';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	const toast = getToastManager();

	let currentPassword = $state('');
	let password = $state('');
	let passwordConfirmation = $state('');
	let errorMessage = $state('');
	let isSubmitting = $state(false);

	async function submit() {
		isSubmitting = true;
		errorMessage = '';
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
		toast.success('Password updated.');
	}
</script>

<svelte:head><title>Password and security · Contractor CRM</title></svelte:head>

<BusinessSettingsPresentation
	title="Password and security"
	description="Keep your contractor account protected with a unique password."
	icon={shieldIcon}
>
	<div class="security-page">
		<SectionBlock
			tone="inactive"
			title="Change password"
			icon={keyIcon}
			hint="Confirm your current password, then choose a new one."
		>
			<form
				onsubmit={(event) => {
					event.preventDefault();
					void submit();
				}}
			>
				<label class="security-page__field" for="current-password"
					>Current password<input
						id="current-password"
						type="password"
						bind:value={currentPassword}
						autocomplete="current-password"
						required
					/></label
				>
				<div class="security-page__row">
					<label class="security-page__field" for="new-password"
						>New password<input
							id="new-password"
							type="password"
							bind:value={password}
							autocomplete="new-password"
							minlength="8"
							required
						/></label
					>
					<label class="security-page__field" for="new-password-confirmation"
						>Confirm new password<input
							id="new-password-confirmation"
							type="password"
							bind:value={passwordConfirmation}
							autocomplete="new-password"
							minlength="8"
							required
						/></label
					>
				</div>
				{#if errorMessage}<p class="security-page__error" role="alert">{errorMessage}</p>{/if}
				<div class="security-page__actions">
					<Button type="submit" loading={isSubmitting} disabled={isSubmitting}
						>Update password</Button
					>
				</div>
			</form>
		</SectionBlock>
	</div>
</BusinessSettingsPresentation>

<style lang="scss">
	.security-page {
		max-width: 720px;
		form {
			display: grid;
			gap: 20px;
		}
		&__field {
			display: grid;
			gap: 8px;
			font-size: 13px;
			color: var(--color-heading);
			input {
				width: 100%;
				height: 44px;
				padding: 10px 12px;
				border: 1px solid var(--color-border--interactive);
				border-radius: var(--radius-base);
				color: var(--color-text);
				background: var(--color-surface);
				&:focus-visible {
					outline: 2px solid var(--color-interactive);
					outline-offset: 2px;
				}
			}
		}
		&__row {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: 16px;
		}
		&__actions {
			display: flex;
			justify-content: flex-end;
			border-top: 1px solid var(--color-border);
			padding-top: 16px;
		}
		&__error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
