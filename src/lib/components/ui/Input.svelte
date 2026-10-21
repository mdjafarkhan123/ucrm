<script lang="ts">
	import type { Snippet } from 'svelte';
	import exclamationCircleIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';

	let {
		value = $bindable(''),
		id,
		label,
		type = 'text',
		size = 'base',
		required = false,
		invalid = false,
		errorMessage = '',
		disabled = false,
		white = false,
		class: className = '',
		children,
		...rest
	}: {
		// A number field binds back a number, and an empty one binds back null, so the type covers what
		// the DOM actually hands over rather than only the text case.
		value?: string | number | null;
		id: string;
		label?: string;
		type?: string;
		size?: 'small' | 'base' | 'large';
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		disabled?: boolean;
		/** A white box, for a field on the page colour. Inside a `.tinted-surface` it is white without it. */
		white?: boolean;
		class?: string;
		children?: Snippet;
		[key: string]: unknown;
	} = $props();

	let describedBy = $derived(
		[rest['aria-describedby'], errorMessage ? `${id}-error` : undefined]
			.filter(Boolean)
			.join(' ') || undefined
	);
	let isInvalid = $derived(invalid || Boolean(errorMessage));
</script>

<div
	class={`input input--${size} ${className}`}
	class:input--labeled={Boolean(label) && size !== 'small'}
	class:input--invalid={isInvalid}
	class:input--disabled={disabled}
	class:input--white={white}
>
	{#if label}<label class="input__label" for={id}
			>{label}{#if required}<span class="field-required" aria-hidden="true">*</span>{/if}</label
		>{/if}
	<div class="input__control">
		{#if children}{@render children()}{/if}
		<input
			{...rest}
			{id}
			{type}
			bind:value
			{disabled}
			aria-invalid={isInvalid}
			aria-required={required || undefined}
			aria-describedby={describedBy}
		/>
	</div>
	{#if errorMessage}<p class="input__error" id={`${id}-error`} role="alert">
			<!-- eslint-disable-next-line svelte/no-at-html-tags -->
			<span aria-hidden="true">{@html exclamationCircleIcon}</span>{errorMessage}
		</p>{/if}
</div>

<style lang="scss">
	.input {
		width: 100%;
		min-width: 0;
		font-size: var(--typography--fontSize-base);

		&__label {
			display: block;
			margin-bottom: 6px;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}
		&__error {
			display: flex;
			align-items: flex-start;
			gap: 6px;
			margin: 0;
			padding-top: var(--space-smaller);
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
			line-height: 1.4;
		}
		&__error span {
			display: inline-flex;
			flex: 0 0 auto;
		}
		&__error span :global(svg) {
			width: 14px;
			height: 14px;
		}

		&__control {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-height: 40px;
			padding: 0 var(--space-slim);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--field--fill, var(--color-surface--background));
			&:hover {
				border-color: var(--color-border--interactive--hover);
			}
			&:focus-within {
				box-shadow: var(--shadow-focus);
			}
			// A front icon is quiet grey unless the caller gives it a meaning colour (`--field-icon-color`).
			:global(svg) {
				width: 16px;
				height: 16px;
				color: var(--field-icon-color, var(--color-icon--secondary));
			}
		}
		input {
			width: 100%;
			min-width: 0;
			padding: 9px 0;
			border: 0;
			outline: 0;
			background: transparent;
			color: var(--color-heading);
			font: inherit;
			line-height: 20px;
			&::placeholder {
				color: var(--color-text--secondary);
				opacity: 1;
			}
			&:focus-visible {
				outline: none;
				box-shadow: none;
			}
		}
		&--small &__control {
			min-height: 36px;
		}
		&--small input {
			padding: 7px 0;
			font-size: var(--typography--fontSize-label);
		}
		&--large &__control {
			min-height: var(--space-largest);
		}
		&--large input {
			font-size: var(--typography--fontSize-large);
		}
		&--invalid &__control {
			border: 1.5px solid var(--color-critical);
		}
		&--disabled &__control {
			border-color: var(--color-border);
			background: var(--color-disabled--secondary);
		}
		&--disabled input {
			color: var(--color-disabled);
			-webkit-text-fill-color: var(--color-disabled);
		}
		&--white {
			--field--fill: var(--color-surface);
		}
		&__control:has(input[readonly]) {
			background: var(--color-surface--background--subtle);
		}
	}
</style>
