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
	import clipboardTextIcon from '@tabler/icons/outline/clipboard-text.svg?raw';
	import fileDescriptionIcon from '@tabler/icons/outline/file-description.svg?raw';
	import toolsIcon from '@tabler/icons/outline/tools.svg?raw';
	import fileDollarIcon from '@tabler/icons/outline/file-dollar.svg?raw';
	import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';

	// A work record's place on the line from Request to Paid: one bar per step, filled for what is done,
	// part-filled for where the record is now, and a line of words under each. It only reports; the page
	// says which step is which and what to write under it.

	let {
		steps,
		label = 'Progress',
		look = 'bars'
	}: {
		steps: TrackStep[];
		label?: string;
		/** `steps` is the new concept's strip: a coloured tile per step joined by a line. */
		look?: 'bars' | 'steps';
	} = $props();

	// The concept strip tells the five steps apart by colour: each takes its record's colour once reached.
	const stepKinds: Record<string, { kind: string; icon: string }> = {
		Request: { kind: 'request', icon: clipboardTextIcon },
		Quote: { kind: 'quote', icon: fileDescriptionIcon },
		Job: { kind: 'job', icon: toolsIcon },
		Invoice: { kind: 'invoice', icon: fileDollarIcon },
		Paid: { kind: 'invoice', icon: creditCardIcon }
	};
</script>

<!-- eslint-disable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
{#if look === 'steps'}
	<ol class="track" aria-label={label}>
		{#each steps as step, index (step.label)}
			{@const known = stepKinds[step.label]}
			{#if index > 0}
				<li
					class="track__line"
					class:track__line--reached={steps[index - 1].state === 'done'}
					aria-hidden="true"
				></li>
			{/if}
			<li class="track__step" aria-current={step.state === 'current' ? 'step' : undefined}>
				<span
					class="track__tile"
					class:track__tile--reached={step.state !== 'todo'}
					style:--step-tone={known ? `var(--color-${known.kind})` : undefined}
					style:--step-surface={known ? `var(--color-${known.kind}--surface)` : undefined}
					aria-hidden="true"
				>
					{#if step.state === 'done'}{@html checkIcon}{:else if known}{@html known.icon}{/if}
				</span>
				<span class="track__text">
					{#if step.href}
						<a class="track__label" href={step.href}>{step.label}</a>
					{:else}
						<span class={['track__label', step.state === 'todo' && 'track__label--todo']}
							>{step.label}</span
						>
					{/if}
					<span class={['track__sub', step.tone === 'critical' && 'track__sub--critical']}>
						{step.sub}
					</span>
				</span>
			</li>
		{/each}
	</ol>
{:else}
<div class="lifecycle-frame">
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
</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->

<style lang="scss">
	// Concept strip: tile, label and one line of words per step, with a rule joining one step to the next.
	.track {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		margin: 0;
		padding: 0;
		list-style: none;

		&__step {
			display: flex;
			min-width: 0;
			flex: 0 0 auto;
			align-items: center;
			gap: var(--space-small);
		}

		&__tile {
			display: inline-grid;
			flex: 0 0 auto;
			width: 32px;
			height: 32px;
			place-items: center;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: var(--color-surface);

			&--reached {
				border-color: transparent;
				color: var(--step-tone);
				background: var(--step-surface);
			}

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__text {
			display: flex;
			min-width: 0;
			flex-direction: column;
		}

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-decoration: none;
			white-space: nowrap;

			&--todo {
				color: var(--color-text--secondary);
			}

			&:is(a):hover {
				text-decoration: underline;
			}
		}

		&__sub {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-overline);
			white-space: nowrap;

			&--critical {
				color: var(--color-critical);
			}
		}

		&__line {
			min-width: 16px;
			height: 2px;
			flex: 1 1 0;
			border-radius: 1px;
			background: var(--color-border);

			&--reached {
				background: var(--color-icon--secondary);
			}
		}
	}

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

	// Five steps side by side need about 560px. Narrower than that (a half-width card on a small laptop) they
	// fall into rows of three, so a step's name is never cut short.
	.lifecycle-frame {
		container-type: inline-size;
	}
	@container (max-width: 560px) {
		.lifecycle {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: 14px 12px;
		}
	}
</style>
