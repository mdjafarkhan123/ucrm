<script lang="ts">
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { emptySignature, type SignatureValue } from '$lib/signatures/signature';
	import keyboardIcon from '@tabler/icons/outline/keyboard.svg?raw';
	import signatureIcon from '@tabler/icons/outline/signature.svg?raw';
	import eraserIcon from '@tabler/icons/outline/eraser.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// One pad, both sides of the quote: the customer signs it on their own page, and staff hold the same
	// thing out on a tablet at the customer's door. The only difference is the word the drawn signature is
	// recorded under, which is why the caller names it.
	//
	// The drawing leaves here as a PNG data URL. The server checks the bytes before storing them; nothing
	// here is trusted on the other side.

	let {
		value = $bindable(emptySignature()),
		idPrefix,
		record = 'quote',
		disabled = false
	}: {
		value?: SignatureValue;
		idPrefix: string;
		/** The record being signed; the chosen switch icon takes its colour. */
		record?: 'quote' | 'job';
		disabled?: boolean;
	} = $props();

	const recordColor = $derived(`var(--color-${record})`);

	// A phone with a very high pixel ratio would triple the file for no visible gain, so the backing store
	// stops at twice the drawn size.
	const MAX_PIXEL_RATIO = 2;
	const INK = '#111827';

	let canvas = $state<HTMLCanvasElement | null>(null);
	let drawing = $state(false);
	let hasInk = $state(false);

	function context() {
		const ctx = canvas?.getContext('2d');
		if (!ctx) return null;
		ctx.lineWidth = 2.2;
		ctx.lineCap = 'round';
		ctx.lineJoin = 'round';
		ctx.strokeStyle = INK;
		return ctx;
	}

	// The canvas has to be sized in real pixels before anything is drawn on it, and resized when the
	// column it sits in changes width. Resizing clears it, which is why the ink flag resets with it.
	function fitCanvas() {
		if (!canvas) return;
		const ratio = Math.min(window.devicePixelRatio || 1, MAX_PIXEL_RATIO);
		const box = canvas.getBoundingClientRect();
		if (box.width === 0 || box.height === 0) return;

		const width = Math.round(box.width * ratio);
		const height = Math.round(box.height * ratio);
		if (canvas.width === width && canvas.height === height) return;

		canvas.width = width;
		canvas.height = height;
		const ctx = context();
		ctx?.scale(ratio, ratio);
		hasInk = false;
		value = { ...value, image: null };
	}

	$effect(() => {
		if (!canvas) return;
		fitCanvas();
		const observer = new ResizeObserver(() => fitCanvas());
		observer.observe(canvas);
		return () => observer.disconnect();
	});

	function pointAt(event: PointerEvent) {
		const box = canvas!.getBoundingClientRect();
		return { x: event.clientX - box.left, y: event.clientY - box.top };
	}

	function startStroke(event: PointerEvent) {
		if (disabled || !canvas) return;
		const ctx = context();
		if (!ctx) return;
		canvas.setPointerCapture(event.pointerId);
		drawing = true;
		const point = pointAt(event);
		ctx.beginPath();
		ctx.moveTo(point.x, point.y);
		// A single tap is a dot, not nothing: people sign with dots over their i's.
		ctx.lineTo(point.x, point.y);
		ctx.stroke();
		hasInk = true;
	}

	function continueStroke(event: PointerEvent) {
		if (!drawing) return;
		const ctx = context();
		if (!ctx) return;
		const point = pointAt(event);
		ctx.lineTo(point.x, point.y);
		ctx.stroke();
	}

	function endStroke() {
		if (!drawing) return;
		drawing = false;
		if (!canvas) return;
		value = { ...value, image: hasInk ? canvas.toDataURL('image/png') : null };
	}

	function clearDrawing() {
		const ctx = context();
		if (!ctx || !canvas) return;
		ctx.clearRect(0, 0, canvas.width, canvas.height);
		hasInk = false;
		value = { ...value, image: null };
	}

	function chooseMethod(next: string) {
		const method = next === 'drawn' ? 'drawn' : 'typed';
		if (method === 'typed') clearDrawing();
		value = { ...value, method, image: method === 'typed' ? null : value.image };
	}
</script>

<div class="signature-pad" class:signature-pad--disabled={disabled}>
	<div class="signature-pad__top">
		<SegmentedControl
			value={value.method}
			options={[
				{ value: 'typed', label: 'Type it', icon: keyboardIcon, iconColor: recordColor },
				{ value: 'drawn', label: 'Draw it', icon: signatureIcon, iconColor: recordColor }
			]}
			ariaLabel="How to sign"
			{disabled}
			onchange={chooseMethod}
		/>
		{#if value.method === 'drawn'}
			<Button
				type="button"
				variant="secondary"
				size="small"
				disabled={disabled || !hasInk}
				onclick={clearDrawing}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				{@html eraserIcon} Clear
			</Button>
		{/if}
	</div>

	<div class="signature-pad__sheet" class:signature-pad__sheet--signing={drawing}>
		{#if value.method === 'drawn'}
			<canvas
				bind:this={canvas}
				class="signature-pad__canvas"
				class:signature-pad__canvas--disabled={disabled}
				onpointerdown={startStroke}
				onpointermove={continueStroke}
				onpointerup={endStroke}
				onpointerleave={endStroke}
				onpointercancel={endStroke}
			></canvas>
		{:else}
			<p class="signature-pad__typed" aria-hidden="true">{value.name}</p>
		{/if}
		<span class="signature-pad__line" aria-hidden="true">
			<!-- eslint-disable-next-line svelte/no-at-html-tags -->
			<span class="signature-pad__mark">{@html xIcon}</span>
			<span class="signature-pad__rule"></span>
		</span>
		<span class="signature-pad__caption">
			{value.method === 'drawn'
				? 'Sign above with your finger or mouse'
				: 'Your name is your signature'}
		</span>
	</div>

	<Input
		id={`${idPrefix}-signature-name`}
		label="Full name"
		bind:value={value.name}
		{disabled}
		autocomplete="name"
	/>
</div>

<style lang="scss">
	.signature-pad {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
	}

	.signature-pad__top {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
	}

	// Paper, deliberately, in both themes: the ink is a fixed dark colour because the picture outlives the
	// screen it was drawn on — it ends up in a PDF and on a printout.
	.signature-pad__sheet {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		box-sizing: border-box;
		padding: var(--space-base) 20px 14px;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: 12px;
		background: #ffffff;
		transition:
			border-color var(--timing-base) ease-out,
			box-shadow var(--timing-base) ease-out;

		&--signing {
			border-color: var(--color-focus);
			box-shadow: 0 0 0 1px var(--color-focus);
		}
	}

	.signature-pad--disabled .signature-pad__sheet {
		border-color: var(--color-border);
	}

	.signature-pad__canvas {
		display: block;
		width: 100%;
		height: 128px;
		touch-action: none;
		cursor: crosshair;
	}

	.signature-pad__canvas--disabled {
		cursor: not-allowed;
		opacity: 0.5;
	}

	.signature-pad__typed {
		display: flex;
		align-items: flex-end;
		height: 128px;
		margin: 0;
		padding-left: var(--space-small);
		overflow: hidden;
		color: #111827;
		font-size: var(--typography--fontSize-jumbo);
		font-family: 'Segoe Script', 'Brush Script MT', cursive;
		white-space: nowrap;
	}

	.signature-pad--disabled .signature-pad__typed {
		opacity: 0.5;
	}

	.signature-pad__line {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	.signature-pad__mark {
		display: inline-flex;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.signature-pad__rule {
		flex: 1;
		border-top: var(--border-base) solid var(--color-border--interactive);
	}

	.signature-pad__caption {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
