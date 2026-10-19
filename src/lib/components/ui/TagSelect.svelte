<script lang="ts" module>
	export type TagOption = { id: string; name: string; color?: string | null };
</script>

<script lang="ts">
	import { Popover } from 'bits-ui';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import { tagColor, tagColors, nextTagColor } from '$lib/collaboration/tag-colors';
	import tagIcon from '@tabler/icons/outline/tag.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import circlePlusIcon from '@tabler/icons/outline/circle-plus.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import dotsIcon from '@tabler/icons/outline/dots.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import tagPlusIcon from '@tabler/icons/outline/tag-plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// Chips for the chosen entries of one shared catalog, plus a searchable popover to add more. It holds the
	// chosen ids only; the catalog and creating a new entry belong to the caller, so client tags and photo
	// labels are the same control over two different lists. Without `onCreate` the list is pick-only.
	let {
		tagIds = $bindable<string[]>([]),
		onChange,
		catalog,
		onCreate,
		onColorChange,
		noun = 'tag',
		addLabel = 'Add tag',
		searchId,
		disabled = false,
		readonly = false
	}: {
		tagIds?: string[];
		onChange?: (next: string[]) => void;
		catalog: TagOption[];
		/** Adds a new entry to the catalog and returns it. Leave out when this person may only pick. */
		onCreate?: (name: string, color?: string) => Promise<TagOption>;
		/** What one entry is called in sentences: "tag", "label". */
		onColorChange?: (id: string, color: string) => Promise<void>;
		noun?: string;
		addLabel?: string;
		searchId: string;
		/** Chips only: no remove buttons and no popover, for someone who may see the entries but not change them. */
		disabled?: boolean;
		readonly?: boolean;
	} = $props();

	function setTags(next: string[]) {
		tagIds = next;
		onChange?.(next);
	}

	const tagsById = $derived(new Map(catalog.map((tag) => [tag.id, tag])));
	const chosen = $derived(tagIds.map((id) => tagsById.get(id)).filter((tag) => tag !== undefined));

	let open = $state(false);
	let search = $state('');
	let actionError = $state('');
	let creating = $state(false);
	let selectedColor = $state<string | null>(null);
	let changingColor = $state<string | null>(null);
	const newColor = $derived(selectedColor ?? nextTagColor(catalog).hex);
	async function recolor(id: string, color: string) {
		if (!onColorChange || changingColor) return;
		changingColor = `${id}:${color}`;
		actionError = '';
		try {
			await onColorChange(id, color);
		} catch (error) {
			actionError = error instanceof Error ? error.message : 'Colour could not be saved.';
		} finally {
			changingColor = null;
		}
	}

	const normalizedSearch = $derived(search.trim().toLowerCase());
	const filteredTags = $derived(
		normalizedSearch
			? catalog.filter((tag) => tag.name.toLowerCase().includes(normalizedSearch))
			: catalog
	);
	const hasExactMatch = $derived(
		catalog.some((tag) => tag.name.toLowerCase() === normalizedSearch)
	);

	function toggle(tagId: string, checked: boolean) {
		if (disabled) return;
		setTags(checked ? [...tagIds, tagId] : tagIds.filter((id) => id !== tagId));
	}

	// A brand-new entry joins the shared catalog straight away, since the catalog does not belong to this
	// record. Only the assignment waits for the caller's save.
	async function createFromSearch() {
		const name = search.trim();
		if (!onCreate || !name || creating || disabled) return;
		creating = true;
		actionError = '';
		try {
			const tag = await onCreate(name, newColor);
			if (!tagIds.includes(tag.id)) setTags([...tagIds, tag.id]);
			search = '';
		} catch (error) {
			actionError = error instanceof Error ? error.message : `That ${noun} could not be created.`;
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
<div class="tag-select">
	{#each chosen as tag (tag.id)}
		<span
			class="tag-select__chip tag-select__chip--{tagColor(tag.color).token}"
			class:tag-select__chip--readonly={readonly}
		>
			<span class="tag-select__icon" aria-hidden="true">{@html tagIcon}</span>{tag.name}
			{#if !readonly}
				<button
					type="button"
					class="tag-select__chip-remove"
					{disabled}
					aria-label={`Remove ${tag.name} ${noun}`}
					onclick={() => toggle(tag.id, false)}
				>
					{@html xIcon}
				</button>
			{/if}
		</span>
	{/each}

	{#if !readonly}
		<Popover.Root bind:open>
			<Popover.Trigger class="tag-select__trigger" {disabled}>
				{@html tagPlusIcon}
				<span>{addLabel}</span>
			</Popover.Trigger>
			<Popover.Portal>
				<Popover.Content
					class="tag-select__popover"
					align="start"
					sideOffset={8}
					collisionPadding={12}
				>
					<SearchInput
						id={searchId}
						bind:value={search}
						placeholder={onCreate ? `Find or create a ${noun}` : `Find a ${noun}`}
						onkeydown={onSearchKeydown}
					/>
					{#if actionError}<p class="tag-select__error" role="alert">
							<span aria-hidden="true">{@html alertIcon}</span>{actionError}
						</p>{/if}
					<div class="tag-select__options">
						{#each filteredTags as tag (tag.id)}
							<!-- Checkbox inside the label with no `for`: pairing both makes Chrome
						     fire two clicks for one press, which toggles the tag straight back off. -->
							<div class="tag-select__row">
								<label class="tag-select__option">
									<input
										type="checkbox"
										{disabled}
										checked={tagIds.includes(tag.id)}
										onchange={(event) =>
											toggle(tag.id, (event.currentTarget as HTMLInputElement).checked)}
									/>
									<span
										class="tag-select__dot tag-select__dot--{tagColor(tag.color).token}"
										aria-hidden="true">{@html tagIcon}</span
									>
									<span class="tag-select__option-label">{tag.name}</span>
								</label>
								{#if onColorChange}
									<Popover.Root>
										<Popover.Trigger
											class="tag-select__more"
											aria-label={`Change colour for ${tag.name}`}>{@html dotsIcon}</Popover.Trigger
										>
										<Popover.Portal
											><Popover.Content class="tag-select__colours" side="right" sideOffset={4}>
												<span class="tag-select__caption">COLOUR</span>
												{#each tagColors as color (color.hex)}
													<Button
														variant="quiet"
														size="small"
														loading={changingColor === `${tag.id}:${color.hex}`}
														disabled={Boolean(changingColor)}
														onclick={() => recolor(tag.id, color.hex)}
														><span
															class="tag-select__swatch"
															style:background={`var(--color-${color.token})`}
														></span>{color.name}{#if tagColor(tag.color).hex === color.hex}<span
																class="tag-select__check"
																aria-label="Current colour">{@html checkIcon}</span
															>{/if}</Button
													>
												{/each}
											</Popover.Content></Popover.Portal
										>
									</Popover.Root>
								{/if}
							</div>
						{:else}
							<p class="tag-select__empty">
								{normalizedSearch ? `No matching ${noun}s.` : `No ${noun}s yet.`}
							</p>
						{/each}
						{#if onCreate && normalizedSearch && !hasExactMatch}
							<Button
								variant="quiet"
								loading={creating}
								{disabled}
								icon={circlePlusIcon}
								onclick={createFromSearch}>Create {noun} “{search.trim()}”</Button
							>
							<div class="tag-select__palette" aria-label="New tag colour">
								{#each tagColors as color (color.hex)}
									<button
										type="button"
										aria-label={color.name}
										aria-pressed={newColor === color.hex}
										style:background={`var(--color-${color.token})`}
										onclick={() => (selectedColor = color.hex)}
									></button>
								{/each}
							</div>
							<span class="tag-select__hint">Choose a colour for this {noun}.</span>
						{/if}
					</div>
				</Popover.Content>
			</Popover.Portal>
		</Popover.Root>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.tag-select {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);

		&__chip {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			height: 28px;
			padding: 0 4px 0 10px;
			font-weight: 600;
			border-radius: var(--radius-circle);
			color: var(--tag-fg, var(--color-inactive--onSurface));
			background: var(--tag-bg, var(--color-inactive--surface));
			font-size: var(--typography--fontSize-small);
		}

		&__chip-remove {
			display: grid;
			width: 20px;
			height: 20px;
			place-items: center;
			border: 0;
			border-radius: var(--radius-circle);
			color: inherit;
			background: transparent;
			cursor: pointer;
			opacity: 0.7;

			&:hover {
				background: var(--color-surface--active);
				opacity: 1;
			}

			:global(svg) {
				display: block;
				width: 12px;
				height: 12px;
			}
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
				width: 18px;
				height: 18px;
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
	}

	:global(.tag-select__trigger) {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		padding: 5px var(--space-small) 5px 8px;
		border: var(--border-base) solid var(--color-border--interactive);
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

	:global(.tag-select__popover) {
		z-index: var(--elevation-tooltip);
		display: flex;
		width: min(280px, calc(100vw - var(--space-large) * 2));
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	.tag-select {
		&__row {
			display: flex;
			align-items: center;
			min-height: 36px;
		}
		&__option {
			flex: 1;
			min-width: 0;
			min-height: 36px;
		}
		&__icon {
			display: inline-flex;
			color: var(--tag-color);
			:global(svg) {
				width: 13px;
				height: 13px;
			}
		}
		&__dot {
			width: 14px;
			height: 14px;
			flex: 0 0 14px;
			border-radius: var(--radius-circle);
			color: var(--tag-color);
			background: transparent;
			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
		&__palette {
			display: flex;
			gap: 8px;
			padding: 4px;
			button {
				width: 16px;
				height: 16px;
				border: 0;
				border-radius: var(--radius-circle);
				cursor: pointer;
				&[aria-pressed='true'] {
					outline: 1.5px solid var(--color-heading);
					outline-offset: 3px;
				}
				&:focus-visible {
					box-shadow: var(--shadow-focus);
				}
			}
		}
		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
	:global(.tag-select__more) {
		width: 28px;
		height: 28px;
		border: 0;
		border-radius: var(--radius-tile-small);
		color: var(--color-icon);
		background: var(--color-surface--active);
		cursor: pointer;
		:global(svg) {
			width: 16px;
			height: 16px;
		}
		&:focus-visible {
			box-shadow: var(--shadow-focus);
		}
	}
	:global(.tag-select__colours) {
		z-index: var(--elevation-tooltip);
		display: flex;
		flex-direction: column;
		width: 200px;
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	:global(.tag-select__swatch) {
		width: 14px;
		height: 14px;
		border-radius: var(--radius-circle);
	}
	:global(.tag-select__caption) {
		padding: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-overline);
	}
	.tag-select__chip--inactive,
	.tag-select__dot--inactive {
		--tag-bg: var(--color-inactive--surface);
		--tag-fg: var(--color-inactive--onSurface);
		--tag-color: var(--color-inactive);
	}
	.tag-select__chip--critical,
	.tag-select__dot--critical {
		--tag-bg: var(--color-critical--surface);
		--tag-fg: var(--color-critical--onSurface);
		--tag-color: var(--color-critical);
	}
	.tag-select__chip--request,
	.tag-select__dot--request {
		--tag-bg: var(--color-request--surface);
		--tag-fg: var(--color-request--onSurface);
		--tag-color: var(--color-request);
	}
	.tag-select__chip--review,
	.tag-select__dot--review {
		--tag-bg: var(--color-review--surface);
		--tag-fg: var(--color-review--onSurface);
		--tag-color: var(--color-review);
	}
	.tag-select__chip--job,
	.tag-select__dot--job {
		--tag-bg: var(--color-job--surface);
		--tag-fg: var(--color-job--onSurface);
		--tag-color: var(--color-job);
	}
	.tag-select__chip--conversation,
	.tag-select__dot--conversation {
		--tag-bg: var(--color-conversation--surface);
		--tag-fg: var(--color-conversation--onSurface);
		--tag-color: var(--color-conversation);
	}
	.tag-select__chip--invoice,
	.tag-select__dot--invoice {
		--tag-bg: var(--color-invoice--surface);
		--tag-fg: var(--color-invoice--onSurface);
		--tag-color: var(--color-invoice);
	}
	.tag-select__chip--time,
	.tag-select__dot--time {
		--tag-bg: var(--color-time--surface);
		--tag-fg: var(--color-time--onSurface);
		--tag-color: var(--color-time);
	}
	.tag-select__chip--growth,
	.tag-select__dot--growth {
		--tag-bg: var(--color-growth--surface);
		--tag-fg: var(--color-growth--onSurface);
		--tag-color: var(--color-growth);
	}
	.tag-select__chip--quote,
	.tag-select__dot--quote {
		--tag-bg: var(--color-quote--surface);
		--tag-fg: var(--color-quote--onSurface);
		--tag-color: var(--color-quote);
	}
	.tag-select__chip--readonly {
		padding: 0 10px;
	}
	.tag-select__option:has(input:checked) .tag-select__option-label {
		font-weight: 600;
	}
	.tag-select__check {
		display: inline-flex;
		color: var(--color-interactive);
		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
	.tag-select__error {
		display: flex;
		gap: 6px;
		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}
</style>
