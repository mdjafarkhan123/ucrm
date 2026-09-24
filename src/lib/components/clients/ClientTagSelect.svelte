<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import TagSelect from '$lib/components/ui/TagSelect.svelte';
	import { createTag, fetchTags, tagsKey, type Tag } from '$lib/collaboration/api';

	// Holds the chosen tag ids until the page saves them with everything else. The create form binds to
	// `tagIds`; a detail page passes the ids one way and stages the change through `onChange`.
	let {
		tagIds = $bindable<string[]>([]),
		onChange
	}: { tagIds?: string[]; onChange?: (next: string[]) => void } = $props();

	const queryClient = useQueryClient();
	const tagsQuery = createQuery<Tag[]>(() => ({ queryKey: tagsKey, queryFn: fetchTags }));

	async function create(name: string) {
		const tag = await createTag(name);
		queryClient.setQueryData<Tag[]>(tagsKey, (catalog) => {
			const current = catalog ?? [];
			if (current.some((entry) => entry.id === tag.id)) return current;
			return [...current, tag].sort((left, right) => left.name.localeCompare(right.name));
		});
		return tag;
	}
</script>

<TagSelect
	bind:tagIds
	{onChange}
	catalog={tagsQuery.data ?? []}
	onCreate={create}
	searchId="client-form-tag-search"
/>
