<script lang="ts">
	import { Popover } from 'bits-ui';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// A free-text multi-value field for rule conditions that have no id-backed catalog -- a city name, a
	// lead source. `suggestions` offers known values (e.g. the lead source list) without limiting entry to
	// them, since a rule has to keep matching a value typed before the suggestion list existed.
	let {
		values = $bindable<string[]>([]),
		id,
		max,
		placeholder = 'Type a value and press Enter',
		suggestions = [],
		onChange
	}: {
		values?: string[];
		id: string;
		max: number;
		placeholder?: string;
		suggestions?: string[];
		onChange?: (next: string[]) => void;
	} = $props();

	function setValues(next: string[]) {
		values = next;
		onChange?.(next);
	}

	let open = $state(false);
	let draft = $state('');

	const normalizedDraft = $derived(draft.trim());
	const atMax = $derived(values.length >= max);
	const filteredSuggestions = $derived(
		suggestions.filter(
			(suggestion) =>
				!values.includes(suggestion) &&
				(!normalizedDraft || suggestion.toLowerCase().includes(normalizedDraft.toLowerCase()))
		)
	);

	function add(raw: string) {
		const value = raw.trim();
		if (!value || atMax || values.includes(value)) return;
		setValues([...values, value]);
		draft = '';
	}

	function remove(value: string) {
		setValues(values.filter((entry) => entry !== value));
	}

	function onKeydown(event: KeyboardEvent) {
		if (event.key === 'Enter' || event.key === ',') {
			event.preventDefault();
			add(draft);
		} else if (event.key === 'Backspace' && !draft && values.length > 0) {
			remove(values[values.length - 1]);
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="free-text-chips">
	{#each values as value (value)}
		<span class="free-text-chips__chip">
			{value}
			<button
				type="button"
				class="free-text-chips__chip-remove"
				aria-label={`Remove ${value}`}
				onclick={() => remove(value)}
			>
				{@html xIcon}
			</button>
		</span>
	{/each}

	{#if !atMax}
		<Popover.Root bind:open>
			<Popover.Trigger class="free-text-chips__trigger">
				{@html plusIcon}
				<span>Add</span>
			</Popover.Trigger>
			<Popover.Portal>
				<Popover.Content
					class="free-text-chips__popover"
					align="start"
					sideOffset={8}
					collisionPadding={12}
				>
					<input
						{id}
						class="free-text-chips__input"
						type="text"
						bind:value={draft}
						{placeholder}
						onkeydown={onKeydown}
					/>
					{#if filteredSuggestions.length > 0}
						<div class="free-text-chips__suggestions">
							{#each filteredSuggestions as suggestion (suggestion)}
								<button
									type="button"
									class="free-text-chips__suggestion"
									onclick={() => add(suggestion)}
								>
									{suggestion}
								</button>
							{/each}
						</div>
					{/if}
					<p class="free-text-chips__hint">Press Enter to add.</p>
				</Popover.Content>
			</Popover.Portal>
		</Popover.Root>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.free-text-chips {
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
			color: var(--color-inactive--onSurface);
			background: var(--color-inactive--surface);
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

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__suggestions {
			display: flex;
			max-height: 160px;
			flex-direction: column;
			gap: 2px;
			overflow-y: auto;
		}

		&__suggestion {
			padding: var(--space-small);
			border: 0;
			border-radius: var(--radius-small);
			color: var(--color-text);
			background: transparent;
			font-size: var(--typography--fontSize-small);
			text-align: left;
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
			}
		}

		&__input {
			width: 100%;
			padding: var(--space-small);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-heading);
			background: var(--color-surface);
			font: inherit;

			&:focus {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
	}

	:global(.free-text-chips__trigger) {
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

	:global(.free-text-chips__popover) {
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
