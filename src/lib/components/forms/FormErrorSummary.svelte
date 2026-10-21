<script lang="ts">
	import arrowIcon from '@tabler/icons/outline/arrow-down-right.svg?raw';
	import { tick } from 'svelte';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// The one place a create/edit form shows why a save did not go through. It sits at the top of the form's
	// main card, but the person is usually scrolled down near the Save button when it appears — so on every
	// failed save the form calls `reveal()` and this scrolls itself into view and takes keyboard focus, the
	// way GitHub, Stripe and the GOV.UK Design System handle form errors. Without that the message renders
	// off-screen and Save just looks broken.
	let {
		message = '',
		fields = [],
		hint = 'Your other changes are kept.'
	}: {
		message?: string;
		hint?: string;
		/** Optional jump links to the fields that need fixing. `anchor` is the target element's DOM id. */
		fields?: { anchor: string; label: string; message?: string }[];
	} = $props();

	let region = $state<HTMLElement>();

	function focusTarget(el: HTMLElement | null) {
		if (!el) return;
		el.scrollIntoView({ behavior: 'smooth', block: 'center' });
		// A field is focusable on its own; the summary opts in with tabindex="-1".
		el.focus({ preventScroll: true });
	}

	// Called by the parent form after a failed save. Waits a frame for the message to render, then moves the
	// person to it. Safe to call when there is no error — `region` stays undefined and this does nothing.
	export async function reveal() {
		await tick();
		focusTarget(region ?? null);
	}

	function jump(anchor: string, event: Event) {
		event.preventDefault();
		focusTarget(document.getElementById(anchor));
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if message}<div class="form-error-summary" role="alert" tabindex="-1" bind:this={region}>
		<div class="form-error-summary__head">
			<span class="form-error-summary__icon" aria-hidden="true">{@html alertTriangleIcon}</span>
			<div>
				<p class="form-error-summary__message">{message}</p>
				<p class="form-error-summary__hint">{hint}</p>
			</div>
		</div>
		{#if fields.length}<ol class="form-error-summary__list">
				{#each fields as field, index (field.anchor)}<li>
						<a href={`#${field.anchor}`} onclick={(event) => jump(field.anchor, event)}
							><span class="form-error-summary__number">{index + 1}</span><span
								class="form-error-summary__field"
								>{field.label}{#if field.message}<small>{field.message}</small>{/if}</span
							><span class="form-error-summary__arrow" aria-hidden="true">{@html arrowIcon}</span
							></a
						>
					</li>{/each}
			</ol>{/if}
	</div>{/if}

<!-- eslint-enable svelte/no-at-html-tags -->
<style lang="scss">
	.form-error-summary {
		overflow: hidden;
		border: 1.5px solid var(--color-critical);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&__head {
			display: flex;
			align-items: center;
			gap: 12px;
			padding: 12px 14px;
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
		}
		&__icon {
			display: grid;
			place-items: center;
			flex: 0 0 32px;
			height: 32px;
			border-radius: var(--radius-base);
			background: var(--color-critical);
			color: var(--color-white);
			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__message {
			margin: 0;
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		&__hint {
			margin: 4px 0 0;
			font-size: var(--typography--fontSize-small);
		}
		&__list {
			list-style: none;
			margin: 0;
			padding: 0;
			li {
				border-top: 1px solid var(--color-border);
			}
			a {
				display: flex;
				align-items: center;
				gap: 10px;
				padding: 10px 14px;
				text-decoration: none;
				&:hover {
					background: var(--color-surface--hover);
				}
				&:focus-visible {
					outline: none;
					box-shadow: inset 0 0 0 2px var(--color-focus);
				}
			}
		}
		&__number {
			display: grid;
			place-items: center;
			flex: 0 0 20px;
			height: 20px;
			border-radius: var(--radius-circle);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-overline);
			font-weight: 700;
		}
		&__field {
			flex: 1;
			min-width: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			small {
				display: block;
				margin-top: 4px;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 400;
			}
		}
		&__arrow {
			color: var(--color-icon--secondary);
			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
