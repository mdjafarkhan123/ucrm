<script lang="ts">
	// One pick from a small set of options whose labels are too long for a SegmentedControl. Options sit
	// side by side where there is room and stack on a narrow screen. Looks follow the Radio spec in the
	// design skill (radios-checkboxes-toggle.md).
	type Option = { value: string; label: string };

	let {
		value = $bindable(''),
		options,
		label,
		name,
		disabled = false,
		onchange
	}: {
		value?: string;
		options: Option[];
		/** The question the options answer, shown above them. */
		label: string;
		name?: string;
		disabled?: boolean;
		onchange?: (value: string) => void;
	} = $props();

	const uid = $props.id();
	const groupName = $derived(name ?? uid);
</script>

<div class="radio-group" role="radiogroup" aria-labelledby={`${uid}-label`}>
	<span class="radio-group__label" id={`${uid}-label`}>{label}</span>
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
	}

	@media (max-width: 560px) {
		.radio-group__options {
			flex-direction: column;
		}
	}
</style>
