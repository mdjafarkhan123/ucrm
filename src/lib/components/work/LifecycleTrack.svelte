<script module lang="ts">
	export type TrackStep = {
		label: string;
		/** The line under the label, e.g. "Waiting on David". */
		sub: string;
		state: 'done' | 'current' | 'todo';
		/** Where a finished step's own page lives. A step with a link shows a small arrow. */
		href?: string;
		/** `critical` draws the line under the label as something the business is waiting on. */
		tone?: 'neutral' | 'critical';
		/** How much of a `current` step's bar is filled, from 0 to 1. */
		progress?: number;
	};
</script>

<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import arrowUpRightIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';

	// A work record's place on the line from Request to Paid: one bar per step, filled for what is done,
	// part-filled for where the record is now, and a line of words under each. It only reports; the page
	// says which step is which and what to write under it.

	let { steps, label = 'Progress' }: { steps: TrackStep[]; label?: string } = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
<ol class="lifecycle" aria-label={label}>
	{#each steps as step (step.label)}
		<li class="lifecycle__step" aria-current={step.state === 'current' ? 'step' : undefined}>
			<span class="lifecycle__bar" aria-hidden="true">
				{#if step.state === 'done'}
					<span class="lifecycle__fill" style:width="100%"></span>
				{:else if step.state === 'current'}
					<span class="lifecycle__fill" style:width="{Math.round((step.progress ?? 0.5) * 100)}%"
					></span>
				{/if}
			</span>
			<span class="lifecycle__title">
				{#if step.state === 'done'}
					<span class="lifecycle__check" aria-hidden="true">{@html checkIcon}</span>
				{:else if step.state === 'current'}
					<span class="lifecycle__dot" aria-hidden="true"></span>
				{/if}
				{#if step.href}
					<a class="lifecycle__label lifecycle__label--link" href={step.href}>
						{step.label}
						<span class="lifecycle__arrow" aria-hidden="true">{@html arrowUpRightIcon}</span>
					</a>
				{:else}
					<span
						class={[
							'lifecycle__label',
							step.state === 'todo' && 'lifecycle__label--todo',
							step.state === 'current' && 'lifecycle__label--current'
						]}>{step.label}</span
					>
				{/if}
			</span>
			<span class={['lifecycle__sub', step.tone === 'critical' && 'lifecycle__sub--critical']}>
				{step.sub}
			</span>
		</li>
	{/each}
</ol>

<!-- eslint-enable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->

<style lang="scss">
	.lifecycle {
		display: flex;
		gap: 14px;
		margin: 0;
		padding: 0;
		list-style: none;

		&__step {
			display: flex;
			min-width: 0;
			flex: 1 1 0;
			flex-direction: column;
			gap: 0;
		}

		&__bar {
			display: block;
			height: 4px;
			overflow: hidden;
			margin-bottom: 10px;
			border-radius: 999px;
			background: var(--color-surface--background--subtle);
		}

		&__fill {
			display: block;
			height: 100%;
			border-radius: 999px;
			background: var(--color-interactive);
		}

		&__title {
			display: flex;
			align-items: center;
			gap: 4px;
			margin-bottom: 3px;
			min-width: 0;
		}

		&__check :global(svg) {
			display: block;
			width: 14px;
			height: 14px;
			color: var(--color-interactive);
		}

		&__dot {
			flex: 0 0 auto;
			width: 7px;
			height: 7px;
			margin-right: 2px;
			border-radius: 999px;
			background: var(--color-interactive);
		}

		&__label {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;

			&--todo {
				color: var(--color-text--secondary);
			}

			&--link {
				display: inline-flex;
				align-items: center;
				gap: 4px;
				text-decoration: none;

				&:hover {
					text-decoration: underline;
				}
				&:focus-visible {
					outline: none;
					border-radius: 4px;
					box-shadow: var(--shadow-focus);
				}
			}
		}

		&__arrow :global(svg) {
			display: block;
			width: 11px;
			height: 11px;
			color: var(--color-icon--secondary);
		}

		&__sub {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;

			&--critical {
				color: var(--color-critical);
			}
		}
	}

	@media (max-width: 767px) {
		.lifecycle {
			flex-wrap: wrap;
			gap: 14px 12px;

			&__step {
				flex: 1 1 40%;
			}
		}
	}
</style>
