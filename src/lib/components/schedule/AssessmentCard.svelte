<script lang="ts">
	import ScheduleItemCard from '$lib/components/schedule/ScheduleItemCard.svelte';
	import { cardState, visitDerivedStatus, visitShape } from '$lib/schedule/status';
	import { VISIT_STATUS_LABELS } from '$lib/schedule/statuses';
	import { assignmentLabel, clockLabel } from '$lib/schedule/labels';
	import type { CardDensity } from '$lib/schedule/layout';
	import type { AssessmentItem } from '$lib/schedule/items';
	import type { TeamMember } from '$lib/team/api';
	import clipboardListIcon from '@tabler/icons/outline/clipboard-list.svg?raw';

	// One on-site assessment, drawn like a visit so a day reads as one calendar. It is Request-owned: the card
	// is never a drag handle, and its click opens its own preview. The clipboard beside the time is what tells
	// it apart from a visit, so colour never has to.

	let {
		assessment,
		density,
		today,
		nowMinutes = null,
		employeesById,
		selected = false,
		showAssignment = true,
		sharedWith = null,
		onselect
	}: {
		assessment: AssessmentItem;
		density: CardDensity;
		today: string;
		/** Minutes past midnight in the contractor's timezone; an assessment under way today wears "In progress". */
		nowMinutes?: number | null;
		employeesById: Map<string, TeamMember>;
		selected?: boolean;
		/** False where the surface itself already says who is going, as the Day board's employee row does. */
		showAssignment?: boolean;
		/** On a person's row, the other people it is shared with, for `Shared with Sofia Chen`. */
		sharedWith?: string | null;
		/** The element is handed back so the page can anchor the preview to this exact card. */
		onselect: (assessment: AssessmentItem, element: HTMLElement) => void;
	} = $props();

	const state = $derived(cardState(assessment, today, nowMinutes));
	const status = $derived(visitDerivedStatus(assessment, today));

	const timeLabel = $derived.by(() => {
		if (visitShape(assessment) === 'anytime') return 'Anytime';
		const start = clockLabel(assessment.start_time);
		if (!start) return 'Anytime';
		const end = clockLabel(assessment.end_time);
		return end ? `${start} – ${end}` : start;
	});
	const startLabel = $derived(
		visitShape(assessment) === 'anytime'
			? 'Anytime'
			: (clockLabel(assessment.start_time) ?? 'Anytime')
	);

	const clientLabel = $derived(
		assessment.client_name ?? assessment.client_company_name ?? 'Client hidden'
	);
	const workLabel = $derived(assessment.request_title?.trim() || 'Assessment');
	const place = $derived(
		[assessment.property_label, assessment.property_address_line1, assessment.property_city]
			.filter((part): part is string => Boolean(part))
			.join(' · ') || null
	);
	const people = $derived(
		assessment.assignee_ids.map((id) => employeesById.get(id)?.full_name ?? 'One employee')
	);

	const summary = $derived(
		[
			'Assessment',
			timeLabel,
			clientLabel,
			workLabel,
			assignmentLabel(assessment.assignee_ids, employeesById),
			status ? VISIT_STATUS_LABELS[status] : null,
			state === 'in-progress' ? 'In progress' : null
		]
			.filter(Boolean)
			.join(', ')
	);
</script>

<ScheduleItemCard
	{density}
	{state}
	kind="assessment"
	time={timeLabel}
	startTime={startLabel}
	client={clientLabel}
	work={workLabel}
	{place}
	{people}
	showPeople={showAssignment}
	sharedLabel={sharedWith ? `Shared with ${sharedWith}` : null}
	inlineChip={!showAssignment}
	marker={clipboardListIcon}
	{selected}
	{summary}
	onclick={(event) => onselect(assessment, event.currentTarget)}
/>
