<script lang="ts">
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';

	// One internal note written while a record is being created or edited. It saves with the record, so it
	// holds plain text rather than talking to the notes API the way NotesPanel does for a saved record.
	let {
		value = $bindable(''),
		id = 'record-initial-note',
		title = 'Notes',
		icon,
		label = 'Leave an internal note for yourself or a team member',
		maxlength = 500,
		error = ''
	}: {
		value?: string;
		id?: string;
		title?: string;
		icon?: string;
		label?: string;
		maxlength?: number;
		error?: string;
	} = $props();
</script>

<RailCard {title} {icon}>
	<Textarea
		{id}
		{label}
		rows={4}
		{maxlength}
		bind:value
		invalid={Boolean(error)}
		errorMessage={error}
	/>
</RailCard>
