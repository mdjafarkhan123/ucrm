<script lang="ts" module>
	// A signature has exactly one of four states: nothing pending (keep whatever is saved), a freshly
	// picked file waiting to be uploaded, a freshly drawn image, or an explicit removal. The parent reads
	// this to decide what to send on save — never more than one of signature_object_key/signature_image/
	// remove_signature, matching the API's own "at most one" rule.
	export type PendingSignature =
		| { kind: 'none' }
		| { kind: 'upload'; file: File; previewUrl: string }
		| { kind: 'drawn'; dataUrl: string }
		| { kind: 'remove' };
</script>

<script lang="ts">
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// Two ways to give the representative block a signature: pick an image file (same presign/PUT/commit
	// flow the logo already uses, wired up by the caller) or draw one — reusing SignaturePad's canvas
	// mechanics, without its "type it" mode or name field, since this block already collects the name and
	// title as its own plain text fields above.
	let {
		pending = $bindable<PendingSignature>({ kind: 'none' }),
		currentUrl,
		disabled = false,
		idPrefix
	}: {
		pending?: PendingSignature;
		currentUrl: string | null;
		disabled?: boolean;
		idPrefix: string;
	} = $props();

	const ACCEPTED_TYPES = ['image/png', 'image/jpeg', 'image/webp'];
	const MAX_BYTES = 1 * 1024 * 1024;
	const MAX_PIXEL_RATIO = 2;
	const INK = '#111827';

	let mode = $state<'upload' | 'draw'>('upload');
	let fileInput = $state<HTMLInputElement | null>(null);
	let canvas = $state<HTMLCanvasElement | null>(null);
	let drawing = $state(false);
	let hasInk = $state(false);
	let errorMessage = $state('');

	const displayUrl = $derived(
		pending.kind === 'upload'
			? pending.previewUrl
			: pending.kind === 'drawn'
				? pending.dataUrl
				: pending.kind === 'remove'
					? null
					: currentUrl
	);

	function discardPendingUpload() {
		if (pending.kind === 'upload') URL.revokeObjectURL(pending.previewUrl);
	}

	function chooseMode(next: string) {
		const nextMode = next === 'draw' ? 'draw' : 'upload';
		if (nextMode === mode) return;
		discardPendingUpload();
		clearCanvas();
		errorMessage = '';
		pending = { kind: 'none' };
		mode = nextMode;
	}

	function handleFileChosen(event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file) return;
		errorMessage = '';

		if (!ACCEPTED_TYPES.includes(file.type)) {
			errorMessage = 'Upload a PNG, JPG, or WEBP image.';
			return;
		}
		if (file.size > MAX_BYTES) {
			errorMessage = 'Signature images have to be under 1 MB.';
			return;
		}

		discardPendingUpload();
		pending = { kind: 'upload', file, previewUrl: URL.createObjectURL(file) };
	}

	function removeSignature() {
		discardPendingUpload();
		clearCanvas();
		pending = { kind: 'remove' };
	}

	function undoRemove() {
		pending = { kind: 'none' };
	}

	function context() {
		const ctx = canvas?.getContext('2d');
		if (!ctx) return null;
		ctx.lineWidth = 2.2;
		ctx.lineCap = 'round';
		ctx.lineJoin = 'round';
		ctx.strokeStyle = INK;
		return ctx;
	}

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
	}

	$effect(() => {
		if (mode !== 'draw' || !canvas) return;
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
		pending = hasInk ? { kind: 'drawn', dataUrl: canvas.toDataURL('image/png') } : { kind: 'none' };
	}

	function clearCanvas() {
		const ctx = context();
		if (!ctx || !canvas) return;
		ctx.clearRect(0, 0, canvas.width, canvas.height);
		hasInk = false;
		if (pending.kind === 'drawn') pending = { kind: 'none' };
	}
</script>

<div class="rep-signature">
	<SegmentedControl
		value={mode}
		options={[
			{ value: 'upload', label: 'Upload' },
			{ value: 'draw', label: 'Draw' }
		]}
		size="small"
		{disabled}
		onchange={chooseMode}
	/>

	<div
		class="rep-signature__preview"
		class:rep-signature__preview--empty={!displayUrl && mode === 'upload'}
	>
		{#if mode === 'draw'}
			<canvas
				bind:this={canvas}
				class="rep-signature__canvas"
				class:rep-signature__canvas--disabled={disabled}
				onpointerdown={startStroke}
				onpointermove={continueStroke}
				onpointerup={endStroke}
				onpointerleave={endStroke}
				onpointercancel={endStroke}
			></canvas>
		{:else if displayUrl}
			<img src={displayUrl} alt="Representative signature" />
		{:else}
			<span>No signature yet</span>
		{/if}
	</div>

	{#if errorMessage}
		<p class="rep-signature__error" role="alert">{errorMessage}</p>
	{/if}
	{#if pending.kind === 'upload'}
		<p class="rep-signature__note">Not saved yet</p>
	{:else if pending.kind === 'remove'}
		<p class="rep-signature__note">Removed when you save.</p>
	{/if}

	{#if !disabled}
		<div class="rep-signature__actions">
			{#if mode === 'upload'}
				<Button variant="secondary" size="small" onclick={() => fileInput?.click()}>
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span aria-hidden="true">{@html uploadIcon}</span>{displayUrl
						? 'Replace image'
						: 'Upload image'}
				</Button>
				<input
					bind:this={fileInput}
					id={`${idPrefix}-signature-file`}
					type="file"
					accept="image/png,image/jpeg,image/webp"
					class="rep-signature__file-input"
					onchange={handleFileChosen}
				/>
			{:else}
				<Button variant="tertiary" size="small" disabled={!hasInk} onclick={clearCanvas}
					>Clear</Button
				>
			{/if}
			{#if pending.kind === 'remove'}
				<Button variant="tertiary" size="small" onclick={undoRemove}>Undo</Button>
			{:else if currentUrl && pending.kind === 'none'}
				<Button variant="tertiary" variation="destructive" size="small" onclick={removeSignature}>
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span aria-hidden="true">{@html trashIcon}</span>Remove
				</Button>
			{/if}
		</div>
	{/if}
</div>

<style lang="scss">
	.rep-signature {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&__preview {
			display: grid;
			width: 220px;
			height: 110px;
			place-items: center;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: #ffffff;
			overflow: hidden;

			img {
				width: 100%;
				height: 100%;
				object-fit: contain;
			}
			&--empty {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__canvas {
			display: block;
			width: 100%;
			height: 100%;
			touch-action: none;
			cursor: crosshair;

			&--disabled {
				cursor: not-allowed;
			}
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__note {
			margin: 0;
			padding: var(--space-smaller) var(--space-small);
			border-radius: var(--radius-small);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-smaller);
			width: fit-content;
		}

		&__actions {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__file-input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
		}
	}
</style>
