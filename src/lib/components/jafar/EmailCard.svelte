<script lang="ts">
	import {
		emailDomainsQuery,
		emailSetupRequestQuery,
		marketingDomainsQuery
	} from '$lib/jafar/organization-communications-queries';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { mailboxProviderLabel, type EmailSetupRequest } from '$lib/communications/email-setup';
	import {
		jafarOrganizationEmailDomainRemovalKey,
		jafarOrganizationEmailDomainsKey,
		jafarOrganizationEmailSetupRequestKey,
		jafarOrganizationMarketingDomainsKey
	} from '$lib/jafar/query-keys';

	type DnsStatus = 'unchecked' | 'pending' | 'passing' | 'failing';
	type RowStatus = 'not_set_up' | 'setting_up' | 'ready' | 'problem' | 'removal_unfinished';
	type MenuItem = {
		label: string;
		onSelect: () => void;
		destructive?: boolean;
	};

	type OperationalDomain = {
		id: string;
		purpose: 'sending' | 'receiving';
		provider: string;
		domain_name: string;
		dns_zone: string | null;
		lifecycle_state: string;
		ownership_status: DnsStatus;
		dkim_status: DnsStatus;
		dmarc_status: DnsStatus;
		spf_status: DnsStatus;
		inbound_mx_status: DnsStatus;
		provider_verified: boolean;
		provider_authenticated: boolean;
		last_checked_at: string | null;
		verified_at: string | null;
		created_at: string;
	};
	type OperationalListResponse = { domains?: OperationalDomain[]; error?: string };

	type ClickStatus = 'not_set_up' | 'waiting_certificate' | 'working' | 'turned_off' | 'problem';
	type MarketingDomain = {
		id: string;
		domain_name: string;
		dns_zone: string | null;
		lifecycle_state: string;
		ownership_status: DnsStatus;
		dkim_status: DnsStatus;
		spf_status: DnsStatus;
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
	type MarketingListResponse = {
		domains?: MarketingDomain[];
		suggested_root_domain?: string | null;
		branded_links_configured?: boolean;
		error?: string;
	};

	type MutationResponse = { error?: string; field_errors?: Record<string, string> };
	type RemovalPreview = {
		domain_name: string;
		can_remove: boolean;
		impact: { live_sender_count: number; live_replacement_count: number };
		error?: string;
	};
	type OperationalActivationResult = {
		root_domain: string;
		sending: { domain_name: string };
		receiving: { domain_name: string };
		replayed?: boolean;
		error?: string;
		field_errors?: Record<string, string>;
	};
	type MarketingActivationResult = {
		root_domain: string;
		marketing: { domain_name: string };
		replayed?: boolean;
		error?: string;
		field_errors?: Record<string, string>;
	};

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();

	const operationalKey = $derived(jafarOrganizationEmailDomainsKey(organizationId));
	const operationalQuery = createQuery<OperationalListResponse>(() =>
		emailDomainsQuery<OperationalListResponse>(organizationId)
	);

	// The contractor's open ask, until Jafar sets the domain up or closes it. Setting up is done with the same
	// Set up action below, prefilled with the domain they asked for.
	const requestKey = $derived(jafarOrganizationEmailSetupRequestKey(organizationId));
	const requestQuery = createQuery<{ request: EmailSetupRequest | null; error?: string }>(() =>
		emailSetupRequestQuery<{ request: EmailSetupRequest | null; error?: string }>(organizationId)
	);
	const setupRequest = $derived(requestQuery.data?.request ?? null);

	const marketingKey = $derived(jafarOrganizationMarketingDomainsKey(organizationId));
	const marketingQuery = createQuery<MarketingListResponse>(() =>
		marketingDomainsQuery<MarketingListResponse>(organizationId)
	);

	const sending = $derived(
		operationalQuery.data?.domains?.find((domain) => domain.purpose === 'sending') ?? null
	);
	const receiving = $derived(
		operationalQuery.data?.domains?.find((domain) => domain.purpose === 'receiving') ?? null
	);
	const marketing = $derived(marketingQuery.data?.domains?.[0] ?? null);

	function rowStatus(lifecycleState: string | null | undefined): RowStatus {
		if (!lifecycleState) return 'not_set_up';
		if (lifecycleState === 'verified') return 'ready';
		if (lifecycleState === 'unhealthy') return 'problem';
		// A removal whose provider cleanup failed stays pending until Remove is run again.
		if (lifecycleState === 'removal_pending') return 'removal_unfinished';
		return 'setting_up';
	}
	const statusLabel: Record<RowStatus, string> = {
		not_set_up: 'Not set up',
		setting_up: 'Setting up',
		ready: 'Ready',
		problem: 'Problem',
		removal_unfinished: 'Removal unfinished'
	};
	const statusTone: Record<RowStatus, 'informative' | 'warning' | 'success' | 'critical'> = {
		not_set_up: 'informative',
		setting_up: 'warning',
		ready: 'success',
		problem: 'critical',
		removal_unfinished: 'warning'
	};
	// One status for sending and customer replies together: Ready only when both work. Replies are routed on
	// the Check after the reply domain verifies, so a verified sender without a reply row is still setting up.
	const everydayStatus = $derived.by((): RowStatus => {
		const sendingStatus = rowStatus(sending?.lifecycle_state);
		if (sendingStatus !== 'ready') return sendingStatus;
		const repliesStatus = rowStatus(receiving?.lifecycle_state);
		return repliesStatus === 'not_set_up' ? 'setting_up' : repliesStatus;
	});
	const marketingStatus = $derived(rowStatus(marketing?.lifecycle_state));

	function formatTime(value: string | null | undefined) {
		return value
			? new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' })
			: 'Not checked yet';
	}
	function statusText(value: string) {
		return value.replaceAll('_', ' ');
	}

	let feedbackMessage = $state('');
	let feedbackError = $state('');

	async function refreshOperational() {
		await queryClient.invalidateQueries({ queryKey: operationalKey });
	}
	async function refreshMarketing() {
		await queryClient.invalidateQueries({ queryKey: marketingKey });
	}

	// ---- Everyday email + replies: Set up ----
	let everydaySetupOpen = $state(false);
	let everydayRootDomain = $state('');
	let everydayFieldErrors = $state<Record<string, string>>({});
	let everydayActivationResult = $state<OperationalActivationResult | null>(null);

	function openEverydaySetup() {
		feedbackError = '';
		feedbackMessage = '';
		everydayFieldErrors = {};
		everydayActivationResult = null;
		everydayRootDomain = sending?.dns_zone ?? setupRequest?.root_domain ?? '';
		everydaySetupOpen = true;
	}
	function closeEverydaySetup() {
		if (everydayActivateMutation.isPending) return;
		everydaySetupOpen = false;
		everydayRootDomain = '';
		everydayFieldErrors = {};
		everydayActivationResult = null;
	}

	const everydayActivateMutation = createMutation<OperationalActivationResult, Error, void>(() => ({
		mutationFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/domains/activate`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({
						root_domain: everydayRootDomain.trim().toLowerCase(),
						idempotency_key: crypto.randomUUID()
					})
				}
			);
			const result = (await response.json()) as OperationalActivationResult;
			if (!response.ok) {
				everydayFieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'Everyday email could not be set up.');
			}
			return result;
		},
		onMutate: () => {
			everydayFieldErrors = {};
			feedbackError = '';
			everydayActivationResult = null;
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async (result) => {
			everydayActivationResult = result;
			await Promise.all([
				refreshOperational(),
				queryClient.invalidateQueries({ queryKey: requestKey })
			]);
		}
	}));

	function submitEverydaySetup(event: SubmitEvent) {
		event.preventDefault();
		if (!everydayRootDomain.trim()) {
			everydayFieldErrors = { root_domain: 'Enter the root domain, such as yourbusiness.com.' };
			return;
		}
		everydayActivateMutation.mutate();
	}

	const everydayRecheckMutation = createMutation<MutationResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!sending) throw new Error('Set up Everyday email before checking it.');
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/domains/${sending.id}/recheck`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ idempotency_key: crypto.randomUUID() })
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'Everyday email could not be checked.');
			return result;
		},
		onMutate: () => {
			feedbackError = '';
			feedbackMessage = '';
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async () => {
			feedbackMessage = `Checked ${sending?.domain_name}.`;
			await refreshOperational();
		}
	}));

	let everydayProblemOpen = $state(false);
	const everydayProblemReasons = $derived.by(() => {
		if (!sending) return [];
		const reasons: string[] = [];
		if (sending.ownership_status !== 'passing')
			reasons.push('Domain ownership is not verified yet.');
		if (sending.dkim_status !== 'passing') reasons.push('DKIM signing is not passing yet.');
		if (!sending.provider_verified) reasons.push('Amazon SES has not verified this domain.');
		if (receiving?.lifecycle_state === 'unhealthy')
			reasons.push(
				`Customer replies to ${receiving.domain_name} are not reaching UCRM. Check again repairs the mail route.`
			);
		if (!reasons.length)
			reasons.push('This domain needs attention. Run Check for the latest state.');
		return reasons;
	});

	// ---- Contractor's request: Close request ----
	let closeRequestOpen = $state(false);
	let closeNote = $state('');
	let closeFieldErrors = $state<Record<string, string>>({});
	function openCloseRequest() {
		feedbackError = '';
		feedbackMessage = '';
		closeNote = '';
		closeFieldErrors = {};
		closeRequestOpen = true;
	}
	function dismissCloseRequest() {
		if (closeRequestMutation.isPending) return;
		closeRequestOpen = false;
	}
	const closeRequestMutation = createMutation<MutationResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!setupRequest) throw new Error('There is no open request to close.');
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/email-setup/${setupRequest.id}/close`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ note: closeNote })
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) {
				closeFieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'The request could not be closed.');
			}
			return result;
		},
		onMutate: () => {
			closeFieldErrors = {};
			feedbackError = '';
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async () => {
			closeRequestOpen = false;
			feedbackMessage = 'Request closed. The contractor can see your note.';
			await queryClient.invalidateQueries({ queryKey: requestKey });
		}
	}));
	function submitCloseRequest(event: SubmitEvent) {
		event.preventDefault();
		if (!closeNote.trim()) {
			closeFieldErrors = { note: 'Write a note the contractor will see.' };
			return;
		}
		closeRequestMutation.mutate();
	}

	// ---- Everyday email + replies: Remove (sending and customer replies together) ----
	let removalOpen = $state(false);
	let removalReason = $state('');
	let removalConfirmation = $state('');
	function openRemoval() {
		feedbackError = '';
		feedbackMessage = '';
		removalReason = '';
		removalConfirmation = '';
		removalOpen = true;
	}
	function closeRemoval() {
		if (removalMutation.isPending) return;
		removalOpen = false;
		removalReason = '';
		removalConfirmation = '';
	}
	const removalPreviewQuery = createQuery<RemovalPreview>(() => ({
		queryKey: jafarOrganizationEmailDomainRemovalKey(organizationId, sending?.id),
		enabled: Boolean(sending && removalOpen),
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/domains/${sending?.id}/remove`
			);
			const result = (await response.json()) as RemovalPreview;
			if (!response.ok) throw new Error(result.error ?? 'The removal impact could not be loaded.');
			return result;
		}
	}));
	const removalMutation = createMutation<MutationResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!sending || !removalPreviewQuery.data)
				throw new Error('Review the current removal impact first.');
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/domains/${sending.id}/remove`,
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
			if (!response.ok) throw new Error(result.error ?? 'Everyday email could not be removed.');
			return result;
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async () => {
			feedbackMessage = 'Everyday email removal has been recorded.';
			// closeRemoval() refuses while the mutation is pending, which it still is inside onSuccess.
			removalOpen = false;
			removalReason = '';
			removalConfirmation = '';
			await refreshOperational();
		}
	}));

	// ---- Marketing email: Set up ----
	let marketingSetupOpen = $state(false);
	let marketingRootDomain = $state('');
	let marketingFieldErrors = $state<Record<string, string>>({});
	let marketingActivationResult = $state<MarketingActivationResult | null>(null);

	function openMarketingSetup() {
		feedbackError = '';
		feedbackMessage = '';
		marketingFieldErrors = {};
		marketingActivationResult = null;
		marketingRootDomain = marketingQuery.data?.suggested_root_domain ?? '';
		marketingSetupOpen = true;
	}
	function closeMarketingSetup() {
		if (marketingActivateMutation.isPending) return;
		marketingSetupOpen = false;
		marketingRootDomain = '';
		marketingFieldErrors = {};
		marketingActivationResult = null;
	}
	const marketingActivateMutation = createMutation<MarketingActivationResult, Error, void>(() => ({
		mutationFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/marketing-domain/activate`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({
						root_domain: marketingRootDomain.trim().toLowerCase(),
						idempotency_key: crypto.randomUUID()
					})
				}
			);
			const result = (await response.json()) as MarketingActivationResult;
			if (!response.ok) {
				marketingFieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'Marketing email could not be set up.');
			}
			return result;
		},
		onMutate: () => {
			marketingFieldErrors = {};
			feedbackError = '';
			marketingActivationResult = null;
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async (result) => {
			marketingActivationResult = result;
			await refreshMarketing();
		}
	}));
	function submitMarketingSetup(event: SubmitEvent) {
		event.preventDefault();
		if (!marketingRootDomain.trim()) {
			marketingFieldErrors = { root_domain: 'Enter the root domain, such as yourbusiness.com.' };
			return;
		}
		marketingActivateMutation.mutate();
	}

	const marketingRecheckMutation = createMutation<MutationResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!marketing) throw new Error('Set up Marketing email before checking it.');
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/marketing-domain/${marketing.id}/recheck`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ idempotency_key: crypto.randomUUID() })
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'Marketing email could not be checked.');
			return result;
		},
		onMutate: () => {
			feedbackError = '';
			feedbackMessage = '';
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async () => {
			feedbackMessage = `Checked ${marketing?.domain_name}.`;
			await refreshMarketing();
		}
	}));

	let marketingProblemOpen = $state(false);
	const marketingProblemReasons = $derived.by(() => {
		if (!marketing) return [];
		const reasons: string[] = [];
		if (marketing.ownership_status !== 'passing')
			reasons.push('Domain ownership is not verified yet.');
		if (marketing.dkim_status !== 'passing') reasons.push('DKIM signing is not passing yet.');
		if (!marketing.provider_verified) reasons.push('Amazon SES has not verified this domain.');
		if (!reasons.length)
			reasons.push('This domain needs attention. Run Check for the latest state.');
		return reasons;
	});

	// ---- Marketing email: branded links (unchanged behavior, moved into the row's menu) ----
	type ClickAction = 'turn_on' | 'turn_off' | 'remove';
	const clickLabels: Record<ClickStatus, string> = {
		not_set_up: 'Not set up',
		waiting_certificate: 'Waiting for certificate',
		working: 'Working',
		turned_off: 'Turned off',
		problem: 'Problem'
	};
	let pendingBrandedRemoval = $state<MarketingDomain | null>(null);
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
			pendingBrandedRemoval = null;
			await refreshMarketing();
		}
	}));

	// ---- Technical records (read-only, both rows) ----
	let technicalRecords = $state<{ title: string; rows: [string, string][] } | null>(null);
	function openEverydayTechnical() {
		const rows: [string, string][] = [];
		if (sending) {
			rows.push(['Sending domain', sending.domain_name]);
			rows.push(['Root domain', sending.dns_zone ?? '—']);
			rows.push(['Provider', 'Amazon SES']);
			rows.push(['Ownership', statusText(sending.ownership_status)]);
			rows.push(['DKIM', statusText(sending.dkim_status)]);
			rows.push(['SPF (MAIL FROM)', statusText(sending.spf_status)]);
			rows.push(['Verified', sending.verified_at ? formatTime(sending.verified_at) : 'Not yet']);
			rows.push(['Last checked', formatTime(sending.last_checked_at)]);
		}
		if (receiving) {
			rows.push(['Receiving domain', receiving.domain_name]);
			rows.push(['Receiving state', statusText(receiving.lifecycle_state)]);
			rows.push(['Inbound mail', statusText(receiving.inbound_mx_status)]);
		}
		technicalRecords = { title: 'Everyday email + replies — technical records', rows };
	}
	function openMarketingTechnical() {
		if (!marketing) return;
		technicalRecords = {
			title: 'Marketing email — technical records',
			rows: [
				['Sending domain', marketing.domain_name],
				['Root domain', marketing.dns_zone ?? '—'],
				['Ownership', statusText(marketing.ownership_status)],
				['DKIM', statusText(marketing.dkim_status)],
				['SPF', statusText(marketing.spf_status)],
				['Verified', marketing.verified_at ? formatTime(marketing.verified_at) : 'Not yet'],
				['Last checked', formatTime(marketing.last_checked_at)],
				['Branded links', marketing.click_domain_name ?? 'Not set up']
			]
		};
	}

	const everydayMenuItems = $derived.by((): MenuItem[] => {
		if (!sending) return [];
		const items: MenuItem[] = [{ label: 'Technical records', onSelect: openEverydayTechnical }];
		items.push({ label: 'Remove', onSelect: openRemoval, destructive: true });
		return items;
	});

	const marketingMenuItems = $derived.by((): MenuItem[] => {
		if (!marketing) return [];
		const items: MenuItem[] = [{ label: 'Technical records', onSelect: openMarketingTechnical }];
		const configured = Boolean(marketingQuery.data?.branded_links_configured);
		const clickOn =
			marketing.click_domain_status === 'working' ||
			marketing.click_domain_status === 'waiting_certificate' ||
			marketing.click_domain_status === 'problem';
		if (configured && clickOn) {
			items.push({
				label: 'Turn off branded links',
				onSelect: () => clickMutation.mutate({ domain: marketing, action: 'turn_off' })
			});
		} else if (configured && marketing.lifecycle_state === 'verified') {
			items.push({
				label: 'Turn on branded links',
				onSelect: () => clickMutation.mutate({ domain: marketing, action: 'turn_on' })
			});
		}
		if (marketing.click_domain_name) {
			items.push({
				label: 'Remove branded links',
				onSelect: () => (pendingBrandedRemoval = marketing),
				destructive: true
			});
		}
		return items;
	});

	const everydayDescription = $derived(
		sending
			? `${sending.domain_name} for sending${receiving ? ` · ${receiving.domain_name} for replies` : ''}`
			: 'UCRM will create mail. for sending and reply. for replies automatically — nothing to copy or paste.'
	);
	const everydayPrimaryLabel = $derived(
		everydayStatus === 'not_set_up'
			? 'Set up'
			: everydayStatus === 'problem'
				? "See what's wrong"
				: everydayStatus === 'removal_unfinished'
					? 'Finish removal'
					: 'Check'
	);
	function everydayPrimaryAction() {
		if (everydayStatus === 'not_set_up') openEverydaySetup();
		else if (everydayStatus === 'problem') openProblem('everyday');
		else if (everydayStatus === 'removal_unfinished') openRemoval();
		else everydayRecheckMutation.mutate();
	}

	const marketingDescription = $derived(
		marketing
			? `${marketing.domain_name} for campaign sending${marketing.click_domain_name ? ` · ${clickLabels[marketing.click_domain_status]} branded links` : ''}`
			: 'UCRM will create news. for campaign sending automatically — nothing to copy or paste.'
	);
	const marketingPrimaryLabel = $derived(
		marketingStatus === 'not_set_up'
			? 'Set up'
			: marketingStatus === 'problem'
				? "See what's wrong"
				: 'Check'
	);
	// A dialog opens clean, so an earlier action's error is not shown as if it came from this one.
	function openProblem(row: 'everyday' | 'marketing') {
		feedbackError = '';
		feedbackMessage = '';
		if (row === 'everyday') everydayProblemOpen = true;
		else marketingProblemOpen = true;
	}

	const dialogOpen = $derived(
		everydaySetupOpen ||
			marketingSetupOpen ||
			everydayProblemOpen ||
			marketingProblemOpen ||
			closeRequestOpen ||
			removalOpen
	);

	function marketingPrimaryAction() {
		if (marketingStatus === 'not_set_up') openMarketingSetup();
		else if (marketingStatus === 'problem') openProblem('marketing');
		else marketingRecheckMutation.mutate();
	}
</script>

<!-- A failure that happens while a dialog is open has to show inside it: the card's own alert sits behind
     the dialog's backdrop, where a failed Check or Set up would otherwise look like nothing happened. -->
{#snippet dialogError()}
	{#if feedbackError}<p class="email-card__error" role="alert">{feedbackError}</p>{/if}
{/snippet}

<div class="email-card">
	<div class="email-card__heading">
		<h3>Email</h3>
		<p>
			Provisioning is platform-managed on Amazon SES. A contractor can add senders only after a
			healthy domain is verified.
		</p>
	</div>

	{#if feedbackMessage}<p class="email-card__success" role="status">{feedbackMessage}</p>{/if}
	{#if feedbackError && !dialogOpen}<p class="email-card__error" role="alert">
			{feedbackError}
		</p>{/if}

	{#if setupRequest}
		<div class="email-card__request" role="status">
			<div class="email-card__row-main">
				<div class="email-card__row-heading">
					<strong>Email setup requested</strong>
					<Badge status="warning">Waiting on you</Badge>
				</div>
				<p>
					{setupRequest.root_domain} · email lives at {mailboxProviderLabel(
						setupRequest.mailbox_provider
					)} · asked {formatTime(setupRequest.created_at)}
				</p>
				{#if setupRequest.note}<p class="email-card__request-note">“{setupRequest.note}”</p>{/if}
			</div>
			<div class="email-card__row-actions">
				<Button size="small" onclick={openEverydaySetup}>Set up</Button>
				<Button size="small" variant="secondary" variation="subtle" onclick={openCloseRequest}
					>Close request</Button
				>
			</div>
		</div>
	{/if}

	<div class="email-card__rows">
		{#if operationalQuery.isPending}
			<LoadingSkeleton variant="text" label="Loading Everyday email" />
		{:else if operationalQuery.isError}
			<ErrorState
				title="Everyday email could not be loaded"
				description={operationalQuery.error instanceof Error
					? operationalQuery.error.message
					: 'Everyday email could not be loaded. Try again.'}
				retry={() => operationalQuery.refetch()}
			/>
		{:else}
			<div class="email-card__row">
				<div class="email-card__row-main">
					<div class="email-card__row-heading">
						<strong>Everyday email + replies</strong>
						<Badge status={statusTone[everydayStatus]}>{statusLabel[everydayStatus]}</Badge>
					</div>
					<p>{everydayDescription}</p>
				</div>
				<div class="email-card__row-actions">
					<Button
						size="small"
						variant="secondary"
						variation="subtle"
						loading={everydayRecheckMutation.isPending}
						onclick={everydayPrimaryAction}>{everydayPrimaryLabel}</Button
					>
					{#if everydayMenuItems.length > 0}
						<DropdownMenu
							items={everydayMenuItems}
							triggerLabel="More actions for Everyday email"
						/>
					{/if}
				</div>
			</div>
		{/if}

		{#if marketingQuery.isPending}
			<LoadingSkeleton variant="text" label="Loading Marketing email" />
		{:else if marketingQuery.isError}
			<ErrorState
				title="Marketing email could not be loaded"
				description={marketingQuery.error instanceof Error
					? marketingQuery.error.message
					: 'Marketing email could not be loaded. Try again.'}
				retry={() => marketingQuery.refetch()}
			/>
		{:else}
			<div class="email-card__row">
				<div class="email-card__row-main">
					<div class="email-card__row-heading">
						<strong>Marketing email</strong>
						<Badge status={statusTone[marketingStatus]}>{statusLabel[marketingStatus]}</Badge>
					</div>
					<p>{marketingDescription}</p>
				</div>
				<div class="email-card__row-actions">
					<Button
						size="small"
						variant="secondary"
						variation="subtle"
						loading={marketingRecheckMutation.isPending}
						onclick={marketingPrimaryAction}>{marketingPrimaryLabel}</Button
					>
					{#if marketingMenuItems.length > 0}
						<DropdownMenu
							items={marketingMenuItems}
							triggerLabel="More actions for Marketing email"
						/>
					{/if}
				</div>
			</div>
		{/if}
	</div>
</div>

<Dialog open={everydaySetupOpen} title="Set up Everyday email" onClose={closeEverydaySetup}>
	{#if everydayActivationResult}
		<div class="email-card__result">
			<p>
				{everydayActivationResult.replayed
					? `Everyday email was already set up for ${everydayActivationResult.root_domain}.`
					: `Everyday email is set up for ${everydayActivationResult.root_domain}. UCRM created ${everydayActivationResult.sending.domain_name} for sending and ${everydayActivationResult.receiving.domain_name} for replies.`}
			</p>
			<p class="email-card__result-note">
				The existing mailbox on {everydayActivationResult.root_domain} was left untouched. Use Check in
				a minute if it still shows "Setting up".
			</p>
			<div class="email-card__dialog-actions">
				<Button type="button" onclick={closeEverydaySetup}>Done</Button>
			</div>
		</div>
	{:else}
		<form class="email-card__form" onsubmit={submitEverydaySetup}>
			<p>
				Enter the contractor's root domain, such as <strong>yourbusiness.com</strong>. UCRM sets up
				<strong>mail.</strong> for sending and <strong>reply.</strong> for replies, writes the DNS through
				Cloudflare, and verifies Amazon SES. The existing root mailbox is never touched.
			</p>
			<Input
				id="everyday-root-domain"
				label="Root domain"
				placeholder="yourbusiness.com"
				bind:value={everydayRootDomain}
				invalid={Boolean(everydayFieldErrors.root_domain)}
				errorMessage={everydayFieldErrors.root_domain}
			/>
			{#if !everydayFieldErrors.root_domain}{@render dialogError()}{/if}
			<div class="email-card__dialog-actions">
				<Button type="submit" loading={everydayActivateMutation.isPending}>Set up</Button><Button
					type="button"
					variant="secondary"
					variation="subtle"
					onclick={closeEverydaySetup}>Cancel</Button
				>
			</div>
		</form>
	{/if}
</Dialog>

<Dialog open={closeRequestOpen} title="Close request" onClose={dismissCloseRequest}>
	{#if closeRequestOpen}
		<form class="email-card__form" onsubmit={submitCloseRequest}>
			<p>
				The contractor sees this note on their Email settings page. They can send a new request any
				time.
			</p>
			<Textarea
				id="close-request-note"
				label="Note for the contractor"
				rows={4}
				maxlength={1000}
				bind:value={closeNote}
				invalid={Boolean(closeFieldErrors.note)}
				errorMessage={closeFieldErrors.note}
			/>
			{#if !closeFieldErrors.note}{@render dialogError()}{/if}
			<div class="email-card__dialog-actions">
				<Button type="submit" loading={closeRequestMutation.isPending}>Close request</Button><Button
					type="button"
					variant="secondary"
					variation="subtle"
					onclick={dismissCloseRequest}>Keep open</Button
				>
			</div>
		</form>
	{/if}
</Dialog>

<Dialog open={marketingSetupOpen} title="Set up Marketing email" onClose={closeMarketingSetup}>
	{#if marketingActivationResult}
		<div class="email-card__result">
			<p>
				{marketingActivationResult.replayed
					? `Marketing email was already set up for ${marketingActivationResult.root_domain}.`
					: `Marketing email is set up for ${marketingActivationResult.root_domain}. UCRM created ${marketingActivationResult.marketing.domain_name} for campaign sending.`}
			</p>
			<p class="email-card__result-note">
				DNS was written automatically. Use Check in a minute if it still shows "Setting up".
			</p>
			<div class="email-card__dialog-actions">
				<Button type="button" onclick={closeMarketingSetup}>Done</Button>
			</div>
		</div>
	{:else}
		<form class="email-card__form" onsubmit={submitMarketingSetup}>
			<p>
				Enter the contractor's root domain, such as <strong>yourbusiness.com</strong>. UCRM sets up
				<strong>news.</strong> for campaign sending and writes the DNS through Cloudflare automatically
				— nothing to copy or paste.
			</p>
			<Input
				id="marketing-root-domain"
				label="Root domain"
				placeholder="yourbusiness.com"
				bind:value={marketingRootDomain}
				invalid={Boolean(marketingFieldErrors.root_domain)}
				errorMessage={marketingFieldErrors.root_domain}
			/>
			{#if !marketingFieldErrors.root_domain}{@render dialogError()}{/if}
			<div class="email-card__dialog-actions">
				<Button type="submit" loading={marketingActivateMutation.isPending}>Set up</Button><Button
					type="button"
					variant="secondary"
					variation="subtle"
					onclick={closeMarketingSetup}>Cancel</Button
				>
			</div>
		</form>
	{/if}
</Dialog>

<Dialog
	open={everydayProblemOpen}
	title="What's wrong with Everyday email"
	onClose={() => (everydayProblemOpen = false)}
>
	<div class="email-card__problem">
		<ul>
			{#each everydayProblemReasons as reason (reason)}<li>{reason}</li>{/each}
		</ul>
		{@render dialogError()}
		<div class="email-card__dialog-actions">
			<Button
				type="button"
				loading={everydayRecheckMutation.isPending}
				onclick={() => everydayRecheckMutation.mutate()}>Check again</Button
			><Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (everydayProblemOpen = false)}>Close</Button
			>
		</div>
	</div>
</Dialog>

<Dialog
	open={marketingProblemOpen}
	title="What's wrong with Marketing email"
	onClose={() => (marketingProblemOpen = false)}
>
	<div class="email-card__problem">
		<ul>
			{#each marketingProblemReasons as reason (reason)}<li>{reason}</li>{/each}
		</ul>
		{@render dialogError()}
		<div class="email-card__dialog-actions">
			<Button
				type="button"
				loading={marketingRecheckMutation.isPending}
				onclick={() => marketingRecheckMutation.mutate()}>Check again</Button
			><Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (marketingProblemOpen = false)}>Close</Button
			>
		</div>
	</div>
</Dialog>

<Dialog
	open={Boolean(technicalRecords)}
	title={technicalRecords?.title ?? 'Technical records'}
	onClose={() => (technicalRecords = null)}
>
	{#if technicalRecords}
		<dl class="email-card__technical">
			{#each technicalRecords.rows as [key, value] (key)}
				<div>
					<dt>{key}</dt>
					<dd>{value}</dd>
				</div>
			{/each}
		</dl>
	{/if}
	<div class="email-card__dialog-actions">
		<Button type="button" onclick={() => (technicalRecords = null)}>Close</Button>
	</div>
</Dialog>

<ConfirmDialog
	open={removalOpen}
	title="Remove Everyday email"
	tone="critical"
	confirmLabel="Remove"
	destructive
	loading={removalMutation.isPending}
	confirmDisabled={!removalPreviewQuery.data?.can_remove ||
		removalConfirmation !== sending?.domain_name ||
		!removalReason.trim()}
	onConfirm={() => removalMutation.mutate()}
	onClose={closeRemoval}
>
	{#if removalPreviewQuery.isPending}
		<LoadingSkeleton variant="text" label="Loading removal impact" />
	{:else if removalPreviewQuery.isError}
		<p class="email-card__error" role="alert">
			{removalPreviewQuery.error instanceof Error
				? removalPreviewQuery.error.message
				: 'The removal impact could not be loaded.'}
		</p>
	{:else if removalPreviewQuery.data}
		<p class="email-card__impact">
			{removalPreviewQuery.data.impact.live_sender_count} active senders would be affected. Customer replies{receiving
				? ` to ${receiving.domain_name}`
				: ''} stop coming into the inbox too.
		</p>
		<Input
			id="remove-domain-confirmation"
			label={`Type ${sending?.domain_name ?? 'the domain'} to confirm`}
			bind:value={removalConfirmation}
		/>
		<Input id="remove-domain-reason" label="Private removal reason" bind:value={removalReason} />
		{@render dialogError()}
		{#if !removalPreviewQuery.data.can_remove}<p class="email-card__error" role="alert">
				Remove the affected senders first.
			</p>{/if}
	{/if}
</ConfirmDialog>

<ConfirmDialog
	open={Boolean(pendingBrandedRemoval)}
	title="Remove branded links"
	tone="critical"
	confirmLabel="Remove branded links"
	destructive
	loading={clickMutation.isPending}
	onConfirm={() => {
		if (pendingBrandedRemoval)
			clickMutation.mutate({ domain: pendingBrandedRemoval, action: 'remove' });
	}}
	onClose={() => {
		if (!clickMutation.isPending) pendingBrandedRemoval = null;
	}}
>
	<p>
		Campaign links go back to Amazon's address right away, and
		<strong>{pendingBrandedRemoval?.click_domain_name}</strong> is deleted along with its certificate
		and DNS record. Turning branded links on again later takes a few minutes while Amazon issues a new
		certificate.
	</p>
</ConfirmDialog>

<style lang="scss">
	.email-card {
		display: grid;
		gap: var(--space-base);
	}
	.email-card__heading h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.email-card__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.email-card__success {
		color: var(--color-success--onSurface);
	}
	.email-card__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.email-card__rows {
		display: grid;
		gap: var(--space-base);
	}
	.email-card__row {
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
	.email-card__request {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.email-card__request-note {
		font-style: italic;
	}
	.email-card__row-main {
		display: grid;
		gap: var(--space-smallest);
		min-width: 0;
	}
	.email-card__row-heading {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.email-card__row-heading strong {
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
	}
	.email-card__row-main p {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}
	.email-card__row-actions {
		display: flex;
		flex: 0 0 auto;
		align-items: center;
		gap: var(--space-small);
	}
	.email-card__form,
	.email-card__result,
	.email-card__problem {
		display: grid;
		gap: var(--space-base);
	}
	.email-card__form > p:not(.email-card__error),
	.email-card__result > p {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.email-card__result-note {
		font-size: var(--typography--fontSize-small);
	}
	.email-card__problem ul {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding-left: var(--space-large);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.email-card__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.email-card__impact {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.email-card__technical {
		display: grid;
		gap: var(--space-small);
		margin: 0;
	}
	.email-card__technical > div {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-base);
		padding-bottom: var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.email-card__technical dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.email-card__technical dd {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		text-align: right;
		overflow-wrap: anywhere;
	}
	@media (max-width: 639px) {
		.email-card__row {
			flex-direction: column;
			align-items: stretch;
		}
		.email-card__row-actions {
			justify-content: flex-end;
		}
	}
</style>
