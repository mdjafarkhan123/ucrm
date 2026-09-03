<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import briefcaseOffIcon from '@tabler/icons/outline/briefcase-off.svg?raw';
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
<Dialog {open} title="Final visit completed" size="small" onClose={onKeepOpen}>
	<ul class="final-visit-dialog__list">
		{#if canClose}
			<li>
				<button type="button" class="final-visit-dialog__row" onclick={onFinish} disabled={closing}>
					<span class="final-visit-dialog__icon">{@html briefcaseOffIcon}</span>
					<span>{closing ? 'Finishing…' : 'Finish job'}</span>
				</button>
			</li>
		{/if}
		<li>
			<button type="button" class="final-visit-dialog__row" onclick={onAddReturnVisit}>
				<span class="final-visit-dialog__icon">{@html calendarPlusIcon}</span>
				<span>Add a return visit</span>
			</button>
		</li>
		<li>
			<button type="button" class="final-visit-dialog__row" onclick={onKeepOpen}>
				<span class="final-visit-dialog__icon">{@html flagIcon}</span>
				<span>Keep open — Action required</span>
			</button>
		</li>
	</ul>
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.final-visit-dialog {
		&__list {
			margin: 0;
			padding: 0;
			list-style: none;

			li:not(:last-child) {
				border-bottom: var(--border-base) solid var(--color-border);
			}
		}

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			width: 100%;
			padding: var(--space-small) var(--space-smallest);
			border: 0;
			background: transparent;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			text-align: left;
			cursor: pointer;

			&:hover:not(:disabled) {
				background: var(--color-surface--hover);
			}

			&:disabled {
				color: var(--color-text--subdued);
				cursor: not-allowed;
			}
		}

		&__icon {
			display: flex;
			flex: 0 0 auto;
			width: var(--space-large);
			height: var(--space-large);
			box-sizing: content-box;
			color: var(--color-icon);

			:global(svg) {
				width: 100%;
				height: 100%;
			}
		}
	}
</style>
