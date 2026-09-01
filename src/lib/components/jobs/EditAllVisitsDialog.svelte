<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import RecurrenceFields from '$lib/components/jobs/RecurrenceFields.svelte';
	import {
		previewJobRecurrence,
		jobRecurrencePreviewKey,
		type JobRecurrenceInput,
		type JobVisit
	} from '$lib/jobs/api';

	// "Edit all visits": change how a recurring job repeats, after the job already exists.
	//
	// The repeat controls are the same component the New Job page uses, so a schedule means the same thing
	// wherever it is set. What this screen adds is the consequence, because here the change is destructive:
	// every incomplete visit is cleared and rebuilt, past-dated ones included, and anything customised on
	// them is lost. That is Jobber's behaviour and its own words — "rescheduling will delete all incomplete
	// visits and recreate them" — and like Jobber we make the person tick a box that says so before the
	// button will work.
	//
	// The numbers cost nothing extra: the visits are already on the page, and the new count is the same
	// server preview the repeat controls are already showing, read from the same cache key.
	let {
		open,
		visits,
		currentRule,
		locale = 'en-US',
		saving = false,
		error = '',
		onSave,
		onClose
	}: {
		open: boolean;
		visits: JobVisit[];
		currentRule: JobRecurrenceInput | null;
		locale?: string;
		saving?: boolean;
		error?: string;
		onSave: (rule: JobRecurrenceInput) => void;
		onClose: () => void;
	} = $props();

	function blankRule(): JobRecurrenceInput {
		return {
			frequency: 'weekly',
			interval_count: 1,
			weekdays: [],
			monthly_mode: null,
			month_day: null,
			ordinal_week: null,
			ordinal_weekday: null,
			start_date: '',
			end_mode: 'after',
			duration_count: 6,
			duration_unit: 'month',
			end_date: null,
			start_time: null,
			end_time: null,
			all_day: false
		};
	}

	let rule = $state<JobRecurrenceInput>(blankRule());
	let acknowledged = $state(false);

	// Re-read the job's own schedule each time the dialog opens, never while it is open, so a background
	// refetch of the job cannot overwrite what someone is in the middle of choosing.
	let wasOpen = false;
	$effect(() => {
		if (open && !wasOpen) {
			rule = currentRule ? { ...currentRule, weekdays: [...currentRule.weekdays] } : blankRule();
			acknowledged = false;
		}
		wasOpen = open;
	});

	// --- What this will cost ---------------------------------------------------------------------------------

	const completedCount = $derived(visits.filter((visit) => visit.completed_at).length);
	const incompleteCount = $derived(visits.filter((visit) => !visit.completed_at).length);

	// The same beat-after-typing settle and the same cache key the repeat controls use, so the two share one
	// answer from the server rather than asking twice for the same rule.
	let settledRule = $state<JobRecurrenceInput | null>(null);
	$effect(() => {
		const snapshot = JSON.stringify(rule);
		const timer = setTimeout(() => {
			settledRule = JSON.parse(snapshot) as JobRecurrenceInput;
		}, 300);
		return () => clearTimeout(timer);
	});

	const askable = $derived(
		settledRule !== null &&
			Boolean(settledRule.start_date) &&
			(settledRule.frequency !== 'weekly' || settledRule.weekdays.length > 0) &&
			(settledRule.frequency !== 'monthly' || Boolean(settledRule.monthly_mode)) &&
			(settledRule.end_mode === 'after'
				? Boolean(settledRule.duration_count)
				: Boolean(settledRule.end_date))
	);

	const previewQuery = createQuery(() => ({
		queryKey: jobRecurrencePreviewKey(settledRule ?? rule),
		queryFn: () => previewJobRecurrence(settledRule as JobRecurrenceInput),
		enabled: open && askable,
		staleTime: 5 * 60 * 1000
	}));

	const createdCount = $derived(previewQuery.data?.visit_count ?? null);
	const overLimit = $derived(previewQuery.data?.over_limit ?? false);

	const plural = (count: number, one: string, many: string) =>
		`${count} ${count === 1 ? one : many}`;

	const canSave = $derived(acknowledged && askable && !overLimit && !saving);
</script>

<Dialog {open} title="Edit all visits" {onClose}>
	<div class="edit-all-visits">
		{#if error}<p class="edit-all-visits__alert" role="alert">{error}</p>{/if}

		<p class="edit-all-visits__intro">
			Changing how this job repeats rebuilds its visits. Visits your crew has already completed stay
			exactly as they are.
		</p>

		<RecurrenceFields bind:rule {locale} disabled={saving} />

		<div class="edit-all-visits__consequence">
			<p class="edit-all-visits__consequence-title">What saving this does</p>
			<ul class="edit-all-visits__list">
				<li>
					Removes {plural(incompleteCount, 'visit that has not been completed', 'visits that have not been completed')}, including any still sitting in the past.
				</li>
				<li>
					{#if createdCount === null}
						Creates the visits your new schedule lands on.
					{:else}
						Creates {plural(createdCount, 'new visit', 'new visits')} from the schedule above.
					{/if}
				</li>
				<li>
					Anything you changed on those visits — a different time, a different crew, their own
					instructions — is lost.
				</li>
				<li>
					{#if completedCount === 0}
						No completed visits on this job yet, so there is no history to keep.
					{:else}
						{plural(completedCount, 'completed visit stays', 'completed visits stay')} untouched.
					{/if}
				</li>
			</ul>
		</div>

		<Checkbox
			id="edit-all-visits-ack"
			label="I understand this cannot be undone"
			checked={acknowledged}
			onchange={(checked) => (acknowledged = checked)}
		/>

		<div class="edit-all-visits__actions">
			<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
			<Button onclick={() => onSave(rule)} loading={saving} disabled={!canSave}>
				Save schedule
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.edit-all-visits {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__alert {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__intro {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__consequence {
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
		}

		&__consequence-title {
			margin: 0 0 var(--space-small);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			margin: 0;
			padding-left: var(--space-base);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}
</style>
