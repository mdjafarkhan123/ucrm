<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';

	// Jobber's "Apply visit settings to future visits", asked after saving one visit of a repeating job.
	//
	// Jobber offers four boxes; two of theirs have nothing to act on here and one of them should not be here
	// at all. Line items wait for a visit to own its own quantities. A lasting instruction belongs on the job,
	// where every visit already reads it, including visits made later. And changing how the job repeats is a
	// destructive rebuild, so it lives behind "Edit all visits", which shows what it costs — the same change
	// must not also be reachable from a quiet checkbox that warns about nothing.
	let {
		open,
		visitLabel,
		laterCount,
		saving = false,
		error = '',
		onApply,
		onClose
	}: {
		open: boolean;
		visitLabel: string;
		laterCount: number;
		saving?: boolean;
		error?: string;
		onApply: (fields: { time_of_day: boolean; assigned_team: boolean }) => void;
		onClose: () => void;
	} = $props();

	let timeOfDay = $state(false);
	let assignedTeam = $state(false);

	let wasOpen = false;
	$effect(() => {
		if (open && !wasOpen) {
			timeOfDay = false;
			assignedTeam = false;
		}
		wasOpen = open;
	});

	const canApply = $derived((timeOfDay || assignedTeam) && laterCount > 0 && !saving);
</script>

<Dialog {open} title="Apply to later visits" {onClose}>
	<div class="apply-future">
		{#if error}<p class="apply-future__alert" role="alert">{error}</p>{/if}

		<p class="apply-future__intro">
			{#if laterCount === 0}
				This is the last visit on the job, so there is nothing after it to update.
			{:else}
				Which settings from {visitLabel} should also apply to the
				{laterCount === 1 ? 'visit' : `${laterCount} visits`} after it? Completed visits are never changed.
			{/if}
		</p>

		<Checkbox
			id="apply-future-time"
			label="Time of day"
			description="The start and end time this visit now has."
			checked={timeOfDay}
			onchange={(checked) => (timeOfDay = checked)}
		/>
		<Checkbox
			id="apply-future-team"
			label="Assigned team"
			description="The crew on this visit replaces the crew on the later ones."
			checked={assignedTeam}
			onchange={(checked) => (assignedTeam = checked)}
		/>

		<div class="apply-future__actions">
			<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
			<Button
				onclick={() => onApply({ time_of_day: timeOfDay, assigned_team: assignedTeam })}
				loading={saving}
				disabled={!canApply}
			>
				Apply
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.apply-future {
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

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}
</style>
