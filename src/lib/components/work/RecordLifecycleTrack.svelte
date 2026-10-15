<script lang="ts">
	import type { RecordLifecycleStep } from './types';
	import arrowIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	let { steps }: { steps: RecordLifecycleStep[] } = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<ol class="record-lifecycle" aria-label="Work journey">
	{#each steps as step (step.key)}
		<li
			class={[
				'record-lifecycle__step',
				{
					'record-lifecycle__step--current': step.current,
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
					>{step.label}<span aria-hidden="true">{@html arrowIcon}</span></a
				>
			{:else}
				<span class="record-lifecycle__label"
					>{#if step.current}<span class="record-lifecycle__dot" aria-hidden="true"
						></span>{/if}{step.label}</span
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
		&__step {
			display: flex;
			flex-direction: column;
			min-width: 0;
			gap: 3px;
			color: var(--classic2-muted);
		}
		&__bar {
			display: block;
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
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-label);
			font-weight: 600;
			text-decoration: none;
			overflow-wrap: anywhere;
		}
		&__label span {
			display: inline-flex;
		}
		&__label :global(svg) {
			width: 13px;
			height: 13px;
			flex-shrink: 0;
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
			line-height: 1.5;
			overflow-wrap: anywhere;
		}
		&__dot {
			width: 6px;
			height: 6px;
			border-radius: 50%;
			background: var(--classic2-green);
			flex-shrink: 0;
		}
		&__step--complete .record-lifecycle__bar,
		&__step--current .record-lifecycle__bar {
			background: var(--classic2-green);
		}
		&__step--current .record-lifecycle__label {
			color: var(--classic2-green);
		}
		&__step--linked .record-lifecycle__bar {
			background: var(--classic2-secondary);
		}
	}
	@media (max-width: 767px) {
		:global(:root:has(.app-shell[data-presentation='classic'])) .record-lifecycle {
			gap: 8px;
		}
	}
</style>
