<script lang="ts">
	import alertIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';
	let {
		value = $bindable(''),
		id,
		label,
		rows = 3,
		maxlength,
		showCount = true,
		required = false,
		invalid = false,
		errorMessage = '',
		disabled = false,
		class: className = '',
		...rest
	}: {
		value?: string;
		id: string;
		label?: string;
		rows?: number;
		maxlength?: number;
		showCount?: boolean;
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		disabled?: boolean;
		class?: string;
		[key: string]: unknown;
	} = $props();

	let describedBy = $derived(errorMessage ? `${id}-error` : undefined);
	let isInvalid = $derived(invalid || Boolean(errorMessage));
	let remaining = $derived(maxlength !== undefined && showCount ? maxlength - value.length : null);
</script>

<div
	class={`textarea ${className}`}
	class:textarea--invalid={isInvalid}
	class:textarea--disabled={disabled}
>
	{#if label}<label class="textarea__label" for={id}
			>{label}{#if required}<span class="field-required" aria-hidden="true">*</span>{/if}</label
		>{/if}
	<textarea
		{...rest}
		{id}
		{rows}
		{maxlength}
		bind:value
		{disabled}
		aria-invalid={isInvalid}
		aria-required={required || undefined}
		aria-describedby={describedBy}></textarea>
	<div class="textarea__footer">
		{#if errorMessage}
			<p class="textarea__error" id={`${id}-error`} role="alert">
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<span aria-hidden="true">{@html alertIcon}</span>{errorMessage}
			</p>
		{:else}
			<span></span>
		{/if}
		{#if remaining !== null}
			<span class="textarea__count" class:textarea__count--low={remaining < 0}
				>{remaining < 0 ? `${Math.abs(remaining)} too many` : `${remaining} left`}</span
			>
		{/if}
	</div>
</div>

<style lang="scss">
	.textarea {
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

		textarea {
			display: block;
			width: 100%;
			min-height: 96px;
			padding: 10px var(--space-slim);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			outline: 0;
			color: var(--color-heading);
			background: var(--color-surface);
			font: inherit;
			line-height: 1.45;
			resize: vertical;
			&::placeholder {
				color: var(--color-text--secondary);
				opacity: 1;
			}
			&:hover {
				border-color: var(--color-border--interactive--hover);
			}
			&:focus {
				box-shadow: var(--shadow-focus);
			}
		}
		&--invalid textarea {
			border: 1.5px solid var(--color-critical);
		}
		&--disabled textarea {
			color: var(--color-disabled);
			border-color: var(--color-border);
			background: var(--color-disabled--secondary);
		}
		&__footer {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			padding-top: var(--space-smaller);
		}
		&__error {
			padding-top: 0;
		}
		&__count {
			margin-left: auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			white-space: nowrap;
		}
		&__count--low {
			color: var(--color-critical);
			font-weight: 600;
		}
	}
</style>
