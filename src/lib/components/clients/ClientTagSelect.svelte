<script lang="ts">
	import { Popover } from 'bits-ui';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import { colorForId } from '$lib/collaboration/format';
	import { createTag, fetchTags, tagsKey, type Tag } from '$lib/collaboration/api';
	import tagPlusIcon from '@tabler/icons/outline/tag-plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// Holds the chosen tag ids until the page saves them with everything else. The create form binds to
	// `tagIds`; a detail page passes the ids one way and stages the change through `onChange`.
	let {
		tagIds = $bindable<string[]>([]),
		onChange
	}: { tagIds?: string[]; onChange?: (next: string[]) => void } = $props();

	function setTags(next: string[]) {
		tagIds = next;
		onChange?.(next);
	}

	const queryClient = useQueryClient();

	const tagsQuery = createQuery<Tag[]>(() => ({ queryKey: tagsKey, queryFn: fetchTags }));
	const tags = $derived(tagsQuery.data ?? []);
	const tagsById = $derived(new Map(tags.map((tag) => [tag.id, tag])));
	const chosen = $derived(tagIds.map((id) => tagsById.get(id)).filter((tag) => tag !== undefined));

	let open = $state(false);
	let search = $state('');
	let actionError = $state('');
	let creating = $state(false);

	const normalizedSearch = $derived(search.trim().toLowerCase());
	const filteredTags = $derived(
		normalizedSearch
			? tags.filter((tag) => tag.name.toLowerCase().includes(normalizedSearch))
			: tags
	);
	const hasExactMatch = $derived(tags.some((tag) => tag.name.toLowerCase() === normalizedSearch));

	function toggle(tagId: string, checked: boolean) {
		setTags(checked ? [...tagIds, tagId] : tagIds.filter((id) => id !== tagId));
	}

	// A brand-new tag joins the organization's catalog straight away, since the catalog is shared and does
	// not belong to this client. Only the assignment waits for the save.
	async function createFromSearch() {
		const name = search.trim();
		if (!name || creating) return;
		creating = true;
		actionError = '';
		try {
			const tag = await createTag(name);
			queryClient.setQueryData<Tag[]>(tagsKey, (catalog) => {
				const current = catalog ?? [];
				if (current.some((entry) => entry.id === tag.id)) return current;
				return [...current, tag].sort((left, right) => left.name.localeCompare(right.name));
			});
			if (!tagIds.includes(tag.id)) setTags([...tagIds, tag.id]);
			search = '';
		} catch (error) {
			actionError = error instanceof Error ? error.message : 'That tag could not be created.';
		} finally {
			creating = false;
		}
	}

	function onSearchKeydown(event: KeyboardEvent) {
		if (event.key !== 'Enter') return;
		event.preventDefault();
		if (!normalizedSearch) return;

		const exact = filteredTags.find((tag) => tag.name.toLowerCase() === normalizedSearch);
		const target = exact ?? (filteredTags.length === 1 ? filteredTags[0] : undefined);
		if (target) {
			if (!tagIds.includes(target.id)) toggle(target.id, true);
			search = '';
			return;
		}
		if (filteredTags.length === 0) void createFromSearch();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="client-tag-select">
	{#each chosen as tag (tag.id)}
		<span class="client-tag-select__chip client-tag-select__chip--{colorForId(tag.id)}">
			{tag.name}
			<button
				type="button"
				class="client-tag-select__chip-remove"
				aria-label={`Remove ${tag.name} tag`}
				onclick={() => toggle(tag.id, false)}
			>
				{@html xIcon}
			</button>
		</span>
	{/each}

	<Popover.Root bind:open>
		<Popover.Trigger class="client-tag-select__trigger">
			{@html tagPlusIcon}
			<span>Add tags</span>
		</Popover.Trigger>
		<Popover.Portal>
			<Popover.Content
				class="client-tag-select__popover"
				align="start"
				sideOffset={8}
				collisionPadding={12}
			>
				<SearchInput
					id="client-form-tag-search"
					bind:value={search}
					placeholder="Find or create a tag"
					onkeydown={onSearchKeydown}
				/>
				{#if actionError}<p class="client-tag-select__error" role="alert">{actionError}</p>{/if}
				<div class="client-tag-select__options">
					{#each filteredTags as tag (tag.id)}
						<!-- Checkbox inside the label with no `for`, matching TagPicker: pairing both makes Chrome
						     fire two clicks for one press, which toggles the tag straight back off. -->
						<label class="client-tag-select__option">
							<input
								type="checkbox"
								checked={tagIds.includes(tag.id)}
								onchange={(event) =>
									toggle(tag.id, (event.currentTarget as HTMLInputElement).checked)}
							/>
							<span
								class="client-tag-select__dot client-tag-select__dot--{colorForId(tag.id)}"
								aria-hidden="true"
							></span>
							<span class="client-tag-select__option-label">{tag.name}</span>
						</label>
					{:else}
						<p class="client-tag-select__empty">
							{normalizedSearch ? 'No matching tags.' : 'No tags yet.'}
						</p>
					{/each}
					{#if normalizedSearch && !hasExactMatch}
						<button
							type="button"
							class="client-tag-select__create"
							disabled={creating}
							onclick={createFromSearch}
						>
							Create tag "{search.trim()}"
						</button>
					{/if}
				</div>
			</Popover.Content>
		</Popover.Portal>
	</Popover.Root>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-tag-select {
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
			color: var(--tag-fg, var(--color-inactive--onSurface));
			background: var(--tag-bg, var(--color-inactive--surface));
			font-size: var(--typography--fontSize-small);
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
				background: rgba(0, 0, 0, 0.08);
				opacity: 1;
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

		&__dot {
			width: 8px;
			height: 8px;
			flex: 0 0 auto;
			border-radius: var(--radius-circle);
			background: var(--tag-fg, var(--color-inactive));
		}
		&__dot--red {
			--tag-fg: var(--color-critical);
		}
		&__dot--orange {
			--tag-fg: var(--color-base-orange--600);
		}
		&__dot--green {
			--tag-fg: var(--color-success);
		}
		&__dot--teal {
			--tag-fg: var(--color-base-teal--700);
		}
		&__dot--blue {
			--tag-fg: var(--color-inactive);
		}
		&__dot--purple {
			--tag-fg: var(--color-base-purple--700, var(--color-inactive));
		}
		&__dot--pink {
			--tag-fg: var(--color-quote);
		}
		&__dot--yellowGreen {
			--tag-fg: var(--color-job);
		}

		&__options {
			display: flex;
			max-height: 220px;
			flex-direction: column;
			gap: var(--space-small);
			overflow-y: auto;
		}

		&__option {
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

		&__option-label {
			overflow: hidden;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__empty {
			padding: var(--space-small) 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__create {
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
	}

	:global(.client-tag-select__trigger) {
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
			border-color: var(--color-interactive);
			color: var(--color-heading);
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

	:global(.client-tag-select__popover) {
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
</style>
