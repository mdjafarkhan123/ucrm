<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import NotesPanel from '$lib/components/collaboration/NotesPanel.svelte';
	import AttachmentsCard from '$lib/components/collaboration/AttachmentsCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import {
		fetchVisitChecklists,
		saveVisitChecklistAnswers,
		visitChecklistsKey
	} from '$lib/checklists/api';
	import type { ChecklistAnswerValue, VisitChecklistQuestion } from '$lib/checklists/types';
	import checklistIcon from '@tabler/icons/outline/checklist.svg?raw';
	import {
		activityKey,
		attachmentsKey,
		createNote,
		deleteNote,
		notesKey,
		updateNote,
		type NoteChange
	} from '$lib/collaboration/api';

	let {
		open,
		jobId,
		visitId,
		visitLabel,
		currentUserId,
		canRecord,
		canManageTeam,
		onSaved,
		onClose
	}: {
		open: boolean;
		jobId: string;
		visitId: string | null;
		visitLabel: string;
		currentUserId: string;
		canRecord: boolean;
		canManageTeam: boolean;
		onSaved?: () => void;
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	let pendingNotes = $state<NoteChange[]>([]);
	let pendingFiles = $state(0);
	let pendingAnswers = $state<Record<string, ChecklistAnswerValue>>({});
	let attachmentsCard = $state<AttachmentsCard>();
	let saving = $state(false);
	let error = $state('');

	const checklistsQuery = createQuery(() => ({
		queryKey: visitChecklistsKey(visitId ?? ''),
		queryFn: () => fetchVisitChecklists(jobId, visitId!),
		enabled: open && Boolean(jobId) && Boolean(visitId)
	}));

	const dirty = $derived(
		pendingNotes.length > 0 || pendingFiles > 0 || Object.keys(pendingAnswers).length > 0
	);

	function answerValue(question: VisitChecklistQuestion): ChecklistAnswerValue {
		return Object.hasOwn(pendingAnswers, question.id)
			? pendingAnswers[question.id]
			: question.value;
	}

	function setAnswer(question: VisitChecklistQuestion, value: ChecklistAnswerValue) {
		const normalized = typeof value === 'string' && value.length === 0 ? null : value;
		if (Object.is(normalized, question.value)) {
			const { [question.id]: _removed, ...rest } = pendingAnswers;
			pendingAnswers = rest;
		} else {
			pendingAnswers = { ...pendingAnswers, [question.id]: normalized };
		}
	}

	function discardAndClose() {
		pendingNotes = [];
		pendingFiles = 0;
		pendingAnswers = {};
		attachmentsCard?.discardChanges();
		error = '';
		onClose();
	}

	async function save() {
		if (!visitId || !dirty || saving) return;
		saving = true;
		error = '';
		try {
			const answers = Object.entries(pendingAnswers).map(([item_id, value]) => ({
				item_id,
				value
			}));
			if (answers.length > 0) {
				await saveVisitChecklistAnswers(jobId, visitId, answers);
				pendingAnswers = {};
				await queryClient.invalidateQueries({ queryKey: visitChecklistsKey(visitId) });
			}

			for (const change of [...pendingNotes]) {
				if (change.kind === 'create')
					await createNote({ entityType: 'visit', entityId: visitId, body: change.body });
				else if (change.kind === 'update')
					await updateNote({
						id: change.id,
						entityType: 'visit',
						entityId: visitId,
						body: change.body
					});
				else if (change.kind === 'pin')
					await updateNote({
						id: change.id,
						entityType: 'visit',
						entityId: visitId,
						pinned: change.pinned
					});
				else await deleteNote({ id: change.id, entityType: 'visit', entityId: visitId });
				pendingNotes = pendingNotes.filter((entry) => entry !== change);
			}

			const failedFiles = (await attachmentsCard?.saveAll(visitId)) ?? 0;
			if (failedFiles > 0) {
				error =
					failedFiles === 1
						? 'The notes were saved, but one file still needs attention.'
						: `The notes were saved, but ${failedFiles} files still need attention.`;
				return;
			}

			await Promise.all([
				queryClient.invalidateQueries({ queryKey: notesKey('visit', visitId) }),
				queryClient.invalidateQueries({ queryKey: attachmentsKey('visit', visitId) }),
				queryClient.invalidateQueries({ queryKey: activityKey('visit', visitId) }),
				queryClient.invalidateQueries({ queryKey: visitChecklistsKey(visitId) })
			]);
			onSaved?.();
			discardAndClose();
		} catch (caught) {
			error = caught instanceof Error ? caught.message : 'Those visit records could not be saved.';
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Visit records" size="large" onClose={discardAndClose}>
	<div class="visit-records">
		<p class="visit-records__context">{visitLabel}</p>
		{#if error}<p class="visit-records__error" role="alert">{error}</p>{/if}

		{#if visitId}
			<div class="visit-records__grid">
				<div class="visit-records__checklists">
					<SectionBlock title="Checklists" icon={checklistIcon} level={3} form>
						{#if checklistsQuery.isPending}
							<LoadingSkeleton variant="text" rows={3} label="Loading checklists" />
						{:else if checklistsQuery.isError}
							<p class="visit-records__error" role="alert">Checklists could not be loaded.</p>
						{:else if (checklistsQuery.data?.checklists ?? []).length === 0}
							<EmptyState
								icon={checklistIcon}
								title="No checklist for this visit"
								description="This job has no checklist attached for this visit."
							/>
						{:else}
							{#if (checklistsQuery.data?.outstanding_required ?? 0) > 0}
								<p class="visit-records__outstanding">
									{checklistsQuery.data?.outstanding_required} required
									{checklistsQuery.data?.outstanding_required === 1 ? 'answer is' : 'answers are'}
									still blank. You can save part of the checklist now and finish it later.
								</p>
							{/if}
							<div class="visit-records__forms">
								{#each checklistsQuery.data?.checklists ?? [] as checklist (checklist.id)}
									<section
										class="visit-records__form"
										aria-labelledby={`checklist-${checklist.id}`}
									>
										<h4 id={`checklist-${checklist.id}`}>{checklist.name}</h4>
										<div class="visit-records__questions">
											{#each checklist.items as question (question.id)}
												{@const value = answerValue(question)}
												{#if question.item_type === 'checkbox'}
													<Checkbox
														id={`checklist-question-${question.id}`}
														label={`${question.label}${question.required ? ' (required)' : ''}`}
														checked={value === true}
														disabled={!checklistsQuery.data?.can_answer}
														onchange={(checked) => setAnswer(question, checked)}
													/>
												{:else if question.item_type === 'long_text'}
													<Textarea
														id={`checklist-question-${question.id}`}
														label={question.label}
														required={question.required}
														maxlength={5000}
														showCount={false}
														value={typeof value === 'string' ? value : ''}
														disabled={!checklistsQuery.data?.can_answer}
														oninput={(event: Event) =>
															setAnswer(
																question,
																(event.currentTarget as HTMLTextAreaElement).value
															)}
													/>
												{:else if question.item_type === 'dropdown'}
													<Select
														id={`checklist-question-${question.id}`}
														label={question.label}
														required={question.required}
														value={typeof value === 'string' ? value : ''}
														options={[
															{ value: '__no_answer__', label: 'No answer' },
															...(question.options ?? []).map((option) => ({
																value: option,
																label: option
															}))
														]}
														disabled={!checklistsQuery.data?.can_answer}
														onchange={(next) =>
															setAnswer(question, next === '__no_answer__' ? null : next)}
													/>
												{:else}
													<Input
														id={`checklist-question-${question.id}`}
														label={question.label}
														type={question.item_type === 'number'
															? 'number'
															: question.item_type === 'date'
																? 'date'
																: 'text'}
														required={question.required}
														maxlength={question.item_type === 'short_text' ? 500 : undefined}
														value={typeof value === 'number' || typeof value === 'string'
															? value
															: ''}
														disabled={!checklistsQuery.data?.can_answer}
														oninput={(event: Event) => {
															const input = event.currentTarget as HTMLInputElement;
															setAnswer(
																question,
																question.item_type === 'number'
																	? input.value === ''
																		? null
																		: input.valueAsNumber
																	: input.value
															);
														}}
													/>
												{/if}
											{/each}
										</div>
									</section>
								{/each}
							</div>
						{/if}
					</SectionBlock>
				</div>

				<SectionBlock title="Notes" level={3}>
					<NotesPanel
						entityType="visit"
						entityId={visitId}
						canManage={canRecord}
						{canManageTeam}
						{currentUserId}
						pending={pendingNotes}
						onChange={(next) => (pendingNotes = next)}
					/>
				</SectionBlock>

				<AttachmentsCard
					bind:this={attachmentsCard}
					entityType="visit"
					entityId={visitId}
					title="Photos and files"
					surface="section"
					canManage={canRecord}
					{canManageTeam}
					{currentUserId}
					onPendingChange={(count) => (pendingFiles = count)}
				/>
			</div>
		{/if}

		<div class="visit-records__actions">
			<Button variant="tertiary" onclick={discardAndClose} disabled={saving}>Cancel</Button>
			{#if canRecord || canManageTeam}
				<Button onclick={() => void save()} loading={saving} disabled={!dirty}>Save records</Button>
			{/if}
		</div>
	</div>
</Dialog>

<style lang="scss">
	.visit-records {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__context {
			margin: 0;
			color: var(--color-text--secondary);
		}

		&__error {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
		}

		&__grid {
			display: grid;
			grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
			gap: var(--space-large);
		}

		&__checklists {
			grid-column: 1 / -1;
		}

		&__outstanding {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
		}

		&__forms,
		&__questions {
			display: grid;
			gap: var(--space-base);
		}

		&__form {
			display: grid;
			gap: var(--space-base);
			padding-top: var(--space-small);

			h4 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
			}
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}

	@media (max-width: 767px) {
		.visit-records__grid {
			grid-template-columns: 1fr;
		}
	}
</style>
