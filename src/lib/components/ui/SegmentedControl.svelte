<script lang="ts">
	import { untrack } from 'svelte';

	// One pick out of a short list, shown as joined segments — "One-off / Recurring", "Person / Company".
	// Use it for 2-4 options that fit in a word or two; anything longer or larger belongs in a Select.
	type Option = {
		value: string;
		label: string;
		disabled?: boolean;
		/** Shown on hover, e.g. why an option is closed off. */
		title?: string;
	};

	let {
		value = $bindable(''),
		options,
		label = '',
		name,
		size = 'base',
		fullWidth = false,
		disabled = false,
		onchange
	}: {
		value?: string;
		options: Option[];
		/** Small uppercase caption above the control. */
		label?: string;
		name?: string;
		size?: 'small' | 'base';
		fullWidth?: boolean;
		disabled?: boolean;
		onchange?: (value: string) => void;
	} = $props();

	const uid = $props.id();
	const groupName = $derived(name ?? uid);
	const labelId = $derived(label ? `${uid}-label` : undefined);
	const activeIndex = $derived(options.findIndex((option) => option.value === value));

	// The outlined box is one element that slides, rather than a border switched on and off per segment.
	// Its position has to be measured because the segments are as wide as their own labels.
	let trackEl = $state<HTMLElement>();
	let optionEls = $state<(HTMLElement | undefined)[]>([]);
	let thumb = $state({ left: 0, width: 0, visible: false });

	// Off for the first paint, so the box appears where it belongs instead of sliding in from the left.
	let animate = $state(false);

	function measure() {
		const el = optionEls[activeIndex];
		if (!el) {
			thumb = { left: 0, width: 0, visible: false };
			return;
		}
		thumb = { left: el.offsetLeft, width: el.offsetWidth, visible: true };
	}

	$effect(() => {
		measure();
	});

	$effect(() => {
		if (!thumb.visible || untrack(() => animate)) return;
		const frame = requestAnimationFrame(() => (animate = true));
		return () => cancelAnimationFrame(frame);
	});

	// Labels reflow when the column narrows or a font finishes loading, so the box re-measures with them.
	$effect(() => {
		if (!trackEl) return;
		const observer = new ResizeObserver(() => measure());
		observer.observe(trackEl);
		return () => observer.disconnect();
	});
</script>

<div class="segmented" class:segmented--full-width={fullWidth}>
	{#if label}
		<span class="segmented__caption" id={labelId}>{label}</span>
	{/if}

	<div
		bind:this={trackEl}
		class={`segmented__track segmented__track--${size}`}
		class:segmented__track--disabled={disabled}
		role="radiogroup"
		aria-labelledby={labelId}
	>
		{#if thumb.visible}
			<span
				class="segmented__thumb"
				class:segmented__thumb--animated={animate}
				aria-hidden="true"
				style={`transform: translateX(${thumb.left}px); width: ${thumb.width}px;`}
			></span>
		{/if}

		{#each options as option, index (option.value)}
			<label
				bind:this={optionEls[index]}
				class="segmented__option"
				class:segmented__option--active={option.value === value}
				class:segmented__option--disabled={disabled || option.disabled}
				title={option.title}
			>
				<input
					type="radio"
					name={groupName}
					value={option.value}
					disabled={disabled || option.disabled}
					checked={option.value === value}
					onchange={() => {
						value = option.value;
						onchange?.(option.value);
					}}
				/>
				<span class="segmented__text">{option.label}</span>
			</label>
		{/each}
	</div>
</div>

<style lang="scss">
	.segmented {
		display: inline-flex;
		flex-direction: column;
		gap: var(--space-smaller);

		&--full-width {
			display: flex;
			width: 100%;
		}

		&__caption {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__track {
			position: relative;
			display: inline-flex;
			gap: var(--space-smallest);
			padding: var(--space-smaller);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&--full-width &__track {
			display: flex;
			width: 100%;
		}

		&__thumb {
			position: absolute;
			top: var(--space-smaller);
			left: 0;
			bottom: var(--space-smaller);
			box-sizing: border-box;
			border: var(--border-base) solid var(--color-interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			&--animated {
				transition:
					transform var(--timing-base) cubic-bezier(0.4, 0, 0.2, 1),
					width var(--timing-base) cubic-bezier(0.4, 0, 0.2, 1);
			}
		}

		&__option {
			position: relative;
			z-index: 1;
			display: inline-flex;
			flex: 1 1 auto;
			align-items: center;
			justify-content: center;
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: transparent;
			font-weight: 600;
			white-space: nowrap;
			cursor: pointer;
			transition: color var(--timing-base) ease-out;

			input {
				position: absolute;
				width: 1px;
				height: 1px;
				overflow: hidden;
				clip: rect(0 0 0 0);
				white-space: nowrap;
			}

			&:hover:not(.segmented__option--disabled):not(.segmented__option--active) {
				color: var(--color-heading);
			}

			&:has(input:focus-visible) {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&--active {
				color: var(--color-interactive);
			}

			&--disabled {
				color: var(--color-disabled);
				cursor: not-allowed;
			}

			&--active#{&}--disabled {
				color: var(--color-disabled);
			}
		}

		&__track--base &__option {
			min-height: 36px;
			padding: 0 var(--space-base);
		}

		&__track--small &__option {
			min-height: 28px;
			padding: 0 var(--space-slim);
			font-size: var(--typography--fontSize-small);
		}

		&__track--disabled &__thumb {
			border-color: var(--color-disabled--secondary);
		}

		&__track--disabled {
			background: var(--color-disabled--secondary);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.segmented__thumb--animated {
			transition: none;
		}
	}
</style>
