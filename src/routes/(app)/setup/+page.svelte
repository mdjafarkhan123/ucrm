<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchSetupCheck,
		fetchSetupSection,
		fetchSetupSummary,
		markSetupWelcomeSeen,
		setSetupReminderEmails,
		setupCheckKey,
		setupSectionKey,
		setupSummaryKey,
		type SetupSummary
	} from '$lib/setup/api';
	import type { SetupSectionStatus } from '$lib/setup/catalogue';
	import { SETUP_CHECK_DESCRIPTION, SETUP_CHECK_KEY, SETUP_CHECK_TITLE } from '$lib/setup/check';
	import { setupClientReviewBadge } from '$lib/setup/review';
	import type { HttpError } from '$lib/http-error';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import toolsIcon from '@tabler/icons/outline/tools.svg?raw';
	import folderIcon from '@tabler/icons/outline/folder.svg?raw';
	import cloudCheckIcon from '@tabler/icons/outline/cloud-check.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import layoutDashboardIcon from '@tabler/icons/outline/layout-dashboard.svg?raw';
	import lifebuoyIcon from '@tabler/icons/outline/lifebuoy.svg?raw';
	import type { PageProps } from './$types';

	let { data: shell }: PageProps = $props();
	const userId = $derived(shell.user?.id ?? null);

	const queryClient = useQueryClient();
	const query = createQuery(() => ({
		queryKey: setupSummaryKey(userId),
		queryFn: fetchSetupSummary
	}));

	// Whether this visit is the first one is decided once, when the answer first arrives: the welcome stays
	// on screen for the whole visit even though showing it is what marks it as seen.
	let firstVisit = $state<boolean | null>(null);
	$effect(() => {
		const summary = query.data;
		if (!summary) return;
		untrack(() => {
			if (firstVisit !== null) return;
			firstVisit = !summary.welcome_seen;
			if (firstVisit) void recordWelcomeSeen();
		});
	});

	async function recordWelcomeSeen() {
		try {
			await markSetupWelcomeSeen();
			queryClient.setQueryData<SetupSummary>(setupSummaryKey(userId), (current) =>
				current ? { ...current, welcome_seen: true } : current
			);
		} catch {
			// Nothing to tell the person: the welcome simply greets them again next time.
		}
	}

	// What the plan promises the welcome explains (§2), in the order a new client needs it.
	const WELCOME_POINTS = [
		{
			icon: toolsIcon,
			title: 'What Uplift sets up for you',
			body: 'Your website, brand, Google presence, calls and texts, reviews and CRM defaults — whichever your package includes.'
		},
		{
			icon: folderIcon,
			title: 'Handy to have nearby',
			body: 'Your business details, logo and photos if you have them, and the phone and email customers use.'
		},
		{
			icon: cloudCheckIcon,
			title: 'Saves as you go',
			body: 'Every answer saves on its own. Stop whenever you like and carry on later, on your laptop or your phone.'
		},
		{
			icon: pencilIcon,
			title: 'Plain facts are enough',
			body: 'No need to write anything polished. Give us the facts and Uplift writes the wording.'
		},
		{
			icon: layoutDashboardIcon,
			title: 'Your CRM already works',
			body: 'Everything in the menu is ready to use today. Setup never locks any of it.'
		},
		{
			icon: lifebuoyIcon,
			title: 'Stuck on something?',
			body: 'Choose “I need Uplift’s help” on a question and carry on, or ask us anything with Chat with Uplift in the bottom corner of every screen.'
		}
	];

	const STATUS: Record<
		SetupSectionStatus,
		{ label: string; badge: 'inactive' | 'informative' | 'success' }
	> = {
		not_started: { label: 'Not started', badge: 'inactive' },
		in_progress: { label: 'In progress', badge: 'informative' },
		done: { label: 'Done', badge: 'success' }
	};

	// C3b: once sent, a finished task shows where it stands with Uplift; one reopened shows its own status.
	function taskStatus(section: SetupSummary['sections'][number]) {
		return (
			(section.status === 'done' ? setupClientReviewBadge(section.review) : null) ??
			STATUS[section.status]
		);
	}

	// The section's answers start loading when the pointer or keyboard reaches its row, so the form is
	// already there on the click.
	function warmSection(key: string) {
		if (key === SETUP_CHECK_KEY) return warmCheck();
		void queryClient.prefetchQuery({
			queryKey: setupSectionKey(userId, key),
			queryFn: () => fetchSetupSection(key),
			staleTime: 30_000
		});
	}

	function warmCheck() {
		void queryClient.prefetchQuery({
			queryKey: setupCheckKey(userId),
			queryFn: fetchSetupCheck,
			staleTime: 30_000
		});
	}

	// B13: the last row, which the system writes — GOV.UK's "Cannot start yet" until every task is done.
	function checkStatus(summary: SetupSummary): {
		label: string;
		badge: 'inactive' | 'informative' | 'success';
	} {
		if (summary.delivery.state === 'sent')
			return summary.sections.some((section) => section.review?.changed)
				? { label: 'Changes to send', badge: 'informative' }
				: { label: 'Sent to Uplift', badge: 'success' };
		return summary.progress.done === summary.progress.total
			? { label: 'Ready to send', badge: 'informative' }
			: { label: 'Cannot send yet', badge: 'inactive' };
	}

	// Reminder emails are each person's own choice. The switch moves at once and goes back if the save fails.
	const toast = getToastManager();
	let savingReminders = $state(false);
	async function changeReminderEmails(emailsOn: boolean) {
		const key = setupSummaryKey(userId);
		const setOn = (on: boolean) =>
			queryClient.setQueryData<SetupSummary>(key, (current) =>
				current ? { ...current, reminder_emails_on: on } : current
			);
		setOn(emailsOn);
		savingReminders = true;
		try {
			await setSetupReminderEmails(emailsOn);
			toast.success(emailsOn ? 'Reminder emails are on.' : 'Reminder emails are off.');
		} catch (error) {
			setOn(!emailsOn);
			toast.error('Could not change reminder emails', (error as Error).message);
		} finally {
			savingReminders = false;
		}
	}

	const forbidden = $derived((query.error as HttpError | null)?.status === 403);
</script>

<svelte:head><title>Setup · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<div class="setup">
		<PageHeader
			eyebrow="Setup"
			title="Set up your Uplift system"
			description="Tell Uplift about your business once. We use your answers to build everything in your package."
		/>

		{#if query.isPending || firstVisit === null}
			{#if query.isError}
				{#if forbidden}
					<ErrorState
						title="Setup is handled by your account owner"
						description="Only an owner or administrator fills in setup. The rest of the CRM is ready for you to use."
					/>
				{:else}
					<ErrorState description="Setup could not be loaded." retry={() => query.refetch()} />
				{/if}
			{:else}
				<LoadingSkeleton variant="card" rows={3} />
			{/if}
		{:else if query.data}
			{@const summary = query.data}

			{#snippet howItWorks()}
				<ul class="setup__points">
					{#each WELCOME_POINTS as point (point.title)}
						<li class="setup__point">
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							<span class="setup__point-icon" aria-hidden="true">{@html point.icon}</span>
							<div>
								<strong>{point.title}</strong>
								<p>{point.body}</p>
							</div>
						</li>
					{/each}
				</ul>
			{/snippet}

			{#snippet returned()}
				{#if summary.returned_count > 0}
					{@const count = summary.returned_count}
					<Banner type="warning">
						{#if summary.next?.returned}
							Uplift looked over your setup and sent back {count === 1
								? 'one task'
								: `${count} tasks`}. Change the highlighted answers, then send your setup again.
							Everything else stays as you sent it.
						{:else}
							You have changed what Uplift asked for. Send your setup again so Uplift can look.
						{/if}
						{#snippet action()}
							{#if summary.next?.returned}
								<Button
									size="small"
									variant="secondary"
									href={resolve('/(app)/setup/[section]', { section: summary.next.key })}
									onhover={() => summary.next && warmSection(summary.next.key)}
									>Open {summary.next.title}</Button
								>
							{:else}
								<Button
									size="small"
									variant="secondary"
									href={resolve('/(app)/setup/check-and-send')}
									onhover={warmCheck}>Send your changes</Button
								>
							{/if}
						{/snippet}
					</Banner>
				{/if}
			{/snippet}

			{#snippet tasks()}
				<SectionBlock title="Your setup tasks" hint="Do them in any order, a little at a time.">
					{#snippet actions()}
						<span class="setup__count"
							>{summary.progress.done} of {summary.progress.total} done</span
						>
					{/snippet}
					<ul class="setup__tasks">
						{#each summary.sections as section (section.key)}
							{@const status = taskStatus(section)}
							<li>
								<a
									class="setup__task"
									href={resolve('/(app)/setup/[section]', { section: section.key })}
									onpointerenter={() => warmSection(section.key)}
									onfocus={() => warmSection(section.key)}
								>
									<span class="setup__task-copy">
										<strong>{section.title}</strong>
										<span>{section.description}</span>
									</span>
									<Badge status={status.badge} size="small">{status.label}</Badge>
									<span class="setup__task-chevron" aria-hidden="true">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -->
										{@html chevronRightIcon}
									</span>
								</a>
							</li>
						{/each}
						<li>
							<a
								class="setup__task"
								href={resolve('/(app)/setup/check-and-send')}
								onpointerenter={warmCheck}
								onfocus={warmCheck}
							>
								<span class="setup__task-copy">
									<strong>{SETUP_CHECK_TITLE}</strong>
									<span>{SETUP_CHECK_DESCRIPTION}</span>
								</span>
								<Badge status={checkStatus(summary).badge} size="small"
									>{checkStatus(summary).label}</Badge
								>
								<span class="setup__task-chevron" aria-hidden="true">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									{@html chevronRightIcon}
								</span>
							</a>
						</li>
					</ul>
				</SectionBlock>
			{/snippet}

			{#snippet reminders()}
				<section id="reminder-emails" class="setup__reminders" aria-label="Reminder emails">
					<Toggle
						id="setup-reminder-emails"
						label="Email me reminders"
						description="If setup sits untouched, we email you after a day, 3 days and a week with the next task. They stop once setup is sent to Uplift, and start again if Uplift sends a task back."
						labelSide="start"
						checked={summary.reminder_emails_on}
						disabled={savingReminders}
						onchange={changeReminderEmails}
					/>
				</section>
			{/snippet}

			{#if firstVisit}
				<section class="setup__welcome" aria-labelledby="setup-welcome-heading">
					<h2 id="setup-welcome-heading">Welcome — here is how setup works</h2>
					{@render howItWorks()}
					<div class="setup__welcome-actions">
						{#if summary.next}
							<Button
								href={resolve('/(app)/setup/[section]', { section: summary.next.key })}
								onhover={() => summary.next && warmSection(summary.next.key)}>Start setup</Button
							>
						{/if}
						<Button variant="tertiary" href={resolve('/(app)/dashboard')}
							>Look around the CRM first</Button
						>
					</div>
				</section>
				{@render returned()}
				{@render tasks()}
				{@render reminders()}
			{:else}
				{@render returned()}
				{@render tasks()}
				<SectionBlock title="How setup works">
					{@render howItWorks()}
				</SectionBlock>
				{@render reminders()}
			{/if}
		{/if}
	</div>
</PageContainer>

<style lang="scss">
	.setup {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		max-width: 880px;
		margin-inline: auto;

		// PageHeader carries its own bottom margin; the column gap already spaces what follows.
		:global(.page-header) {
			margin-bottom: 0;
		}

		&__welcome {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-large);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);

			h2 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
			}
		}

		&__welcome-actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__points {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base) var(--space-large);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__point {
			display: flex;
			gap: var(--space-slim);
			min-width: 0;

			strong {
				display: block;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
			}

			p {
				margin-top: var(--space-smallest);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				line-height: var(--typography--lineHeight-base);
			}
		}

		&__point-icon {
			display: grid;
			flex: none;
			place-items: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			background: var(--color-surface);
			border: var(--border-base) solid var(--color-border);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__reminders {
			padding: var(--space-base) var(--space-large);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			scroll-margin-top: var(--space-large);
		}

		&__count {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__tasks {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;

			li + li {
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__task {
			display: flex;
			align-items: center;
			gap: var(--space-base);
			padding: var(--space-slim) var(--space-small);
			border-radius: var(--radius-base);
			color: inherit;
			text-decoration: none;
			transition: background var(--timing-quick) ease;

			&:hover {
				background: var(--color-surface--hover);
			}
		}

		&__task-copy {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__task-chevron {
			display: grid;
			flex: none;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}
	}

	@media (max-width: 767px) {
		.setup {
			&__points {
				grid-template-columns: 1fr;
			}

			&__welcome,
			&__reminders {
				padding: var(--space-base);
			}

			&__task {
				flex-wrap: wrap;
				gap: var(--space-small);
				padding-inline: 0;
			}

			&__task-copy {
				flex-basis: 100%;
			}

			&__task-chevron {
				margin-left: auto;
			}
		}
	}
</style>
