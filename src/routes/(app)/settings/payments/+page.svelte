<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { relativeTime, exactTime } from '$lib/collaboration/format';
	import {
		checkStripeConnection,
		connectStripe,
		disconnectStripe,
		fetchSettingsPayments,
		isSaveConflict,
		savePaymentSettings,
		settingsHomeKey,
		settingsPaymentsKey,
		type PaymentSettings,
		type SettingsPayments,
		type StripeCheckStatus,
		type StripeConnectError,
		type StripeConnectionStatus
	} from '$lib/settings/api';
	import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import stripeIcon from '@tabler/icons/outline/brand-stripe.svg?raw';
	import settingsIcon from '@tabler/icons/outline/adjustments-horizontal.svg?raw';
	import keyIcon from '@tabler/icons/outline/key.svg?raw';
	import lifebuoyIcon from '@tabler/icons/outline/lifebuoy.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import plugOffIcon from '@tabler/icons/outline/plug-connected-x.svg?raw';

	type Toggles = Omit<PaymentSettings, 'revision'>;

	// The restricted key's permissions, exactly as Stripe's "Create restricted API key" screen names them
	// (checked 2026-09-18). Everything not listed stays "None".
	const KEY_PERMISSIONS = [
		{ resource: 'Charges and Refunds', access: 'Write', why: 'records payments and sends refunds' },
		{ resource: 'Payment Intents', access: 'Read', why: 'confirms a payment went through' },
		{
			resource: 'Checkout Sessions',
			access: 'Write',
			why: 'opens Stripe’s secure payment page'
		},
		{
			resource: 'Accounts (in the Connect section)',
			access: 'Read',
			why: 'shows your Stripe business name here'
		},
		{
			resource: 'Webhook Endpoints, Event Destinations',
			access: 'Write',
			why: 'lets Stripe tell UCRM when you’re paid'
		}
	] as const;

	const CHECK_PROBLEMS: Record<Exclude<StripeCheckStatus, 'ok'>, string> = {
		key_rejected:
			'Stripe no longer accepts the saved key. It may have been deleted or rolled in Stripe. Replace the key to reconnect.',
		permission_missing:
			'The saved key is missing a permission UCRM needs. Edit the key in Stripe to match the list, or replace it.',
		account_unavailable: 'Stripe could not be reached at the last check. Try checking again.',
		webhook_missing:
			'The link that tells UCRM about payments was removed in Stripe. Replace the key to set it up again.'
	};

	const TOGGLES: Array<{ key: keyof Toggles; label: string; description: string }> = [
		{
			key: 'online_invoice_payments_enabled',
			label: 'Accept online payments on invoices',
			description: 'Customers see a Pay button on invoices you send them.'
		},
		{
			key: 'online_deposit_payments_enabled',
			label: 'Accept online quote deposits',
			description: 'Customers can pay the required deposit right after approving a quote.'
		},
		{
			key: 'online_tips_enabled',
			label: 'Allow tips',
			description:
				'Customers can add 10%, 15%, 20% or a custom tip. Tips never change the invoice total.'
		},
		{
			key: 'online_receipt_email_enabled',
			label: 'Email a receipt automatically',
			description: 'Customers get a receipt by email after they pay online.'
		}
	];

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsPaymentsKey,
		queryFn: fetchSettingsPayments
	}));

	let toggles = $state<Toggles | null>(null);
	let savedToggles = $state<Toggles | null>(null);
	let saving = $state(false);
	let errorMessage = $state('');
	let conflict = $state<{ editor_name: string | null } | null>(null);
	let layout = $state<RecordFormLayout>();

	let apiKey = $state('');
	let keyError = $state('');
	let connecting = $state(false);
	let replacing = $state(false);
	let checking = $state(false);
	let confirmDisconnect = $state(false);
	let disconnecting = $state(false);

	const saveError = $derived(
		conflict
			? `${conflict.editor_name ?? 'Someone else'} just changed these settings. Refresh the page to see their version before saving yours.`
			: errorMessage
	);

	function pick(settings: PaymentSettings): Toggles {
		return {
			online_invoice_payments_enabled: settings.online_invoice_payments_enabled,
			online_deposit_payments_enabled: settings.online_deposit_payments_enabled,
			online_tips_enabled: settings.online_tips_enabled,
			online_receipt_email_enabled: settings.online_receipt_email_enabled
		};
	}

	$effect(() => {
		const settings = query.data?.settings;
		if (!settings) return;
		untrack(() => {
			if (toggles !== null) return;
			toggles = pick(settings);
			savedToggles = pick(settings);
		});
	});

	const dirty = $derived(
		toggles !== null &&
			savedToggles !== null &&
			TOGGLES.some(({ key }) => toggles![key] !== savedToggles![key])
	);

	beforeNavigate((navigation) => {
		if (!dirty) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});
	$effect(() => {
		function handler(event: BeforeUnloadEvent) {
			if (!dirty) return;
			event.preventDefault();
		}
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	function cancel() {
		toggles = savedToggles ? { ...savedToggles } : null;
		conflict = null;
		errorMessage = '';
	}

	async function save() {
		if (!query.data || !toggles) return;
		saving = true;
		errorMessage = '';
		conflict = null;

		const result = await savePaymentSettings({
			expected_revision: query.data.settings.revision,
			...toggles
		}).catch((error: Error) => {
			errorMessage = error.message;
			return null;
		});
		saving = false;
		if (!result) return;
		if (isSaveConflict(result)) {
			conflict = { editor_name: result.editor_name };
			return;
		}

		savedToggles = { ...toggles };
		queryClient.setQueryData<SettingsPayments>(settingsPaymentsKey, (current) =>
			current
				? {
						...current,
						settings: {
							...current.settings,
							...toggles!,
							revision: result.payment_settings_revision
						}
					}
				: current
		);
		toast.success('Payment settings saved.');
	}

	function applyStripe(stripe: StripeConnectionStatus) {
		queryClient.setQueryData<SettingsPayments>(settingsPaymentsKey, (current) =>
			current ? { ...current, stripe } : current
		);
		void queryClient.invalidateQueries({ queryKey: settingsHomeKey });
	}

	async function connect(event: SubmitEvent) {
		event.preventDefault();
		keyError = '';
		if (!/^rk_(test|live)_/.test(apiKey.trim())) {
			keyError = 'Paste a restricted key. It starts with rk_live_ (or rk_test_ for practice mode).';
			return;
		}
		connecting = true;
		try {
			const wasConnected = query.data?.stripe.connected === true;
			const result = await connectStripe(apiKey.trim());
			apiKey = '';
			replacing = false;
			applyStripe(result.stripe);
			toast.success(wasConnected ? 'Stripe key replaced.' : 'Stripe connected.');
		} catch (error) {
			const failure = error as StripeConnectError;
			keyError = failure.fieldErrors?.api_key ?? failure.message;
		} finally {
			connecting = false;
		}
	}

	async function recheck() {
		checking = true;
		try {
			const result = await checkStripeConnection();
			applyStripe(result.stripe);
			if (result.stripe.connected && result.stripe.last_check_status === 'ok') {
				toast.success('Stripe is connected and working.');
			}
		} catch (error) {
			toast.error((error as Error).message);
		} finally {
			checking = false;
		}
	}

	async function disconnect() {
		disconnecting = true;
		try {
			const result = await disconnectStripe();
			applyStripe(result.stripe);
			confirmDisconnect = false;
			replacing = false;
			toast.success('Stripe disconnected. Pay buttons are hidden.');
		} catch (error) {
			toast.error((error as Error).message);
		} finally {
			disconnecting = false;
		}
	}
</script>

<svelte:head><title>Payments · Settings · Contractor CRM</title></svelte:head>

{#snippet keyForm(submitLabel: string)}
	<form class="payments__key-form" onsubmit={connect} novalidate>
		<Input
			id="stripe-api-key"
			label="Stripe restricted key"
			type="password"
			bind:value={apiKey}
			invalid={Boolean(keyError)}
			errorMessage={keyError}
			autocomplete="off"
			spellcheck="false"
			disabled={connecting}
		/>
		<p class="payments__fine-print">
			Paste it here yourself. Never send your key by email, chat or text — not even to us. Once
			saved, it’s locked away and never shown again.
		</p>
		<div class="payments__key-actions">
			<Button type="submit" loading={connecting} disabled={connecting || !apiKey.trim()}
				>{submitLabel}</Button
			>
			{#if replacing}
				<Button
					variant="tertiary"
					disabled={connecting}
					onclick={() => {
						replacing = false;
						apiKey = '';
						keyError = '';
					}}>Cancel</Button
				>
			{/if}
		</div>
	</form>
{/snippet}

{#if query.isPending || (query.isSuccess && toggles === null)}
	<LoadingSkeleton variant="card" rows={3} />
{:else if query.isError}
	<ErrorState description="Payment settings could not be loaded." retry={() => query.refetch()} />
{:else}
	{@const stripe = query.data.stripe}

	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Payments' }]}
	/>

	<RecordFormLayout title="Payments" icon={creditCardIcon} bind:this={layout} error={saveError}>
		{#snippet main()}
			<SectionBlock
				title="Card payments with Stripe"
				icon={stripeIcon}
				hint="Customers pay by card, Apple Pay, Google Pay or bank on Stripe’s secure page. Money goes straight to your own Stripe account — UCRM never holds it."
				level={3}
			>
				{#if stripe.connected}
					<div class="payments__status">
						<div class="payments__status-main">
							<span class="payments__status-name">
								Connected as {stripe.account_name ?? stripe.stripe_account_id}
							</span>
							{#if stripe.livemode}
								<Badge status="success">Live</Badge>
							{:else}
								<Badge status="informative">Test mode</Badge>
							{/if}
						</div>
						<p class="payments__status-meta">
							Key ending {stripe.key_last4} · Last checked
							<time datetime={stripe.last_checked_at} title={exactTime(stripe.last_checked_at)}
								>{relativeTime(stripe.last_checked_at)}</time
							>
						</p>
					</div>

					{#if !stripe.livemode}
						<p class="payments__note payments__note--info" role="status">
							Test mode is for practice. Invoices will say “Test mode — no real money”, and you can
							pay with Stripe’s test card 4242 4242 4242 4242. Replace the key with a live key
							(rk_live_…) when you’re ready to get paid.
						</p>
					{/if}

					{#if stripe.last_check_status !== 'ok'}
						<p class="payments__note payments__note--warning" role="alert">
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							<span class="payments__note-icon" aria-hidden="true">{@html alertIcon}</span>
							{CHECK_PROBLEMS[stripe.last_check_status]}
						</p>
					{/if}

					{#if replacing}
						{@render keyForm('Replace key')}
					{:else}
						<div class="payments__key-actions">
							<Button variant="secondary" onclick={recheck} loading={checking} disabled={checking}
								>Check connection</Button
							>
							<Button variant="secondary" onclick={() => (replacing = true)}>Replace key</Button>
							<Button
								variant="tertiary"
								variation="destructive"
								onclick={() => (confirmDisconnect = true)}>Disconnect</Button
							>
						</div>
					{/if}
				{:else}
					{@render keyForm('Connect Stripe')}
				{/if}
			</SectionBlock>

			{#if toggles}
				{@const current = toggles}
				<SectionBlock
					title="Payment settings"
					icon={settingsIcon}
					hint={stripe.connected
						? 'What customers can do when they pay you online.'
						: 'These apply once Stripe is connected.'}
					form
					level={3}
				>
					{#each TOGGLES as toggle (toggle.key)}
						<Toggle
							id={`payments-${toggle.key}`}
							label={toggle.label}
							description={toggle.description}
							checked={current[toggle.key]}
							labelSide="start"
							onchange={(checked) => (toggles = { ...current, [toggle.key]: checked })}
						/>
					{/each}
					<p class="payments__fine-print">
						Which payment types appear (card, Apple Pay, Google Pay, bank) is chosen inside Stripe
						under Settings → Payment methods.
					</p>
				</SectionBlock>
			{/if}
		{/snippet}

		{#snippet rail()}
			<RailCard title="How to connect" icon={keyIcon}>
				<ol class="payments__steps">
					<li>
						<a
							href="https://dashboard.stripe.com/register"
							target="_blank"
							rel="noopener noreferrer">Create a free Stripe account</a
						>
						and finish Stripe’s identity and bank checks.
					</li>
					<li>
						In Stripe, open
						<a href="https://dashboard.stripe.com/apikeys" target="_blank" rel="noopener noreferrer"
							>API keys</a
						>
						and click <strong>Create restricted key</strong>. Name it <strong>UCRM</strong>.
					</li>
					<li>
						Set only these permissions. Leave everything else as <strong>None</strong>.
						<ul class="payments__permissions">
							{#each KEY_PERMISSIONS as permission (permission.resource)}
								<li>
									<span class="payments__permission-name">{permission.resource}</span>
									<span class="payments__permission-access">{permission.access}</span>
									<span class="payments__permission-why">{permission.why}</span>
								</li>
							{/each}
						</ul>
					</li>
					<li>Click <strong>Create key</strong>, copy the key, and paste it here.</li>
				</ol>
				<p class="payments__fine-print">
					Want to practice first? Switch Stripe to test mode and make the key there (it starts with
					rk_test_).
				</p>
			</RailCard>

			<RailCard title="Stuck? We’ll set it up with you" icon={lifebuoyIcon}>
				<p class="payments__rail-text">
					Contact UCRM support for a free screen-share call and we’ll walk through it together. You
					paste the key yourself — we never ask you to send it.
				</p>
			</RailCard>
		{/snippet}

		{#snippet actions()}
			<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
			<Button
				onclick={() => void save().finally(() => layout?.revealError())}
				disabled={!dirty || saving}
				loading={saving}>Save</Button
			>
		{/snippet}
	</RecordFormLayout>

	<ConfirmDialog
		open={confirmDisconnect}
		title="Disconnect Stripe?"
		icon={plugOffIcon}
		tone="critical"
		destructive
		confirmLabel="Disconnect"
		loading={disconnecting}
		onConfirm={disconnect}
		onClose={() => (confirmDisconnect = false)}
	>
		<p>
			Customers will stop seeing Pay buttons right away. Payments already received stay recorded,
			and your Stripe account itself isn’t changed.
		</p>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.payments {
		&__status {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__status-main {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__status-name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
			overflow-wrap: anywhere;
		}

		&__status-meta,
		&__fine-print,
		&__rail-text {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__rail-text {
			font-size: var(--typography--fontSize-base);
		}

		&__note {
			display: flex;
			gap: var(--space-small);
			align-items: flex-start;
			margin: 0;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			font-size: var(--typography--fontSize-base);

			&--info {
				background: var(--color-informative--surface);
				color: var(--color-informative--onSurface);
			}

			&--warning {
				background: var(--color-warning--surface);
				color: var(--color-warning--onSurface);
			}
		}

		&__note-icon {
			display: inline-flex;
			flex: 0 0 auto;

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}

		&__key-form {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			max-width: 520px;
		}

		&__key-actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__steps {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			margin: 0;
			padding-left: var(--space-large);
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);

			a {
				color: var(--color-interactive);
			}
		}

		&__permissions {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: var(--space-small) 0 0;
			padding: 0;
			list-style: none;

			li {
				display: grid;
				grid-template-columns: 1fr auto;
				gap: 0 var(--space-small);
				padding: var(--space-small);
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-small);
			}
		}

		&__permission-name {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__permission-access {
			color: var(--color-success--onSurface);
			font-weight: 600;
		}

		&__permission-why {
			grid-column: 1 / -1;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
