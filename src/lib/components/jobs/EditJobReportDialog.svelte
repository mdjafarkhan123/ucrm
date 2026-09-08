<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import { attachmentImageUrl } from '$lib/collaboration/api';
	import type { JobReportState } from '$lib/jobs/report-types';
	import type { SaveJobReportInput } from '$lib/jobs/report-api';

	// Choosing what the customer sees. Nothing here is new content — every photo, answer and line already
	// exists on the job; this only marks which of them ride along on the report. Saving replaces the whole
	// selection in one call, the way the checklist template editor already does.

	let {
		open,
		jobReport,
		saving = false,
		onClose,
		onSave
	}: {
		open: boolean;
		jobReport: JobReportState;
		saving?: boolean;
		onClose: () => void;
		onSave: (input: SaveJobReportInput) => Promise<void>;
	} = $props();

	// Mounted only while open, so every field starts fresh from the last saved selection each time.
	let includeServiceDetails = $state(untrack(() => jobReport.report.include_service_details));
	let includePrice = $state(untrack(() => jobReport.report.include_price));
	let signatureId = $state(untrack(() => jobReport.report.signature_id ?? ''));
	let summary = $state(untrack(() => jobReport.report.summary ?? ''));
	let selectedPhotoIds = $state(new Set(untrack(() => jobReport.report.photo_ids)));
	let selectedChecklist = $state(
		new Set(
			untrack(() => jobReport.report.checklist.map((row) => `${row.visit_id}:${row.item_id}`))
		)
	);
	let problem = $state('');

	const signatureOptions = $derived([
		{ value: '', label: 'No signature' },
		...jobReport.candidates.signatures.map((signature) => ({
			value: signature.id,
			label: `${signature.signer_name} · ${new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' }).format(new Date(signature.collected_at))}`
		}))
	]);

	const visitDateFormat = new Intl.DateTimeFormat('en-US', {
		month: 'short',
		day: 'numeric',
		year: 'numeric'
	});

	function formatAnswer(value: string | number | boolean | null) {
		if (typeof value === 'boolean') return value ? 'Yes' : 'No';
		return String(value ?? '');
	}

	function togglePhoto(attachmentId: string, checked: boolean) {
		const next = new Set(selectedPhotoIds);
		if (checked) next.add(attachmentId);
		else next.delete(attachmentId);
		selectedPhotoIds = next;
	}

	function toggleChecklistItem(key: string, checked: boolean) {
		const next = new Set(selectedChecklist);
		if (checked) next.add(key);
		else next.delete(key);
		selectedChecklist = next;
	}

	// The database refuses prices without the work list; unchecking the list here clears the price toggle
	// too, rather than letting a save fail on a rule the person cannot see coming.
	function toggleServiceDetails(checked: boolean) {
		includeServiceDetails = checked;
		if (!checked) includePrice = false;
	}

	async function submit() {
		if (saving) return;
		problem = '';
		try {
			await onSave({
				include_service_details: includeServiceDetails,
				include_price: includePrice,
				signature_id: signatureId || null,
				summary: summary.trim() || null,
				photo_attachment_ids: [...selectedPhotoIds],
				checklist_selections: [...selectedChecklist].map((key) => {
					const [visit_id, item_id] = key.split(':');
					return { visit_id, item_id };
				})
			});
		} catch (error) {
			problem = error instanceof Error ? error.message : 'That work report could not be saved.';
		}
	}
</script>

<Dialog {open} title="Edit work report" size="large" onClose={() => onClose()}>
	<div class="edit-job-report">
		<section class="edit-job-report__section">
			<Checkbox
				id="job-report-service-details"
				label="Show the work list"
				checked={includeServiceDetails}
				onchange={toggleServiceDetails}
				disabled={saving}
			/>
			{#if jobReport.can_view_price}
				<Checkbox
					id="job-report-price"
					label="Show prices"
					checked={includePrice}
					onchange={(checked) => (includePrice = checked)}
					disabled={saving || !includeServiceDetails}
				/>
			{/if}
		</section>

		<Select
			id="job-report-signature"
			label="Signature to include"
			options={signatureOptions}
			bind:value={signatureId}
			disabled={saving}
		/>

		<Textarea
			id="job-report-summary"
			label="Summary for the customer (optional)"
			bind:value={summary}
			rows={3}
			maxlength={2000}
			disabled={saving}
		/>

		<section class="edit-job-report__section">
			<h3 class="edit-job-report__section-title">Photos</h3>
			{#if jobReport.candidates.photos.length === 0}
				<p class="edit-job-report__empty">This job has no photos yet.</p>
			{:else}
				<div class="edit-job-report__photos">
					{#each jobReport.candidates.photos as photo (photo.attachment_id)}
						<label class="edit-job-report__photo">
							<input
								type="checkbox"
								checked={selectedPhotoIds.has(photo.attachment_id)}
								disabled={saving}
								onchange={(event) => togglePhoto(photo.attachment_id, event.currentTarget.checked)}
							/>
							<img
								src={attachmentImageUrl(photo.attachment_id, 'thumb')}
								alt={photo.file_name}
								loading="lazy"
							/>
						</label>
					{/each}
				</div>
			{/if}
		</section>

		<section class="edit-job-report__section">
			<h3 class="edit-job-report__section-title">Checklist answers</h3>
			{#if jobReport.candidates.visits.length === 0}
				<p class="edit-job-report__empty">No visit has any answered checklist questions yet.</p>
			{:else}
				<div class="edit-job-report__visits">
					{#each jobReport.candidates.visits as visit (visit.visit_id)}
						<div class="edit-job-report__visit">
							<h4 class="edit-job-report__visit-date">
								{visit.visit_date
									? visitDateFormat.format(new Date(`${visit.visit_date}T00:00:00`))
									: 'Unscheduled visit'}
							</h4>
							{#each visit.items as item (item.item_id)}
								{@const key = `${visit.visit_id}:${item.item_id}`}
								<Checkbox
									id={`job-report-item-${key}`}
									label={`${item.label} — ${formatAnswer(item.value)}`}
									checked={selectedChecklist.has(key)}
									onchange={(checked) => toggleChecklistItem(key, checked)}
									disabled={saving}
								/>
							{/each}
						</div>
					{/each}
				</div>
			{/if}
		</section>

		{#if problem}
			<p class="edit-job-report__problem" role="alert">{problem}</p>
		{/if}

		<footer class="edit-job-report__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={() => onClose()}>
				Cancel
			</Button>
			<Button variant="primary" loading={saving} onclick={() => void submit()}>
				Save work report
			</Button>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	.edit-job-report {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__section {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__section-title {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-transform: uppercase;
			letter-spacing: 0.04em;
		}

		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__photos {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
			gap: var(--space-small);
		}

		&__photo {
			position: relative;
			display: block;
			cursor: pointer;

			img {
				display: block;
				width: 100%;
				aspect-ratio: 1;
				object-fit: cover;
				border-radius: var(--radius-base);
				border: var(--border-thick) solid var(--color-border);
			}

			input {
				position: absolute;
				top: var(--space-smaller);
				left: var(--space-smaller);
				width: 18px;
				height: 18px;
			}

			&:has(input:checked) img {
				border-color: var(--color-interactive);
			}
		}

		&__visits {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__visit {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__visit-date {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__problem {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-base);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
