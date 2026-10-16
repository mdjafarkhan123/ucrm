<script lang="ts">
	import { Tabs as TabsPrimitive } from 'bits-ui';
	import { createQuery, useQueryClient, type CreateQueryResult } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import ConversationMessagingStatus from '$lib/components/communications/ConversationMessagingStatus.svelte';
	import ConversationContextSection from '$lib/components/communications/ConversationContextSection.svelte';
	import InquiryAutomationCard from '$lib/components/automation/InquiryAutomationCard.svelte';
	import { AUTOMATION_JOURNEY_READY } from '$lib/automation/journey';
	import {
		conversationContextSectionKey,
		conversationCustomerEmail,
		fetchConversationContextSection,
		type ConversationContext,
		type ConversationContextJob,
		type OpenConversation
	} from '$lib/communications/inbox';
	import {
		CONTEXT_SECTION_LABELS,
		CONTEXT_SECTIONS,
		type ContextSection
	} from '$lib/communications/context-sections';
	import { JOB_STATUS_LABELS, type JobDerivedStatus } from '$lib/jobs/statuses';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import requestsIcon from '@tabler/icons/outline/clipboard-list.svg?raw';
	import quotesIcon from '@tabler/icons/outline/file-text.svg?raw';
	import jobsIcon from '@tabler/icons/outline/tool.svg?raw';
	import invoicesIcon from '@tabler/icons/outline/file-invoice.svg?raw';
	import pipelineIcon from '@tabler/icons/outline/layout-kanban.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import currencyIcon from '@tabler/icons/outline/currency-dollar.svg?raw';

	// The customer context beside a conversation: who this is, and what work the business has with them,
	// one tab per kind of record. Every tab but Contact loads only when it is reached for -- hovering its
	// icon warms it, so the click usually finds it ready.
	//
	// A conversation with no client yet (an unlinked sender, an unresolved chat visitor) has no records to
	// show, so it gets the plain identity panel and no tabs rather than empty ones.
	let {
		group,
		context,
		channels,
		onChooseChannel
	}: {
		group: OpenConversation;
		context: CreateQueryResult<ConversationContext, Error>;
		channels: Array<'email' | 'sms' | 'website_chat'>;
		onChooseChannel: (channel: 'email' | 'sms') => void;
	} = $props();

	const queryClient = useQueryClient();

	type Tab = 'contact' | ContextSection;

	const ICONS: Record<Tab, string> = {
		contact: userIcon,
		properties: mapPinIcon,
		requests: requestsIcon,
		quotes: quotesIcon,
		jobs: jobsIcon,
		invoices: invoicesIcon,
		pipeline: pipelineIcon
	};

	// Kept while the member moves between conversations: someone scanning quotes across customers should
	// not be sent back to Contact every time.
	let selected = $state<Tab>('contact');

	// The tabs this member may see, in the order of the customer's journey. Until the client has loaded
	// there is nothing to say which those are, so the strip waits rather than flashing tabs that then vanish.
	const visibleSections = $derived(
		context.data
			? CONTEXT_SECTIONS.filter((section) => context.data?.sections.includes(section))
			: []
	);
	const tabs = $derived<{ value: Tab; label: string }[]>([
		{ value: 'contact', label: 'Contact' },
		...visibleSections.map((section) => ({
			value: section,
			label: CONTEXT_SECTION_LABELS[section]
		}))
	]);
	const active = $derived<Tab>(tabs.some((tab) => tab.value === selected) ? selected : 'contact');
	const activeLabel = $derived(tabs.find((tab) => tab.value === active)?.label ?? 'Contact');

	function warm(clientId: string, tab: Tab) {
		if (tab === 'contact') return;
		queryClient.prefetchQuery({
			queryKey: conversationContextSectionKey(clientId, tab),
			queryFn: () => fetchConversationContextSection(clientId, tab),
			staleTime: 30_000
		});
	}

	// The customer's most recent job that is still live, for the dark card under the quick actions. It reads
	// the same list as the Jobs tab, under the same key, so opening that tab afterwards finds it already
	// there; a member who may not see jobs never asks.
	const canSeeJobs = $derived(Boolean(context.data?.sections.includes('jobs')));
	const jobsQuery = createQuery(() => ({
		queryKey: conversationContextSectionKey(group.clientId ?? '', 'jobs'),
		queryFn: () => fetchConversationContextSection(group.clientId as string, 'jobs'),
		enabled: Boolean(group.clientId) && canSeeJobs,
		staleTime: 30_000
	}));
	const openJob = $derived<ConversationContextJob | null>(
		jobsQuery.data?.items.find((job) => job.derived_status !== 'archived') ?? null
	);

	function jobStatusLabel(job: ConversationContextJob) {
		return JOB_STATUS_LABELS[job.derived_status as JobDerivedStatus] ?? job.derived_status;
	}

	function jobMoney(job: ConversationContextJob) {
		if (job.total_minor === null) return null;
		return new Intl.NumberFormat(jobsQuery.data?.locale ?? 'en-US', {
			style: 'currency',
			currency: job.currency_code
		}).format(job.total_minor / 100);
	}

	function jobStarted(job: ConversationContextJob) {
		const date = new Date(job.created_at);
		return new Intl.DateTimeFormat(jobsQuery.data?.locale ?? 'en-US', {
			month: 'short',
			day: 'numeric',
			...(date.getFullYear() === new Date().getFullYear() ? {} : { year: 'numeric' })
		}).format(date);
	}

	const phone = $derived(context.data?.client.phone ?? null);
	const canText = $derived(channels.includes('sms'));
	const canEmail = $derived(channels.includes('email'));
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet automation()}
	{#if AUTOMATION_JOURNEY_READY && group.chatSession}
		<div class="context-rail__automation">
			<InquiryAutomationCard record={{ kind: 'chat_session', id: group.chatSession.id }} />
		</div>
	{/if}
{/snippet}

{#snippet detail(label: string, value: string, tone: 'email' | 'phone' | 'company')}
	<div class="context-rail__detail">
		<span class="context-rail__tile context-rail__tile--{tone}" aria-hidden="true">
			{@html tone === 'email' ? mailIcon : tone === 'phone' ? phoneIcon : buildingIcon}
		</span>
		<div class="context-rail__detail-copy">
			<dt>{label}</dt>
			<dd>{value}</dd>
		</div>
	</div>
{/snippet}

{#if group.clientId}
	{@const clientId = group.clientId}
	<TabsPrimitive.Root
		class="context-rail"
		orientation="vertical"
		activationMode="manual"
		value={active}
		onValueChange={(next) => (selected = next as Tab)}
	>
		<div class="context-rail__panel">
			<header class="context-rail__identity">
				<Avatar id={clientId} name={group.name} size="large" />
				<div class="context-rail__who">
					<h2>{group.name}</h2>
					<a
						class="context-rail__client-link"
						href={resolve('/(app)/clients/[id=uuid]', { id: clientId })}
					>
						View client
						<span class="context-rail__link-icon" aria-hidden="true">{@html externalLinkIcon}</span>
					</a>
				</div>
			</header>

			<div class="context-rail__quick" role="group" aria-label="Contact this customer">
				{#if phone}
					<a
						class="context-rail__quick-button context-rail__quick-button--phone"
						href={`tel:${phone}`}
					>
						<span aria-hidden="true">{@html phoneIcon}</span>Call
					</a>
				{:else}
					<button
						type="button"
						class="context-rail__quick-button context-rail__quick-button--phone"
						disabled
						title="No phone number on file"
					>
						<span aria-hidden="true">{@html phoneIcon}</span>Call
					</button>
				{/if}
				<button
					type="button"
					class="context-rail__quick-button context-rail__quick-button--text"
					disabled={!canText}
					onclick={() => onChooseChannel('sms')}
				>
					<span aria-hidden="true">{@html messageIcon}</span>Text
				</button>
				<button
					type="button"
					class="context-rail__quick-button context-rail__quick-button--email"
					disabled={!canEmail}
					onclick={() => onChooseChannel('email')}
				>
					<span aria-hidden="true">{@html mailIcon}</span>Email
				</button>
			</div>

			{#each tabs as tab (tab.value)}
				<TabsPrimitive.Content value={tab.value} class="context-rail__content">
					{#if active === tab.value}
						{#if tab.value === 'contact'}
							{#if openJob}
								<section class="context-rail__job" aria-label="Open job">
									<div class="context-rail__job-eyebrow">
										<span class="context-rail__job-tile" aria-hidden="true">{@html jobsIcon}</span>
										<span class="context-rail__job-kicker">Open job</span>
										<span class="context-rail__job-status">
											<span class="context-rail__job-dot" aria-hidden="true"></span>
											{jobStatusLabel(openJob)}
										</span>
									</div>
									<div class="context-rail__job-title">
										<strong>{openJob.title}</strong>
										<span>Job #{openJob.job_number}</span>
									</div>
									<dl class="context-rail__job-facts">
										<div>
											<span aria-hidden="true">{@html calendarIcon}</span>
											<dt>Started</dt>
											<dd>{jobStarted(openJob)}</dd>
										</div>
										{#if jobMoney(openJob)}
											<div>
												<span aria-hidden="true">{@html currencyIcon}</span>
												<dt>Job total</dt>
												<dd>{jobMoney(openJob)}</dd>
											</div>
										{/if}
									</dl>
									<a
										class="context-rail__job-open"
										href={resolve('/(app)/jobs/[id=uuid]', { id: openJob.id })}
									>
										Open job
										<span aria-hidden="true">{@html arrowRightIcon}</span>
									</a>
								</section>
							{/if}
							<h3 class="context-rail__eyebrow">Contact</h3>
							<dl class="context-rail__details">
								{@render detail(
									'Email',
									context.data?.client.email ?? conversationCustomerEmail(group),
									'email'
								)}
								{#if context.data?.client.phone}
									{@render detail('Phone', context.data.client.phone, 'phone')}
								{/if}
								{#if context.data?.client.company_name}
									{@render detail('Company', context.data.client.company_name, 'company')}
								{/if}
							</dl>
							<ConversationMessagingStatus {clientId} />
							{@render automation()}
						{:else}
							<h3 class="context-rail__title">{activeLabel}</h3>
							<ConversationContextSection {clientId} section={tab.value} />
						{/if}
					{/if}
				</TabsPrimitive.Content>
			{/each}
		</div>

		<TabsPrimitive.List class="context-rail__strip" aria-label="Customer context sections">
			{#if context.isPending}
				{#each { length: 5 } as _, index (index)}
					<span class="context-rail__ghost" aria-hidden="true"></span>
				{/each}
			{:else}
				{#each tabs as tab (tab.value)}
					<TabsPrimitive.Trigger
						value={tab.value}
						class={`context-rail__tab context-rail__tab--${tab.value}`}
						aria-label={tab.label}
						title={tab.label}
						onmouseenter={() => warm(clientId, tab.value)}
						onfocus={() => warm(clientId, tab.value)}
					>
						<span class="context-rail__tab-icon" aria-hidden="true">{@html ICONS[tab.value]}</span>
					</TabsPrimitive.Trigger>
				{/each}
			{/if}
		</TabsPrimitive.List>
	</TabsPrimitive.Root>
{:else}
	<div class="context-rail context-rail--plain">
		<div class="context-rail__panel">
			<header class="context-rail__identity">
				<Avatar id={group.avatarId} name={group.name} size="large" />
				<div class="context-rail__who"><h2>{group.name}</h2></div>
			</header>
			{#if group.chatSession}
				<p class="context-rail__note">
					This visitor's phone and email matched two different clients. UCRM never guesses --
					resolve identity to bring this conversation into one client's history.
				</p>
				<dl class="context-rail__details">
					{#if group.chatSession.visitor_email}
						{@render detail('Email', group.chatSession.visitor_email, 'email')}
					{/if}
					{#if group.chatSession.visitor_phone}
						{@render detail('Phone', group.chatSession.visitor_phone, 'phone')}
					{/if}
				</dl>
			{:else}
				<p class="context-rail__note">
					This sender is not yet linked to a customer. It stays out of the customer's conversation
					until reviewed.
				</p>
				<dl class="context-rail__details">
					{@render detail('Email', group.avatarId, 'email')}
				</dl>
			{/if}
			{@render automation()}
		</div>
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.context-rail) {
		display: flex;
		height: 100%;
		min-height: 0;
	}

	.context-rail__panel {
		display: flex;
		flex: 1;
		min-width: 0;
		flex-direction: column;
		gap: var(--space-base);
		padding: 20px 18px 84px;
		overflow-y: auto;
	}

	.context-rail__identity {
		display: flex;
		align-items: center;
		gap: var(--space-slim);

		:global(.avatar--large) {
			width: 48px;
			height: 48px;
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
		}
	}

	.context-rail__who {
		display: grid;
		min-width: 0;
		gap: 3px;

		h2 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
			line-height: 1.25;
			overflow-wrap: anywhere;
		}
	}

	.context-rail__client-link {
		display: inline-flex;
		width: fit-content;
		align-items: center;
		gap: var(--space-smaller);
		border-radius: var(--radius-small);
		color: var(--color-interactive);
		font-size: 12px;
		font-weight: 600;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.context-rail__link-icon {
		display: inline-flex;

		:global(svg) {
			width: 13px;
			height: 13px;
		}
	}

	.context-rail__quick {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-small);
	}

	.context-rail__quick-button {
		display: inline-flex;
		height: 34px;
		align-items: center;
		justify-content: center;
		gap: 6px;
		padding: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: 10px;
		color: var(--color-text);
		background: var(--color-surface);
		font: inherit;
		font-size: 12px;
		font-weight: 600;
		text-decoration: none;
		cursor: pointer;
		transition:
			background var(--timing-base) ease-out,
			border-color var(--timing-base) ease-out;

		span {
			display: inline-flex;
		}

		:global(svg) {
			width: 14px;
			height: 14px;
		}

		&:hover:not(:disabled) {
			background: var(--color-surface--hover);
			border-color: var(--color-border--interactive);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&:disabled {
			cursor: not-allowed;
			color: var(--color-disabled);
		}
	}

	.context-rail__quick-button--phone span,
	.context-rail__quick-button--text span {
		color: var(--color-interactive);
	}

	.context-rail__quick-button--email span {
		color: var(--color-informative--onSurface);
	}

	.context-rail__quick-button:disabled span {
		color: var(--color-disabled);
	}

	.context-rail__title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
	}

	.context-rail__eyebrow {
		margin: var(--space-smaller) 0 calc(var(--space-smaller) * -1);
		color: var(--color-text--secondary);
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
	}

	:global(.context-rail__content) {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	:global(.context-rail__content[hidden]) {
		display: none;
	}

	/* The open job: always the dark navy card, in light and dark mode alike, so it reads as the one thing
	   on the panel that is about work rather than about the person. */
	.context-rail__job {
		display: flex;
		flex-direction: column;
		gap: 14px;
		padding: 18px;
		border-radius: var(--radius-base);
		color: #fff;
		background:
			radial-gradient(circle at 100% 100%, rgb(4 154 84 / 0.28), transparent 60%),
			var(--color-base-blue--900);
	}

	.context-rail__job-eyebrow {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.context-rail__job-tile {
		display: inline-flex;
		width: 28px;
		height: 28px;
		align-items: center;
		justify-content: center;
		border: var(--border-base) solid rgb(255 255 255 / 0.08);
		border-radius: var(--radius-base);
		background: rgb(255 255 255 / 0.08);

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.context-rail__job-kicker {
		flex: 1;
		color: var(--color-base-blue--500);
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
	}

	.context-rail__job-status {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		padding: 3px 8px;
		border: var(--border-base) solid rgb(255 255 255 / 0.08);
		border-radius: 10px;
		background: rgb(255 255 255 / 0.08);
		font-size: 11px;
		font-weight: 700;
	}

	.context-rail__job-dot {
		width: 6px;
		height: 6px;
		border-radius: var(--radius-circle);
		background: var(--color-base-green--500);
	}

	.context-rail__job-title {
		display: grid;
		gap: 3px;

		strong {
			font-size: var(--typography--fontSize-large);
			font-weight: 800;
			line-height: 1.25;
			overflow-wrap: anywhere;
		}

		span {
			font-size: 12px;
			font-weight: 500;
		}
	}

	.context-rail__job-facts {
		display: grid;
		gap: var(--space-slim) 0;
		margin: 0;
		padding-top: var(--space-slim);
		border-top: var(--border-base) solid rgb(255 255 255 / 0.1);

		div {
			display: flex;
			align-items: center;
			gap: 10px;
			font-size: 12px;
		}

		div > span {
			display: inline-flex;
			color: rgb(255 255 255 / 0.7);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		dt {
			flex: 1;
			font-weight: 500;
		}

		dd {
			margin: 0;
			font-weight: 600;
		}
	}

	.context-rail__job-open {
		display: inline-flex;
		height: 38px;
		align-items: center;
		justify-content: center;
		gap: var(--space-small);
		border-radius: var(--radius-base);
		color: var(--color-base-blue--900);
		background: #fff;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-decoration: none;

		span {
			display: inline-flex;
		}

		:global(svg) {
			width: 15px;
			height: 15px;
		}

		&:hover {
			background: var(--color-base-blue--200);
		}

		&:focus-visible {
			outline: none;
			box-shadow:
				0 0 0 2px var(--color-base-blue--900),
				0 0 0 4px #fff;
		}
	}

	.context-rail__details {
		display: grid;
		gap: var(--space-slim);
		margin: 0;
	}

	.context-rail__detail {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	.context-rail__tile {
		display: inline-flex;
		width: 32px;
		height: 32px;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		border-radius: var(--radius-base);

		:global(svg) {
			width: 15px;
			height: 15px;
		}
	}

	.context-rail__tile--email {
		color: var(--color-informative--onSurface);
		background: color-mix(in srgb, var(--color-informative) 16%, transparent);
	}

	.context-rail__tile--phone {
		color: var(--color-interactive);
		background: color-mix(in srgb, var(--color-base-green--500) 16%, transparent);
	}

	.context-rail__tile--company {
		color: var(--color-quote);
		background: color-mix(in srgb, var(--color-quote) 16%, transparent);
	}

	.context-rail__detail-copy {
		display: grid;
		min-width: 0;
		gap: 1px;

		dt {
			color: var(--color-text--secondary);
			font-size: 11px;
			font-weight: 500;
		}

		dd {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			overflow-wrap: anywhere;
		}
	}

	.context-rail__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.context-rail__automation {
		margin-top: var(--space-smaller);
	}

	/* The strip: a slim rail of icons down the right edge, each tinted for the kind of record it opens
	   (the same colour that kind wears everywhere else). The open one sits in a soft tile of its own tint. */
	:global(.context-rail__strip) {
		display: flex;
		flex: 0 0 auto;
		width: 56px;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		padding: var(--space-base) 0;
		border-left: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
		overflow-x: hidden;
		overflow-y: auto;
	}

	:global(.context-rail__tab) {
		--tab-color: var(--color-quote);
		position: relative;
		display: inline-flex;
		width: 40px;
		height: 40px;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		padding: 0;
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		background: transparent;
		color: var(--tab-color);
		cursor: pointer;
		transition:
			background var(--timing-base) ease-out,
			border-color var(--timing-base) ease-out;

		&:hover {
			background: color-mix(in srgb, var(--tab-color) 10%, transparent);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	:global(.context-rail__tab--properties) {
		--tab-color: var(--color-quote);
	}

	:global(.context-rail__tab--requests) {
		--tab-color: var(--color-warning--onSurface);
	}

	:global(.context-rail__tab--quotes) {
		--tab-color: var(--color-critical);
	}

	:global(.context-rail__tab--jobs) {
		--tab-color: var(--color-interactive);
	}

	:global(.context-rail__tab--invoices),
	:global(.context-rail__tab--pipeline) {
		--tab-color: var(--color-informative--onSurface);
	}

	:global(.context-rail__tab[data-state='active']) {
		border-color: var(--color-surface);
		background: color-mix(in srgb, var(--tab-color) 16%, transparent);
	}

	.context-rail__tab-icon {
		display: inline-flex;

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.context-rail__ghost {
		width: 40px;
		height: 40px;
		border-radius: var(--radius-base);
		background: var(--color-surface--hover);
		opacity: 0.6;
	}
</style>
