<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';

	// Dropping a New request card onto the collapsed Assessment column is ambiguous on its own -- the
	// column holds both the unscheduled and the scheduled sub-state, and a plain drop cannot say which one
	// was meant. This dialog asks once, up front, before either real domain action runs. Scheduling a time
	// is a second step this dialog does not own: choosing "Schedule" hands off to `ScheduleAssessmentDialog`
	// rather than collecting a time itself, so there is exactly one place that ever asks for one.
	let {
		open,
		title,
		onSchedule,
		onAddWithoutScheduling,
		onClose
	}: {
		open: boolean;
		title: string;
		onSchedule: () => void;
		onAddWithoutScheduling: () => Promise<void>;
		onClose: () => void;
	} = $props();

	let saving = $state(false);

	async function addWithoutScheduling() {
		if (saving) return;
		saving = true;
		try {
			await onAddWithoutScheduling();
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} {title} onClose={saving ? () => {} : onClose}>
	<div class="assessment-choice">
		<p class="assessment-choice__notice">
			Book the visit now, or add it to Assessment and schedule it later.
		</p>

		<div class="assessment-choice__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button variant="secondary" disabled={saving} onclick={() => void addWithoutScheduling()}>
				Add without scheduling
			</Button>
			<Button variant="primary" loading={saving} onclick={onSchedule}>Schedule</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.assessment-choice {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__notice {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-large);
		}
		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
