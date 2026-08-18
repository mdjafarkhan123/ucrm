<script lang="ts">
	import { Popover } from 'bits-ui';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import { colorForId } from '$lib/collaboration/format';
	import {
		activityKey,
		assignTag,
		fetchTagAssignments,
		fetchTags,
		tagAssignmentsKey,
		tagsKey,
		unassignTag,
		type EntityType,
		type Tag,
		type TagAssignment
	} from '$lib/collaboration/api';
	import tagPlusIcon from '@tabler/icons/outline/tag-plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	let {
		entityType,
		entityId,
		canManage = false
	}: {
		entityType: EntityType;
		entityId: string;
		canManage?: boolean;
	} = $props();

	const queryClient = useQueryClient();

	const tagsQuery = createQuery<Tag[]>(() => ({
		queryKey: tagsKey,
		queryFn: fetchTags
	}));
	const tags = $derived(tagsQuery.data ?? []);

	const assignmentsQuery = createQuery(() => ({
		queryKey: tagAssignmentsKey(entityType, entityId),
		queryFn: () => fetchTagAssignments(entityType, entityId)
	}));
	const assignments = $derived(assignmentsQuery.data ?? []);
	const assignmentIdByTagId = $derived(new Map(assignments.map((a) => [a.tag_id, a.id])));

	let open = $state(false);
	let search = $state('');
	const normalizedSearch = $derived(search.trim().toLowerCase());
	const filteredTags = $derived(
		normalizedSearch
			? tags.filter((tag) => tag.name.toLowerCase().includes(normalizedSearch))
			: tags
	);
	const hasExactMatch = $derived(tags.some((tag) => tag.name.toLowerCase() === normalizedSearch));

	let actionError = $state('');

	const assignmentsCacheKey = $derived(tagAssignmentsKey(entityType, entityId));

	function readAssignments() {
		return queryClient.getQueryData<TagAssignment[]>(assignmentsCacheKey) ?? [];
	}

	function writeAssignments(next: TagAssignment[]) {
		queryClient.setQueryData<TagAssignment[]>(assignmentsCacheKey, next);
	}

	// The activity feed is the only list that still needs the server's version after a tag change, and it
	// is not what the chip is waiting on, so it refreshes quietly in the background.
	function refreshActivity() {
		void queryClient.invalidateQueries({ queryKey: activityKey(entityType, entityId) });
	}

	// Stands in for the real row until the server answers, so the chip appears on click instead of after a
	// round trip. A placeholder tag id also gives an unrecognised name a stable chip color straight away.
	function placeholderAssignment(tag: Tag): TagAssignment {
		return {
			id: `optimistic-${tag.id}`,
			organization_id: tag.organization_id,
			tag_id: tag.id,
			entity_type: entityType,
			entity_id: entityId,
			created_by: null,
			created_at: new Date().toISOString(),
			tag
		};
	}

	function placeholderTag(name: string): Tag {
		return {
			id: `optimistic-${name.toLowerCase()}`,
			organization_id: '',
			name,
			normalized_name: name.toLowerCase(),
			color: null,
			created_at: new Date().toISOString()
		};
	}

	type AssignInput = { tag: Tag; isNew: boolean };

	const assignMutation = createMutation(() => ({
		mutationFn: (input: AssignInput) =>
			assignTag(
				input.isNew
					? { tagName: input.tag.name, entityType, entityId }
					: { tagId: input.tag.id, entityType, entityId }
			),
		onMutate: async (input: AssignInput) => {
			actionError = '';
			await queryClient.cancelQueries({ queryKey: assignmentsCacheKey });
			const previous = readAssignments();
			writeAssignments([...previous, placeholderAssignment(input.tag)]);
			return { previous, placeholderId: `optimistic-${input.tag.id}` };
		},
		onSuccess: (assignment, _input, context) => {
			// Swap the placeholder for the saved row, and teach the catalog about a tag it has not seen.
			writeAssignments(
				readAssignments().map((existing) =>
					existing.id === context?.placeholderId ? assignment : existing
				)
			);
			if (assignment.tag) {
				const tag = assignment.tag;
				queryClient.setQueryData<Tag[]>(tagsKey, (catalog) => {
					const current = catalog ?? [];
					if (current.some((entry) => entry.id === tag.id)) return current;
					return [...current, tag].sort((left, right) => left.name.localeCompare(right.name));
				});
			}
		},
		onError: (error: Error, _input, context) => {
			if (context) writeAssignments(context.previous);
			actionError = error.message;
		},
		onSettled: refreshActivity
	}));

	const unassignMutation = createMutation(() => ({
		mutationFn: (assignmentId: string) => unassignTag(assignmentId),
		onMutate: async (assignmentId: string) => {
			actionError = '';
			await queryClient.cancelQueries({ queryKey: assignmentsCacheKey });
			const previous = readAssignments();
			writeAssignments(previous.filter((assignment) => assignment.id !== assignmentId));
			return { previous };
		},
		onError: (error: Error, _assignmentId, context) => {
			if (context) writeAssignments(context.previous);
			actionError = error.message;
		},
		onSettled: refreshActivity
	}));

	function applyTag(tag: Tag, isNew = false) {
		assignMutation.mutate({ tag, isNew });
	}

	function createFromSearch() {
		const name = search.trim();
		if (!name) return;
		search = '';
		applyTag(placeholderTag(name), true);
	}

	// Enter applies the one obvious choice: an existing tag when the search matches, otherwise a new one.
	function onSearchKeydown(event: KeyboardEvent) {
		if (event.key !== 'Enter') return;
		event.preventDefault();
		if (!normalizedSearch) return;

		const exact = filteredTags.find((tag) => tag.name.toLowerCase() === normalizedSearch);
		const target = exact ?? (filteredTags.length === 1 ? filteredTags[0] : undefined);
		if (target) {
			if (!assignmentIdByTagId.has(target.id)) applyTag(target);
			search = '';
			return;
		}
		if (filteredTags.length === 0) createFromSearch();
	}

	function toggleTag(tag: Tag, checked: boolean) {
		if (checked) {
			applyTag(tag);
			return;
		}
		const assignmentId = assignmentIdByTagId.get(tag.id);
		if (assignmentId) unassignMutation.mutate(assignmentId);
	}

	function unassignFromChip(tag: Tag) {
		const assignmentId = assignmentIdByTagId.get(tag.id);
		if (assignmentId) unassignMutation.mutate(assignmentId);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<!-- The container owns the "Tags" heading and its count, so the panel draws no heading of its own. -->
<div class="tag-picker-panel">
	<div class="tag-picker">
		{#each assignments as assignment (assignment.id)}
			{#if assignment.tag}
				<span class="tag-picker__chip tag-picker__chip--{colorForId(assignment.tag.id)}">
					{assignment.tag.name}
					{#if canManage}
						<button
							type="button"
							class="tag-picker__chip-remove"
							aria-label={`Remove ${assignment.tag.name} tag`}
							disabled={unassignMutation.isPending}
							onclick={() => unassignFromChip(assignment.tag as Tag)}
						>
							{@html xIcon}
						</button>
					{/if}
				</span>
			{/if}
		{/each}

		{#if canManage}
			<Popover.Root bind:open>
				<Popover.Trigger class="tag-picker__trigger">
					{@html tagPlusIcon}
					<span>Add tag</span>
				</Popover.Trigger>
				<Popover.Portal>
					<Popover.Content
						class="tag-picker__popover"
						align="start"
						sideOffset={8}
						collisionPadding={12}
					>
						<SearchInput
							id={`tag-search-${entityId}`}
							bind:value={search}
							placeholder="Find or create a tag"
							onkeydown={onSearchKeydown}
						/>
						{#if actionError}<p class="tag-picker__error" role="alert">{actionError}</p>{/if}
						<div class="tag-picker__options">
							{#each filteredTags as tag (tag.id)}
								<!-- The checkbox is inside the label, so no `for` attribute: pairing both makes Chrome
							     deliver two clicks for one press on the row, which toggled the tag off and on again. -->
								<label class="tag-picker__option">
									<input
										type="checkbox"
										checked={assignmentIdByTagId.has(tag.id)}
										onchange={(event) =>
											toggleTag(tag, (event.currentTarget as HTMLInputElement).checked)}
									/>
									<span
										class="tag-picker__option-dot tag-picker__option-dot--{colorForId(tag.id)}"
										aria-hidden="true"
									></span>
									<span class="tag-picker__option-label">{tag.name}</span>
								</label>
							{:else}
								<p class="tag-picker__empty">
									{normalizedSearch ? 'No matching tags.' : 'No tags yet.'}
								</p>
							{/each}
							{#if normalizedSearch && !hasExactMatch}
								<button type="button" class="tag-picker__create" onclick={createFromSearch}>
									Create tag "{search.trim()}"
								</button>
							{/if}
						</div>
					</Popover.Content>
				</Popover.Portal>
			</Popover.Root>
		{/if}
	</div>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.tag-picker-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}

	.tag-picker {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);

		&__chip {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			padding: 6px 10px;
			border-radius: var(--radius-large);
			background: var(--tag-bg, var(--color-inactive--surface));
			color: var(--tag-fg, var(--color-inactive--onSurface));
			font-size: var(--typography--fontSize-small);
			font-weight: 400;
		}

		&__chip-remove {
			display: grid;
			width: 16px;
			height: 16px;
			place-items: center;
			border: 0;
			border-radius: var(--radius-circle);
			color: inherit;
			background: transparent;
			cursor: pointer;
			opacity: 0.7;

			&:hover {
				opacity: 1;
				background: rgba(0, 0, 0, 0.08);
			}

			:global(svg) {
				display: block;
				width: 12px;
				height: 12px;
			}
		}

		&__chip--red {
			--tag-bg: var(--color-critical--surface);
			--tag-fg: var(--color-critical--onSurface);
		}
		&__chip--orange {
			--tag-bg: var(--color-base-orange--200);
			--tag-fg: var(--color-base-orange--600);
		}
		&__chip--green {
			--tag-bg: var(--color-success--surface);
			--tag-fg: var(--color-success--onSurface);
		}
		&__chip--teal {
			--tag-bg: var(--color-base-teal--200);
			--tag-fg: var(--color-base-teal--700);
		}
		&__chip--blue {
			--tag-bg: var(--color-inactive--surface);
			--tag-fg: var(--color-inactive--onSurface);
		}
		&__chip--purple {
			--tag-bg: var(--color-base-purple--200, var(--color-inactive--surface));
			--tag-fg: var(--color-base-purple--700, var(--color-inactive--onSurface));
		}
		&__chip--pink {
			--tag-bg: var(--color-quote--surface);
			--tag-fg: var(--color-quote--onSurface);
		}
		&__chip--yellowGreen {
			--tag-bg: var(--color-job--surface);
			--tag-fg: var(--color-job--onSurface);
		}
	}

	:global(.tag-picker__trigger) {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		padding: 5px var(--space-small) 5px 8px;
		border: var(--border-base) dashed var(--color-border--interactive);
		border-radius: var(--radius-large);
		color: var(--color-text--secondary);
		background: transparent;
		font-size: var(--typography--fontSize-small);
		cursor: pointer;
		transition: all var(--timing-quick);

		&:hover {
			color: var(--color-heading);
			border-color: var(--color-interactive);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	:global(.tag-picker__popover) {
		z-index: var(--elevation-tooltip);
		display: flex;
		width: min(280px, calc(100vw - var(--space-large) * 2));
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	.tag-picker__options {
		display: flex;
		max-height: 220px;
		flex-direction: column;
		gap: var(--space-small);
		overflow-y: auto;
	}

	.tag-picker__option {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border-radius: var(--radius-small);
		cursor: pointer;
		transition: background-color var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}

		input {
			width: 16px;
			height: 16px;
			accent-color: var(--color-interactive);
		}

		input:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.tag-picker__option-dot {
		width: 8px;
		height: 8px;
		flex: 0 0 auto;
		border-radius: var(--radius-circle);
		background: var(--tag-fg, var(--color-inactive));
	}

	.tag-picker__option-dot--red {
		--tag-fg: var(--color-critical);
	}
	.tag-picker__option-dot--orange {
		--tag-fg: var(--color-base-orange--600);
	}
	.tag-picker__option-dot--green {
		--tag-fg: var(--color-success);
	}
	.tag-picker__option-dot--teal {
		--tag-fg: var(--color-base-teal--700);
	}
	.tag-picker__option-dot--blue {
		--tag-fg: var(--color-inactive);
	}
	.tag-picker__option-dot--purple {
		--tag-fg: var(--color-base-purple--700, var(--color-inactive));
	}
	.tag-picker__option-dot--pink {
		--tag-fg: var(--color-quote);
	}
	.tag-picker__option-dot--yellowGreen {
		--tag-fg: var(--color-job);
	}

	.tag-picker__option-label {
		overflow: hidden;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.tag-picker__empty {
		padding: var(--space-small) 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.tag-picker__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.tag-picker__create {
		padding: var(--space-small);
		border: var(--border-base) dashed var(--color-border--interactive);
		border-radius: var(--radius-small);
		color: var(--color-interactive);
		background: transparent;
		font-size: var(--typography--fontSize-small);
		text-align: left;
		cursor: pointer;

		&:hover:not(:disabled) {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&:disabled {
			color: var(--color-disabled);
			cursor: not-allowed;
		}
	}
</style>
