<script lang="ts">
	import moveIcon from '@tabler/icons/outline/arrows-move-horizontal.svg?raw';

	// The drag line between two side-by-side cards (design `inbox.md`, Layout), following the WAI-ARIA window
	// splitter: drag it, or focus it and use the arrow keys (Home and End jump to the limits); a double-click puts
	// the pane back to its own width. It sets the width of one pane -- the one on the `pane` side of the line.
	let {
		width,
		min,
		max,
		defaultWidth,
		pane = 'before',
		label,
		controls,
		onResize,
		onCommit
	}: {
		width: number;
		min: number;
		max: number;
		defaultWidth: number;
		/** Which side of the line the resized pane is on: dragging toward it makes it smaller. */
		pane?: 'before' | 'after';
		label: string;
		/** The id of the pane this line resizes. */
		controls?: string;
		/** The new width while dragging, on each key press and on reset. */
		onResize: (width: number) => void;
		/** A drag, key press or reset has finished: a good moment to remember the width. */
		onCommit?: (width: number) => void;
	} = $props();

	const STEP = 16;
	let dragging = $state(false);
	let startX = 0;
	let startWidth = 0;

	function clamp(value: number) {
		return Math.round(Math.min(max, Math.max(min, value)));
	}

	function onpointerdown(event: PointerEvent) {
		if (event.button !== 0) return;
		event.preventDefault();
		(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
		dragging = true;
		startX = event.clientX;
		startWidth = width;
	}

	function onpointermove(event: PointerEvent) {
		if (!dragging) return;
		const moved = event.clientX - startX;
		onResize(clamp(startWidth + (pane === 'before' ? moved : -moved)));
	}

	function onpointerup(event: PointerEvent) {
		if (!dragging) return;
		dragging = false;
		(event.currentTarget as HTMLElement).releasePointerCapture(event.pointerId);
		onCommit?.(width);
	}

	function onkeydown(event: KeyboardEvent) {
		const grow = pane === 'before' ? 'ArrowRight' : 'ArrowLeft';
		const shrink = pane === 'before' ? 'ArrowLeft' : 'ArrowRight';
		let next: number | null = null;
		if (event.key === grow) next = width + STEP;
		else if (event.key === shrink) next = width - STEP;
		else if (event.key === 'Home') next = min;
		else if (event.key === 'End') next = max;
		else if (event.key === 'Enter') next = defaultWidth;
		if (next === null) return;
		event.preventDefault();
		const resized = clamp(next);
		onResize(resized);
		onCommit?.(resized);
	}

	function reset() {
		const resized = clamp(defaultWidth);
		onResize(resized);
		onCommit?.(resized);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -- a focusable
     separator is the WAI-ARIA window splitter pattern. -->
<div
	class="pane-resizer"
	class:pane-resizer--dragging={dragging}
	role="separator"
	aria-orientation="vertical"
	aria-label={label}
	aria-controls={controls}
	aria-valuenow={width}
	aria-valuemin={min}
	aria-valuemax={max}
	tabindex="0"
	{onpointerdown}
	{onpointermove}
	{onpointerup}
	onpointercancel={onpointerup}
	ondblclick={reset}
	{onkeydown}
>
	<span class="pane-resizer__line" aria-hidden="true"></span>
	<span class="pane-resizer__grip" aria-hidden="true"><i></i><i></i><i></i></span>
	<span class="pane-resizer__tip" aria-hidden="true">
		{@html moveIcon}
		Drag to resize · double-click to reset
	</span>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// 9 wide, invisible at rest. Hover, focus or a drag shows the green line, its grip and the tip.
	.pane-resizer {
		position: relative;
		z-index: 2;
		width: 9px;
		height: 100%;
		margin-inline: -4.5px;
		cursor: col-resize;
		touch-action: none;
		outline: none;
	}

	.pane-resizer__line {
		position: absolute;
		inset-block: 0;
		left: 3px;
		width: 3px;
		border-radius: var(--radius-circle);
		background: var(--color-interactive);
	}

	.pane-resizer__grip {
		position: absolute;
		top: 50%;
		left: -3px;
		display: flex;
		width: 15px;
		height: 44px;
		box-sizing: border-box;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 3px;
		border: 1.5px solid var(--color-interactive);
		border-radius: var(--radius-circle);
		background: var(--color-surface);
		transform: translateY(-50%);

		i {
			width: 3px;
			height: 3px;
			border-radius: var(--radius-circle);
			background: var(--color-interactive);
		}
	}

	.pane-resizer__tip {
		position: absolute;
		top: calc(50% + 30px);
		left: 50%;
		z-index: var(--elevation-tooltip);
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: var(--space-small) var(--space-slim);
		border-radius: var(--radius-base);
		color: var(--color-text--reverse);
		background: var(--color-surface--reverse);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
		white-space: nowrap;
		transform: translateX(-50%);
		pointer-events: none;

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.pane-resizer__line,
	.pane-resizer__grip,
	.pane-resizer__tip {
		opacity: 0;
		transition: opacity var(--timing-quick);
	}

	.pane-resizer:hover,
	.pane-resizer:focus-visible,
	.pane-resizer--dragging {
		.pane-resizer__line,
		.pane-resizer__grip {
			opacity: 1;
		}
	}

	// The tip explains the line on hover and focus, and gets out of the way while dragging.
	.pane-resizer:hover:not(.pane-resizer--dragging) .pane-resizer__tip,
	.pane-resizer:focus-visible .pane-resizer__tip {
		opacity: 1;
		transition-delay: 300ms;
	}
</style>
