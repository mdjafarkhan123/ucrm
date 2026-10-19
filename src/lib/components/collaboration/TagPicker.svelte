<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import TagSelect from '$lib/components/ui/TagSelect.svelte';
	import {
		assignTag,
		unassignTag,
		createTag,
		updateTagColor,
		fetchTagPermissions,
		fetchTags,
		fetchTagAssignments,
		tagsKey,
		tagAssignmentsKey,
		activityKey,
		type EntityType
	} from '$lib/collaboration/api';
	let {
		entityType,
		entityId,
		canManage = false
	}: { entityType: EntityType; entityId: string; canManage?: boolean } = $props();
	const client = useQueryClient();
	const tags = createQuery(() => ({ queryKey: tagsKey, queryFn: fetchTags }));
	const catalog = createQuery(() => ({
		queryKey: [...tagsKey, 'permissions'],
		queryFn: fetchTagPermissions
	}));
	const assignments = createQuery(() => ({
		queryKey: tagAssignmentsKey(entityType, entityId),
		queryFn: () => fetchTagAssignments(entityType, entityId)
	}));
	const ids = $derived((assignments.data ?? []).map((item) => item.tag_id));
	let saving = $state(false);
	let error = $state('');
	async function change(next: string[]) {
		if (saving) return;
		saving = true;
		error = '';
		try {
			const added = next.find((id) => !ids.includes(id));
			const removed = (assignments.data ?? []).find((item) => !next.includes(item.tag_id));
			if (added) await assignTag({ tagId: added, entityType, entityId });
			if (removed) await unassignTag(removed.id);
			await client.invalidateQueries({ queryKey: tagAssignmentsKey(entityType, entityId) });
			void client.invalidateQueries({ queryKey: activityKey(entityType, entityId) });
		} catch (e) {
			error = e instanceof Error ? e.message : 'Tags could not be saved.';
		} finally {
			saving = false;
		}
	}
	async function create(name: string, color?: string) {
		const tag = await createTag(name, color);
		await client.invalidateQueries({ queryKey: tagsKey });
		return tag;
	}
	async function recolor(id: string, color: string) {
		await updateTagColor(id, color);
		await client.invalidateQueries({ queryKey: ['collaboration'] });
		await client.invalidateQueries({ queryKey: ['clients'] });
	}
</script>

<TagSelect
	tagIds={ids}
	catalog={tags.data ?? []}
	readonly={!canManage}
	disabled={saving}
	onChange={change}
	onCreate={catalog.data?.canManage ? create : undefined}
	onColorChange={catalog.data?.canManage ? recolor : undefined}
	searchId={`tag-search-${entityType}-${entityId}`}
/>
{#if saving}<p class="tag-picker__status" role="status">Saving tags…</p>{/if}
{#if error}<p class="tag-picker__error" role="alert">{error}</p>{/if}

<style lang="scss">
	.tag-picker__status {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.tag-picker__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
