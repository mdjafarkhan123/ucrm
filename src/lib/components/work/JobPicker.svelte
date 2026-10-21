<script lang="ts">
	import { untrack } from 'svelte';
	import { Combobox } from 'bits-ui';
	import { createQuery } from '@tanstack/svelte-query';
	import { fetchJobs, type JobListItem } from '$lib/jobs/api';
	import type { PickedJob } from '$lib/time-clock/corrections';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import exclamationCircleIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';

	// Search-and-pick a job, the same combobox shape as `work/ClientPicker.svelte`. Typing searches the Jobs
	// list itself — a title, a client's name, or the job's number — so it only ever offers jobs this person
	// may open, ranked as the Jobs page ranks them.

	let {
		value = $bindable(''),
		id,
		label = 'Job',
		required = false,
		invalid = false,
		errorMessage = '',
		placeholder = 'Search by title, client or number',
		initialJob = null,
		onSelect
	}: {
		value?: string;
		id: string;
		label?: string;
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		placeholder?: string;
		/** The job already chosen when the field opens (an entry being corrected), so it reads at rest. */
		initialJob?: PickedJob | null;
		onSelect?: (job: PickedJob | null) => void;
	} = $props();

	let query = $state('');
	let open = $state(false);
	let debouncedQuery = $state('');
	let selected = $state<PickedJob | null>(untrack(() => initialJob));

	$effect(() => {
		const term = query.trim();
		const handle = setTimeout(() => (debouncedQuery = term), 300);
		return () => clearTimeout(handle);
	});

	const jobsQuery = createQuery(() => ({
		queryKey: ['jobs', 'picker', debouncedQuery],
		queryFn: () =>
			fetchJobs({
				search: debouncedQuery,
				statuses: [],
				types: [],
				created_from: '',
				created_to: '',
				sort: 'created',
				dir: 'desc',
				limit: 20
			}),
		enabled: open,
		staleTime: 15_000,
		gcTime: 60_000
	}));
	const results = $derived(jobsQuery.data?.jobs ?? []);
	const comboboxItems = $derived(results.map((job) => ({ value: job.id, label: jobLabel(job) })));

	function jobLabel(job: Pick<JobListItem, 'job_number' | 'title'>) {
		return job.title ? `#${job.job_number} · ${job.title}` : `Job #${job.job_number}`;
	}

	function metaFor(job: JobListItem) {
		return job.client?.display_name ?? job.client?.company_name ?? 'No client';
	}

	let inputValue = $derived(open ? query : selected ? jobLabel(selected) : '');
	let describedBy = $derived(errorMessage ? `${id}-error` : undefined);

	function focusPicker(input: HTMLInputElement) {
		query = '';
		open = true;
		input.select();
	}

	function chooseJob(jobId: string) {
		// Clicking the picked job again is a deselect to the combobox; keep it, as ClientPicker does.
		if (!jobId) {
			value = selected?.id ?? '';
			open = false;
			return;
		}
		const job = results.find((entry) => entry.id === jobId);
		selected = job ? { id: job.id, job_number: job.job_number, title: job.title } : null;
		value = jobId;
		query = '';
		open = false;
		onSelect?.(selected);
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="job-picker" class:job-picker--invalid={invalid}>
	<label for={id}
		>{label}{#if required}<span aria-hidden="true">*</span>{/if}</label
	>
	<Combobox.Root
		type="single"
		bind:value
		bind:open
		{inputValue}
		items={comboboxItems}
		onValueChange={chooseJob}
	>
		<div class="job-picker__control">
			<span class="job-picker__search" aria-hidden="true">{@html searchIcon}</span>
			<Combobox.Input
				{id}
				{placeholder}
				autocomplete="off"
				aria-describedby={describedBy}
				aria-invalid={invalid}
				onfocus={(event) => focusPicker(event.currentTarget)}
				onclick={() => (open = true)}
				oninput={(event) => {
					query = event.currentTarget.value;
					open = true;
				}}
			/>
			<Combobox.Trigger class="job-picker__trigger" aria-label="Show jobs">
				<span aria-hidden="true">{@html chevronDownIcon}</span>
			</Combobox.Trigger>
		</div>
		<Combobox.Portal>
			<Combobox.Content
				class="job-picker__menu"
				data-elevation="elevated"
				align="start"
				sideOffset={4}
				collisionPadding={8}
			>
				<Combobox.Viewport class="job-picker__viewport">
					{#if jobsQuery.isPending}
						<div class="job-picker__empty">Searching…</div>
					{:else if jobsQuery.isError}
						<div class="job-picker__empty" role="alert">Jobs could not be loaded. Try again.</div>
					{:else}
						{#each results as job (job.id)}
							<Combobox.Item value={job.id} label={jobLabel(job)} class="job-picker__option">
								<span class="job-picker__option-copy">
									<strong>{jobLabel(job)}</strong>
									<small>{metaFor(job)}</small>
								</span>
								{#if value === job.id}<span class="job-picker__check" aria-hidden="true"
										>{@html checkIcon}</span
									>{/if}
							</Combobox.Item>
						{:else}<div class="job-picker__empty">
								{debouncedQuery ? `No jobs match “${debouncedQuery}”.` : 'No jobs yet.'}
							</div>{/each}
					{/if}
				</Combobox.Viewport>
			</Combobox.Content>
		</Combobox.Portal>
	</Combobox.Root>
	{#if errorMessage}<p class="job-picker__error" id={`${id}-error`} role="alert">
			<span aria-hidden="true">{@html exclamationCircleIcon}</span>{errorMessage}
		</p>{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.job-picker {
		width: 100%;
	}
	.job-picker > label {
		display: block;
		margin-bottom: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}
	.job-picker > label span {
		color: var(--color-critical);
	}
	.job-picker__control {
		position: relative;
		display: flex;
		min-height: var(--space-largest);
		align-items: center;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--field--fill, var(--color-surface--background));
	}
	.job-picker__control:focus-within {
		z-index: var(--elevation-base);
		box-shadow: var(--shadow-focus);
	}
	.job-picker--invalid .job-picker__control {
		border-color: var(--color-critical);
	}
	.job-picker__control :global(input) {
		width: 100%;
		min-width: 0;
		min-height: calc(var(--space-largest) - (var(--border-base) * 2));
		padding: var(--space-small) var(--space-largest);
		border: 0;
		outline: 0;
		color: var(--color-heading);
		background: transparent;
		font: inherit;
	}
	.job-picker__search {
		position: absolute;
		left: var(--space-base);
		display: grid;
		width: 16px;
		height: 16px;
		place-items: center;
		color: var(--color-icon--secondary);
		pointer-events: none;
	}
	:global(.job-picker__trigger) {
		position: absolute;
		right: 0;
		display: grid;
		width: var(--space-largest);
		height: 100%;
		place-items: center;
		border: 0;
		border-radius: 0 var(--radius-base) var(--radius-base) 0;
		outline: 0;
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
	}
	:global(.job-picker__trigger:focus-visible) {
		box-shadow: var(--shadow-focus);
	}
	:global(.job-picker__trigger[data-state='open']) span {
		transform: rotate(180deg);
	}
	:global(.job-picker__trigger span) {
		display: grid;
		width: 18px;
		height: 18px;
		place-items: center;
		transition: transform var(--timing-quick);
	}
	:global(.job-picker__trigger svg),
	.job-picker__search :global(svg),
	.job-picker__check :global(svg),
	.job-picker__error :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
	:global(.job-picker__menu) {
		z-index: var(--elevation-modal);
		width: var(--bits-floating-anchor-width);
		max-height: min(300px, var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	:global(.job-picker__viewport) {
		max-height: inherit;
		overflow-y: auto;
		padding: var(--space-small);
	}
	:global(.job-picker__option) {
		display: flex;
		width: 100%;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-small);
		outline: 0;
		color: var(--color-text);
		background: transparent;
		text-align: left;
		cursor: pointer;
		transition:
			color var(--timing-quick),
			background-color var(--timing-quick);
	}
	:global(.job-picker__option[data-highlighted]) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}
	.job-picker__option-copy {
		display: grid;
		min-width: 0;
		flex: 1;
		gap: 2px;
	}
	.job-picker__option-copy strong {
		overflow: hidden;
		color: inherit;
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.job-picker__option-copy small {
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.job-picker__check {
		display: grid;
		width: 16px;
		height: 16px;
		flex: 0 0 16px;
		place-items: center;
		color: var(--color-interactive);
	}
	.job-picker__empty {
		padding: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
	.job-picker__error {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		margin: var(--space-smaller) 0 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
