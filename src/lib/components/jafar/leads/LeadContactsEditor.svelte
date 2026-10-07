<script lang="ts" module>
	import type { ContactMethodKind } from '$lib/jafar/leads';

	export type ContactEdit = {
		add: { kind: ContactMethodKind; value: string; found_at: string }[];
		change: { id: string; kind: ContactMethodKind; value: string; found_at: string }[];
		remove: string[];
	};
</script>

<script lang="ts">
	import { untrack } from 'svelte';
	import type { LeadContactMethodDetail } from '$lib/jafar/lead-history';
	import LeadBlockEditor from './LeadBlockEditor.svelte';
	import LeadContactRows, {
		contactRow,
		filledRows,
		type ContactRow
	} from './LeadContactRows.svelte';
	import LeadDuplicateWarning from './LeadDuplicateWarning.svelte';

	// Jafar business management B2b: a Lead's contact details edited in place. Correcting a detail keeps it the
	// same detail, so a logged "Emailed info@…" reads the corrected address. A removed detail leaves this list
	// but stays named in the history (Jafar, 2026-10-07). Sent as add / change / remove, so someone else's edit
	// made meanwhile is not undone.

	let {
		leadId,
		methods,
		saving = false,
		error = '',
		fieldErrors = {},
		onSave,
		onCancel
	}: {
		leadId: string;
		methods: LeadContactMethodDetail[];
		saving?: boolean;
		error?: string;
		fieldErrors?: Record<string, string>;
		onSave: (edit: ContactEdit) => void;
		onCancel: () => void;
	} = $props();

	// Taken once on mount; the page mounts this fresh each time it opens.
	const saved = untrack(() => methods);
	let rows = $state<ContactRow[]>(
		untrack(() =>
			methods.length
				? methods.map((method) => contactRow({ ...method }))
				: [contactRow({ kind: 'email', value: '', found_at: '' })]
		)
	);

	const edit = $derived.by((): ContactEdit => {
		const kept = filledRows(rows);
		const keptIds = new Set(kept.map((row) => row.id));
		return {
			add: kept
				.filter((row) => !row.id)
				.map(({ kind, value, found_at }) => ({ kind, value, found_at })),
			change: kept
				.filter((row) => {
					const before = saved.find((method) => method.id === row.id);
					return (
						before && (row.value.trim() !== before.value || row.found_at.trim() !== before.found_at)
					);
				})
				.map(({ id, kind, value, found_at }) => ({ id: id as string, kind, value, found_at })),
			remove: saved.filter((method) => !keptIds.has(method.id)).map((method) => method.id)
		};
	});

	const dirty = $derived(edit.add.length + edit.change.length + edit.remove.length > 0);
	const removing = $derived(saved.filter((method) => edit.remove.includes(method.id)));

	// The server names a row by its place in the add or change list it was sent in.
	function rowError(key: number, field: 'value' | 'found_at') {
		const row = rows.find((candidate) => candidate.key === key);
		if (!row) return '';
		const list = row.id ? 'change' : 'add';
		const index = row.id
			? edit.change.findIndex((change) => change.id === row.id)
			: filledRows(rows)
					.filter((candidate) => !candidate.id)
					.findIndex((candidate) => candidate.key === key);
		return index === -1 ? '' : (fieldErrors[`contact_methods.${list}.${index}.${field}`] ?? '');
	}

	// Only new or corrected details can newly match another business.
	const checked = $derived([
		...edit.add,
		...edit.change.filter((change) => {
			const before = saved.find((method) => method.id === change.id);
			return before?.value !== change.value.trim();
		})
	]);
</script>

<LeadBlockEditor
	label="Edit contact details"
	{dirty}
	{saving}
	{error}
	onSave={() => onSave(edit)}
	{onCancel}
>
	<p class="lead-contacts-editor__hint">
		Fix a typo right here and the history follows it. If the business has a new email or number, add
		it and remove the old one.
	</p>

	<LeadContactRows bind:rows idPrefix="lead-edit-contact" errorFor={rowError} />

	{#if removing.length}
		<p class="lead-contacts-editor__removing" role="status">
			Removing {removing.map((method) => method.value).join(', ')}.
			{removing.length === 1 ? 'It stays' : 'They stay'} in any history that used
			{removing.length === 1 ? 'it' : 'them'}, marked removed, and can't be chosen again.
		</p>
	{/if}

	<LeadDuplicateWarning
		businessName=""
		countryCode=""
		website=""
		contacts={checked}
		excludeId={leadId}
	/>
</LeadBlockEditor>

<style lang="scss">
	.lead-contacts-editor {
		&__hint,
		&__removing {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__removing {
			padding: var(--space-small) var(--space-slim);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			color: var(--color-text);
		}
	}
</style>
