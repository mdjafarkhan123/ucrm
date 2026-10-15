<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import RecordCard from '$lib/components/layout/RecordCard.svelte';
	import JobSignaturesCard from '$lib/components/jobs/JobSignaturesCard.svelte';
	import JobWorkReportCard from '$lib/components/jobs/JobWorkReportCard.svelte';
	import { fetchFiles, filesListKey, type FileListFilters } from '$lib/files/api';
	import { fetchJobChecklists, jobChecklistsKey } from '$lib/checklists/api';
	import type { JobLineItem, JobVisit } from '$lib/jobs/api';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';

	// The Classic job page's Close-out card (classic.pen "Close-out card"): what is left before the job is
	// invoiced. It reads what the job already holds — photos, checklist answers, finished visits — and hosts
	// the signature and work-report rows, whose Collect and Start open the same dialogs their old cards did.
	// It decides nothing and blocks nothing; invoicing works the same whatever the ring says.
	let {
		jobId,
		visits,
		lines,
		totalMinor,
		currencyCode,
		locale,
		clientName,
		canRecord,
		active,
		canEditReport,
		onReportStateChange,
		workReport = $bindable()
	}: {
		jobId: string;
		visits: JobVisit[];
		lines: JobLineItem[];
		totalMinor: number | null;
		currencyCode: string;
		locale: string;
		clientName: string | null;
		canRecord: boolean;
		active: boolean;
		/** jobs.edit: the work report row only exists for someone who may edit the report. */
		canEditReport: boolean;
		onReportStateChange?: (hasContent: boolean) => void;
		/** The report row, so the page's More menu can still preview, print and copy its link. */
		workReport?: JobWorkReportCard;
	} = $props();

	let signed = $state(false);
	let reportReady = $state(false);

	// The same list RecordFilesCard draws, so the count and the grid never disagree or fetch twice.
	const filters = $derived<FileListFilters>({
		view: 'on_record',
		folderId: '',
		search: '',
		entityType: 'job',
		entityId: jobId
	});
	const filesQuery = createQuery(() => ({
		queryKey: filesListKey(filters),
		queryFn: () => fetchFiles(filters)
	}));
	const photoCount = $derived(
		(filesQuery.data?.files ?? []).filter((file) => file.mime_type?.startsWith('image/')).length
	);

	const checklistsQuery = createQuery(() => ({
		queryKey: jobChecklistsKey(jobId),
		queryFn: () => fetchJobChecklists(jobId)
	}));
	const checklistTotals = $derived.by(() => {
		const checklists = checklistsQuery.data?.checklists ?? [];
		const questions = checklists.reduce((sum, checklist) => sum + checklist.items.length, 0);
		const answers = checklists.reduce((sum, checklist) => sum + checklist.answers_count, 0);
		return { attached: checklists.length, expected: questions * visits.length, answers };
	});

	const visitsDone = $derived(visits.filter((visit) => visit.completed_at).length);

	type Item = { key: string; label: string; detail: string; state: 'done' | 'waiting' | 'todo' };
	const items = $derived.by(() => {
		const list: Item[] = [
			{
				key: 'photos',
				label: 'Before & after photos',
				detail: photoCount === 0 ? 'None added' : `${photoCount} added`,
				state: photoCount > 0 ? 'done' : 'todo'
			}
		];
		if (checklistTotals.attached > 0) {
			const { expected, answers } = checklistTotals;
			const complete = expected > 0 && answers >= expected;
			list.push({
				key: 'checklists',
				label: 'Checklists complete',
				detail:
					expected > 0 ? `${Math.min(answers, expected)} of ${expected} answers` : 'No visits yet',
				state: complete ? 'done' : answers > 0 ? 'waiting' : 'todo'
			});
		}
		if (visits.length > 0) {
			list.push({
				key: 'visits',
				label: 'All visits complete',
				detail: `${visitsDone} of ${visits.length} done`,
				state: visitsDone === visits.length ? 'done' : visitsDone > 0 ? 'waiting' : 'todo'
			});
		}
		return list;
	});

	const total = $derived(items.length + 1 + (canEditReport ? 1 : 0));
	const done = $derived(
		items.filter((item) => item.state === 'done').length +
			(signed ? 1 : 0) +
			(canEditReport && reportReady ? 1 : 0)
	);
	// The ring is drawn as a stroke on a 52px circle; its length is the share of items done.
	const circumference = 2 * Math.PI * 23;
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<RecordCard
	title="Close-out"
	subtitle="What's left before you invoice"
	size="rail"
	id="job-close-out"
	class="close-out"
>
	{#snippet lead()}
		<span class="close-out__ring" role="img" aria-label={`${done} of ${total} done`}>
			<svg viewBox="0 0 52 52" aria-hidden="true">
				<circle class="close-out__track" cx="26" cy="26" r="23" />
				<circle
					class="close-out__progress"
					cx="26"
					cy="26"
					r="23"
					stroke-dasharray={`${(done / total) * circumference} ${circumference}`}
				/>
			</svg>
			<span aria-hidden="true">{done}/{total}</span>
		</span>
	{/snippet}

	<ul class="close-out__list">
		{#each items as item (item.key)}
			<li
				class="close-out__item"
				class:close-out__item--done={item.state === 'done'}
				class:close-out__item--waiting={item.state === 'waiting'}
			>
				<span class="close-out__state" aria-hidden="true">
					{#if item.state === 'done'}{@html checkIcon}{:else if item.state === 'waiting'}{@html hourglassIcon}{/if}
				</span>
				<div class="close-out__text">
					<p class="close-out__label">{item.label}</p>
					<p class="close-out__detail">{item.detail}</p>
				</div>
			</li>
		{/each}
		<JobSignaturesCard
			variant="row"
			{jobId}
			{lines}
			{visits}
			{totalMinor}
			{currencyCode}
			{locale}
			{clientName}
			{canRecord}
			{active}
			onDoneChange={(next) => (signed = next)}
		/>
		{#if canEditReport}
			<JobWorkReportCard
				bind:this={workReport}
				variant="row"
				{jobId}
				onStateChange={(next) => {
					reportReady = next;
					onReportStateChange?.(next);
				}}
			/>
		{/if}
	</ul>
</RecordCard>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.close-out__ring {
		position: relative;
		display: inline-grid;
		width: 52px;
		height: 52px;
		place-items: center;
		color: var(--classic2-ink);
		font-size: var(--classic2-font-label);
		font-weight: 700;

		svg {
			position: absolute;
			inset: 0;
			transform: rotate(-90deg);
		}
	}

	.close-out__track,
	.close-out__progress {
		fill: none;
		stroke-width: 5.5;
	}

	.close-out__track {
		stroke: var(--classic2-chip);
	}

	.close-out__progress {
		stroke: var(--classic2-green);
		stroke-linecap: round;
	}

	.close-out__list {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	// Rows come from this card and from the signature and report components, so they are styled here.
	:global(.close-out) {
		:global(.close-out__item) {
			display: flex;
			align-items: center;
			gap: 12px;
			padding: 12px 20px;
			border-top: 1px solid var(--classic2-divider);
			font-family: var(--classic2-font);
		}

		:global(.close-out__state) {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			box-sizing: border-box;
			width: 24px;
			height: 24px;
			border: 1.5px solid var(--classic2-border-control);
			border-radius: 50%;
		}

		:global(.close-out__state svg) {
			width: 13px;
			height: 13px;
		}

		:global(.close-out__item--done .close-out__state) {
			border-color: var(--classic2-green);
			background: var(--classic2-green);
			color: var(--classic2-surface);
		}

		:global(.close-out__item--waiting .close-out__state) {
			border: 1px solid var(--classic2-amber-soft);
			background: var(--classic2-amber-tint);
			color: var(--classic2-amber);
		}

		:global(.close-out__item--waiting .close-out__state svg) {
			width: 12px;
			height: 12px;
		}

		:global(.close-out__text) {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			align-items: flex-start;
			gap: 2px;
			min-width: 0;
		}

		:global(.close-out__label) {
			margin: 0;
			color: var(--classic2-ink);
			font-size: var(--classic2-font-body);
			font-weight: 600;
		}

		:global(.close-out__item--done .close-out__label) {
			color: var(--classic2-secondary);
		}

		:global(.close-out__detail) {
			margin: 0;
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 500;
		}

		:global(.close-out__detail--warn) {
			color: var(--classic2-amber);
		}

		:global(.close-out__link) {
			padding: 0;
			border: 0;
			background: none;
			color: var(--classic2-green);
			font-family: var(--classic2-font);
			font-size: var(--classic2-font-small);
			font-weight: 600;
			text-align: left;
			cursor: pointer;
		}

		:global(.close-out__link--quiet) {
			color: var(--classic2-secondary);
		}

		:global(.close-out__link:hover) {
			text-decoration: underline;
		}

		:global(.close-out__action) {
			flex: 0 0 auto;
			height: 30px;
			padding: 0 10px;
			border: 1px solid var(--classic2-border-control);
			border-radius: 8px;
			background: var(--classic2-button-surface);
			color: var(--classic2-ink);
			font-family: var(--classic2-font);
			font-size: var(--classic2-font-small);
			font-weight: 600;
			cursor: pointer;
		}

		:global(.close-out__action:hover) {
			border-color: var(--classic2-green);
		}

		:global(.close-out__link:focus-visible),
		:global(.close-out__action:focus-visible) {
			outline: 2px solid var(--classic2-green);
			outline-offset: 2px;
		}
	}
</style>
