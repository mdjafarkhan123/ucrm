<script lang="ts">
	import { createQuery, keepPreviousData, useQueryClient } from '@tanstack/svelte-query';
	import linkIcon from '@tabler/icons/outline/link.svg?raw';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { APPLICATION_STAGE_LABELS, type ApplicationCandidate } from '$lib/jafar/lead-history';
	import {
		jafarDealsKey,
		jafarLeadApplicationCandidatesKey,
		jafarProspectKey,
		jafarProspectsKey
	} from '$lib/jafar/query-keys';
	import {
		APPLICATION_CANDIDATES_STALE_MS,
		fetchApplicationCandidates,
		refreshLead,
		sendLeadWrite
	} from '$lib/jafar/lead-page-api';

	// Jafar business management B2: linking an Application someone submitted on the website to the Lead it
	// belongs to, so the business has one history instead of two records. With no search it offers Applications
	// that share this Lead's name, email or phone; one already linked to another business is shown but refused.
	let {
		leadId,
		businessName,
		onClose
	}: {
		leadId: string;
		businessName: string;
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let typed = $state('');
	let search = $state('');
	// Asks once typing pauses, not per keystroke.
	$effect(() => {
		const next = typed.trim();
		const handle = setTimeout(() => (search = next), 300);
		return () => clearTimeout(handle);
	});

	const candidates = createQuery(() => ({
		queryKey: jafarLeadApplicationCandidatesKey(leadId, search),
		queryFn: () => fetchApplicationCandidates(leadId, search),
		staleTime: APPLICATION_CANDIDATES_STALE_MS,
		placeholderData: keepPreviousData
	}));

	let linkingId = $state<string | null>(null);
	let error = $state('');

	async function link(candidate: ApplicationCandidate) {
		if (linkingId) return;
		linkingId = candidate.id;
		error = '';
		const result = await sendLeadWrite(
			`/api/jafar/leads/${encodeURIComponent(leadId)}/applications`,
			'POST',
			{ application_id: candidate.id }
		);
		linkingId = null;
		if (!result.ok) {
			error = result.error;
			return;
		}
		await Promise.all([
			refreshLead(queryClient, leadId),
			// B5: linking an Application that is already paid makes the business's Deal Won.
			queryClient.invalidateQueries({ queryKey: jafarDealsKey }),
			queryClient.invalidateQueries({ queryKey: jafarProspectsKey }),
			queryClient.invalidateQueries({ queryKey: jafarProspectKey(candidate.id) })
		]);
		toast.success('Application linked', `${candidate.business_name} is now part of this Lead.`);
		onClose();
	}

	const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' });
</script>

<Dialog open={true} title="Link an Application" initialFocusId="link-application-search" {onClose}>
	<div class="link-application">
		<p class="link-application__intro">
			Did {businessName} apply on the website? Link their Application so everything about them stays in
			one place.
		</p>

		<SearchInput
			id="link-application-search"
			label="Search Applications"
			placeholder="Business, contact name or email"
			bind:value={typed}
		/>

		<p class="link-application__caption" aria-live="polite">
			{search ? `Applications matching “${search}”` : 'Applications that look like this business'}
		</p>

		{#if candidates.isPending}
			<LoadingSkeleton variant="table" rows={3} label="Loading Applications" />
		{:else if candidates.isError}
			<p class="link-application__error" role="alert">{candidates.error.message}</p>
		{:else if candidates.data.length === 0}
			<EmptyState
				title={search ? 'No matching Applications' : 'No look-alike Applications'}
				description={search
					? 'Try the business name, the person who applied, or their email.'
					: 'Search by business name, contact name or email to find one.'}
			/>
		{:else}
			<ul
				class={[
					'link-application__list',
					candidates.isPlaceholderData && 'link-application__list--refreshing'
				]}
			>
				{#each candidates.data as candidate (candidate.id)}
					{@const linkedHere = candidate.linked_to?.id === leadId}
					{@const linkedElsewhere = candidate.linked_to && !linkedHere}
					<li class="link-application__item">
						<div class="link-application__who">
							<strong>{candidate.business_name}</strong>
							<span>{candidate.main_contact_name} · {candidate.main_contact_email}</span>
							<span class="link-application__meta">
								Applied {dateFormat.format(new Date(candidate.submitted_at))}
								<Badge size="small" dot={false} status="inactive"
									>{APPLICATION_STAGE_LABELS[candidate.stage] ?? candidate.stage}</Badge
								>
							</span>
							{#if linkedElsewhere}
								<span class="link-application__note">
									Already linked to {candidate.linked_to?.business_name}
								</span>
							{/if}
						</div>
						{#if linkedHere}
							<Badge size="small" status="success">Linked</Badge>
						{:else}
							<Button
								variant="secondary"
								size="small"
								disabled={Boolean(linkedElsewhere) ||
									(linkingId !== null && linkingId !== candidate.id)}
								loading={linkingId === candidate.id}
								onclick={() => link(candidate)}
							>
								<!-- eslint-disable svelte/no-at-html-tags -->
								<span class="link-application__button-icon" aria-hidden="true"
									>{@html linkIcon}</span
								>Link
								<!-- eslint-enable svelte/no-at-html-tags -->
							</Button>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}

		{#if error}
			<p class="link-application__error" role="alert">{error}</p>
		{/if}
	</div>
</Dialog>

<style lang="scss">
	.link-application {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__intro,
		&__caption {
			margin: 0;
			color: var(--color-text--secondary);
		}

		&__caption {
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__list {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			list-style: none;
			transition: opacity var(--timing-quick);
		}

		&__list--refreshing {
			opacity: 0.6;
		}

		&__item {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-slim) var(--space-base);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__who {
			display: flex;
			min-width: 0;
			flex-direction: column;
			gap: 2px;
			overflow-wrap: anywhere;

			strong {
				color: var(--color-heading);
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__meta {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__note {
			color: var(--color-warning--onSurface) !important;
			font-weight: 600;
		}

		&__button-icon {
			display: inline-flex;
			margin-right: var(--space-smaller);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
