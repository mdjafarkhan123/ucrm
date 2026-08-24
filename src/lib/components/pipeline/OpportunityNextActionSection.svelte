<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import ScheduleAssessmentDialog from './ScheduleAssessmentDialog.svelte';
	import ConvertToQuoteDialog from './ConvertToQuoteDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { dragOpportunity, invalidatePipeline, type OpportunityCard } from '$lib/pipeline/api';

	// The Brief's own next-action affordance for the collapsed Assessment column's three sub-states -- the
	// same real command the board's own drag already performs (`dragOpportunity`), offered here because the
	// collapsed card shows a state badge, not a per-card button. The parent keys this component by
	// `opportunity.id`, so switching cards resets any open dialog.
	let {
		opportunity,
		canEdit,
		onUpdate,
		onConverted
	}: {
		opportunity: OpportunityCard;
		canEdit: boolean;
		onUpdate: (patch: Partial<OpportunityCard>) => void;
		// Told after a successful conversion -- the Request becomes `converted` and a Quote now exists, so
		// this snapshot no longer describes a card the board still shows this way. The parent owns closing
		// the drawer, the same as it already does for Mark as lost.
		onConverted: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const nextAction = $derived.by(
		():
			| { kind: 'schedule'; label: string }
			| { kind: 'complete'; label: string }
			| { kind: 'convert'; label: string }
			| null => {
			if (opportunity.stage === 'assessment_unscheduled') {
				return { kind: 'schedule', label: 'Schedule assessment' };
			}
			if (opportunity.stage === 'assessment_scheduled') {
				return { kind: 'complete', label: 'Mark assessment complete' };
			}
			if (opportunity.stage === 'assessment_completed') {
				return { kind: 'convert', label: 'Create quote' };
			}
			return null;
		}
	);

	const clientName = $derived(
		opportunity.client?.company_name?.trim() || opportunity.client?.display_name || 'this client'
	);

	let scheduleOpen = $state(false);
	let convertOpen = $state(false);
	let completing = $state(false);

	// Mirrors `PipelineColumn`'s own `performMove`: a loading toast while the write is in flight, the same
	// success wording (naming the quote when conversion made one), and the error surfaced back to the
	// caller only when a dialog needs to show it inline.
	async function performMove(
		toStage: 'assessment_scheduled' | 'assessment_completed' | 'quote_draft',
		opts: { startsAt?: string; endsAt?: string; idempotencyKey?: string } = {},
		rethrow = false
	) {
		const loadingToastId = toast.loading('Saving change…');
		try {
			const result = await dragOpportunity(opportunity.id, { toStage, ...opts });
			await invalidatePipeline(queryClient);
			toast.dismiss(loadingToastId);
			toast.success(
				result.quote
					? `Change saved. Quote #${result.quote.quote_number} created.`
					: 'Change saved.'
			);
			return result;
		} catch (error) {
			toast.dismiss(loadingToastId);
			toast.error(
				'That card could not be moved.',
				error instanceof Error ? error.message : undefined
			);
			if (rethrow) throw error;
			return null;
		}
	}

	async function markComplete() {
		if (completing) return;
		completing = true;
		const result = await performMove('assessment_completed');
		if (result) onUpdate({ stage: result.to_stage });
		completing = false;
	}

	async function confirmSchedule(startsAt: string, endsAt: string) {
		const result = await performMove('assessment_scheduled', { startsAt, endsAt }, true);
		if (!result) return;
		onUpdate({ stage: result.to_stage, assessment: { starts_at: startsAt, ends_at: endsAt } });
		scheduleOpen = false;
	}

	async function confirmConvert() {
		await performMove('quote_draft', { idempotencyKey: crypto.randomUUID() }, true);
		convertOpen = false;
		onConverted();
	}
</script>

{#if canEdit && nextAction}
	<section class="next-action" aria-labelledby="brief-next-action-heading">
		<h3 id="brief-next-action-heading" class="next-action__heading">Next step</h3>
		{#if nextAction.kind === 'schedule'}
			<Button variant="primary" onclick={() => (scheduleOpen = true)}>{nextAction.label}</Button>
		{:else if nextAction.kind === 'complete'}
			<Button variant="primary" loading={completing} onclick={markComplete}>
				{nextAction.label}
			</Button>
		{:else if nextAction.kind === 'convert'}
			<Button variant="primary" onclick={() => (convertOpen = true)}>{nextAction.label}</Button>
		{/if}
	</section>
{/if}

{#if scheduleOpen}
	<ScheduleAssessmentDialog
		open={true}
		title={`Schedule the assessment - ${opportunity.title}`}
		onConfirm={confirmSchedule}
		onClose={() => (scheduleOpen = false)}
	/>
{/if}

{#if convertOpen}
	<ConvertToQuoteDialog
		open={true}
		{clientName}
		requestTitle={opportunity.title}
		onConfirm={confirmConvert}
		onClose={() => (convertOpen = false)}
	/>
{/if}

<style lang="scss">
	.next-action {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	.next-action__heading {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
</style>
