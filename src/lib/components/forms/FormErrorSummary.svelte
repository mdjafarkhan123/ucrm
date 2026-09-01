<script lang="ts">
	import { tick } from 'svelte';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// The one place a create/edit form shows why a save did not go through. It sits at the top of the form's
	// main card, but the person is usually scrolled down near the Save button when it appears — so on every
	// failed save the form calls `reveal()` and this scrolls itself into view and takes keyboard focus, the
	// way GitHub, Stripe and the GOV.UK Design System handle form errors. Without that the message renders
	// off-screen and Save just looks broken.
	let {
		message = '',
		fields = []
	}: {
		message?: string;
		/** Optional jump links to the fields that need fixing. `anchor` is the target element's DOM id. */
		fields?: { anchor: string; label: string }[];
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

{#if message}
	<div class="form-error-summary" role="alert" tabindex="-1" bind:this={region}>
		<span class="form-error-summary__icon" aria-hidden="true">
			<!-- eslint-disable-next-line svelte/no-at-html-tags -->
			{@html alertTriangleIcon}
		</span>
		<div class="form-error-summary__body">
			<p class="form-error-summary__message">{message}</p>
			{#if fields.length > 0}
				<ul class="form-error-summary__list">
					{#each fields as field (field.anchor)}
						<li>
							<a href={`#${field.anchor}`} onclick={(event) => jump(field.anchor, event)}>
								{field.label}
							</a>
						</li>
					{/each}
				</ul>
			{/if}
		</div>
	</div>
{/if}

<style lang="scss">
	.form-error-summary {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&__icon :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
			// Nudge the icon onto the first line of text.
			margin-top: 1px;
			flex: 0 0 auto;
		}

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			min-width: 0;
		}

		&__message {
			margin: 0;
		}

		&__list {
			margin: 0;
			padding-left: var(--space-base);
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);

			a {
				color: inherit;
				font-weight: 600;
				text-decoration: underline;

				&:hover {
					color: var(--color-heading);
				}
				&:focus-visible {
					outline: none;
					box-shadow: var(--shadow-focus);
				}
			}
		}
	}
</style>
