<script lang="ts">
	import { resolve } from '$app/paths';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	type OwnerSettings = {
		privacy_policy_url: string;
		privacy_policy_version: string;
		payment_instructions: string;
		sender_display_name: string;
		reply_to_address: string;
		alert_recipient_emails: string[];
		updated_at: string;
	};
	type SettingsResponse = { settings: OwnerSettings; error?: string };
	type MutationResponse = {
		settings?: OwnerSettings;
		error?: string;
		field_errors?: Record<string, string>;
	};
	type SettingsDraft = Omit<OwnerSettings, 'updated_at'>;

	let initialized = $state(false);
	let privacyPolicyUrl = $state('');
	let privacyPolicyVersion = $state('');
	let paymentInstructions = $state('');
	let senderDisplayName = $state('');
	let replyToAddress = $state('');
	let alertRecipientEmails = $state<string[]>([]);
	let savedDraft = $state<SettingsDraft | null>(null);
	let actionError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let isDirty = $derived(
		savedDraft !== null && JSON.stringify(savedDraft) !== JSON.stringify(getDraft())
	);

	function getDraft(): SettingsDraft {
		return {
			privacy_policy_url: privacyPolicyUrl,
			privacy_policy_version: privacyPolicyVersion,
			payment_instructions: paymentInstructions,
			sender_display_name: senderDisplayName,
			reply_to_address: replyToAddress,
			alert_recipient_emails: alertRecipientEmails.map((email) => email.trim()).filter(Boolean)
		};
	}

	function draftFromSettings(data: OwnerSettings): SettingsDraft {
		return {
			privacy_policy_url: data.privacy_policy_url,
			privacy_policy_version: data.privacy_policy_version,
			payment_instructions: data.payment_instructions,
			sender_display_name: data.sender_display_name,
			reply_to_address: data.reply_to_address,
			alert_recipient_emails: data.alert_recipient_emails
		};
	}

	const settings = createQuery<SettingsResponse>(() => ({
		queryKey: ['jafar', 'settings'],
		queryFn: async () => {
			const response = await fetch('/api/jafar/settings');
			const result = (await response.json()) as SettingsResponse;
			if (!response.ok) throw new Error(result.error ?? 'Settings could not be loaded.');
			return result;
		}
	}));

	$effect(() => {
		const data = settings.data?.settings;
		if (data && !initialized) {
			privacyPolicyUrl = data.privacy_policy_url;
			privacyPolicyVersion = data.privacy_policy_version;
			paymentInstructions = data.payment_instructions;
			senderDisplayName = data.sender_display_name;
			replyToAddress = data.reply_to_address;
			alertRecipientEmails = data.alert_recipient_emails.length
				? [...data.alert_recipient_emails]
				: [''];
			savedDraft = draftFromSettings(data);
			initialized = true;
		}
	});

	const save = createMutation<MutationResponse, Error, void>(() => ({
		mutationFn: async () => {
			const response = await fetch('/api/jafar/settings', {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					privacy_policy_url: privacyPolicyUrl,
					privacy_policy_version: privacyPolicyVersion,
					payment_instructions: paymentInstructions,
					sender_display_name: senderDisplayName,
					reply_to_address: replyToAddress,
					alert_recipient_emails: alertRecipientEmails.map((email) => email.trim()).filter(Boolean)
				})
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'Settings could not be saved.');
			}
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: (result) => {
			toast.success('Settings saved.');
			savedDraft = result.settings ? draftFromSettings(result.settings) : getDraft();
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'settings'] });
		}
	}));

	function clearFeedback() {
		actionError = '';
		fieldErrors = {};
	}

	function addAlertRecipient() {
		alertRecipientEmails = [...alertRecipientEmails, ''];
	}

	function removeAlertRecipient(index: number) {
		alertRecipientEmails = alertRecipientEmails.filter((_, current) => current !== index);
	}

	function formatDate(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}
</script>

<svelte:head><title>Settings · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="owner-settings">
	<header class="owner-settings__header">
		<div>
			<p class="owner-settings__eyebrow">Platform configuration</p>
			<h1>Settings</h1>
			<p class="owner-settings__description">
				The payment instructions, privacy-policy link, and email details shown to prospects and used
				for owner alerts.
			</p>
		</div>
	</header>

	{#if actionError}<p class="owner-settings__feedback owner-settings__feedback--error" role="alert">
			{actionError}
		</p>{/if}

	{#if settings.isPending}
		<LoadingSkeleton variant="table" rows={5} label="Loading settings" />
	{:else if settings.isError}
		<ErrorState
			title="Settings could not be loaded"
			description={settings.error.message}
			retry={() => settings.refetch()}
		/>
	{:else}
		<form
			class="owner-settings__form"
			onsubmit={(event) => {
				event.preventDefault();
				save.mutate();
			}}
		>
			<section class="owner-settings__section">
				<h2>Privacy policy</h2>
				<div class="owner-settings__grid">
					<label
						><span>Privacy-policy URL</span><input
							type="url"
							bind:value={privacyPolicyUrl}
							required
							maxlength="500"
						/>{#if fieldErrors.privacy_policy_url}<small class="owner-settings__field-error"
								>{fieldErrors.privacy_policy_url}</small
							>{/if}</label
					>
					<label
						><span>Privacy-policy version</span><input
							bind:value={privacyPolicyVersion}
							required
							maxlength="40"
						/>{#if fieldErrors.privacy_policy_version}<small class="owner-settings__field-error"
								>{fieldErrors.privacy_policy_version}</small
							>{/if}</label
					>
				</div>
			</section>

			<section class="owner-settings__section">
				<h2>Payment instructions</h2>
				<p class="owner-settings__hint">
					Shown on the application-received page and in the receipt email. Do not include the
					package name or price here — those are inserted automatically.
				</p>
				<label class="owner-settings__wide"
					><span>Instructions</span><textarea
						bind:value={paymentInstructions}
						required
						maxlength="5000"></textarea>{#if fieldErrors.payment_instructions}<small
							class="owner-settings__field-error">{fieldErrors.payment_instructions}</small
						>{/if}</label
				>
			</section>

			<section class="owner-settings__section">
				<h2>Outgoing email</h2>
				<div class="owner-settings__grid">
					<label
						><span>Sender display name</span><input
							bind:value={senderDisplayName}
							required
							maxlength="200"
						/>{#if fieldErrors.sender_display_name}<small class="owner-settings__field-error"
								>{fieldErrors.sender_display_name}</small
							>{/if}</label
					>
					<label
						><span>Reply-to address</span><input
							type="email"
							bind:value={replyToAddress}
							required
							maxlength="254"
						/>{#if fieldErrors.reply_to_address}<small class="owner-settings__field-error"
								>{fieldErrors.reply_to_address}</small
							>{/if}</label
					>
				</div>
			</section>

			<section class="owner-settings__section">
				<h2>Owner alert recipients</h2>
				<p class="owner-settings__hint">
					These addresses get emailed when a new application arrives or something needs attention.
				</p>
				<div class="owner-settings__recipients">
					{#each alertRecipientEmails as email, index (index)}
						<div class="owner-settings__recipient-row">
							<input
								type="email"
								value={email}
								required
								maxlength="254"
								placeholder="owner@example.com"
								oninput={(event) =>
									(alertRecipientEmails = alertRecipientEmails.map((current, currentIndex) =>
										currentIndex === index ? event.currentTarget.value : current
									))}
							/>
							<Button
								type="button"
								variant="tertiary"
								disabled={alertRecipientEmails.length <= 1}
								onclick={() => removeAlertRecipient(index)}
								><span aria-hidden="true">{@html trashIcon}</span>Remove</Button
							>
						</div>
					{/each}
				</div>
				{#if fieldErrors.alert_recipient_emails}<small class="owner-settings__field-error"
						>{fieldErrors.alert_recipient_emails}</small
					>{/if}
				<Button type="button" variant="tertiary" onclick={addAlertRecipient}>Add email</Button>
			</section>

			<footer class="owner-settings__actions">
				{#if settings.data}<p class="owner-settings__updated">
						Last saved {formatDate(settings.data.settings.updated_at)}
					</p>{/if}
				<Button type="submit" loading={save.isPending} disabled={save.isPending || !isDirty}
					>Save settings</Button
				>
			</footer>
		</form>
	{/if}

	<section class="owner-settings__section">
		<h2>Organization cleanup</h2>
		<p class="owner-settings__hint">
			Organizations currently in their 30-day recovery window after closure, with an option to
			delete one early.
		</p>
		<a class="owner-settings__cleanup-link" href={resolve('/jafar/settings/cleanup')}
			>View cleanup queue <span aria-hidden="true">{@html arrowRightIcon}</span></a
		>
	</section>
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.owner-settings {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}
	.owner-settings__header {
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.owner-settings__eyebrow {
		margin: 0 0 var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h1,
	h2,
	p {
		margin: 0;
	}
	h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}
	h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-tightest);
	}
	.owner-settings__description {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
	}
	.owner-settings__feedback {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
	}
	.owner-settings__feedback--error {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.owner-settings__form {
		display: grid;
		gap: var(--space-large);
	}
	.owner-settings__section {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}
	.owner-settings__hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.owner-settings__grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.owner-settings__wide {
		grid-column: 1 / -1;
	}
	label {
		display: grid;
		gap: var(--space-small);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}
	input,
	textarea {
		width: 100%;
		min-height: 40px;
		box-sizing: border-box;
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: var(--color-surface);
		font: inherit;
	}
	textarea {
		min-height: 120px;
		resize: vertical;
	}
	input:focus-visible,
	textarea:focus-visible {
		outline: none;
		border-color: var(--color-interactive);
		box-shadow: var(--shadow-focus);
	}
	.owner-settings__cleanup-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smallest);
		width: fit-content;
		color: var(--color-interactive);
		font-weight: 600;
		text-decoration: none;
	}
	.owner-settings__cleanup-link:hover {
		text-decoration: underline;
	}
	.owner-settings__cleanup-link :global(svg) {
		width: 16px;
		height: 16px;
	}
	.owner-settings__field-error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}
	.owner-settings__recipients {
		display: grid;
		gap: var(--space-small);
	}
	.owner-settings__recipient-row {
		display: flex;
		gap: var(--space-small);
		align-items: center;
	}
	.owner-settings__recipient-row input {
		flex: 1;
	}
	.owner-settings__recipient-row :global(svg) {
		width: 18px;
		height: 18px;
	}
	.owner-settings__actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		align-items: center;
		gap: var(--space-base);
	}
	.owner-settings__updated {
		margin-right: auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	@media (max-width: 767px) {
		.owner-settings__grid {
			grid-template-columns: 1fr;
		}
		.owner-settings__actions {
			align-items: stretch;
			flex-direction: column;
		}
		.owner-settings__updated {
			margin-right: 0;
		}
	}
</style>
