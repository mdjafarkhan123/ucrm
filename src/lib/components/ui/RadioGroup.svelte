<script lang="ts">
	// One pick from a small set of options whose labels are too long for a SegmentedControl. Options sit
	// side by side where there is room and stack on a narrow screen. Looks follow the Radio spec in the
	// design skill (radios-checkboxes-toggle.md).
	type Option = { value: string; label: string };

	let {
		value = $bindable(''),
		options,
		label,
		labelledby,
		variant = 'plain',
		name,
		disabled = false,
		onchange
	}: {
		value?: string;
		options: Option[];
		/** The question the options answer, shown above them. */
		label: string;
		/** The id of a question already shown elsewhere; the group then draws no label of its own. */
		labelledby?: string;
		/** `cards` draws each option as a bordered tile, for question-and-answer screens like setup. */
		variant?: 'plain' | 'cards';
		name?: string;
		disabled?: boolean;
		onchange?: (value: string) => void;
	} = $props();

	const uid = $props.id();
	const groupName = $derived(name ?? uid);
</script>

<div
	class={['radio-group', variant === 'cards' && 'radio-group--cards']}
	role="radiogroup"
	aria-labelledby={labelledby ?? `${uid}-label`}
>
	{#if !labelledby}<span class="radio-group__label" id={`${uid}-label`}>{label}</span>{/if}
	<div class="radio-group__options">
		{#each options as option (option.value)}
			<label class="radio-group__option" class:radio-group__option--disabled={disabled}>
				<input
					type="radio"
					name={groupName}
					value={option.value}
					{disabled}
					checked={option.value === value}
					onchange={() => {
						value = option.value;
						onchange?.(option.value);
					}}
				/>
				<span class="radio-group__circle" aria-hidden="true"></span>
				<span>{option.label}</span>
			</label>
		{/each}
	</div>
</div>

<style lang="scss">
	.radio-group {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		min-width: 0;

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__options {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small) var(--space-base);
		}

		&__option {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			cursor: pointer;

			// The native input is hidden; the circle beside it is what people see.
			input {
				position: absolute;
				width: 1px;
				height: 1px;
				overflow: hidden;
				clip-path: inset(50%);
				white-space: nowrap;
			}

			&:hover .radio-group__circle {
				border-color: var(--color-interactive);
			}

			&--disabled {
				color: var(--color-disabled);
				cursor: not-allowed;

				.radio-group__circle {
					border-color: var(--color-disabled--secondary);
				}
			}
		}

		&__circle {
			flex-shrink: 0;
			width: 20px;
			height: 20px;
			border: var(--border-thick) solid var(--color-border--interactive);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			box-sizing: border-box;
			transition: all var(--timing-quick) ease-out;
		}

		input:checked + &__circle {
			border-color: var(--color-interactive);
			border-width: 6px;
		}

		input:focus-visible + &__circle {
			box-shadow: var(--shadow-focus);
		}

		&--cards &__options {
			gap: var(--space-small);
		}

		&--cards &__option {
			flex: 1 1 180px;
			align-items: center;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			transition:
				border-color var(--timing-quick) ease-out,
				background-color var(--timing-quick) ease-out;

			&:hover {
				border-color: var(--color-interactive);
			}

			&:has(input:checked) {
				border-color: var(--color-interactive);
				background: var(--color-interactive--background--subtle--hover);
				box-shadow: inset 0 0 0 1px var(--color-interactive);
				color: var(--color-heading);
				font-weight: 600;
			}

			&:has(input:focus-visible) {
				box-shadow: var(--shadow-focus);
			}
		}

		&--cards input:focus-visible + &__circle {
			box-shadow: none;
		}
	}

	@media (max-width: 560px) {
		.radio-group__options {
			flex-direction: column;
		}

		// Stacked, a card's 180px starting width would become its height.
		.radio-group--cards .radio-group__option {
			flex: none;
		}
	}
</style>
