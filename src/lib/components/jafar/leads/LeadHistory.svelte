<script lang="ts">
	import { createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import phoneOutIcon from '@tabler/icons/outline/phone-outgoing.svg?raw';
	import phoneInIcon from '@tabler/icons/outline/phone-incoming.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import whatsappIcon from '@tabler/icons/outline/brand-whatsapp.svg?raw';
	import linkedinIcon from '@tabler/icons/outline/brand-linkedin.svg?raw';
	import instagramIcon from '@tabler/icons/outline/brand-instagram.svg?raw';
	import facebookIcon from '@tabler/icons/outline/brand-facebook.svg?raw';
	import formsIcon from '@tabler/icons/outline/forms.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import flagIcon from '@tabler/icons/outline/flag.svg?raw';
	import calendarPlusIcon from '@tabler/icons/outline/calendar-plus.svg?raw';
	import calendarCheckIcon from '@tabler/icons/outline/calendar-check.svg?raw';
	import calendarXIcon from '@tabler/icons/outline/calendar-x.svg?raw';
	import linkIcon from '@tabler/icons/outline/link.svg?raw';
	import unlinkIcon from '@tabler/icons/outline/unlink.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import sparklesIcon from '@tabler/icons/outline/sparkles.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import shieldXIcon from '@tabler/icons/outline/shield-x.svg?raw';
	import arrowBackIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';
	import bellOffIcon from '@tabler/icons/outline/bell-off.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import briefcaseOffIcon from '@tabler/icons/outline/briefcase-off.svg?raw';
	import stageIcon from '@tabler/icons/outline/arrows-right-left.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt-2.svg?raw';
	import thumbDownIcon from '@tabler/icons/outline/thumb-down.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import discountIcon from '@tabler/icons/outline/discount.svg?raw';
	import trophyIcon from '@tabler/icons/outline/trophy.svg?raw';
	import userCheckIcon from '@tabler/icons/outline/user-check.svg?raw';
	import calendarClockIcon from '@tabler/icons/outline/calendar-clock.svg?raw';
	import userXIcon from '@tabler/icons/outline/user-x.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import HistoryEntryForm from './HistoryEntryForm.svelte';
	import {
		CALL_OUTCOME_LABELS,
		CONTACT_CHANNEL_LABELS,
		applicationHref,
		contactHeadline,
		detailChangeLine,
		approvalMethodLine,
		withdrawnBecause,
		isEditableEntry,
		type ContactChannel,
		type HistoryEntry,
		type HistoryPage,
		type LeadContactMethodDetail
	} from '$lib/jafar/lead-history';
	import { LEAD_SOURCE_LABELS, LEAD_STATUS_LABELS, type LeadStatus } from '$lib/jafar/leads';
	import {
		DEAL_STAGE_LABELS,
		LOST_REASON_LABELS,
		type DealStage,
		type LostReason
	} from '$lib/jafar/deals';
	import { formatUsd } from '$lib/jafar/packages';
	import { jafarLeadHistoryKey } from '$lib/jafar/query-keys';
	import { fetchOlderHistory, refreshLead, sendLeadWrite } from '$lib/jafar/lead-page-api';

	// Jafar business management B2: everything that happened with one business, newest first, in one list --
	// notes, contact logged from outside UCRM, status and next-action changes, and Applications. The page brings
	// the newest entries; "Show older" continues from where they end. Notes and logged contact can be corrected
	// or deleted; what the app recorded by itself cannot.
	let {
		leadId,
		history,
		contactMethods
	}: {
		leadId: string;
		history: HistoryPage;
		contactMethods: LeadContactMethodDetail[];
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// Older pages are keyed by where the newest page ends, so a new note (which moves that point) starts them
	// afresh instead of leaving a gap. Nothing loads until "Show older" is pressed.
	let olderWanted = $state(false);
	const older = createInfiniteQuery<HistoryPage>(() => ({
		queryKey: [...jafarLeadHistoryKey(leadId), history.next_cursor] as const,
		queryFn: ({ pageParam }) => fetchOlderHistory(leadId, pageParam as string),
		initialPageParam: history.next_cursor,
		getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined,
		enabled: olderWanted && Boolean(history.next_cursor)
	}));

	const entries = $derived.by(() => {
		const seen: Record<string, true> = {};
		const all = [
			...history.entries,
			...(olderWanted ? (older.data?.pages ?? []) : []).flatMap((p) => p.entries)
		];
		return all.filter((entry) => {
			if (seen[entry.id]) return false;
			seen[entry.id] = true;
			return true;
		});
	});
	const hasMore = $derived(olderWanted ? Boolean(older.hasNextPage) : Boolean(history.next_cursor));

	function showOlder() {
		if (!olderWanted) olderWanted = true;
		else void older.fetchNextPage();
	}

	// --- How each entry reads -------------------------------------------------------------------------

	const CHANNEL_ICONS: Record<ContactChannel, string> = {
		email: mailIcon,
		phone: phoneOutIcon,
		text: messageIcon,
		whatsapp: whatsappIcon,
		linkedin: linkedinIcon,
		instagram: instagramIcon,
		facebook: facebookIcon,
		contact_form: formsIcon,
		in_person: usersIcon,
		other: messageIcon
	};

	function iconFor(entry: HistoryEntry) {
		switch (entry.kind) {
			case 'note':
				return notesIcon;
			case 'contact':
				if (entry.contact_channel === 'phone' && entry.contact_direction === 'inbound')
					return phoneInIcon;
				return entry.contact_channel ? CHANNEL_ICONS[entry.contact_channel] : messageIcon;
			case 'status_changed':
				return flagIcon;
			case 'next_action_set':
				return calendarPlusIcon;
			case 'next_action_done':
				return calendarCheckIcon;
			case 'next_action_cleared':
				return calendarXIcon;
			case 'application_linked':
				return linkIcon;
			case 'application_unlinked':
				return unlinkIcon;
			case 'application_submitted':
				return fileTextIcon;
			case 'details_changed':
				return pencilIcon;
			case 'contact_approved':
				return shieldCheckIcon;
			case 'approval_withdrawn':
				return shieldXIcon;
			case 'sent_back':
				return arrowBackIcon;
			case 'do_not_contact_set':
				return bellOffIcon;
			case 'do_not_contact_cleared':
				return bellIcon;
			case 'lead_added':
				return sparklesIcon;
			case 'deal_started':
				return briefcaseIcon;
			case 'deal_stage_changed':
				return stageIcon;
			case 'pricing_shared':
				return receiptIcon;
			case 'deal_lost':
				return thumbDownIcon;
			case 'deal_reopened':
				return refreshIcon;
			case 'deal_terms_changed':
				return discountIcon;
			case 'deal_removed':
				return briefcaseOffIcon;
			case 'deal_won':
				return trophyIcon;
			case 'setup_owner_changed':
			case 'owner_changed':
				return userCheckIcon;
			case 'call_booked':
				return calendarPlusIcon;
			case 'call_moved':
				return calendarClockIcon;
			case 'call_held':
				return calendarCheckIcon;
			case 'call_no_show':
				return userXIcon;
			case 'call_cancelled':
				return calendarXIcon;
			default:
				return historyIcon;
		}
	}

	/** "Pro · $129 a month · $1,290 a year", as it was shared. */
	function sharedPackageLine(shared: {
		name: string;
		monthly_price_usd_cents?: number;
		yearly_price_usd_cents?: number;
	}) {
		const parts = [shared.name];
		if (shared.monthly_price_usd_cents !== undefined)
			parts.push(`${formatUsd(shared.monthly_price_usd_cents)} a month`);
		if (shared.yearly_price_usd_cents !== undefined)
			parts.push(`${formatUsd(shared.yearly_price_usd_cents)} a year`);
		return parts.join(' · ');
	}

	function headline(entry: HistoryEntry) {
		const details = entry.details ?? {};
		switch (entry.kind) {
			case 'note':
				return 'Note';
			case 'contact':
				return entry.contact_direction && entry.contact_channel
					? contactHeadline(entry.contact_direction, entry.contact_channel)
					: 'Contact logged';
			case 'status_changed':
				return `Status changed to ${details.to ? LEAD_STATUS_LABELS[details.to as LeadStatus] : 'another status'}`;
			case 'next_action_set':
				return 'Next action set';
			case 'next_action_done':
				return 'Next action done';
			case 'next_action_cleared':
				return 'Next action removed';
			case 'application_linked':
				return 'Application linked';
			case 'application_unlinked':
				return 'Application unlinked';
			case 'application_submitted':
				return 'Application submitted';
			case 'details_changed':
				return 'Details changed';
			case 'contact_approved':
				return 'Approved for first contact';
			case 'approval_withdrawn':
				return `Approval withdrawn ${withdrawnBecause(details.reason)}`.trim();
			case 'sent_back':
				return 'Sent back for more research';
			case 'do_not_contact_set':
				return 'Asked not to be contacted';
			case 'do_not_contact_cleared':
				return 'Contact allowed again';
			case 'lead_added':
				return 'Lead added';
			case 'deal_started':
				return `Deal started at ${details.stage ? DEAL_STAGE_LABELS[details.stage] : 'its first stage'}`;
			case 'deal_stage_changed':
				return `Deal moved to ${details.to ? DEAL_STAGE_LABELS[details.to as DealStage] : 'another stage'}`;
			case 'pricing_shared':
				return 'Pricing shared';
			case 'deal_lost':
				return 'Deal marked Lost';
			case 'deal_reopened':
				return `Deal reopened at ${details.to ? DEAL_STAGE_LABELS[details.to as DealStage] : 'its last stage'}`;
			case 'deal_terms_changed':
				return details.terms ? 'Special terms agreed' : 'Special terms removed';
			case 'deal_removed':
				return 'Deal removed';
			case 'deal_won':
				return 'Deal Won — payment confirmed';
			case 'setup_owner_changed':
				return `Setup now looked after by ${details.to || 'Jafar'}`;
			case 'owner_changed':
				return `Now owned by ${details.to || 'Jafar'}`;
			case 'call_booked':
				return 'Call booked';
			case 'call_moved':
				return 'Call moved';
			case 'call_held':
				return 'Call held';
			case 'call_no_show':
				return "They didn't show for the call";
			case 'call_cancelled':
				return 'Call cancelled';
			default:
				return 'Update';
		}
	}

	/** "Tue 14 Oct, 3:00 pm" for a call's time, in this browser's clock. */
	const callFormat = new Intl.DateTimeFormat(undefined, {
		weekday: 'short',
		day: 'numeric',
		month: 'short',
		hour: 'numeric',
		minute: '2-digit'
	});

	function formatDay(day: string) {
		const [year, month, date] = day.split('-').map(Number);
		return new Intl.DateTimeFormat(undefined, {
			day: 'numeric',
			month: 'short',
			year: 'numeric'
		}).format(new Date(year, month - 1, date));
	}

	const timeFormat = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
	const dayFormat = new Intl.DateTimeFormat(undefined, {
		weekday: 'long',
		day: 'numeric',
		month: 'long',
		year: 'numeric'
	});
	const fullFormat = new Intl.DateTimeFormat(undefined, {
		dateStyle: 'medium',
		timeStyle: 'short'
	});

	function dayKey(iso: string) {
		const date = new Date(iso);
		return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
	}

	function dayHeading(iso: string) {
		const now = Date.now();
		if (dayKey(iso) === dayKey(new Date(now).toISOString())) return 'Today';
		if (dayKey(iso) === dayKey(new Date(now - 86_400_000).toISOString())) return 'Yesterday';
		return dayFormat.format(new Date(iso));
	}

	// Entries arrive newest first, so each day's entries sit next to each other.
	const groups = $derived.by(() => {
		const list: { key: string; heading: string; items: HistoryEntry[] }[] = [];
		for (const entry of entries) {
			const key = dayKey(entry.occurred_at);
			const last = list.at(-1);
			if (last?.key === key) last.items.push(entry);
			else list.push({ key, heading: dayHeading(entry.occurred_at), items: [entry] });
		}
		return list;
	});

	// --- Correcting and deleting ----------------------------------------------------------------------

	let editingEntry = $state<HistoryEntry | null>(null);
	let deletingEntry = $state<HistoryEntry | null>(null);
	let deleting = $state(false);

	async function confirmDelete() {
		const entry = deletingEntry;
		if (!entry || deleting) return;
		deleting = true;
		const result = await sendLeadWrite(
			`/api/jafar/leads/${encodeURIComponent(leadId)}/history/${encodeURIComponent(entry.id)}`,
			'DELETE'
		);
		deleting = false;
		if (!result.ok) {
			toast.error('That entry could not be deleted.', result.error);
			return;
		}
		await refreshLead(queryClient, leadId);
		deletingEntry = null;
		toast.success(entry.kind === 'note' ? 'Note deleted' : 'Logged contact deleted');
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if entries.length === 0}
	<EmptyState
		title="Nothing here yet"
		description="Notes and contact you log will show here, newest first."
		icon={historyIcon}
	/>
{:else}
	<div class="lead-history">
		{#each groups as group (group.key)}
			<section class="lead-history__day" aria-label={group.heading}>
				<h3 class="lead-history__day-heading">{group.heading}</h3>
				<ol class="lead-history__list">
					{#each group.items as entry (entry.id)}
						<li
							class={[
								'lead-history__item',
								`lead-history__item--${entry.kind}`,
								entry.kind === 'contact' && `lead-history__item--${entry.contact_direction}`
							]}
						>
							<span class="lead-history__icon" aria-hidden="true">{@html iconFor(entry)}</span>
							<div class="lead-history__body">
								<div class="lead-history__top">
									<p class="lead-history__headline">
										<strong>{headline(entry)}</strong>
										{#if entry.call_outcome}
											<Badge
												size="small"
												status={entry.call_outcome === 'connected' ? 'success' : 'inactive'}
												>{CALL_OUTCOME_LABELS[entry.call_outcome]}</Badge
											>
										{/if}
									</p>
									{#if isEditableEntry(entry)}
										<DropdownMenu
											triggerLabel={`Options for this ${entry.kind === 'note' ? 'note' : 'logged contact'}`}
											items={[
												{ label: 'Edit', icon: pencilIcon, onSelect: () => (editingEntry = entry) },
												{
													label: 'Delete',
													icon: trashIcon,
													destructive: true,
													onSelect: () => (deletingEntry = entry)
												}
											]}
										/>
									{/if}
								</div>

								{#if entry.kind === 'contact' && entry.contact_method}
									<p class="lead-history__detail">
										{entry.contact_direction === 'outbound' ? 'To' : 'From'}
										<span class="lead-history__value">{entry.contact_method.value}</span>
										{#if entry.contact_method.removed}
											<Badge size="small" dot={false} status="inactive">Removed</Badge>
										{/if}
									</p>
								{:else if entry.kind === 'contact' && entry.contact_channel && entry.contact_channel !== 'in_person'}
									<p class="lead-history__detail">
										{CONTACT_CHANNEL_LABELS[entry.contact_channel]}
									</p>
								{/if}

								{#if entry.kind === 'status_changed' && entry.details?.from}
									<p class="lead-history__detail">
										Was {LEAD_STATUS_LABELS[entry.details.from as LeadStatus]}
									</p>
								{/if}

								{#if (entry.kind === 'next_action_set' || entry.kind === 'next_action_done' || entry.kind === 'next_action_cleared') && entry.details?.next_action}
									<p
										class={[
											'lead-history__detail',
											entry.kind === 'next_action_cleared' && 'lead-history__detail--past'
										]}
									>
										<span class="lead-history__value">{entry.details.next_action}</span>
										{#if entry.details.due_at}
											· due {callFormat.format(new Date(entry.details.due_at))}
										{:else if entry.details.due_on}
											· due {formatDay(entry.details.due_on)}
										{/if}
									</p>
								{/if}

								{#if entry.kind.startsWith('call_') && entry.details?.starts_at}
									<p
										class={[
											'lead-history__detail',
											entry.kind === 'call_cancelled' && 'lead-history__detail--past'
										]}
									>
										{#if entry.details.title}
											<span class="lead-history__value">{entry.details.title}</span> ·
										{/if}
										{#if entry.kind === 'call_moved' && entry.details.from_starts_at}
											{callFormat.format(new Date(entry.details.from_starts_at))} →
										{/if}
										{callFormat.format(new Date(entry.details.starts_at))}
									</p>
								{/if}

								{#if entry.kind === 'details_changed' && entry.details?.changes?.length}
									<ul class="lead-history__changes">
										{#each entry.details.changes as change, index (index)}
											<li>{detailChangeLine(change)}</li>
										{/each}
									</ul>
								{/if}

								{#if (entry.kind === 'contact_approved' || entry.kind === 'approval_withdrawn') && entry.details?.methods?.length}
									<ul class="lead-history__changes">
										{#each entry.details.methods as method, index (index)}
											<li>{approvalMethodLine(method)}</li>
										{/each}
									</ul>
								{/if}

								{#if (entry.kind === 'sent_back' || entry.kind === 'do_not_contact_set' || entry.kind === 'do_not_contact_cleared') && entry.details?.reason}
									<p class="lead-history__detail">“{entry.details.reason}”</p>
								{/if}

								{#if entry.kind === 'deal_stage_changed' && entry.details?.from}
									<p class="lead-history__detail">
										Was {DEAL_STAGE_LABELS[entry.details.from as DealStage]}
									</p>
								{/if}

								{#if entry.kind === 'pricing_shared' && entry.details?.packages?.length}
									<ul class="lead-history__changes">
										{#each entry.details.packages as shared, index (index)}
											<li>{sharedPackageLine(shared)}</li>
										{/each}
									</ul>
								{/if}

								{#if entry.kind === 'deal_lost' && entry.details?.reason}
									<p class="lead-history__detail">
										{LOST_REASON_LABELS[entry.details.reason as LostReason] ?? entry.details.reason}
										{#if entry.details.from}
											· was at {DEAL_STAGE_LABELS[entry.details.from as DealStage]}
										{/if}
									</p>
									{#if entry.details.note}
										<p class="lead-history__detail">“{entry.details.note}”</p>
									{/if}
								{/if}

								{#if entry.kind === 'deal_terms_changed' && entry.details?.terms}
									<p class="lead-history__detail">“{entry.details.terms}”</p>
								{/if}

								{#if entry.kind === 'deal_removed' && entry.details?.stage}
									<p class="lead-history__detail">
										It was at {DEAL_STAGE_LABELS[entry.details.stage]}
									</p>
								{/if}

								{#if entry.kind === 'deal_won'}
									<p class="lead-history__detail">
										{[
											entry.details?.package_name,
											entry.details?.amount_usd_cents !== undefined
												? `${formatUsd(entry.details.amount_usd_cents)} received`
												: null,
											entry.details?.from
												? `was at ${DEAL_STAGE_LABELS[entry.details.from as DealStage]}`
												: null
										]
											.filter(Boolean)
											.join(' · ')}
									</p>
								{/if}

								{#if entry.kind === 'setup_owner_changed'}
									<p class="lead-history__detail">Was {entry.details?.from || 'Jafar'}</p>
								{/if}

								{#if entry.kind === 'owner_changed'}
									<p class="lead-history__detail">
										Was {entry.details?.from || 'Jafar'}{entry.details?.reason === 'removed'
											? ' · they left the team'
											: ''}
									</p>
								{/if}

								{#if entry.kind === 'lead_added' && entry.details?.source}
									<p class="lead-history__detail">
										Found through {LEAD_SOURCE_LABELS[entry.details.source]}
									</p>
								{/if}

								{#if entry.application_id && entry.details?.business_name}
									<p class="lead-history__detail">
										<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- applicationHref resolves the path. -->
										<a class="lead-history__link" href={applicationHref(entry.application_id)}
											>{entry.details.business_name}</a
										>
									</p>
								{/if}

								{#if entry.body}
									<p class="lead-history__text">{entry.body}</p>
								{/if}

								<p class="lead-history__meta">
									<time
										datetime={entry.occurred_at}
										title={fullFormat.format(new Date(entry.occurred_at))}
										>{timeFormat.format(new Date(entry.occurred_at))}</time
									>
									{#if entry.actor}<span>· {entry.actor}</span>{/if}
									{#if entry.kind === 'application_submitted'}<span>· through the website</span
										>{/if}
									{#if entry.edited_at}<span
											title={`Edited ${fullFormat.format(new Date(entry.edited_at))}`}
											>· edited</span
										>{/if}
								</p>
							</div>
						</li>
					{/each}
				</ol>
			</section>
		{/each}

		{#if older.isError}
			<p class="lead-history__error" role="alert">{older.error.message}</p>
		{/if}
		{#if hasMore}
			<div class="lead-history__more">
				<Button variant="secondary" size="small" loading={older.isFetching} onclick={showOlder}>
					Show older
				</Button>
			</div>
		{:else if olderWanted}
			<p class="lead-history__end">That is the whole history.</p>
		{/if}
	</div>
{/if}

{#if editingEntry}
	<Dialog
		open={true}
		title={editingEntry.kind === 'note' ? 'Edit note' : 'Edit logged contact'}
		onClose={() => (editingEntry = null)}
	>
		<HistoryEntryForm
			{leadId}
			{contactMethods}
			entry={editingEntry}
			idPrefix="history-edit"
			onSaved={() => (editingEntry = null)}
			onCancel={() => (editingEntry = null)}
		/>
	</Dialog>
{/if}

{#if deletingEntry}
	<ConfirmDialog
		open={true}
		title={deletingEntry.kind === 'note' ? 'Delete this note?' : 'Delete this logged contact?'}
		icon={trashIcon}
		tone="critical"
		destructive
		confirmLabel="Delete"
		loading={deleting}
		onConfirm={confirmDelete}
		onClose={() => (deletingEntry = null)}
	>
		<p>It is removed from this Lead's history for everyone. This cannot be undone.</p>
	</ConfirmDialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.lead-history {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__day-heading {
			margin: 0 0 var(--space-small);
			padding-bottom: var(--space-smaller);
			border-bottom: var(--border-base) solid var(--color-border--section);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			letter-spacing: var(--typography--letterSpacing-loose);
			text-transform: uppercase;
		}

		&__list {
			position: relative;
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			position: relative;
			display: flex;
			align-items: flex-start;
			gap: var(--space-base);
			padding-bottom: var(--space-base);

			// The line joining one entry's icon to the next.
			&:not(:last-child)::before {
				content: '';
				position: absolute;
				top: 36px;
				bottom: 4px;
				left: 17px;
				width: 2px;
				border-radius: 1px;
				background: var(--color-border);
			}
		}

		&__icon {
			display: grid;
			width: 36px;
			height: 36px;
			flex: 0 0 auto;
			place-items: center;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			color: var(--color-icon);

			:global(svg) {
				display: block;
				width: 18px;
				height: 18px;
			}
		}

		&__item--note &__icon {
			border-color: transparent;
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
		}

		&__item--outbound &__icon {
			border-color: transparent;
			background: var(--color-informative--surface);
			color: var(--color-informative--onSurface);
		}

		&__item--inbound &__icon {
			border-color: transparent;
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);
		}

		&__body {
			display: flex;
			min-width: 0;
			flex: 1;
			flex-direction: column;
			gap: var(--space-smaller);
			padding-top: var(--space-smaller);
		}

		&__top {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-small);
			min-height: 28px;
		}

		&__headline {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-base);
		}

		&__detail,
		&__meta {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			overflow-wrap: anywhere;
		}

		&__detail--past &__value {
			text-decoration: line-through;
			text-decoration-color: var(--color-text--secondary);
		}

		&__value {
			color: var(--color-text);
			font-weight: 600;
		}

		&__changes {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			margin: 0;
			padding-left: var(--space-base);
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			overflow-wrap: anywhere;
		}

		&__text {
			margin: var(--space-smaller) 0 0;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-base);
			white-space: pre-wrap;
			overflow-wrap: anywhere;
		}

		&__link {
			color: var(--color-interactive);
			font-weight: 600;
			text-decoration: underline;
			text-underline-offset: 3px;

			&:hover {
				color: var(--color-interactive--hover);
			}
		}

		&__more {
			display: flex;
			justify-content: center;
		}

		&__end,
		&__error {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-align: center;
		}

		&__error {
			color: var(--color-critical);
		}
	}
</style>
