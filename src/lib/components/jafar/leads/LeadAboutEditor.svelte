<script lang="ts">
	import { untrack } from 'svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { LEAD_SOURCES, LEAD_SOURCE_LABELS } from '$lib/jafar/leads';
	import type { LeadDetail } from '$lib/jafar/lead-history';
	import LeadBlockEditor from './LeadBlockEditor.svelte';

	// Jafar business management B2b: how Uplift came across the business and why it may fit, edited in place in
	// the Lead page's About card. Only what changed is sent.
	let {
		lead,
		saving = false,
		error = '',
		fieldErrors = {},
		onSave,
		onCancel
	}: {
		lead: LeadDetail;
		saving?: boolean;
		error?: string;
		fieldErrors?: Record<string, string>;
		onSave: (fields: Record<string, string>) => void;
		onCancel: () => void;
	} = $props();

	type Draft = { source: string; source_detail: string; fit_notes: string };

	// Taken once on mount; the page mounts this fresh each time it opens.
	const saved: Draft = untrack(() => ({
		source: lead.source,
		source_detail: lead.source_detail ?? '',
		fit_notes: lead.fit_notes ?? ''
	}));
	let draft = $state<Draft>({ ...saved });

	const changes = $derived(
		Object.fromEntries(
			(Object.keys(saved) as (keyof Draft)[])
				.filter((key) => draft[key].trim() !== saved[key])
				.map((key) => [key, draft[key]])
		)
	);

	const sourceOptions = LEAD_SOURCES.map((source) => ({
		value: source,
		label: LEAD_SOURCE_LABELS[source]
	}));
	const error_ = (key: keyof Draft) => fieldErrors[`fields.${key}`] ?? '';
</script>

<LeadBlockEditor
	label="Edit about this Lead"
	dirty={Object.keys(changes).length > 0}
	{saving}
	{error}
	onSave={() => onSave(changes)}
	{onCancel}
>
	<div class="lead-about-editor">
		<Select
			id="lead-edit-source"
			label="How you found them"
			options={sourceOptions}
			bind:value={draft.source}
		/>
		{#if error_('source')}<p class="lead-about-editor__error">{error_('source')}</p>{/if}
		<Input
			id="lead-edit-source-detail"
			label="Source details (optional)"
			placeholder="Who referred them, which directory…"
			bind:value={draft.source_detail}
			invalid={Boolean(error_('source_detail'))}
			errorMessage={error_('source_detail')}
			autocomplete="off"
		/>
		<Textarea
			id="lead-edit-fit-notes"
			label="Why they may fit"
			rows={5}
			maxlength={4000}
			bind:value={draft.fit_notes}
			invalid={Boolean(error_('fit_notes'))}
			errorMessage={error_('fit_notes')}
		/>
	</div>
</LeadBlockEditor>

<style lang="scss">
	.lead-about-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
