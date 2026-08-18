<script lang="ts">
	let {
		value = $bindable(''),
		id,
		label,
		rows = 3,
		maxlength,
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
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		disabled?: boolean;
		class?: string;
		[key: string]: unknown;
	} = $props();

	let describedBy = $derived(errorMessage ? `${id}-error` : undefined);
	let hasValue = $derived(Boolean(value));
	let remaining = $derived(maxlength ? maxlength - value.length : null);
</script>

<div
	class={`textarea ${className}`}
	class:textarea--has-value={hasValue}
	class:textarea--invalid={invalid}
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
		aria-invalid={invalid}
		aria-required={required || undefined}
		aria-describedby={describedBy}></textarea>
	<div class="textarea__footer">
		{#if errorMessage}
			<p class="textarea__error" id={`${id}-error`} role="alert">{errorMessage}</p>
		{:else}
			<span></span>
		{/if}
		{#if remaining !== null}
			<span class="textarea__count" class:textarea__count--low={remaining < 0}>{remaining}</span>
		{/if}
	</div>
</div>

<style lang="scss">
	.textarea {
		position: relative;
		width: 100%;
		font-size: var(--typography--fontSize-base);

		&__label {
			position: absolute;
			z-index: var(--elevation-base);
			top: var(--space-base);
			left: var(--space-base);
			max-width: calc(100% - var(--space-largest));
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			text-overflow: ellipsis;
			white-space: nowrap;
			transition: all var(--timing-quick);
			pointer-events: none;
		}

		textarea {
			display: block;
			width: 100%;
			min-height: var(--space-largest);
			padding: calc(var(--space-base) - var(--space-smallest)) var(--space-base);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			outline: 0;
			color: var(--color-heading);
			background: var(--color-surface);
			font: inherit;
			line-height: 20px;
			resize: vertical;
		}

		textarea:focus {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&:focus-within .textarea__label,
		&--has-value .textarea__label {
			top: var(--space-smallest);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&:focus-within textarea,
		&--has-value textarea {
			padding-top: calc(var(--space-base) + var(--space-smaller));
		}

		&--invalid textarea {
			border-color: var(--color-critical);
		}

		&--disabled textarea {
			color: var(--color-disabled);
			border-color: var(--color-border);
			background: var(--color-disabled--secondary);
		}

		&__footer {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-small);
			min-height: 18px;
			padding-top: var(--space-smaller);
		}

		&__error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__count {
			margin-left: auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);

			&--low {
				color: var(--color-critical);
			}
		}
	}
</style>
