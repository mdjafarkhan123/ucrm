<script lang="ts">
	import IconTile from './IconTile.svelte';

	// One choice drawn as a tile (design skill `layout.md` → Setup steps, the New campaign goal tiles): a 40 icon
	// tile, the title over a quiet description, and the radio circle at the top right. Chosen: a 1.5px
	// `--color-interactive` edge. Put tiles of one question inside an element with `role="radiogroup"`.
	let {
		name,
		value,
		checked,
		icon,
		tone,
		title,
		description,
		disabled = false,
		onselect
	}: {
		name: string;
		value: string;
		checked: boolean;
		/** A Tabler icon (raw SVG) on the tile. */
		icon: string;
		/** The tile's colour family. */
		tone: string;
		title: string;
		description?: string;
		disabled?: boolean;
		onselect: (value: string) => void;
	} = $props();
</script>

<label
	class={['radio-tile', checked && 'radio-tile--selected', disabled && 'radio-tile--disabled']}
>
	<input type="radio" {name} {value} {checked} {disabled} onchange={() => onselect(value)} />
	<IconTile {icon} {tone} />
	<span class="radio-tile__copy">
		<span class="radio-tile__title">{title}</span>
		{#if description}<span class="radio-tile__description">{description}</span>{/if}
	</span>
	<span class="radio-tile__radio" aria-hidden="true"></span>
</label>

<style lang="scss">
	.radio-tile {
		position: relative;
		display: flex;
		align-items: flex-start;
		gap: 14px;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		cursor: pointer;
		transition:
			border-color var(--timing-quick) ease-out,
			box-shadow var(--timing-quick) ease-out;

		input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}

		&:hover {
			border-color: var(--color-border--interactive--hover);
		}

		&:active {
			background: var(--color-surface--hover);
		}

		&:has(input:focus-visible) {
			box-shadow: var(--shadow-focus);
		}

		&--selected {
			border-color: var(--color-interactive);
			box-shadow: inset 0 0 0 0.5px var(--color-interactive);

			&:hover {
				border-color: var(--color-interactive);
			}

			&:has(input:focus-visible) {
				box-shadow:
					inset 0 0 0 0.5px var(--color-interactive),
					var(--shadow-focus);
			}
		}

		&--disabled {
			opacity: 0.55;
			cursor: not-allowed;
		}

		&__copy {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-smaller);
			min-width: 0;
			padding-right: var(--space-small);
		}

		&__title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__description {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			line-height: var(--typography--lineHeight-large);
		}

		&__radio {
			flex: none;
			box-sizing: border-box;
			width: 18px;
			height: 18px;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			transition: border-width var(--timing-quick) ease-out;
		}

		&--selected &__radio {
			border-width: 5px;
			border-color: var(--color-interactive);
		}
	}
</style>
