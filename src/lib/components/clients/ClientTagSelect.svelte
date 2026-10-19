<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import TagSelect from '$lib/components/ui/TagSelect.svelte';
	import {
		createTag,
		fetchTags,
		fetchTagPermissions,
		updateTagColor,
		tagsKey,
		type Tag
	} from '$lib/collaboration/api';

	// Holds the chosen tag ids until the page saves them with everything else. The create form binds to
	// `tagIds`; a detail page passes the ids one way and stages the change through `onChange`.
	let {
		tagIds = $bindable<string[]>([]),
		onChange
	}: { tagIds?: string[]; onChange?: (next: string[]) => void } = $props();

	const queryClient = useQueryClient();
	const tagsQuery = createQuery<Tag[]>(() => ({ queryKey: tagsKey, queryFn: fetchTags }));

	const catalogQuery = createQuery(() => ({
		queryKey: [...tagsKey, 'permissions'],
		queryFn: fetchTagPermissions
	}));
	async function recolor(id: string, color: string) {
		await updateTagColor(id, color);
		await queryClient.invalidateQueries({ queryKey: ['collaboration'] });
		await queryClient.invalidateQueries({ queryKey: ['clients'] });
	}
	async function create(name: string, color?: string) {
		const tag = await createTag(name, color);
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
	onCreate={catalogQuery.data?.canManage ? create : undefined}
	onColorChange={catalogQuery.data?.canManage ? recolor : undefined}
	searchId="client-form-tag-search"
/>
