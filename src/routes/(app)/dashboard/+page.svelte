<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import coinsIcon from '@tabler/icons/outline/coins.svg?raw';
	import FieldWorkerHome from '$lib/components/dashboard/FieldWorkerHome.svelte';
	import HomeMoneyOwedCard from '$lib/components/dashboard/HomeMoneyOwedCard.svelte';
	import HomePerformanceCard, {
		type PerformanceMetric
	} from '$lib/components/dashboard/HomePerformanceCard.svelte';
	import HomeScheduleCard from '$lib/components/dashboard/HomeScheduleCard.svelte';
	import HomeTodoCard from '$lib/components/dashboard/HomeTodoCard.svelte';
	import ReadinessCard from '$lib/components/dashboard/ReadinessCard.svelte';
	import SetupCard from '$lib/components/dashboard/SetupCard.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import DayClockCard from '$lib/components/time-clock/DayClockCard.svelte';
	import {
		collectedKey,
		fetchCollected,
		fetchInvoiced,
		fetchMoneyOwed,
		fetchPastDueInvoices,
		invoicedKey,
		moneyOwedKey,
		pastDueInvoicesKey
	} from '$lib/home/api';
	import { monthComparison } from '$lib/home/money';
	import { buildHomeSchedule, scheduleWindowFor } from '$lib/home/schedule';
	import { buildTodoColumns, type TodoColumnKey } from '$lib/home/todo';
	import { fallbackContractorNavigation } from '$lib/account/navigation';
	import { fetchInvoiceOverview, invoiceCountsKey } from '$lib/invoices/api';
	import { fetchJobOverview, jobCountsKey } from '$lib/jobs/api';
	import { fetchQuoteOverview, quoteCountsKey } from '$lib/quotes/api';
	import { fetchRequestCounts, requestCountsKey } from '$lib/requests/api';
	import {
		fetchScheduleContext,
		fetchScheduleWindow,
		scheduleContextKey,
		scheduleWindowKey
	} from '$lib/schedule/api';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';
	import { calendarDay, clockMinutesInZone } from '$lib/time/calendar-day';
	import type { PageProps } from './$types';

	// Home. The owner, office and finance see the day at a glance (what is waiting, today's schedule, money
	// owed, how the month is going), each card only if the person may see its area. A field worker keeps the
	// workspace summary they always had. Every card reads on its own, so one failing never blocks the rest.
	let { data: shell }: PageProps = $props();
	const hasOrganization = $derived(Boolean(shell.organization));
	const role = $derived(shell.organization?.role);
	const isFieldWorker = $derived(role === 'field');
	// Client setup is the owner's or an administrator's job, so nobody else is asked about it.
	const runsSetup = $derived(role === 'owner' || role === 'admin');
	const nav = $derived(shell.navigation ?? fallbackContractorNavigation);
	const ready = $derived(hasOrganization && !isFieldWorker);

	// --- Time: the business's own day, ticking so a page left open overnight rolls over ---------------------

	let clock = $state(new Date());
	$effect(() => {
		const tick = setInterval(() => (clock = new Date()), 60_000);
		return () => clearInterval(tick);
	});

	const scheduleContext = createQuery(() => ({
		queryKey: scheduleContextKey,
		queryFn: fetchScheduleContext,
		enabled: ready && nav.schedule,
		staleTime: 10 * 60 * 1000
	}));

	// --- To do: the same overviews the list pages draw -----------------------------------------------------

	const requestCounts = createQuery(() => ({
		queryKey: requestCountsKey,
		queryFn: fetchRequestCounts,
		enabled: ready && nav.requests,
		staleTime: 30_000
	}));
	const quoteOverview = createQuery(() => ({
		queryKey: quoteCountsKey,
		queryFn: fetchQuoteOverview,
		enabled: ready && nav.quotes,
		staleTime: 30_000
	}));
	const jobOverview = createQuery(() => ({
		queryKey: jobCountsKey,
		queryFn: fetchJobOverview,
		enabled: ready && nav.jobs,
		staleTime: 30_000
	}));
	const invoiceOverview = createQuery(() => ({
		queryKey: invoiceCountsKey,
		queryFn: fetchInvoiceOverview,
		enabled: ready && nav.invoices,
		staleTime: 30_000
	}));

	const timezone = $derived(
		scheduleContext.data?.timezone ??
			quoteOverview.data?.timezone ??
			Intl.DateTimeFormat().resolvedOptions().timeZone
	);
	// The business's timezone is known once the schedule context or the quotes overview has answered; before
	// that the device's own is the best guess, and the day-dependent cards wait for the real one.
	const timezoneKnown = $derived(
		Boolean(scheduleContext.data?.timezone ?? quoteOverview.data?.timezone) ||
			(!nav.schedule && !nav.quotes)
	);
	const today = $derived(calendarDay(clock, timezone));

	const todoColumns = $derived(
		buildTodoColumns(
			{
				requests: nav.requests,
				quotes: nav.quotes,
				jobs: nav.jobs,
				invoices: nav.invoices
			},
			{
				requests: requestCounts.data,
				quotes: quoteOverview.data,
				jobs: jobOverview.data,
				invoices: invoiceOverview.data
			}
		)
	);
	const failedColumns = $derived<TodoColumnKey[]>([
		...(requestCounts.isError ? (['requests'] as const) : []),
		...(quoteOverview.isError ? (['quotes'] as const) : []),
		...(jobOverview.isError ? (['jobs'] as const) : []),
		...(invoiceOverview.isError ? (['invoices'] as const) : [])
	]);
	function retryColumn(key: TodoColumnKey) {
		void { requests: requestCounts, quotes: quoteOverview, jobs: jobOverview, invoices: invoiceOverview }[
			key
		].refetch();
	}
	const currency = $derived(
		invoiceOverview.data?.currency_code ??
			jobOverview.data?.currency_code ??
			quoteOverview.data?.currency_code ??
			'USD'
	);
	const locale = $derived(
		invoiceOverview.data?.locale ??
			jobOverview.data?.locale ??
			quoteOverview.data?.locale ??
			'en-US'
	);

	// --- Today's schedule ------------------------------------------------------------------------------------

	const scheduleWindow = $derived(scheduleWindowFor(today));
	const windowQuery = createQuery(() => ({
		queryKey: scheduleWindowKey(scheduleWindow),
		queryFn: () => fetchScheduleWindow(scheduleWindow),
		enabled: ready && nav.schedule && Boolean(scheduleContext.data),
		staleTime: 30_000
	}));
	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		enabled: ready && nav.schedule,
		staleTime: 5 * 60 * 1000
	}));
	const schedule = $derived(
		windowQuery.data && scheduleContext.data
			? buildHomeSchedule(windowQuery.data, scheduleContext.data.timezone, today)
			: undefined
	);

	// --- Money: shown only to people who may see invoice prices -------------------------------------------

	// Until the invoices overview answers, a person with invoice access is assumed to see money; the overview
	// carries nothing for a reader without prices, and then the whole money rail is left out.
	const canSeeMoney = $derived(
		ready &&
			nav.invoices &&
			!invoiceOverview.isError &&
			(invoiceOverview.data ? invoiceOverview.data.outstanding_minor !== null : true)
	);
	const moneyReady = $derived(canSeeMoney && timezoneKnown);

	const moneyOwed = createQuery(() => ({
		queryKey: moneyOwedKey(today),
		queryFn: () => fetchMoneyOwed(today),
		enabled: moneyReady,
		staleTime: 60_000
	}));
	const pastDue = createQuery(() => ({
		queryKey: pastDueInvoicesKey,
		queryFn: fetchPastDueInvoices,
		enabled: moneyReady,
		staleTime: 60_000
	}));

	const months = $derived(monthComparison(today));
	const invoicedNow = createQuery(() => ({
		queryKey: invoicedKey(months.current),
		queryFn: () => fetchInvoiced(months.current),
		enabled: moneyReady,
		staleTime: 60_000
	}));
	const invoicedBefore = createQuery(() => ({
		queryKey: invoicedKey(months.previous),
		queryFn: () => fetchInvoiced(months.previous),
		enabled: moneyReady,
		staleTime: 60_000
	}));
	const collectedNow = createQuery(() => ({
		queryKey: collectedKey(months.current),
		queryFn: () => fetchCollected(months.current),
		enabled: moneyReady,
		staleTime: 60_000
	}));
	const collectedBefore = createQuery(() => ({
		queryKey: collectedKey(months.previous),
		queryFn: () => fetchCollected(months.previous),
		enabled: moneyReady,
		staleTime: 60_000
	}));

	const metrics = $derived<PerformanceMetric[]>([
		{
			key: 'invoiced',
			label: 'Invoiced · this month',
			icon: receiptIcon,
			tone: 'informative',
			current: invoicedNow.data ?? null,
			previous: invoicedBefore.data ?? null,
			loading: !moneyReady || invoicedNow.isPending || invoicedBefore.isPending,
			failed: invoicedNow.isError || invoicedBefore.isError
		},
		{
			key: 'collected',
			label: 'Collected · this month',
			icon: coinsIcon,
			tone: 'success',
			current: collectedNow.data ?? null,
			previous: collectedBefore.data ?? null,
			loading: !moneyReady || collectedNow.isPending || collectedBefore.isPending,
			failed: collectedNow.isError || collectedBefore.isError
		}
	]);
	function retryMetric(key: string) {
		if (key === 'invoiced') {
			void invoicedNow.refetch();
			void invoicedBefore.refetch();
		} else {
			void collectedNow.refetch();
			void collectedBefore.refetch();
		}
	}

	// --- The header ------------------------------------------------------------------------------------------

	const firstName = $derived(shell.account?.name?.trim().split(/\s+/)[0] ?? '');
	const greeting = $derived.by(() => {
		const hour = Math.floor(clockMinutesInZone(clock, timezone) / 60);
		const part = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
		return firstName ? `${part}, ${firstName}` : part;
	});
	const dateLine = $derived.by(() => {
		const day = new Intl.DateTimeFormat('en-US', {
			weekday: 'long',
			month: 'long',
			day: 'numeric',
			timeZone: timezone
		}).format(clock);
		const business = shell.organization?.name;
		return business ? `${day} · Here’s your day at ${business}.` : `${day}.`;
	});

	const showSchedule = $derived(nav.schedule);
	const showRail = $derived(canSeeMoney);
</script>

<svelte:head><title>Home · Contractor CRM</title></svelte:head>

{#if isFieldWorker}
	<FieldWorkerHome {hasOrganization} {runsSetup} userId={shell.user?.id ?? null} />
{:else}
	<div class="page-scroller">
		<PageContainer variant="open">
			<PageHeader class="home-page__header" eyebrow="Home" title={greeting} description={dateLine}>
				{#snippet actions()}
					{#if hasOrganization}<DayClockCard />{/if}
				{/snippet}
			</PageHeader>

			{#if hasOrganization}
				<div class="home">
					{#if runsSetup}
						<div class="home__setup">
							<SetupCard userId={shell.user?.id ?? null} />
							<ReadinessCard userId={shell.user?.id ?? null} />
						</div>
					{/if}

					{#if todoColumns.length > 0}
						<HomeTodoCard
							columns={todoColumns}
							failed={failedColumns}
							{currency}
							{locale}
							onretry={retryColumn}
						/>
					{/if}

					{#if showSchedule || showRail}
						<div class={['home__grid', !showSchedule && 'home__grid--rail-only']}>
							{#if showSchedule}
								<HomeScheduleCard
									{schedule}
									team={teamQuery.data ?? []}
									loading={!schedule && !scheduleContext.isError && !windowQuery.isError}
									failed={scheduleContext.isError || windowQuery.isError}
									onretry={() => {
										if (scheduleContext.isError) void scheduleContext.refetch();
										void windowQuery.refetch();
									}}
								/>
							{/if}
							{#if showRail}
								<div class="home__rail">
									<HomeMoneyOwedCard
										owed={moneyOwed.data}
										overdueInvoices={pastDue.data ?? []}
										{today}
										{currency}
										{locale}
										loading={!moneyReady || moneyOwed.isPending}
										failed={moneyOwed.isError}
										onretry={() => void moneyOwed.refetch()}
									/>
									<HomePerformanceCard
										{metrics}
										currentLabel={months.currentLabel}
										previousLabel={months.previousLabel}
										{currency}
										{locale}
										onretry={retryMetric}
									/>
								</div>
							{/if}
						</div>
					{/if}
				</div>
			{:else}
				<section class="home__notice">
					<strong>Your account is signed in, but it is not connected to an organization yet.</strong
					><span
						>Ask the platform owner to add you to a contractor organization before creating records.</span
					>
				</section>
			{/if}
		</PageContainer>
	</div>
{/if}

<style lang="scss">
	:global(.home-page__header) {
		margin-bottom: var(--space-large);
	}

	.home {
		container-type: inline-size;
		display: grid;
		gap: var(--space-large);
		min-width: 0;

		&__setup {
			display: grid;
			gap: var(--space-large);
			min-width: 0;

			&:empty {
				display: none;
			}
		}

		/* The schedule takes the room it needs; the rail keeps a steady width beside it. */
		&__grid {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 336px;
			align-items: start;
			gap: 20px;

			&--rail-only {
				grid-template-columns: minmax(0, 1fr);
			}
		}
		&__rail {
			display: grid;
			gap: 16px;
			min-width: 0;
		}
	}
	.home__notice {
		display: flex;
		flex-direction: column;
		gap: 4px;
		padding: 16px 20px;
		border: 1px solid var(--color-warning);
		border-radius: var(--radius-base);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}

	/* With less room, the rail drops under the schedule and its two cards sit side by side. */
	@container (max-width: 900px) {
		.home__grid {
			grid-template-columns: minmax(0, 1fr);
		}
		.home__rail {
			grid-template-columns: repeat(2, minmax(0, 1fr));
			align-items: start;
		}
	}
	@container (max-width: 640px) {
		.home__rail {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
