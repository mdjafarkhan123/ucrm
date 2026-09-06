<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { fetchJob, jobDetailKey } from '$lib/jobs/api';

	// The visits behind one per-visit row of the ready-to-bill queue.
	//
	// It opens only when the row is expanded, so a page of 25 rows never loads 25 jobs it was not asked
	// about. The queue's own row already prefetches this on hover, so by the time the panel mounts the
	// answer is usually already in the cache and the skeleton never shows.
	//
	// The rule this panel exists to enforce: a finished visit is billed, an UNFINISHED one is only billed if
	// the contractor ticks it here, and ticking it means "mark this complete and bill it" in one save. The
	// database enforces the same thing — it refuses to complete any visit the batch did not explicitly name.
	let {
		jobId,
		locale = 'en-US',
		ticked,
		onToggle
	}: {
		jobId: string;
		locale?: string;
		/** Visit ids the contractor has ticked, owned by the page so the action bar can count them. */
		ticked: Set<string>;
		onToggle: (visitId: string, checked: boolean) => void;
	} = $props();

	const jobQuery = createQuery(() => ({
		queryKey: jobDetailKey(jobId),
		queryFn: () => fetchJob(jobId)
	}));

	const visits = $derived(jobQuery.data?.visits ?? []);
	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);

	// A `date` column arrives as `YYYY-MM-DD`; `new Date` reads that as UTC midnight and shifts the day back
	// one in negative-offset timezones. Appending `T00:00` parses it as local midnight.
	function visitLabel(visit: { visit_date: string | null; title: string | null }) {
		const day = visit.visit_date
			? dateFormat.format(new Date(`${visit.visit_date}T00:00`))
			: 'No date yet';
		return visit.title ? `${day} · ${visit.title}` : day;
	}
</script>

<div class="visit-panel">
	{#if jobQuery.isPending}
		<LoadingSkeleton variant="text" label="Loading this job's visits" rows={2} />
	{:else if jobQuery.isError}
		<p class="visit-panel__note">
			This job's visits could not be loaded. Close this row and try again.
		</p>
	{:else if visits.length === 0}
		<p class="visit-panel__note">This job has no visits yet.</p>
	{:else}
		<ul class="visit-panel__list">
			{#each visits as visit (visit.id)}
				<li class="visit-panel__item">
					{#if visit.invoiced}
						<span class="visit-panel__name visit-panel__name--muted">{visitLabel(visit)}</span>
						<span class="visit-panel__tag">Already invoiced</span>
					{:else if visit.completed_at}
						<span class="visit-panel__name">{visitLabel(visit)}</span>
						<span class="visit-panel__tag visit-panel__tag--ready">Will be billed</span>
					{:else}
						<Checkbox
							id={`ready-visit-${visit.id}`}
							label={visitLabel(visit)}
							checked={ticked.has(visit.id)}
							onchange={(checked) => onToggle(visit.id, checked)}
						/>
						<span class="visit-panel__tag visit-panel__tag--pending">Not finished yet</span>
					{/if}
				</li>
			{/each}
		</ul>
		<p class="visit-panel__note">
			Finished visits are billed automatically. Tick an unfinished one to mark it complete and bill
			it in the same save.
		</p>
	{/if}
</div>

<style lang="scss">
	.visit-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-smaller) 0;
	}

	.visit-panel__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.visit-panel__item {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.visit-panel__name {
		color: var(--color-text);

		&--muted {
			color: var(--color-text--secondary);
			text-decoration: line-through;
		}
	}

	.visit-panel__tag {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--ready {
			color: var(--color-success--onSurface);
		}
		&--pending {
			color: var(--color-warning--onSurface);
		}
	}

	.visit-panel__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
