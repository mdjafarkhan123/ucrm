<script lang="ts">
	import type { RecordLifecycleStep, StatusTone } from './types';
	import arrowIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	// `tone` is the record's status colour, so the current step agrees with the status pill: a declined
	// quote reads red here, not green.
	let { steps, tone = 'success' }: { steps: RecordLifecycleStep[]; tone?: StatusTone } = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<ol class="record-lifecycle record-lifecycle--{tone}" aria-label="Work journey">
	{#each steps as step, index (step.key)}
		<li
			class={[
				'record-lifecycle__step',
				{
					'record-lifecycle__step--current': step.current,
					'record-lifecycle__step--settled': step.current && steps[index + 1]?.complete,
					'record-lifecycle__step--linked': step.href,
					'record-lifecycle__step--complete': step.complete
				}
			]}
			aria-current={step.current ? 'step' : undefined}
		>
			<span class="record-lifecycle__bar" aria-hidden="true"></span>
			{#if step.href && !step.current}
				<!-- The page supplies a resolved, permission-appropriate record link. -->
				<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
				<a class="record-lifecycle__label" href={step.href}
					>{#if step.complete}<span class="record-lifecycle__tick" aria-hidden="true"
							>{@html checkIcon}</span
						>{/if}{step.label}<span class="record-lifecycle__open" aria-hidden="true"
						>{@html arrowIcon}</span
					></a
				>
			{:else}
				<span class="record-lifecycle__label"
					>{#if step.current}<span class="record-lifecycle__dot" aria-hidden="true"
						></span>{:else if step.complete}<span class="record-lifecycle__tick" aria-hidden="true"
							>{@html checkIcon}</span
						>{/if}{step.label}</span
				>
			{/if}
			<span class="record-lifecycle__detail">{step.detail ?? '—'}</span>
		</li>
	{/each}
</ol>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.record-lifecycle {
		display: none;
	}
	:global(:root:has(.app-shell[data-presentation='classic'])) .record-lifecycle {
		display: grid;
		grid-template-columns: repeat(5, minmax(0, 1fr));
		gap: 14px;
		margin: 0;
		padding: 22px 0 0;
		list-style: none;
		width: 100%;
		--lifecycle-tone: var(--classic2-green);
		&--warning {
			--lifecycle-tone: var(--classic2-amber);
		}
		&--critical {
			--lifecycle-tone: var(--classic2-rose);
		}
		&--informative {
			--lifecycle-tone: var(--classic2-blue);
		}
		&--inactive {
			--lifecycle-tone: var(--classic2-icon-muted);
		}
		&__step {
			display: flex;
			flex-direction: column;
			min-width: 0;
			gap: 3px;
			color: var(--classic2-muted);
		}
		&__bar {
			display: block;
			position: relative;
			overflow: hidden;
			height: 4px;
			border-radius: 999px;
			background: var(--classic2-chip);
			margin-bottom: 7px;
		}
		&__label {
			display: flex;
			align-items: center;
			gap: 4px;
			min-height: 20px;
			color: var(--classic2-muted);
			font-size: var(--classic2-font-label);
			font-weight: 600;
			text-decoration: none;
			overflow-wrap: anywhere;
		}
		&__label span {
			display: inline-flex;
			flex-shrink: 0;
		}
		&__tick :global(svg) {
			width: 13px;
			height: 13px;
			color: var(--classic2-green);
			stroke-width: 2.5;
		}
		&__open :global(svg) {
			width: 12px;
			height: 12px;
			color: var(--classic2-icon-muted);
		}
		&__label:hover {
			text-decoration: underline;
		}
		&__label:focus-visible {
			outline: 2px solid var(--classic2-green);
			outline-offset: 3px;
			border-radius: 3px;
		}
		&__detail {
			font-size: var(--classic2-font-small);
			font-weight: 500;
			line-height: 1.5;
			overflow-wrap: anywhere;
		}
		&__dot {
			width: 7px;
			height: 7px;
			margin-right: 2px;
			border-radius: 50%;
			background: var(--lifecycle-tone);
		}
		&__step--complete .record-lifecycle__bar {
			background: var(--classic2-green);
		}
		&__step--complete .record-lifecycle__label,
		&__step--current .record-lifecycle__label {
			color: var(--classic2-ink);
		}
		&__step--complete .record-lifecycle__detail {
			color: var(--classic2-muted);
		}
		// Where the record is now: the step is under way, not finished, so its bar is only part filled.
		&__step--current .record-lifecycle__bar::after {
			content: '';
			position: absolute;
			inset: 0 45% 0 0;
			border-radius: inherit;
			background: var(--lifecycle-tone);
		}
		// A later step is already done (a paid invoice), so this one is finished too.
		&__step--settled .record-lifecycle__bar::after {
			right: 0;
		}
		&__step--current .record-lifecycle__detail {
			color: var(--lifecycle-tone);
		}
	}
	@media (max-width: 767px) {
		:global(:root:has(.app-shell[data-presentation='classic'])) .record-lifecycle {
			gap: 8px;
		}
	}
</style>
