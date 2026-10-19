<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import briefcaseOffIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import chevronIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import calendarPlusIcon from '@tabler/icons/outline/calendar-plus.svg?raw';
	import flagIcon from '@tabler/icons/outline/flag.svg?raw';

	// Jobber's "Final visit completed" dialog (Design/Jobber Jobs, 2026-08-31, screenshot 35), renamed to the
	// contract's approved plain-English wording: Finish job / Add a return visit / Keep open. Fires once, right
	// after a completion actually emptied a one-off job's incomplete visits — never on a replay.
	let {
		open,
		canClose,
		closing,
		onFinish,
		onAddReturnVisit,
		onKeepOpen
	}: {
		open: boolean;
		// Hides "Finish job" for a reader who cannot close a job; they still choose between the other two.
		canClose: boolean;
		closing: boolean;
		onFinish: () => void;
		onAddReturnVisit: () => void;
		onKeepOpen: () => void;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title="Final visit completed"
	size="small"
	icon={checkIcon}
	iconTone="success"
	onClose={() => {
		if (!closing) onKeepOpen();
	}}
>
	<ul class="final-visit-dialog__list">
		{#if canClose}
			<li>
				<button
					type="button"
					class="final-visit-dialog__row"
					onclick={onFinish}
					disabled={closing}
					aria-busy={closing}
				>
					<IconTile icon={briefcaseOffIcon} tone="success" size={32} />
					<span>{closing ? 'Finishing…' : 'Finish job'}</span>
					<span
						class="final-visit-dialog__end"
						class:final-visit-dialog__end--busy={closing}
						aria-hidden="true"
						>{#if !closing}{@html chevronIcon}{/if}</span
					>
				</button>
			</li>
		{/if}
		<li>
			<button
				type="button"
				class="final-visit-dialog__row"
				onclick={onAddReturnVisit}
				disabled={closing}
			>
				<IconTile icon={calendarPlusIcon} tone="job" size={32} />
				<span>Add a return visit</span><span class="final-visit-dialog__end" aria-hidden="true"
					>{@html chevronIcon}</span
				>
			</button>
		</li>
		<li>
			<button type="button" class="final-visit-dialog__row" onclick={onKeepOpen} disabled={closing}>
				<IconTile icon={flagIcon} tone="warning" size={32} />
				<span>Keep open</span><StatusBadge status="warning" size="small"
					>Action required</StatusBadge
				><span class="final-visit-dialog__end" aria-hidden="true">{@html chevronIcon}</span>
			</button>
		</li>
	</ul>
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.final-visit-dialog__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.final-visit-dialog__row {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		width: 100%;
		padding: var(--space-slim);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-tile-large);
		background: var(--color-surface);
		color: var(--color-heading);
		font-family: inherit;
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		line-height: 1.3;
		text-align: left;
		cursor: pointer;
		&:hover:not(:disabled) {
			background: var(--color-surface--hover);
			border-color: var(--color-border--interactive);
		}
		&:active:not(:disabled) {
			background: var(--color-surface--active);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&:disabled {
			opacity: 0.6;
			cursor: wait;
		}
	}
	.final-visit-dialog__end {
		display: inline-flex;
		margin-left: auto;
		flex-shrink: 0;
		width: 16px;
		height: 16px;
		color: var(--color-icon--secondary);
		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
	.final-visit-dialog__end--busy {
		box-sizing: border-box;
		border: 2px solid var(--color-border);
		border-top-color: var(--color-success);
		border-radius: var(--radius-circle);
		animation: final-visit-spin 0.8s linear infinite;
	}
	@keyframes final-visit-spin {
		to {
			transform: rotate(360deg);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.final-visit-dialog__end--busy {
			animation: none;
		}
	}
</style>
