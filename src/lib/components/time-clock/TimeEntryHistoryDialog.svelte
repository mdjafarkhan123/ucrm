<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import {
		entryHistoryKey,
		fetchEntryHistory,
		historyHeadline,
		historyLines
	} from '$lib/time-clock/corrections';

	// An entry's edit history (plan § Timesheets page): who added, stopped, changed or deleted it, when, and
	// what it was before and after, newest last as a log reads. The read starts when the entry's menu is
	// pointed at, so it is usually ready by the time this opens.
	let {
		open,
		entryId,
		heading,
		onClose
	}: {
		open: boolean;
		entryId: string | null;
		/** What the entry is, e.g. "Job #20 · Mon, Oct 5". */
		heading: string;
		onClose: () => void;
	} = $props();

	const historyQuery = createQuery(() => ({
		queryKey: entryHistoryKey(entryId ?? ''),
		queryFn: () => fetchEntryHistory(entryId ?? ''),
		enabled: open && Boolean(entryId),
		staleTime: 15_000
	}));

	function stamp(at: string, timezone: string) {
		return new Intl.DateTimeFormat('en-US', {
			timeZone: timezone,
			month: 'short',
			day: 'numeric',
			year: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		}).format(new Date(at));
	}
</script>

<Dialog {open} title="Edit history" size="small" {onClose}>
	<div class="entry-history">
		<p class="entry-history__subject">{heading}</p>
		{#if historyQuery.isPending}
			<p class="entry-history__status" role="status">Loading the history…</p>
		{:else if historyQuery.isError}
			<p class="entry-history__status entry-history__status--error" role="alert">
				{historyQuery.error.message}
			</p>
		{:else if historyQuery.data.events.length === 0}
			<p class="entry-history__status">
				No changes recorded. Hours recorded before edit history began show their changes from now
				on.
			</p>
		{:else}
			{@const timezone = historyQuery.data.timezone}
			<ol class="entry-history__list">
				{#each historyQuery.data.events as event (event.id)}
					<li class="entry-history__event entry-history__event--{event.action}">
						<div class="entry-history__head">
							<strong>{historyHeadline(event)}</strong>
							<time datetime={event.at}>{stamp(event.at, timezone)}</time>
						</div>
						<ul class="entry-history__changes">
							{#each historyLines(event, timezone) as line (line)}
								<li>{line}</li>
							{:else}
								<li>Saved with no visible change.</li>
							{/each}
						</ul>
					</li>
				{/each}
			</ol>
		{/if}
		<div class="entry-history__actions">
			<Button variant="secondary" onclick={onClose}>Close</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.entry-history {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.entry-history__subject {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.entry-history__status {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--error {
			color: var(--color-critical--onSurface);
		}
	}

	.entry-history__list {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	/* A timeline: each event hangs from a line, its dot coloured by what happened. */
	.entry-history__event {
		position: relative;
		padding: 0 0 var(--space-base) var(--space-large);
		border-left: var(--border-base) solid var(--color-border);
		margin-left: var(--space-smaller);

		&:last-child {
			padding-bottom: 0;
			border-left-color: transparent;
		}

		&::before {
			content: '';
			position: absolute;
			top: 4px;
			left: -6px;
			width: 11px;
			height: 11px;
			border: 2px solid var(--color-surface);
			border-radius: 50%;
			background: var(--color-interactive);
		}

		&--changed::before {
			background: var(--color-warning);
		}

		&--deleted::before {
			background: var(--color-critical);
		}
	}

	.entry-history__head {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: var(--space-smallest) var(--space-base);
		font-size: var(--typography--fontSize-small);

		strong {
			color: var(--color-heading);
		}

		time {
			color: var(--color-text--secondary);
			font-variant-numeric: tabular-nums;
		}
	}

	.entry-history__changes {
		display: flex;
		flex-direction: column;
		gap: var(--space-minuscule);
		margin: var(--space-smaller) 0 0;
		padding: 0;
		list-style: none;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}

	.entry-history__actions {
		display: flex;
		justify-content: flex-end;
	}
</style>
