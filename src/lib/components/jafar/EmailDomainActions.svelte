<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { AlertDialog } from 'bits-ui';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg';
	import chevronUpIcon from '@tabler/icons/outline/chevron-up.svg';
	import copyIcon from '@tabler/icons/outline/copy.svg';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { toCloudflareDnsRecord, type DnsRecord } from '$lib/communications/cloudflare-dns';

	type Domain = {
		id: string;
		domain_name: string;
		dns_zone: string | null;
		lifecycle_state: string;
		ownership_status: string;
		dkim_status: string;
		dmarc_status: string;
		spf_status: string;
		provider_verified: boolean;
		provider_authenticated: boolean;
		last_checked_at: string | null;
		verified_at: string | null;
		warmup_started_at: string | null;
		transition_until: string | null;
		replacement_of_domain_id: string | null;
		provider_cleanup_error: string | null;
		created_at: string;
	};
	type DnsSetupResponse = {
		domain_name: string;
		dns_zone: string | null;
		last_checked_at: string | null;
		dns_records: DnsRecord[];
		error?: string;
	};
	type DomainListResponse = { domains?: Domain[]; error?: string };
	type MutationResponse = { error?: string; field_errors?: Record<string, string> };
	type RemovalPreview = {
		domain_name: string;
		can_remove: boolean;
		impact: { live_sender_count: number; live_replacement_count: number };
		error?: string;
	};

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const domainKey = $derived(['jafar', 'organizations', organizationId, 'email-domains']);
	const domainsQuery = createQuery<DomainListResponse>(() => ({
		queryKey: domainKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/domains`
			);
			const result = (await response.json()) as DomainListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Email domains could not be loaded.');
			return result;
		},
		staleTime: 30_000
	}));

	let activeDialog = $state<'provision' | 'replace' | null>(null);
	let selectedDomain = $state<Domain | null>(null);
	let domainName = $state('');
	let dnsZone = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackError = $state('');
	let feedbackMessage = $state('');
	let removalTarget = $state<Domain | null>(null);
	let removalOpen = $state(false);
	let removalReason = $state('');
	let removalConfirmation = $state('');
	let dnsDomain = $state<Domain | null>(null);
	let copiedRecord = $state('');

	const removalPreviewQuery = createQuery<RemovalPreview>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'email-domain-removal', removalTarget?.id],
		enabled: Boolean(removalTarget && removalOpen),
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/domains/${removalTarget?.id}/remove`
			);
			const result = (await response.json()) as RemovalPreview;
			if (!response.ok) throw new Error(result.error ?? 'The removal impact could not be loaded.');
			return result;
		}
	}));

	const dnsSetupQuery = createQuery<DnsSetupResponse>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'email-domain-dns', dnsDomain?.id],
		enabled: Boolean(dnsDomain),
		queryFn: () => loadDnsSetup(dnsDomain?.id ?? ''),
		staleTime: 30_000
	}));

	function tone(domain: Domain) {
		if (domain.lifecycle_state === 'verified') return 'success';
		if (domain.lifecycle_state === 'unhealthy' || domain.lifecycle_state === 'removal_pending')
			return 'critical';
		if (domain.lifecycle_state === 'replacing') return 'warning';
		return 'informative';
	}

	function stateLabel(domain: Domain) {
		return domain.lifecycle_state.replaceAll('_', ' ');
	}

	function formatTime(value: string | null) {
		return value
			? new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' })
			: 'Not checked yet';
	}

	function resetForm() {
		domainName = '';
		dnsZone = '';
		fieldErrors = {};
	}

	function closeDialog() {
		if (!domainMutation.isPending) {
			activeDialog = null;
			selectedDomain = null;
			resetForm();
		}
	}

	function openProvision(domain?: Domain) {
		feedbackError = '';
		feedbackMessage = '';
		selectedDomain = null;
		resetForm();
		domainName = domain?.domain_name ?? '';
		dnsZone = domain?.dns_zone ?? '';
		activeDialog = 'provision';
	}

	function openReplacement(domain: Domain) {
		feedbackError = '';
		feedbackMessage = '';
		selectedDomain = domain;
		resetForm();
		dnsZone = domain.dns_zone ?? '';
		activeDialog = 'replace';
	}

	function openRemoval(domain: Domain) {
		feedbackError = '';
		feedbackMessage = '';
		removalTarget = domain;
		removalReason = '';
		removalConfirmation = '';
		removalOpen = true;
	}

	function closeRemoval() {
		if (!removalMutation.isPending) {
			removalOpen = false;
			removalTarget = null;
			removalReason = '';
			removalConfirmation = '';
		}
	}

	async function refreshDomains() {
		await queryClient.invalidateQueries({ queryKey: domainKey });
		if (dnsDomain) {
			await queryClient.invalidateQueries({
				queryKey: ['jafar', 'organizations', organizationId, 'email-domain-dns', dnsDomain.id]
			});
		}
	}

	async function loadDnsSetup(domainId: string) {
		const response = await fetch(
			`/api/jafar/organizations/${organizationId}/communications/domains/${domainId}/dns`
		);
		const result = (await response.json()) as DnsSetupResponse;
		if (!response.ok) throw new Error(result.error ?? 'DNS setup records could not be loaded.');
		return result;
	}

	function prefetchDnsSetup(domain: Domain) {
		void queryClient.prefetchQuery({
			queryKey: ['jafar', 'organizations', organizationId, 'email-domain-dns', domain.id],
			queryFn: () => loadDnsSetup(domain.id),
			staleTime: 30_000
		});
	}

	function toggleDnsSetup(domain: Domain) {
		copiedRecord = '';
		dnsDomain = dnsDomain?.id === domain.id ? null : domain;
	}

	async function copyDnsValue(value: string, recordKey: string) {
		try {
			await navigator.clipboard.writeText(value);
			copiedRecord = recordKey;
		} catch {
			feedbackError = 'The DNS value could not be copied. Select and copy it manually.';
		}
	}

	const domainMutation = createMutation<
		MutationResponse,
		Error,
		{ url: string; body: object; message: string }
	>(() => ({
		mutationFn: async ({ url, body }) => {
			const response = await fetch(url, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'The domain action could not be completed.');
			}
			return result;
		},
		onMutate: () => {
			fieldErrors = {};
			feedbackError = '';
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async (_result, input) => {
			feedbackMessage = input.message;
			closeDialog();
			await refreshDomains();
		}
	}));

	const removalMutation = createMutation<MutationResponse, Error>(() => ({
		mutationFn: async () => {
			if (!removalTarget || !removalPreviewQuery.data)
				throw new Error('Review the current removal impact first.');
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/domains/${removalTarget.id}/remove`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({
						confirm_domain_name: removalConfirmation,
						reason: removalReason,
						expected_impact: removalPreviewQuery.data.impact,
						idempotency_key: crypto.randomUUID()
					})
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'The sending domain could not be removed.');
			return result;
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async () => {
			feedbackMessage = 'The sending domain removal has been recorded.';
			closeRemoval();
			await refreshDomains();
		}
	}));

	function submitDomain(event: SubmitEvent) {
		event.preventDefault();
		if (!domainName.trim()) {
			fieldErrors = { domain_name: 'Enter a domain name.' };
			return;
		}
		if (!dnsZone.trim()) {
			fieldErrors = { dns_zone: 'Enter the parent DNS zone.' };
			return;
		}
		const normalized = domainName.trim().toLowerCase();
		const normalizedDnsZone = dnsZone.trim().toLowerCase();
		const replacementDomain = activeDialog === 'replace' ? selectedDomain : null;
		domainMutation.mutate({
			url: replacementDomain
				? `/api/jafar/organizations/${organizationId}/communications/domains/${replacementDomain.id}/replace`
				: `/api/jafar/organizations/${organizationId}/communications/domains`,
			body: replacementDomain
				? {
						domain_name: normalized,
						dns_zone: normalizedDnsZone,
						idempotency_key: crypto.randomUUID()
					}
				: {
						domain_name: normalized,
						dns_zone: normalizedDnsZone,
						purpose: 'sending',
						idempotency_key: crypto.randomUUID()
					},
			message: replacementDomain
				? 'Replacement domain provisioned. Verify it before switching.'
				: 'Sending domain provisioned. Add its DNS records, then check it again.'
		});
	}

	function recheck(domain: Domain) {
		feedbackError = '';
		feedbackMessage = '';
		domainMutation.mutate({
			url: `/api/jafar/organizations/${organizationId}/communications/domains/${domain.id}/recheck`,
			body: { idempotency_key: crypto.randomUUID() },
			message: `Checked ${domain.domain_name}.`
		});
	}
</script>

<div class="email-domain-actions">
	<div class="email-domain-actions__heading">
		<div>
			<h3>Email domains</h3>
			<p>
				Provisioning is platform-managed. A contractor can add senders only after a healthy domain
				is verified.
			</p>
		</div>
		<Button onclick={openProvision}>Provision domain</Button>
	</div>

	{#if feedbackMessage}<p class="email-domain-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="email-domain-actions__error" role="alert">{feedbackError}</p>{/if}

	{#if domainsQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading email domains" />
	{:else if domainsQuery.isError}
		<ErrorState
			title="Email domains could not be loaded"
			description={domainsQuery.error instanceof Error
				? domainsQuery.error.message
				: 'Email domains could not be loaded. Try again.'}
			retry={() => domainsQuery.refetch()}
		/>
	{:else if (domainsQuery.data?.domains ?? []).length === 0}
		<p class="email-domain-actions__empty">
			No sending domain is set up for this organization yet.
		</p>
	{:else}
		<div class="email-domain-actions__table-wrap">
			<table>
				<caption>Sending domains</caption>
				<thead
					><tr
						><th scope="col">Domain</th><th scope="col">Readiness</th><th scope="col"
							>Last checked</th
						><th scope="col"><span class="email-domain-actions__sr-only">Actions</span></th></tr
					></thead
				>
				<tbody>
					{#each domainsQuery.data?.domains ?? [] as domain (domain.id)}
						<tr>
							<td
								><strong>{domain.domain_name}</strong><small
									>Brevo {domain.provider_authenticated ? 'authenticated' : 'pending'} · DKIM {domain.dkim_status}</small
								></td
							>
							<td><Badge status={tone(domain)}>{stateLabel(domain)}</Badge></td>
							<td>{formatTime(domain.last_checked_at)}</td>
							<td
								><div class="email-domain-actions__buttons">
									<Button
										size="small"
										variant="secondary"
										variation="subtle"
										onhover={() => prefetchDnsSetup(domain)}
										onclick={() => toggleDnsSetup(domain)}
										>{dnsDomain?.id === domain.id ? 'Hide DNS setup' : 'DNS setup'}
										<span class="email-domain-actions__button-icon" aria-hidden="true"
											><img
												src={dnsDomain?.id === domain.id ? chevronUpIcon : chevronDownIcon}
												alt=""
											/></span
										></Button
									><Button
										size="small"
										variant="secondary"
										variation="subtle"
										loading={domainMutation.isPending}
										onclick={() => recheck(domain)}>Check</Button
									><Button
										size="small"
										variant="secondary"
										variation="subtle"
										onclick={() => openReplacement(domain)}>Replace</Button
									><Button
										size="small"
										variant="secondary"
										variation="subtle"
										onclick={() => openRemoval(domain)}>Remove</Button
									>
								</div></td
							>
						</tr>
						{#if dnsDomain?.id === domain.id}
							<tr class="email-domain-actions__dns-row">
								<td colspan="4">
									<section
										class="email-domain-actions__dns-setup"
										aria-labelledby={`dns-setup-${domain.id}`}
									>
										<div class="email-domain-actions__dns-heading">
											<div>
												<h4 id={`dns-setup-${domain.id}`}>DNS setup for {domain.domain_name}</h4>
												<p>Use the Cloudflare values below, then run a check.</p>
											</div>
											<Badge status="informative"
												>{formatTime(dnsSetupQuery.data?.last_checked_at ?? null)}</Badge
											>
										</div>
										{#if dnsSetupQuery.isPending}
											<LoadingSkeleton variant="table" label="Loading DNS setup records" />
										{:else if dnsSetupQuery.isError}
											<p class="email-domain-actions__error" role="alert">
												{dnsSetupQuery.error instanceof Error
													? dnsSetupQuery.error.message
													: 'DNS setup records could not be loaded.'}
											</p>
										{:else if !dnsSetupQuery.data?.dns_zone}
											<div class="email-domain-actions__dns-notice" role="status">
												<p>
													Add the parent DNS zone before using Cloudflare guidance. UCRM will not
													guess it for an existing domain.
												</p>
												<Button
													size="small"
													variant="secondary"
													variation="subtle"
													onclick={() => openProvision(domain)}>Add DNS zone</Button
												>
											</div>
										{:else if (dnsSetupQuery.data?.dns_records ?? []).length === 0}
											<p class="email-domain-actions__empty">
												DNS setup records are not available yet. Check the domain again in a moment.
											</p>
										{:else}
											<div class="email-domain-actions__cloudflare-guide" role="status">
												<p>
													In Cloudflare, open <strong>DNS → Records</strong> and select
													<strong>Add record</strong>. Copy the exact <strong>Name</strong> and
													<strong>Target/Content</strong> below.
												</p>
												<p>CNAME records must stay <strong>DNS only</strong>; do not proxy them.</p>
											</div>
											<div class="email-domain-actions__dns-records">
												{#each dnsSetupQuery.data?.dns_records ?? [] as record, index (`${record.type}-${record.host_name}-${record.value}`)}
													{@const cloudflareRecord = toCloudflareDnsRecord(
														record,
														domain.domain_name,
														dnsSetupQuery.data?.dns_zone ?? ''
													)}
													<article class="email-domain-actions__dns-record">
														<div class="email-domain-actions__dns-record-header">
															<Badge status={record.status ? 'success' : 'warning'}
																>{record.status ? 'Found' : 'Waiting'}</Badge
															>
															<span>{record.type}</span>
														</div>
														<dl>
															<div>
																<dt>Cloudflare name</dt>
																<dd class="email-domain-actions__dns-value">
																	<code>{cloudflareRecord.cloudflare_name}</code><button
																		type="button"
																		class="email-domain-actions__copy-button"
																		aria-label={`Copy Cloudflare name for ${record.host_name}`}
																		onclick={() =>
																			copyDnsValue(
																				cloudflareRecord.cloudflare_name,
																				`${domain.id}-${index}-name`
																			)}
																		><img src={copyIcon} alt="" /><span
																			>{copiedRecord === `${domain.id}-${index}-name`
																				? 'Copied'
																				: 'Copy'}</span
																		></button
																	>
																</dd>
															</div>
															<div>
																<dt>{cloudflareRecord.content_label}</dt>
																<dd class="email-domain-actions__dns-value">
																	<code>{record.value}</code><button
																		type="button"
																		class="email-domain-actions__copy-button"
																		aria-label={`Copy DNS value for ${record.host_name}`}
																		onclick={() =>
																			copyDnsValue(record.value, `${domain.id}-${index}-content`)}
																		><img src={copyIcon} alt="" /><span
																			>{copiedRecord === `${domain.id}-${index}-content`
																				? 'Copied'
																				: 'Copy'}</span
																		></button
																	>
																</dd>
															</div>
															{#if cloudflareRecord.proxy_status}
																<div>
																	<dt>Proxy status</dt>
																	<dd>{cloudflareRecord.proxy_status}</dd>
																</div>
															{/if}
															<div>
																<dt>TTL</dt>
																<dd>{cloudflareRecord.ttl}</dd>
															</div>
														</dl>
													</article>
												{/each}
											</div>
										{/if}
									</section>
								</td>
							</tr>
						{/if}
					{/each}
				</tbody>
			</table>
		</div>
	{/if}
</div>

<Dialog open={activeDialog === 'provision'} title="Provision sending domain" onClose={closeDialog}>
	<form class="email-domain-actions__form" onsubmit={submitDomain}>
		<p>
			Use the sending subdomain, such as <strong>mail.yourbusiness.com</strong>. UCRM will return
			the DNS setup needed for verification.
		</p>
		<Input
			id="provision-domain-name"
			label="Sending domain"
			placeholder="mail.yourbusiness.com"
			bind:value={domainName}
			invalid={Boolean(fieldErrors.domain_name)}
			errorMessage={fieldErrors.domain_name}
		/>
		<Input
			id="provision-dns-zone"
			label="Parent DNS zone"
			placeholder="yourbusiness.com"
			bind:value={dnsZone}
			invalid={Boolean(fieldErrors.dns_zone)}
			errorMessage={fieldErrors.dns_zone}
		/>
		<div class="email-domain-actions__dialog-actions">
			<Button type="submit" loading={domainMutation.isPending}>Provision domain</Button><Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={closeDialog}>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<Dialog open={activeDialog === 'replace'} title="Replace sending domain" onClose={closeDialog}>
	<form class="email-domain-actions__form" onsubmit={submitDomain}>
		<p>
			The current verified domain stays in use until the replacement is healthy. Queued manual email
			stays held for review.
		</p>
		<Input
			id="replacement-domain-name"
			label="Replacement sending domain"
			placeholder="mail.yourbusiness.com"
			bind:value={domainName}
			invalid={Boolean(fieldErrors.domain_name)}
			errorMessage={fieldErrors.domain_name}
		/>
		<Input
			id="replacement-dns-zone"
			label="Parent DNS zone"
			placeholder="yourbusiness.com"
			bind:value={dnsZone}
			invalid={Boolean(fieldErrors.dns_zone)}
			errorMessage={fieldErrors.dns_zone}
		/>
		<div class="email-domain-actions__dialog-actions">
			<Button type="submit" loading={domainMutation.isPending}>Provision replacement</Button><Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={closeDialog}>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<AlertDialog.Root bind:open={removalOpen} onOpenChange={(open) => !open && closeRemoval()}>
	<AlertDialog.Portal>
		<AlertDialog.Overlay class="email-domain-actions__overlay" />
		<AlertDialog.Content class="email-domain-actions__removal-dialog">
			<AlertDialog.Title level={2}>Remove sending domain</AlertDialog.Title>
			<AlertDialog.Description
				>Removal is permanent after Brevo confirms it. Review the impact, then enter the exact
				domain name and a private reason.</AlertDialog.Description
			>
			{#if removalPreviewQuery.isPending}<LoadingSkeleton
					variant="text"
					label="Loading removal impact"
				/>
			{:else if removalPreviewQuery.isError}<p class="email-domain-actions__error" role="alert">
					{removalPreviewQuery.error instanceof Error
						? removalPreviewQuery.error.message
						: 'The removal impact could not be loaded.'}
				</p>
			{:else if removalPreviewQuery.data}
				<p class="email-domain-actions__impact">
					{removalPreviewQuery.data.impact.live_sender_count} active senders and {removalPreviewQuery
						.data.impact.live_replacement_count} replacement domains would be affected.
				</p>
				<Input
					id="remove-domain-confirmation"
					label={`Type ${removalTarget?.domain_name ?? 'the domain'} to confirm`}
					bind:value={removalConfirmation}
				/>
				<Input
					id="remove-domain-reason"
					label="Private removal reason"
					bind:value={removalReason}
				/>
				{#if !removalPreviewQuery.data.can_remove}<p
						class="email-domain-actions__error"
						role="alert"
					>
						Remove or finish the affected senders and replacement domains first.
					</p>{/if}
			{/if}
			<div class="email-domain-actions__dialog-actions">
				<AlertDialog.Cancel
					>{#snippet child({ props })}<Button {...props} variant="secondary" variation="subtle"
							>Cancel</Button
						>{/snippet}</AlertDialog.Cancel
				><Button
					variant="primary"
					variation="destructive"
					disabled={!removalPreviewQuery.data?.can_remove ||
						removalConfirmation !== removalTarget?.domain_name ||
						!removalReason.trim()}
					loading={removalMutation.isPending}
					onclick={() => removalMutation.mutate()}>Remove domain</Button
				>
			</div>
		</AlertDialog.Content>
	</AlertDialog.Portal>
</AlertDialog.Root>

<style lang="scss">
	.email-domain-actions,
	.email-domain-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.email-domain-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.email-domain-actions__heading h3 {
		font-size: var(--typography--fontSize-large);
	}
	.email-domain-actions__heading p,
	.email-domain-actions__form > p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.email-domain-actions__success {
		color: var(--color-success--onSurface);
	}
	.email-domain-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.email-domain-actions__empty,
	.email-domain-actions__impact {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.email-domain-actions__dns-notice,
	.email-domain-actions__cloudflare-guide {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.email-domain-actions__dns-notice {
		grid-template-columns: 1fr auto;
		align-items: center;
	}
	.email-domain-actions__cloudflare-guide p {
		line-height: var(--typography--lineHeight-base);
	}
	.email-domain-actions__table-wrap {
		overflow-x: auto;
	}
	.email-domain-actions__table-wrap table {
		width: 100%;
		min-width: 680px;
		border-collapse: collapse;
	}
	.email-domain-actions__table-wrap th,
	.email-domain-actions__table-wrap td {
		padding: var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		vertical-align: top;
	}
	.email-domain-actions__table-wrap th {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.email-domain-actions__table-wrap td {
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
	}
	.email-domain-actions__table-wrap strong,
	.email-domain-actions__table-wrap small {
		display: block;
	}
	.email-domain-actions__table-wrap small {
		margin-top: var(--space-smallest);
		color: var(--color-text--secondary);
	}
	.email-domain-actions__buttons,
	.email-domain-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.email-domain-actions__button-icon {
		display: inline-flex;
		width: 16px;
		height: 16px;
	}
	.email-domain-actions__button-icon img,
	.email-domain-actions__copy-button img {
		width: 16px;
		height: 16px;
	}
	.email-domain-actions__dns-row td {
		padding: 0 var(--space-small) var(--space-base);
		background: var(--color-surface--background);
	}
	.email-domain-actions__dns-setup {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.email-domain-actions__dns-heading,
	.email-domain-actions__dns-record-header,
	.email-domain-actions__dns-value {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
	}
	.email-domain-actions__dns-heading h4 {
		font-size: var(--typography--fontSize-large);
	}
	.email-domain-actions__dns-heading p {
		margin-top: var(--space-smallest);
		color: var(--color-text--secondary);
	}
	.email-domain-actions__dns-records {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
		gap: var(--space-small);
	}
	.email-domain-actions__dns-record {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.email-domain-actions__dns-record-header > span,
	.email-domain-actions__dns-record dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.email-domain-actions__dns-record dl,
	.email-domain-actions__dns-record dl > div {
		display: grid;
		gap: var(--space-smallest);
	}
	.email-domain-actions__dns-record dd {
		margin: 0;
		color: var(--color-text);
	}
	.email-domain-actions__dns-value {
		align-items: flex-start;
	}
	.email-domain-actions__dns-value code {
		overflow-wrap: anywhere;
		font-family: var(--typography--fontFamily-monospace, monospace);
		font-size: var(--typography--fontSize-small);
	}
	.email-domain-actions__copy-button {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		gap: var(--space-smallest);
		padding: var(--space-smallest) var(--space-small);
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-interactive--subtle);
		background: transparent;
		font: inherit;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		cursor: pointer;
	}
	.email-domain-actions__copy-button:hover,
	.email-domain-actions__copy-button:focus-visible {
		outline: none;
		color: var(--color-interactive--subtle--hover);
		background: var(--color-interactive--background--subtle--hover);
		box-shadow: var(--shadow-focus);
	}
	.email-domain-actions__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
	}
	:global(.email-domain-actions__overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: var(--color-overlay);
	}
	:global(.email-domain-actions__removal-dialog) {
		position: fixed;
		top: 50%;
		left: 50%;
		z-index: var(--elevation-modal);
		display: grid;
		gap: var(--space-base);
		width: min(calc(100vw - var(--space-large) * 2), 520px);
		max-height: calc(100dvh - var(--space-large) * 2);
		overflow: auto;
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
		transform: translate(-50%, -50%);
	}
	:global(.email-domain-actions__removal-dialog [data-slot='alert-dialog-title']) {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		font-weight: 700;
	}
	:global(.email-domain-actions__removal-dialog [data-slot='alert-dialog-description']) {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	@media (max-width: 639px) {
		.email-domain-actions__heading {
			flex-direction: column;
			align-items: stretch;
		}
		.email-domain-actions__heading :global(.button) {
			width: 100%;
		}
		.email-domain-actions__buttons,
		.email-domain-actions__dialog-actions {
			justify-content: flex-start;
		}
		.email-domain-actions__dns-heading,
		.email-domain-actions__dns-value,
		.email-domain-actions__dns-notice {
			align-items: flex-start;
			flex-direction: column;
		}
	}
</style>
