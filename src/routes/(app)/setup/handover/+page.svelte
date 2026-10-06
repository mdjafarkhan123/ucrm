<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import keyIcon from '@tabler/icons/outline/key.svg?raw';
	import bookIcon from '@tabler/icons/outline/book.svg?raw';
	import schoolIcon from '@tabler/icons/outline/school.svg?raw';
	import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';
	import lifebuoyIcon from '@tabler/icons/outline/lifebuoy.svg?raw';
	import printerIcon from '@tabler/icons/outline/printer.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import OutsideWaits from '$lib/components/setup/OutsideWaits.svelte';
	import { fetchSetupHandover, setupHandoverKey } from '$lib/setup/api';
	import { LAUNCH_APPROVAL_METHOD_LABEL } from '$lib/setup/launch-approval';
	import { formatMeetingTime, handoverEventText } from '$lib/setup/training';
	import { getSupportAsk } from '$lib/support/ask';
	import type { HttpError } from '$lib/http-error';
	import type { PageProps } from './$types';

	// Client onboarding E6 (plan §6): the handover pack. Once Uplift delivers the project, the client's owners and
	// administrators read here who owns which account, guides for their team, their launch approval, training and
	// its recording while they consent, and anything still waiting on an outside company. It prints as a PDF. Staff
	// get individual guide links from them, not this page.

	let { data: shell }: PageProps = $props();
	const userId = $derived(shell.user?.id ?? null);
	const askUplift = getSupportAsk();

	const query = createQuery(() => ({
		queryKey: setupHandoverKey(userId),
		queryFn: fetchSetupHandover
	}));
	const pack = $derived(query.data?.delivered ? query.data : null);
	const forbidden = $derived((query.error as HttpError | null)?.status === 403);

	const day = (value: string) =>
		new Date(value).toLocaleDateString(undefined, {
			day: 'numeric',
			month: 'long',
			year: 'numeric'
		});
	const moment = (value: string) =>
		new Date(value).toLocaleString(undefined, {
			day: 'numeric',
			month: 'long',
			year: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});
</script>

<svelte:head><title>Handover pack · Contractor CRM</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<PageContainer variant="fill">
	<div class="handover">
		<div class="handover__crumbs">
			<Breadcrumbs
				items={[{ label: 'Setup', href: resolve('/(app)/setup') }, { label: 'Handover pack' }]}
			/>
		</div>
		<PageHeader
			eyebrow={pack ? 'Project delivered' : 'Setup'}
			title="Your handover pack"
			description="Everything you need to run your Uplift system yourself. Once delivered, you can open it any time from Settings."
		>
			{#snippet actions()}
				{#if pack}
					<button type="button" class="handover__print" onclick={() => window.print()}
						><span aria-hidden="true">{@html printerIcon}</span>Print or save as PDF</button
					>
				{/if}
			{/snippet}
		</PageHeader>

		{#if query.isPending}
			<LoadingSkeleton variant="card" label="Loading your handover pack" />
			<LoadingSkeleton variant="card" label="Loading your handover pack" />
		{:else if query.isError}
			<ErrorState
				title={forbidden
					? 'Only owners and administrators can open the handover pack'
					: 'Your handover pack could not be loaded'}
				description={forbidden
					? 'Ask your account owner for the guide links you need.'
					: query.error?.message}
				retry={forbidden ? undefined : () => query.refetch()}
			/>
		{:else if !pack}
			<EmptyState
				icon={packageIcon}
				title="Your handover pack isn’t ready yet"
				description="It opens here once Uplift delivers your project. You can follow where things stand on your Setup page."
			>
				{#snippet action()}
					<Button href={resolve('/(app)/setup')}>Go to Setup</Button>
				{/snippet}
			</EmptyState>
		{:else}
			<p class="handover__stamp">
				Delivered {day(pack.handover.delivered_at!)}{pack.handover.live_at
					? ` · live since ${day(pack.handover.live_at)}`
					: ''}
			</p>

			<SectionBlock title="Who owns what" icon={keyIcon}>
				<p class="handover__summary">{pack.handover.access_summary}</p>
			</SectionBlock>

			<SectionBlock
				title="Guides for your team"
				icon={bookIcon}
				hint="Share any of these links with the people who need them."
			>
				<ul class="handover__guides">
					{#each pack.handover.guides as guide (guide.url)}
						<li>
							<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- an address on another site, given by Uplift. -->
							<a href={guide.url} target="_blank" rel="noreferrer">
								<span>{guide.title}</span>
								<span class="handover__guide-icon" aria-hidden="true">{@html externalLinkIcon}</span
								>
							</a>
							<span class="handover__print-url">{guide.url}</span>
						</li>
					{/each}
				</ul>
			</SectionBlock>

			<SectionBlock title="Training" icon={schoolIcon}>
				<div class="handover__stack">
					{#if pack.training?.meeting_at}
						<p>
							<strong>{formatMeetingTime(pack.training.meeting_at, pack.training.time_zone)}</strong
							>
							with {pack.training.attendees.map((person) => person.name).join(', ')}.
						</p>
					{:else if pack.training?.skipped_at}
						<p>
							{pack.training.skipped_by_name} said your team doesn’t need training on {day(
								pack.training.skipped_at
							)}. Ask in Chat with Uplift if you’d like one after all.
						</p>
					{:else}
						<p>No training is booked. Ask in Chat with Uplift to arrange one.</p>
					{/if}
					{#if pack.recording_url}
						<p>
							<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- an address on another site, given by Uplift. -->
							<a href={pack.recording_url} target="_blank" rel="noreferrer">Watch the recording</a>
							<span class="handover__print-url">{pack.recording_url}</span>
						</p>
						<p class="handover__muted">
							A private link. Share it only with your team. You can withdraw consent on your Setup
							page, which hides it here.
						</p>
					{/if}
				</div>
			</SectionBlock>

			{#if pack.approvals.length}
				<SectionBlock title="Launch approval" icon={rocketIcon}>
					<div class="handover__stack">
						{#each pack.approvals as approval (approval.id)}
							<p>
								<strong>{approval.approved_by_name}</strong> approved preview version {approval.version}
								on {moment(approval.approved_at!)}{approval.approval_method
									? `, ${LAUNCH_APPROVAL_METHOD_LABEL[approval.approval_method]}`
									: ''}.
							</p>
							{#if approval.approval_wording}
								<blockquote class="handover__wording">{approval.approval_wording}</blockquote>
							{/if}
						{/each}
					</div>
				</SectionBlock>
			{/if}

			{#if pack.open_waits.length}
				<OutsideWaits waits={pack.open_waits} />
			{/if}

			<SectionBlock title="Getting help" icon={lifebuoyIcon}>
				<div class="handover__stack">
					<p>
						Uplift is still here. Write to us in <strong>Chat with Uplift</strong>, in the bottom
						corner of every screen. Changes to your website or system go through there too.
					</p>
					<div class="handover__no-print">
						<Button variant="secondary" onclick={() => askUplift(null)}>Chat with Uplift</Button>
					</div>
				</div>
			</SectionBlock>

			{#if pack.events.length}
				<details class="handover__history">
					<summary>History</summary>
					<ul>
						{#each pack.events as event (event.id)}
							<li>
								<span>{day(event.happened_at)}</span>
								{handoverEventText(event, (value) =>
									formatMeetingTime(value, pack.training?.time_zone ?? null)
								)}
							</li>
						{/each}
					</ul>
				</details>
			{/if}
		{/if}
	</div>
</PageContainer>

<style lang="scss">
	.handover {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		max-width: 880px;
		margin-inline: auto;

		:global(.page-header) {
			margin-bottom: 0;
		}

		p {
			margin: 0;
		}

		&__stamp {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__summary {
			overflow-wrap: anywhere;
			white-space: pre-line;
		}

		&__stack {
			display: grid;
			gap: var(--space-small);
		}

		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__print {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			min-height: 4.4rem;
			padding: 0 var(--space-base);
			border: 1px solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: var(--color-heading);
			font: inherit;
			font-weight: 600;
			cursor: pointer;

			:global(svg) {
				width: 1.8rem;
				height: 1.8rem;
			}

			&:hover {
				background: var(--color-surface--hover);
			}
		}

		&__guides {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;

			a {
				display: flex;
				align-items: center;
				justify-content: space-between;
				gap: var(--space-base);
				min-height: 4.8rem;
				padding: var(--space-small) var(--space-base);
				border: 1px solid var(--color-border);
				border-radius: var(--radius-base);
				color: var(--color-heading);
				font-weight: 600;
				text-decoration: none;

				&:hover {
					border-color: var(--color-interactive);
					color: var(--color-interactive);
				}
			}
		}

		&__guide-icon {
			flex: none;
			color: var(--color-text--secondary);

			:global(svg) {
				width: 1.8rem;
				height: 1.8rem;
			}
		}

		&__print-url {
			display: none;
		}

		&__wording {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-left: 3px solid var(--color-success);
			background: var(--color-surface--background);
			font-style: italic;
		}

		&__history {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			summary {
				cursor: pointer;
			}

			ul {
				display: grid;
				gap: var(--space-smaller);
				margin: var(--space-small) 0 0;
				padding-left: var(--space-base);
			}

			span {
				margin-right: var(--space-small);
			}
		}
	}

	// Printed or saved as a PDF: only the pack, with each link's address written out.
	@media print {
		:global(.app-shell > :not(.app-shell__body)),
		:global(.app-shell__body > :not(.app-shell__main)),
		:global(.support-messenger),
		:global(.support-messenger__launcher) {
			display: none !important;
		}

		:global(.app-shell),
		:global(.app-shell__body),
		:global(.app-shell__main) {
			display: block !important;
			height: auto !important;
			overflow: visible !important;
		}

		.handover {
			max-width: none;

			&__crumbs,
			&__print,
			&__no-print,
			&__guide-icon {
				display: none;
			}

			&__print-url {
				display: block;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				overflow-wrap: anywhere;
			}

			&__guides a {
				min-height: 0;
				padding: 0;
				border: 0;
			}

			&__history[open] ul,
			&__history ul {
				display: grid;
			}
		}
	}
</style>
