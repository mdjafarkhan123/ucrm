<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';

	type MarketingDomain = {
		id: string;
		domain_name: string;
		dns_zone: string | null;
		lifecycle_state: string;
		ownership_status: string;
		dkim_status: string;
		spf_status: string;
		provider_verified: boolean;
		provider_authenticated: boolean;
		last_checked_at: string | null;
		verified_at: string | null;
		created_at: string;
		click_domain_status: ClickStatus;
		click_domain_name: string | null;
		click_domain_error: string | null;
		click_domain_checked_at: string | null;
	};
	type ClickStatus = 'not_set_up' | 'waiting_certificate' | 'working' | 'turned_off' | 'problem';
	type ClickAction = 'turn_on' | 'turn_off' | 'remove';
	type ListResponse = {
		domains?: MarketingDomain[];
		suggested_root_domain?: string | null;
		branded_links_configured?: boolean;
		error?: string;
	};
	type ActivationSummary = {
		domain_id: string;
		domain_name: string;
		mail_from_domain: string;
		lifecycle_state: string;
		provider_verified: boolean;
		provider_authenticated: boolean;
		ownership_status: string;
		dkim_status: string;
		spf_status: string;
		records_written: number;
	};
	type ActivationResult = {
		root_domain: string;
		marketing: ActivationSummary;
		replayed?: boolean;
		error?: string;
		field_errors?: Record<string, string>;
	};
	type MutationResponse = { error?: string; field_errors?: Record<string, string> };

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const listKey = $derived(['jafar', 'organizations', organizationId, 'marketing-domains']);
	const listQuery = createQuery<ListResponse>(() => ({
		queryKey: listKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/marketing-domain`
			);
			const result = (await response.json()) as ListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Marketing domains could not be loaded.');
			return result;
		},
		staleTime: 30_000
	}));

	let activateOpen = $state(false);
	let rootDomain = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackError = $state('');
	let feedbackMessage = $state('');
	let activationResult = $state<ActivationResult | null>(null);

	function tone(state: string): 'success' | 'warning' | 'critical' | 'informative' {
		if (state === 'verified') return 'success';
		if (state === 'pending_dns') return 'warning';
		if (state === 'unhealthy') return 'critical';
		return 'informative';
	}

	function statusText(value: string) {
		return value.replaceAll('_', ' ');
	}

	function formatTime(value: string | null) {
		return value
			? new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' })
			: 'Not checked yet';
	}

	async function refreshDomains() {
		await queryClient.invalidateQueries({ queryKey: listKey });
	}

	function openActivate() {
		feedbackError = '';
		feedbackMessage = '';
		fieldErrors = {};
		activationResult = null;
		rootDomain = listQuery.data?.suggested_root_domain ?? '';
		activateOpen = true;
	}

	function closeActivate() {
		if (!activateMutation.isPending) {
			activateOpen = false;
			rootDomain = '';
			fieldErrors = {};
			activationResult = null;
		}
	}

	const activateMutation = createMutation<ActivationResult, Error, void>(() => ({
		mutationFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/marketing-domain/activate`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({
						root_domain: rootDomain.trim().toLowerCase(),
						idempotency_key: crypto.randomUUID()
					})
				}
			);
			const result = (await response.json()) as ActivationResult;
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'Marketing activation could not be completed.');
			}
			return result;
		},
		onMutate: () => {
			fieldErrors = {};
			feedbackError = '';
			activationResult = null;
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async (result) => {
			activationResult = result;
			await refreshDomains();
		}
	}));

	function submitActivation(event: SubmitEvent) {
		event.preventDefault();
		if (!rootDomain.trim()) {
			fieldErrors = { root_domain: 'Enter the root domain, such as yourbusiness.com.' };
			return;
		}
		activateMutation.mutate();
	}

	const recheckMutation = createMutation<MutationResponse, Error, MarketingDomain>(() => ({
		mutationFn: async (domain) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/marketing-domain/${domain.id}/recheck`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ idempotency_key: crypto.randomUUID() })
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The Marketing domain could not be checked.');
			return result;
		},
		onMutate: () => {
			feedbackError = '';
			feedbackMessage = '';
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async (_result, domain) => {
			feedbackMessage = `Checked ${domain.domain_name}.`;
			await refreshDomains();
		}
	}));

	// Branded click links (M6d): campaign links show click.news.<root> instead of Amazon's tracking address.
	const clickLabels: Record<ClickStatus, string> = {
		not_set_up: 'Not set up',
		waiting_certificate: 'Waiting for certificate',
		working: 'Working',
		turned_off: 'Turned off',
		problem: 'Problem'
	};

	function clickTone(status: ClickStatus): 'success' | 'warning' | 'critical' | 'informative' {
		if (status === 'working') return 'success';
		if (status === 'waiting_certificate') return 'warning';
		if (status === 'problem') return 'critical';
		return 'informative';
	}

	function clickDescription(domain: MarketingDomain): string {
		if (!listQuery.data?.branded_links_configured) {
			return "Branded links are not configured on this server. Campaign links use Amazon's address.";
		}
		if (domain.click_domain_error) return domain.click_domain_error;
		switch (domain.click_domain_status) {
			case 'working':
				return 'Campaign links and the open pixel use this address.';
			case 'waiting_certificate':
				return "Amazon is issuing the security certificate. Links use Amazon's address until it is ready — press Check in a few minutes.";
			case 'turned_off':
				return domain.click_domain_name
					? "Turned off. Campaign links use Amazon's address; turning on again is instant."
					: "Turned off. Campaign links use Amazon's address.";
			case 'problem':
				return "Campaign links use Amazon's address until this is fixed.";
			default:
				return domain.lifecycle_state === 'verified'
					? 'Press Check to set up branded links.'
					: 'Sets up automatically once the Marketing domain is verified.';
		}
	}

	let pendingRemoval = $state<MarketingDomain | null>(null);

	const clickMutation = createMutation<
		MutationResponse,
		Error,
		{ domain: MarketingDomain; action: ClickAction }
	>(() => ({
		mutationFn: async ({ domain, action }) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/marketing-domain/${domain.id}/click-domain`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ action, idempotency_key: crypto.randomUUID() })
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'Branded links could not be changed.');
			return result;
		},
		onMutate: () => {
			feedbackError = '';
			feedbackMessage = '';
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async (_result, { action }) => {
			feedbackMessage =
				action === 'turn_on'
					? 'Branded links turned on.'
					: action === 'turn_off'
						? 'Branded links turned off.'
						: 'Branded links removed.';
			pendingRemoval = null;
			await refreshDomains();
		}
	}));

	function isChanging(domain: MarketingDomain, action: ClickAction) {
		return (
			clickMutation.isPending &&
			clickMutation.variables?.domain.id === domain.id &&
			clickMutation.variables?.action === action
		);
	}
</script>

<div class="marketing-domain-actions">
	<div class="marketing-domain-actions__heading">
		<div>
			<h3>Marketing domain</h3>
			<p>The domain campaign emails send from, separate from operational quotes and invoices.</p>
		</div>
		{#if (listQuery.data?.domains ?? []).length === 0}
			<Button onclick={openActivate}>Activate Marketing</Button>
		{/if}
	</div>

	{#if feedbackMessage}<p class="marketing-domain-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="marketing-domain-actions__error" role="alert">
			{feedbackError}
		</p>{/if}

	{#if listQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading Marketing domain" />
	{:else if listQuery.isError}
		<ErrorState
			title="Marketing domain could not be loaded"
			description={listQuery.error instanceof Error
				? listQuery.error.message
				: 'Marketing domain could not be loaded. Try again.'}
			retry={() => listQuery.refetch()}
		/>
	{:else if (listQuery.data?.domains ?? []).length === 0}
		<p class="marketing-domain-actions__empty">
			No Marketing sending domain is set up for this organization yet.
		</p>
	{:else}
		{#each listQuery.data?.domains ?? [] as domain (domain.id)}
			{@const configured = Boolean(listQuery.data?.branded_links_configured)}
			{@const clickOn =
				domain.click_domain_status === 'working' ||
				domain.click_domain_status === 'waiting_certificate' ||
				domain.click_domain_status === 'problem'}
			<div class="marketing-domain-actions__card">
				<div class="marketing-domain-actions__card-main">
					<strong>{domain.domain_name}</strong>
					<small
						>{domain.provider_authenticated ? 'Authenticated' : 'Pending'} · DKIM {statusText(
							domain.dkim_status
						)} · SPF {statusText(domain.spf_status)}</small
					>
					<small>Last checked {formatTime(domain.last_checked_at)}</small>
				</div>
				<div class="marketing-domain-actions__card-status">
					<Badge status={tone(domain.lifecycle_state)}>{statusText(domain.lifecycle_state)}</Badge>
					<Button
						size="small"
						variant="secondary"
						variation="subtle"
						loading={recheckMutation.isPending}
						onclick={() => recheckMutation.mutate(domain)}>Check</Button
					>
				</div>
				<div class="marketing-domain-actions__links">
					<div class="marketing-domain-actions__card-main">
						<strong
							>Branded links{domain.click_domain_name
								? ` — ${domain.click_domain_name}`
								: ''}</strong
						>
						<small>{clickDescription(domain)}</small>
					</div>
					<div class="marketing-domain-actions__card-status">
						<Badge status={clickTone(domain.click_domain_status)}
							>{clickLabels[domain.click_domain_status]}</Badge
						>
						{#if configured && clickOn}
							<Button
								size="small"
								variant="secondary"
								variation="subtle"
								loading={isChanging(domain, 'turn_off')}
								disabled={clickMutation.isPending}
								onclick={() => clickMutation.mutate({ domain, action: 'turn_off' })}
								>Turn off</Button
							>
						{:else if configured && domain.lifecycle_state === 'verified'}
							<Button
								size="small"
								variant="secondary"
								variation="subtle"
								loading={isChanging(domain, 'turn_on')}
								disabled={clickMutation.isPending}
								onclick={() => clickMutation.mutate({ domain, action: 'turn_on' })}>Turn on</Button
							>
						{/if}
						{#if domain.click_domain_name}
							<Button
								size="small"
								variant="secondary"
								variation="destructive"
								disabled={clickMutation.isPending}
								onclick={() => (pendingRemoval = domain)}>Remove</Button
							>
						{/if}
					</div>
				</div>
			</div>
		{/each}
	{/if}
</div>

<ConfirmDialog
	open={Boolean(pendingRemoval)}
	title="Remove branded links"
	tone="critical"
	confirmLabel="Remove branded links"
	destructive
	loading={clickMutation.isPending}
	onConfirm={() => {
		if (pendingRemoval) clickMutation.mutate({ domain: pendingRemoval, action: 'remove' });
	}}
	onClose={() => {
		if (!clickMutation.isPending) pendingRemoval = null;
	}}
>
	<p>
		Campaign links go back to Amazon's address right away, and
		<strong>{pendingRemoval?.click_domain_name}</strong> is deleted along with its certificate and DNS
		record. Turning branded links on again later takes a few minutes while Amazon issues a new certificate.
	</p>
</ConfirmDialog>

<Dialog open={activateOpen} title="Activate Marketing" onClose={closeActivate}>
	{#if activationResult}
		{@const result = activationResult}
		<div class="marketing-domain-actions__activation">
			<p class="marketing-domain-actions__activation-lead">
				{result.replayed
					? `Marketing was already activated for ${result.root_domain}. Here is its current state.`
					: `Marketing is set up for ${result.root_domain}. UCRM created ${result.marketing.domain_name} for campaign sending.`}
			</p>
			<ul class="marketing-domain-actions__readiness">
				<li>
					<div class="marketing-domain-actions__readiness-label">
						<strong>Sending — {result.marketing.domain_name}</strong>
						<small
							>{result.marketing.provider_authenticated ? 'Authenticated' : 'Pending'} · DKIM {statusText(
								result.marketing.dkim_status
							)} · SPF {statusText(result.marketing.spf_status)}</small
						>
					</div>
					<Badge status={tone(result.marketing.lifecycle_state)}
						>{statusText(result.marketing.lifecycle_state)}</Badge
					>
				</li>
			</ul>
			<p class="marketing-domain-actions__activation-note">
				DNS was written automatically — {result.marketing.records_written} record(s) written. If it shows
				"pending dns", use Check again in a minute.
			</p>
			<div class="marketing-domain-actions__dialog-actions">
				<Button type="button" onclick={closeActivate}>Done</Button>
			</div>
		</div>
	{:else}
		<form class="marketing-domain-actions__form" onsubmit={submitActivation}>
			<p>
				Enter the contractor's root domain, such as <strong>yourbusiness.com</strong>. UCRM sets up
				<strong>news.</strong> for campaign sending and writes the DNS through Cloudflare automatically
				— nothing to copy or paste.
			</p>
			<Input
				id="activate-marketing-root-domain"
				label="Root domain"
				placeholder="yourbusiness.com"
				bind:value={rootDomain}
				invalid={Boolean(fieldErrors.root_domain)}
				errorMessage={fieldErrors.root_domain}
			/>
			{#if feedbackError}<p class="marketing-domain-actions__error" role="alert">
					{feedbackError}
				</p>{/if}
			<div class="marketing-domain-actions__dialog-actions">
				<Button type="submit" loading={activateMutation.isPending}>Activate Marketing</Button
				><Button type="button" variant="secondary" variation="subtle" onclick={closeActivate}
					>Cancel</Button
				>
			</div>
		</form>
	{/if}
</Dialog>

<style lang="scss">
	.marketing-domain-actions,
	.marketing-domain-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.marketing-domain-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.marketing-domain-actions__heading h3 {
		font-size: var(--typography--fontSize-large);
	}
	.marketing-domain-actions__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.marketing-domain-actions__form > p {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.marketing-domain-actions__success {
		color: var(--color-success--onSurface);
	}
	.marketing-domain-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.marketing-domain-actions__empty {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.marketing-domain-actions__card {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.marketing-domain-actions__links {
		display: flex;
		flex-basis: 100%;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding-top: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
	}
	.marketing-domain-actions__card-main {
		display: grid;
		gap: var(--space-smallest);
	}
	.marketing-domain-actions__card-main strong {
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
	}
	.marketing-domain-actions__card-main small {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.marketing-domain-actions__card-status {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.marketing-domain-actions__activation {
		display: grid;
		gap: var(--space-base);
	}
	.marketing-domain-actions__activation-lead {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.marketing-domain-actions__activation-note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}
	.marketing-domain-actions__readiness {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.marketing-domain-actions__readiness li {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.marketing-domain-actions__readiness-label {
		display: grid;
		gap: var(--space-smallest);
	}
	.marketing-domain-actions__readiness-label strong {
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
	}
	.marketing-domain-actions__readiness-label small {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.marketing-domain-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
</style>
