<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import RecordCard from '$lib/components/layout/RecordCard.svelte';
	import Tabs from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import JobLaborSection from '$lib/components/jobs/JobLaborSection.svelte';
	import JobExpensesSection from '$lib/components/jobs/JobExpensesSection.svelte';
	import JobChecklistsCard from '$lib/components/jobs/JobChecklistsCard.svelte';
	import {
		fetchJobExpenses,
		fetchJobLabor,
		jobExpensesKey,
		jobLaborKey,
		type JobVisit
	} from '$lib/jobs/api';
	import { fetchJobChecklists, jobChecklistsKey } from '$lib/checklists/api';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	// The Classic job page's Work log (classic.pen "Work log card"): the hours, expenses and checklists the
	// crew records against the job, as three tabs of one card instead of three cards. Each tab is the same
	// section it always was, drawn without its own card; the header's button is the open tab's "add".
	let {
		jobId,
		visits,
		locale,
		currencyCode,
		active,
		onChange
	}: {
		jobId: string;
		visits: JobVisit[];
		locale: string;
		currencyCode: string;
		/** Whether the job is open, which decides if checklists may still be attached. */
		active: boolean;
		/** Hours or an expense changed, so the page's profit figures need a refresh. */
		onChange: () => void;
	} = $props();

	let tab = $state('time');
	let laborSection = $state<JobLaborSection>();
	let expensesSection = $state<JobExpensesSection>();
	let checklistsSection = $state<JobChecklistsCard>();

	// The figures on the tabs. Same queries and keys the sections use, so nothing is fetched twice.
	const laborQuery = createQuery(() => ({
		queryKey: jobLaborKey(jobId),
		queryFn: () => fetchJobLabor(jobId),
		staleTime: 15_000
	}));
	const expensesQuery = createQuery(() => ({
		queryKey: jobExpensesKey(jobId),
		queryFn: () => fetchJobExpenses(jobId),
		staleTime: 15_000
	}));
	const checklistsQuery = createQuery(() => ({
		queryKey: jobChecklistsKey(jobId),
		queryFn: () => fetchJobChecklists(jobId)
	}));

	const money = $derived(
		new Intl.NumberFormat(locale, {
			style: 'currency',
			currency: currencyCode,
			maximumFractionDigits: 0
		})
	);

	function duration(minutes: number) {
		const hours = Math.floor(minutes / 60);
		const rest = minutes % 60;
		if (hours === 0) return `${rest}m`;
		if (rest === 0) return `${hours}h`;
		return `${hours}h ${rest}m`;
	}

	const timeChip = $derived(laborQuery.data ? duration(laborQuery.data.totals.minutes) : undefined);
	const expensesChip = $derived.by(() => {
		const data = expensesQuery.data;
		if (!data) return undefined;
		if (data.can_see_cost && data.totals.total_minor !== null) {
			return money.format(data.totals.total_minor / 100);
		}
		return data.totals.expense_count;
	});
	// Answers given against the answers the job's visits could hold: every question on every visit.
	const checklistsChip = $derived.by(() => {
		const checklists = checklistsQuery.data?.checklists;
		if (!checklists) return undefined;
		if (checklists.length === 0) return 0;
		const questions = checklists.reduce((sum, checklist) => sum + checklist.items.length, 0);
		const answers = checklists.reduce((sum, checklist) => sum + checklist.answers_count, 0);
		const expected = questions * visits.length;
		return expected > 0 ? `${Math.min(answers, expected)} of ${expected}` : checklists.length;
	});

	const tabs = $derived([
		{ value: 'time', label: 'Time', count: timeChip },
		{ value: 'expenses', label: 'Expenses', count: expensesChip },
		{ value: 'checklists', label: 'Checklists', count: checklistsChip }
	]);

	const addAction = $derived.by(() => {
		if (tab === 'time' && laborQuery.data?.can_add) {
			return { label: 'Add time', run: () => laborSection?.openAdd() };
		}
		if (tab === 'expenses' && expensesQuery.data?.can_add) {
			return { label: 'Add expense', run: () => expensesSection?.openAdd() };
		}
		if (tab === 'checklists' && checklistsQuery.data?.can_edit && active) {
			return { label: 'Add checklist', run: () => checklistsSection?.startAdd() };
		}
		return null;
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<RecordCard
	title="Work log"
	subtitle="What the crew has logged on this job"
	id="job-work-log"
	class="work-log"
>
	{#snippet actions()}
		{#if addAction}
			<button type="button" class="work-log__add" onclick={addAction.run}>
				<span aria-hidden="true">{@html plusIcon}</span>{addAction.label}
			</button>
		{/if}
	{/snippet}

	<Tabs {tabs} bind:value={tab} label="Work log" variant="card">
		<TabPanel value="time">
			<JobLaborSection
				bind:this={laborSection}
				embedded
				{jobId}
				{visits}
				{locale}
				{currencyCode}
				{onChange}
			/>
		</TabPanel>
		<TabPanel value="expenses">
			<JobExpensesSection
				bind:this={expensesSection}
				embedded
				{jobId}
				{locale}
				{currencyCode}
				{onChange}
			/>
		</TabPanel>
		<TabPanel value="checklists">
			<JobChecklistsCard bind:this={checklistsSection} embedded {jobId} {active} />
		</TabPanel>
	</Tabs>
</RecordCard>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// Row styles shared by the three tabs' rows (classic.pen Work log "Entry" rows).
	:global(.work-log) {
		:global(.tabs__list) {
			border-bottom: 1px solid var(--classic2-divider);
		}

		.work-log__add {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			height: 36px;
			padding: 0 12px;
			border: 1px solid var(--classic2-border-control);
			border-radius: var(--classic2-radius-control);
			background: var(--classic2-button-surface);
			box-shadow: 0 1px 2px var(--classic2-shadow-far);
			color: var(--classic2-ink);
			font-family: var(--classic2-font);
			font-size: var(--classic2-font-label);
			font-weight: 600;
			cursor: pointer;

			span {
				display: inline-flex;
				color: var(--classic2-secondary);
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			&:hover {
				border-color: var(--classic2-green);
			}

			&:focus-visible {
				outline: 2px solid var(--classic2-green);
				outline-offset: 2px;
			}
		}

		:global(.work-log__rows) {
			margin: 0;
			padding: 0;
			list-style: none;
		}

		:global(.work-log__row) {
			display: grid;
			align-items: center;
			gap: 0 14px;
			grid-template-columns: 34px minmax(0, 1fr) auto 110px 36px;
			padding: 14px 24px;
			font-family: var(--classic2-font);
		}

		:global(.work-log__row + .work-log__row) {
			border-top: 1px solid var(--classic2-divider);
		}

		:global(.work-log__row--busy) {
			opacity: 0.6;
		}

		:global(.work-log__row .avatar) {
			width: 34px;
			height: 34px;
			border: 0;
			font-size: 11px;
		}

		:global(.work-log__tile) {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 34px;
			height: 34px;
			border-radius: var(--classic2-radius-control);
		}

		:global(.work-log__tile svg) {
			width: 16px;
			height: 16px;
		}

		:global(.work-log__tile--amber) {
			background: var(--classic2-amber-tint);
			color: var(--classic2-amber);
		}

		:global(.work-log__tile--teal) {
			background: var(--classic2-teal-tint);
			color: var(--classic2-teal);
		}

		:global(.work-log__info) {
			display: flex;
			flex-direction: column;
			gap: 3px;
			min-width: 0;
		}

		:global(.work-log__who) {
			display: flex;
			align-items: center;
			gap: 6px;
			margin: 0;
			color: var(--classic2-ink);
			font-size: var(--classic2-font-body);
			font-weight: 600;
		}

		:global(.work-log__receipt) {
			display: inline-flex;
			align-items: center;
			gap: 2px;
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
		}

		:global(.work-log__receipt svg) {
			width: 13px;
			height: 13px;
		}

		:global(.work-log__context) {
			margin: 0;
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 500;
		}

		:global(.work-log__notes) {
			margin: 2px 0 0;
			color: var(--classic2-body);
			font-size: var(--classic2-font-small);
			overflow-wrap: anywhere;
		}

		:global(.work-log__range) {
			color: var(--classic2-body);
			font-size: var(--classic2-font-label);
			font-weight: 500;
			white-space: nowrap;
		}

		:global(.work-log__figure) {
			display: flex;
			flex-direction: column;
			align-items: flex-end;
			color: var(--classic2-ink);
			font-size: var(--classic2-font-body);
			font-weight: 700;
			text-align: right;
			white-space: nowrap;
		}

		:global(.work-log__figure small) {
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 500;
		}

		:global(.work-log__figure small.work-log__unrated) {
			color: var(--classic2-amber);
		}

		:global(.work-log__figure--live) {
			flex-direction: row;
			align-items: center;
			justify-content: flex-end;
			gap: 6px;
			color: var(--classic2-green);
		}

		:global(.work-log__live-dot) {
			width: 7px;
			height: 7px;
			border-radius: 50%;
			background: var(--classic2-green);
		}

		:global(.work-log__menu) {
			display: flex;
			justify-content: center;
		}

		:global(.work-log__icon-button) {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 32px;
			height: 32px;
			padding: 0;
			border: 0;
			border-radius: 10px;
			background: transparent;
			color: var(--classic2-icon-muted);
			cursor: pointer;
		}

		:global(.work-log__icon-button svg) {
			width: 16px;
			height: 16px;
		}

		:global(.work-log__icon-button:hover) {
			background: var(--classic2-rose-tint);
			color: var(--classic2-rose);
		}

		:global(.work-log__icon-button:focus-visible) {
			outline: 2px solid var(--classic2-green);
			outline-offset: 2px;
		}

		:global(.work-log__state),
		:global(.work-log__band) {
			margin: 0;
			padding: 14px 24px;
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
		}

		:global(.work-log__band) {
			border-top: 1px solid var(--classic2-divider);
			color: var(--classic2-amber);
		}

		:global(.work-log__empty),
		:global(.work-log__attach) {
			padding: 16px 24px 20px;
		}

		:global(.work-log__attach) {
			border-top: 1px solid var(--classic2-divider);
		}

		:global(.work-log__footer) {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: 12px;
			padding: 12px 24px;
			border-top: 1px solid var(--classic2-divider);
			background: var(--classic2-surface-soft);
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 500;
		}

		:global(.work-log__show) {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			gap: 4px;
			padding: 0;
			border: 0;
			background: none;
			color: var(--classic2-green);
			font-family: var(--classic2-font);
			font-size: var(--classic2-font-label);
			font-weight: 600;
			cursor: pointer;
		}

		:global(.work-log__show svg) {
			width: 14px;
			height: 14px;
		}

		:global(.work-log__show:focus-visible) {
			outline: 2px solid var(--classic2-green);
			outline-offset: 2px;
		}
	}

	@media (max-width: 767px) {
		:global(.work-log .work-log__row) {
			grid-template-columns: 34px minmax(0, 1fr) auto 36px;
			padding: 12px 16px;
		}

		:global(.work-log .work-log__range) {
			display: none;
		}
	}
</style>
