<script lang="ts">
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
	let hasValue = $derived(Boolean(value));
	let remaining = $derived(maxlength && showCount ? maxlength - value.length : null);
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

	:global(:root:has(.app-shell[data-presentation='classic'])) .textarea {
		display: flex;
		flex-direction: column;
		gap: 7px;
		color: var(--classic2-ink);
		font-family: var(--classic2-font);
		font-size: var(--classic2-font-body);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .textarea__label {
		position: static;
		z-index: auto;
		max-width: 100%;
		overflow: visible;
		color: var(--classic2-body);
		font-size: var(--classic2-font-label);
		font-weight: 600;
		line-height: 1.25;
		text-overflow: clip;
		transition: none;
		pointer-events: auto;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .textarea textarea {
		min-height: 88px;
		padding: 12px 14px;
		border-color: var(--classic2-border-input);
		border-radius: 12px;
		color: var(--classic2-ink);
		background: var(--classic2-surface);
		box-shadow: 0 1px 2px var(--classic2-shadow-near);
		font-family: var(--classic2-font);
		font-size: var(--classic2-font-body);
		line-height: 1.5;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .textarea textarea::placeholder {
		color: var(--classic2-muted);
		opacity: 1;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .textarea textarea:focus {
		border-color: var(--classic2-green);
		outline: 3px solid var(--classic2-green-soft);
		outline-offset: 2px;
		box-shadow: 0 1px 2px var(--classic2-shadow-near);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .textarea--invalid textarea {
		border-color: var(--classic2-rose);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .textarea--disabled textarea {
		border-color: var(--classic2-border-input);
		color: var(--classic2-muted);
		background: var(--classic2-surface-soft);
		box-shadow: none;
		-webkit-text-fill-color: var(--classic2-muted);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .textarea__error {
		color: var(--classic2-rose);
		font-size: var(--classic2-font-small);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .textarea__count {
		color: var(--classic2-muted);
		font-size: var(--classic2-font-small);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .textarea__count--low {
		color: var(--classic2-rose);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) :global(.field-required) {
		color: var(--classic2-required);
	}
</style>
