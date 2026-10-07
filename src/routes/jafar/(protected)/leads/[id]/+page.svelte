<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import toolIcon from '@tabler/icons/outline/tool.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import addressBookIcon from '@tabler/icons/outline/address-book.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import linkIcon from '@tabler/icons/outline/link.svg?raw';
	import unlinkIcon from '@tabler/icons/outline/unlink.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import HistoryEntryForm from '$lib/components/jafar/leads/HistoryEntryForm.svelte';
	import LeadHistory from '$lib/components/jafar/leads/LeadHistory.svelte';
	import NextActionDialog from '$lib/components/jafar/leads/NextActionDialog.svelte';
	import LinkApplicationDialog from '$lib/components/jafar/leads/LinkApplicationDialog.svelte';
	import {
		CONTACT_METHOD_LABELS,
		LEAD_SOURCE_LABELS,
		LEAD_STATUSES,
		LEAD_STATUS_LABELS,
		LEAD_STATUS_TONES,
		countryName,
		type LeadStatus
	} from '$lib/jafar/leads';
	import {
		APPLICATION_STAGE_LABELS,
		applicationHref,
		type LinkedApplication
	} from '$lib/jafar/lead-history';
	import { jafarLeadKey, jafarProspectKey, jafarProspectsKey } from '$lib/jafar/query-keys';
	import { canUseJafarPath } from '$lib/jafar/team-access';
	import {
		fetchLeadPage,
		prefetchApplicationCandidates,
		refreshLead,
		sendLeadWrite
	} from '$lib/jafar/lead-page-api';

	// Jafar business management B2: one Lead -- who the business is, how to reach them, its next step, any
	// Application it sent, and one history of everything that happened. The page is one request; older history
	// and the Application picker load only when asked for.

	const leadId = $derived(page.params.id ?? '');
	// A teammate with Applications switched off neither sees nor links them from here.
	const canSeeApplications = $derived(
		canUseJafarPath(
			{ role: page.data.owner.role, access: page.data.owner.access },
			'/jafar/prospects'
		)
	);
	const queryClient = useQueryClient();
	const toast = getToastManager();

	const lead = createQuery(() => ({
		queryKey: jafarLeadKey(leadId),
		queryFn: () => fetchLeadPage(leadId),
		enabled: Boolean(leadId),
		// "This Lead no longer exists" is an answer, not a hiccup to retry.
		retry: (count: number, error: Error & { status?: number }) => error.status !== 404 && count < 2
	}));

	const notFound = $derived(
		lead.isError && (lead.error as Error & { status?: number }).status === 404
	);

	// --- Dates ----------------------------------------------------------------------------------------

	function localToday() {
		const now = new Date();
		return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
	}
	const today = localToday();

	function formatDay(day: string) {
		const [year, month, date] = day.split('-').map(Number);
		return new Intl.DateTimeFormat(undefined, {
			weekday: 'short',
			day: 'numeric',
			month: 'short'
		}).format(new Date(year, month - 1, date));
	}

	const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' });
	const relativeFormat = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });

	// "2 days ago" reads faster than a date for how long it has been quiet; the exact time is on hover.
	function sinceLabel(iso: string | null) {
		if (!iso) return null;
		const minutes = Math.round((Date.parse(iso) - Date.now()) / 60_000);
		if (Math.abs(minutes) < 60) return relativeFormat.format(minutes, 'minute');
		const hours = Math.round(minutes / 60);
		if (Math.abs(hours) < 24) return relativeFormat.format(hours, 'hour');
		const days = Math.round(hours / 24);
		if (Math.abs(days) < 30) return relativeFormat.format(days, 'day');
		return dateFormat.format(new Date(iso));
	}

	function dueState(due: string | null) {
		if (!due) return null;
		if (due < today) return { label: `Overdue · ${formatDay(due)}`, tone: 'overdue' };
		if (due === today) return { label: 'Due today', tone: 'today' };
		return { label: `Due ${formatDay(due)}`, tone: 'later' };
	}

	function contactHref(kind: string, value: string) {
		if (kind === 'email') return `mailto:${value}`;
		if (kind === 'phone') return `tel:${value.replace(/[^\d+]/g, '')}`;
		if (/^https?:\/\//i.test(value)) return value;
		return null;
	}

	// --- Status ---------------------------------------------------------------------------------------

	let statusSaving = $state(false);

	async function changeStatus(status: LeadStatus) {
		if (statusSaving || lead.data?.lead.lead_status === status) return;
		statusSaving = true;
		const result = await sendLeadWrite(`/api/jafar/leads/${encodeURIComponent(leadId)}`, 'PATCH', {
			lead_status: status
		});
		if (result.ok) await refreshLead(queryClient, leadId);
		statusSaving = false;
		if (result.ok) toast.success(`Status changed to ${LEAD_STATUS_LABELS[status]}`);
		else toast.error('The status could not be changed.', result.error);
	}

	const statusItems = $derived(
		LEAD_STATUSES.map((status) => ({
			label: LEAD_STATUS_LABELS[status],
			icon: lead.data?.lead.lead_status === status ? checkIcon : undefined,
			onSelect: () => changeStatus(status)
		}))
	);

	// --- Next action, Applications --------------------------------------------------------------------

	let nextActionMode = $state<'set' | 'done' | null>(null);
	let clearingNextAction = $state(false);
	let clearSaving = $state(false);

	async function clearNextAction() {
		if (clearSaving) return;
		clearSaving = true;
		const result = await sendLeadWrite(`/api/jafar/leads/${encodeURIComponent(leadId)}`, 'PATCH', {
			next_action: { mode: 'clear' }
		});
		if (result.ok) await refreshLead(queryClient, leadId);
		clearSaving = false;
		if (!result.ok) {
			toast.error('The next action could not be removed.', result.error);
			return;
		}
		clearingNextAction = false;
		toast.success('Next action removed');
	}

	let linkOpen = $state(false);
	let unlinking = $state<LinkedApplication | null>(null);
	let unlinkSaving = $state(false);

	async function confirmUnlink() {
		const application = unlinking;
		if (!application || unlinkSaving) return;
		unlinkSaving = true;
		const result = await sendLeadWrite(
			`/api/jafar/leads/${encodeURIComponent(leadId)}/applications/${encodeURIComponent(application.id)}`,
			'DELETE'
		);
		if (result.ok)
			await Promise.all([
				refreshLead(queryClient, leadId),
				queryClient.invalidateQueries({ queryKey: jafarProspectsKey }),
				queryClient.invalidateQueries({ queryKey: jafarProspectKey(application.id) })
			]);
		unlinkSaving = false;
		if (!result.ok) {
			toast.error('The Application could not be unlinked.', result.error);
			return;
		}
		unlinking = null;
		toast.success('Application unlinked');
	}
</script>

<svelte:head
	><title>{lead.data?.lead.business_name ?? 'Lead'} · Leads · Control Room</title></svelte:head
>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="lead-page" aria-busy={lead.isPending}>
	<a class="lead-page__back" href={resolve('/jafar/leads')}
		><span aria-hidden="true">{@html arrowLeftIcon}</span> Leads</a
	>

	{#if lead.isPending}
		<div class="lead-page__hero lead-page__hero--loading">
			<LoadingSkeleton variant="heading" label="Loading the Lead" />
			<LoadingSkeleton variant="text" rows={2} />
		</div>
		<div class="lead-page__layout">
			<div class="lead-page__main"><LoadingSkeleton variant="card" rows={5} /></div>
			<div class="lead-page__rail">
				<LoadingSkeleton variant="card" rows={2} />
				<LoadingSkeleton variant="card" rows={3} />
			</div>
		</div>
	{:else if notFound}
		<div class="lead-page__state">
			<ErrorState
				title="This Lead no longer exists"
				description="It may have been removed. Go back to the Leads list to find the business."
			/>
		</div>
	{:else if lead.isError}
		<div class="lead-page__state">
			<ErrorState
				title="This Lead could not be loaded"
				description={lead.error.message}
				retry={() => lead.refetch()}
			/>
		</div>
	{:else if lead.data}
		{@const data = lead.data}
		{@const details = data.lead}
		{@const due = dueState(details.next_action_due_on)}
		{@const lastContacted = sinceLabel(data.last_contacted_at)}
		{@const lastHeard = sinceLabel(data.last_heard_from_at)}

		<header class="lead-page__hero">
			<div class="lead-page__hero-top">
				<div class="lead-page__identity">
					<p class="lead-page__eyebrow">Lead</p>
					<h1>{details.business_name}</h1>
					<ul class="lead-page__facts">
						<li>
							<span aria-hidden="true">{@html toolIcon}</span>{details.trade}
						</li>
						<li>
							<span aria-hidden="true">{@html mapPinIcon}</span>{countryName(details.country_code)}
						</li>
						{#if details.website}
							<li>
								<span aria-hidden="true">{@html worldIcon}</span>
								<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- the business's own website. -->
								<a href={details.website} target="_blank" rel="noopener noreferrer"
									>{details.website_host ?? details.website}</a
								>
							</li>
						{/if}
						{#if details.contact_name}
							<li><span aria-hidden="true">{@html userIcon}</span>{details.contact_name}</li>
						{/if}
					</ul>
				</div>

				<DropdownMenu
					items={statusItems}
					triggerLabel={`Status: ${LEAD_STATUS_LABELS[details.lead_status]}. Change status`}
					triggerClass="lead-page__status-trigger"
					disabled={statusSaving}
				>
					{#snippet trigger()}
						<Badge status={LEAD_STATUS_TONES[details.lead_status]}
							>{LEAD_STATUS_LABELS[details.lead_status]}</Badge
						>
						<span class="lead-page__status-chevron" aria-hidden="true">{@html chevronDownIcon}</span
						>
					{/snippet}
				</DropdownMenu>
			</div>

			<dl class="lead-page__stats">
				<div>
					<dt>Last contacted</dt>
					<dd
						title={data.last_contacted_at
							? dateFormat.format(new Date(data.last_contacted_at))
							: undefined}
					>
						{lastContacted ?? 'Not yet'}
					</dd>
				</div>
				<div>
					<dt>Last heard from them</dt>
					<dd
						title={data.last_heard_from_at
							? dateFormat.format(new Date(data.last_heard_from_at))
							: undefined}
					>
						{lastHeard ?? 'Not yet'}
					</dd>
				</div>
				<div>
					<dt>Found through</dt>
					<dd>{LEAD_SOURCE_LABELS[details.source]}</dd>
				</div>
				<div>
					<dt>Added</dt>
					<dd>{dateFormat.format(new Date(details.created_at))}</dd>
				</div>
			</dl>
		</header>

		<div class="lead-page__layout">
			<aside class="lead-page__rail" aria-label="About this Lead">
				<RailCard title="Next action" icon={calendarIcon} class="lead-page__next">
					{#if details.next_action}
						<div class="lead-page__next-body">
							<p class="lead-page__next-text">{details.next_action}</p>
							{#if due}
								<span class={['lead-page__due', `lead-page__due--${due.tone}`]}>{due.label}</span>
							{/if}
						</div>
						<div class="lead-page__next-actions">
							<Button variant="primary" size="small" onclick={() => (nextActionMode = 'done')}>
								<span class="lead-page__button-icon" aria-hidden="true">{@html checkIcon}</span>Mark
								done
							</Button>
							<Button variant="secondary" size="small" onclick={() => (nextActionMode = 'set')}>
								<span class="lead-page__button-icon" aria-hidden="true">{@html pencilIcon}</span
								>Change
							</Button>
							<Button variant="tertiary" size="small" onclick={() => (clearingNextAction = true)}>
								<span class="lead-page__button-icon" aria-hidden="true">{@html xIcon}</span>Remove
							</Button>
						</div>
					{:else}
						<p
							class={[
								'lead-page__empty',
								details.lead_status !== 'unsuitable' && 'lead-page__empty--warn'
							]}
						>
							{details.lead_status === 'unsuitable'
								? 'No next action — this Lead is marked unsuitable.'
								: 'No next action. Every Lead being worked needs a dated next step.'}
						</p>
						<div>
							<Button variant="secondary" size="small" onclick={() => (nextActionMode = 'set')}>
								<span class="lead-page__button-icon" aria-hidden="true">{@html plusIcon}</span>Set
								next action
							</Button>
						</div>
					{/if}
				</RailCard>

				<RailCard
					title="Contact details"
					icon={addressBookIcon}
					count={data.contact_methods.length}
				>
					{#if data.contact_methods.length}
						<ul class="lead-page__contacts">
							{#each data.contact_methods as method (method.id)}
								{@const href = contactHref(method.kind, method.value)}
								<li>
									<span class="lead-page__contact-kind">{CONTACT_METHOD_LABELS[method.kind]}</span>
									{#if href}
										<!-- eslint-disable svelte/no-navigation-without-resolve -- an email, phone or outside link. -->
										<a
											class="lead-page__contact-value"
											{href}
											target={href.startsWith('http') ? '_blank' : undefined}
											rel={href.startsWith('http') ? 'noopener noreferrer' : undefined}
											>{method.value}</a
										>
										<!-- eslint-enable svelte/no-navigation-without-resolve -->
									{:else}
										<span class="lead-page__contact-value">{method.value}</span>
									{/if}
									<span class="lead-page__contact-source">Found: {method.found_at}</span>
								</li>
							{/each}
						</ul>
					{:else}
						<p class="lead-page__empty">
							No contact details yet. This Lead can be researched, but cannot be contacted.
						</p>
					{/if}
				</RailCard>

				{#if canSeeApplications}
					<RailCard title="Applications" icon={fileTextIcon} count={data.applications.length}>
						{#snippet actions()}
							<Button
								variant="tertiary"
								size="small"
								onhover={() => prefetchApplicationCandidates(queryClient, leadId)}
								onclick={() => (linkOpen = true)}
							>
								<span class="lead-page__button-icon" aria-hidden="true">{@html linkIcon}</span>Link
							</Button>
						{/snippet}
						{#if data.applications.length}
							<ul class="lead-page__applications">
								{#each data.applications as application (application.id)}
									<li>
										<div class="lead-page__application">
											<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- applicationHref resolves the path. -->
											<a href={applicationHref(application.id)}>{application.business_name}</a>
											<span
												>{application.main_contact_name} · Applied {dateFormat.format(
													new Date(application.submitted_at)
												)}</span
											>
											<Badge size="small" dot={false} status="inactive"
												>{APPLICATION_STAGE_LABELS[application.stage] ?? application.stage}</Badge
											>
										</div>
										<button
											type="button"
											class="lead-page__icon-button"
											aria-label={`Unlink ${application.business_name}'s Application`}
											title="Unlink"
											onclick={() => (unlinking = application)}>{@html unlinkIcon}</button
										>
									</li>
								{/each}
							</ul>
						{:else}
							<p class="lead-page__empty">
								None linked. If this business applied on the website, link the Application here.
							</p>
						{/if}
					</RailCard>
				{/if}

				{#if details.fit_notes || details.source_detail}
					<RailCard title="About" icon={infoIcon}>
						<dl class="lead-page__about">
							{#if details.source_detail}
								<div>
									<dt>Source details</dt>
									<dd>{details.source_detail}</dd>
								</div>
							{/if}
							{#if details.fit_notes}
								<div>
									<dt>Why they may fit</dt>
									<dd class="lead-page__prewrap">{details.fit_notes}</dd>
								</div>
							{/if}
						</dl>
					</RailCard>
				{/if}
			</aside>

			<div class="lead-page__main">
				<SectionBlock title="History" icon={historyIcon} id="lead-history">
					<div class="lead-page__composer">
						<HistoryEntryForm
							{leadId}
							contactMethods={data.contact_methods}
							idPrefix="history-add"
						/>
					</div>
					<LeadHistory {leadId} history={data.history} contactMethods={data.contact_methods} />
				</SectionBlock>
			</div>
		</div>

		{#if nextActionMode}
			<NextActionDialog
				{leadId}
				mode={nextActionMode}
				current={details.next_action && details.next_action_due_on
					? { text: details.next_action, due_on: details.next_action_due_on }
					: null}
				onClose={() => (nextActionMode = null)}
			/>
		{/if}

		{#if clearingNextAction}
			<ConfirmDialog
				open={true}
				title="Remove the next action?"
				confirmLabel="Remove"
				loading={clearSaving}
				onConfirm={clearNextAction}
				onClose={() => (clearingNextAction = false)}
			>
				<p>
					“{details.next_action}” is removed without being marked done. The history keeps a record
					of it.
				</p>
			</ConfirmDialog>
		{/if}

		{#if linkOpen}
			<LinkApplicationDialog
				{leadId}
				businessName={details.business_name}
				onClose={() => (linkOpen = false)}
			/>
		{/if}

		{#if unlinking}
			<ConfirmDialog
				open={true}
				title="Unlink this Application?"
				confirmLabel="Unlink"
				loading={unlinkSaving}
				onConfirm={confirmUnlink}
				onClose={() => (unlinking = null)}
			>
				<p>
					{unlinking.business_name}'s Application stays as it is; it is only no longer part of this
					Lead. The history records the unlink.
				</p>
			</ConfirmDialog>
		{/if}
	{/if}
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.lead-page {
		display: grid;
		gap: var(--space-large);
		min-width: 0;

		h1,
		p,
		dl,
		dd {
			margin: 0;
		}

		&__back {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			justify-self: start;
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-decoration: underline;
			text-underline-offset: var(--space-smaller);

			&:hover {
				color: var(--color-interactive--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__state {
			max-width: 640px;
		}

		// --- The business at a glance ---

		&__hero {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-large);
			border: var(--border-base) solid var(--color-border);
			border-top: 4px solid var(--color-interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			box-shadow: var(--shadow-low);
		}

		&__hero--loading {
			gap: var(--space-base);
		}

		&__hero-top {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-large);
		}

		&__identity {
			display: flex;
			min-width: 0;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__eyebrow {
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			letter-spacing: var(--typography--letterSpacing-loose);
			text-transform: uppercase;
		}

		h1 {
			color: var(--color-heading);
			font-family: var(--typography--fontFamily-display);
			font-size: var(--typography--fontSize-jumbo);
			font-weight: 900;
			line-height: var(--typography--lineHeight-minuscule);
			overflow-wrap: anywhere;
		}

		&__facts {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small) var(--space-large);
			margin: 0;
			padding: 0;
			color: var(--color-text--secondary);
			list-style: none;

			li {
				display: inline-flex;
				align-items: center;
				gap: var(--space-smaller);
				min-width: 0;
				overflow-wrap: anywhere;
			}

			span :global(svg) {
				display: block;
				width: 16px;
				height: 16px;
				color: var(--color-icon--secondary);
			}

			a {
				color: var(--color-interactive);
				font-weight: 600;
				text-decoration: underline;
				text-underline-offset: 3px;
			}
		}

		:global(.lead-page__status-trigger) {
			display: inline-flex;
			flex: none;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-smaller) var(--space-small) var(--space-smaller) var(--space-smaller);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			cursor: pointer;
			transition:
				border-color var(--timing-quick),
				background-color var(--timing-quick);

			&:hover:not(:disabled) {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				cursor: progress;
				opacity: 0.6;
			}
		}

		&__status-chevron :global(svg) {
			display: block;
			width: 16px;
			height: 16px;
			color: var(--color-icon--secondary);
		}

		&__stats {
			display: grid;
			grid-template-columns: repeat(4, minmax(0, 1fr));
			gap: var(--space-base);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);

			div {
				display: flex;
				min-width: 0;
				flex-direction: column;
				gap: 2px;
			}

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			dd {
				color: var(--color-heading);
				font-weight: 700;
				overflow-wrap: anywhere;
			}
		}

		// --- Rail and history ---

		&__layout {
			display: grid;
			grid-template-columns: minmax(0, 1fr) minmax(280px, 360px);
			grid-template-areas: 'main rail';
			align-items: start;
			gap: var(--space-large);
		}

		&__main {
			grid-area: main;
			min-width: 0;
			padding: var(--space-base) var(--space-large) var(--space-large);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			box-shadow: var(--shadow-low);
		}

		&__rail {
			display: flex;
			grid-area: rail;
			min-width: 0;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__composer {
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__next-body {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__next-text {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
			overflow-wrap: anywhere;
		}

		&__due {
			align-self: flex-start;
			padding: 2px var(--space-small);
			border-radius: var(--radius-circle);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__due--overdue {
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
		}

		&__due--today {
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
		}

		&__due--later {
			background: var(--color-informative--surface);
			color: var(--color-informative--onSurface);
		}

		&__next-actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__button-icon {
			display: inline-flex;
			margin-right: var(--space-smaller);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__empty {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__empty--warn {
			color: var(--color-warning--onSurface);
			font-weight: 600;
		}

		&__contacts,
		&__applications {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;

			li + li {
				margin-top: var(--space-slim);
				padding-top: var(--space-slim);
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__contacts li {
			display: flex;
			min-width: 0;
			flex-direction: column;
			gap: 2px;
		}

		&__contact-kind,
		&__contact-source {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__contact-kind {
			font-weight: 700;
		}

		&__contact-value {
			color: var(--color-heading);
			font-weight: 600;
			overflow-wrap: anywhere;
		}

		a.lead-page__contact-value {
			color: var(--color-interactive);
			text-decoration: underline;
			text-underline-offset: 3px;
		}

		&__contact-source {
			overflow-wrap: anywhere;
		}

		&__applications li {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__application {
			display: flex;
			min-width: 0;
			flex-direction: column;
			align-items: flex-start;
			gap: var(--space-smaller);

			a {
				color: var(--color-interactive);
				font-weight: 700;
				text-decoration: underline;
				text-underline-offset: 3px;
				overflow-wrap: anywhere;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__icon-button {
			display: grid;
			width: 32px;
			height: 32px;
			flex: none;
			place-items: center;
			padding: 0;
			border: 0;
			border-radius: var(--radius-base);
			background: transparent;
			color: var(--color-icon--secondary);
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
				color: var(--color-critical);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__about {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 700;
			}

			dd {
				margin-top: 2px;
				color: var(--color-text);
				overflow-wrap: anywhere;
			}
		}

		&__prewrap {
			white-space: pre-wrap;
		}
	}

	@media (max-width: 1100px) {
		.lead-page__stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	// On a tablet or phone the next action and contact details come first, then the history.
	@media (max-width: 960px) {
		.lead-page__layout {
			grid-template-columns: minmax(0, 1fr);
			grid-template-areas:
				'rail'
				'main';
		}
	}

	@media (max-width: 639px) {
		.lead-page h1 {
			font-size: 28px;
		}

		.lead-page__hero {
			padding: var(--space-base);
		}

		.lead-page__hero-top {
			flex-direction: column-reverse;
			gap: var(--space-base);
		}

		.lead-page__main {
			padding: var(--space-small) var(--space-small) var(--space-base);
		}

		.lead-page__composer {
			padding: var(--space-small);
		}
	}
</style>
