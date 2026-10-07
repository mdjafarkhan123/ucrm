<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { removeProfilePhoto, uploadProfilePhoto } from '$lib/profile/api';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import zoomOutIcon from '@tabler/icons/outline/zoom-out.svg?raw';
	import zoomInIcon from '@tabler/icons/outline/zoom-in.svg?raw';

	// The signed-in person's own photo: choose a picture, drag and zoom it inside the circle, save. The crop
	// happens here, in the browser, so a 4 MB phone photo goes up as a ~60 KB square; the server still
	// re-encodes whatever arrives. Like the other settings dialogs it writes straight away.
	let {
		open,
		avatarId,
		name,
		avatarUrl,
		endpoint,
		onClose
	}: {
		open: boolean;
		/** Picks the initials' colour, matching this person's avatar everywhere else. */
		avatarId: string;
		name: string | null;
		avatarUrl: string | null;
		/** The signed-in person's own photo address: the contractor app's or the Jafar Panel's. */
		endpoint: string;
		onClose: () => void;
	} = $props();

	const toast = getToastManager();
	const queryClient = useQueryClient();

	/** The circle's on-screen size. */
	const VIEWPORT = 240;
	/** The square sent to the server; the server stores 256px, so this keeps detail for its resize. */
	const OUTPUT = 512;
	const MAX_ZOOM = 3;
	const ACCEPTED = 'image/jpeg,image/png,image/webp';

	let fileInput = $state<HTMLInputElement | null>(null);
	let image = $state<HTMLImageElement | null>(null);
	let imageUrl = $state<string | null>(null);
	let zoom = $state(1);
	let offsetX = $state(0);
	let offsetY = $state(0);
	let busy = $state<'save' | 'remove' | null>(null);
	let error = $state('');

	// At zoom 1 the picture just covers the circle along its shorter side.
	const scale = $derived(
		image ? (VIEWPORT / Math.min(image.naturalWidth, image.naturalHeight)) * zoom : 1
	);
	const shownWidth = $derived(image ? image.naturalWidth * scale : 0);
	const shownHeight = $derived(image ? image.naturalHeight * scale : 0);

	function clampOffsets(x: number, y: number, width: number, height: number) {
		return {
			x: Math.min(0, Math.max(VIEWPORT - width, x)),
			y: Math.min(0, Math.max(VIEWPORT - height, y))
		};
	}

	function reset() {
		if (imageUrl) URL.revokeObjectURL(imageUrl);
		image = null;
		imageUrl = null;
		zoom = 1;
		error = '';
		if (fileInput) fileInput.value = '';
	}

	function close() {
		if (busy) return;
		reset();
		onClose();
	}

	function choose(event: Event) {
		const file = (event.currentTarget as HTMLInputElement).files?.[0];
		if (!file) return;
		if (!ACCEPTED.split(',').includes(file.type)) {
			error = 'Choose a JPG, PNG, or WEBP photo.';
			return;
		}
		reset();
		const url = URL.createObjectURL(file);
		const loaded = new Image();
		loaded.onload = () => {
			imageUrl = url;
			image = loaded;
			const start = VIEWPORT / Math.min(loaded.naturalWidth, loaded.naturalHeight);
			offsetX = (VIEWPORT - loaded.naturalWidth * start) / 2;
			offsetY = (VIEWPORT - loaded.naturalHeight * start) / 2;
		};
		loaded.onerror = () => {
			URL.revokeObjectURL(url);
			error = 'That file could not be opened as a photo.';
		};
		loaded.src = url;
	}

	// Zooming keeps whatever is in the middle of the circle in the middle.
	function setZoom(next: number) {
		if (!image) return;
		const previous = scale;
		const nextScale = (VIEWPORT / Math.min(image.naturalWidth, image.naturalHeight)) * next;
		const centreX = (VIEWPORT / 2 - offsetX) / previous;
		const centreY = (VIEWPORT / 2 - offsetY) / previous;
		const clamped = clampOffsets(
			VIEWPORT / 2 - centreX * nextScale,
			VIEWPORT / 2 - centreY * nextScale,
			image.naturalWidth * nextScale,
			image.naturalHeight * nextScale
		);
		zoom = next;
		offsetX = clamped.x;
		offsetY = clamped.y;
	}

	function moveBy(dx: number, dy: number) {
		const clamped = clampOffsets(offsetX + dx, offsetY + dy, shownWidth, shownHeight);
		offsetX = clamped.x;
		offsetY = clamped.y;
	}

	let drag: { pointerId: number; x: number; y: number } | null = null;

	function pointerDown(event: PointerEvent) {
		if (!image || busy) return;
		(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
		drag = { pointerId: event.pointerId, x: event.clientX, y: event.clientY };
	}

	function pointerMove(event: PointerEvent) {
		if (!drag || drag.pointerId !== event.pointerId) return;
		moveBy(event.clientX - drag.x, event.clientY - drag.y);
		drag = { ...drag, x: event.clientX, y: event.clientY };
	}

	function pointerUp(event: PointerEvent) {
		if (drag?.pointerId === event.pointerId) drag = null;
	}

	function keyMove(event: KeyboardEvent) {
		const step = event.shiftKey ? 20 : 5;
		const moves: Record<string, [number, number]> = {
			ArrowLeft: [step, 0],
			ArrowRight: [-step, 0],
			ArrowUp: [0, step],
			ArrowDown: [0, -step]
		};
		const move = moves[event.key];
		if (!move) return;
		event.preventDefault();
		moveBy(...move);
	}

	function croppedBlob(): Promise<Blob | null> {
		if (!image) return Promise.resolve(null);
		const canvas = document.createElement('canvas');
		canvas.width = OUTPUT;
		canvas.height = OUTPUT;
		const context = canvas.getContext('2d');
		if (!context) return Promise.resolve(null);
		// A transparent PNG would turn black as a JPEG.
		context.fillStyle = '#ffffff';
		context.fillRect(0, 0, OUTPUT, OUTPUT);
		const side = VIEWPORT / scale;
		context.drawImage(image, -offsetX / scale, -offsetY / scale, side, side, 0, 0, OUTPUT, OUTPUT);
		return new Promise((done) => canvas.toBlob(done, 'image/jpeg', 0.9));
	}

	// Every avatar of this person — the top bar, team lists, the pipeline, the schedule — reads the address
	// that just changed, so every cached read and the shell's own load are refreshed. Only the shell is
	// waited for: it carries the person's own photo, and the lists catch up behind the closed dialog.
	async function refreshEverywhere() {
		void queryClient.invalidateQueries();
		await invalidateAll();
	}

	async function save() {
		error = '';
		const blob = await croppedBlob();
		if (!blob) {
			error = 'Your photo could not be prepared. Try a different one.';
			return;
		}
		busy = 'save';
		try {
			await uploadProfilePhoto(endpoint, blob);
			await refreshEverywhere();
			toast.success('Profile photo saved.');
			busy = null;
			close();
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'Your photo could not be saved.';
			busy = null;
		}
	}

	async function remove() {
		error = '';
		busy = 'remove';
		try {
			await removeProfilePhoto(endpoint);
			await refreshEverywhere();
			toast.success('Profile photo removed.');
			busy = null;
			close();
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'Your photo could not be removed.';
			busy = null;
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<!-- Focus starts on the explanation, not on Remove: Enter on opening must never delete a photo. -->
<Dialog
	{open}
	title="Profile photo"
	size="small"
	initialFocusId="profile-photo-hint"
	onClose={close}
>
	<div class="profile-photo">
		<input
			bind:this={fileInput}
			class="profile-photo__file"
			type="file"
			accept={ACCEPTED}
			tabindex="-1"
			aria-hidden="true"
			onchange={choose}
		/>

		{#if image && imageUrl}
			<p class="profile-photo__hint">Drag to move your photo. Use the slider to zoom.</p>
			<!-- A two-way pan has no native control or ARIA role; it is focusable and moves with the arrow keys,
			     and the zoom slider below is a real one. -->
			<!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
			<div
				class="profile-photo__crop"
				style:width="{VIEWPORT}px"
				style:height="{VIEWPORT}px"
				role="application"
				tabindex="0"
				aria-label="Photo position. Use the arrow keys to move it."
				onpointerdown={pointerDown}
				onpointermove={pointerMove}
				onpointerup={pointerUp}
				onpointercancel={pointerUp}
				onkeydown={keyMove}
			>
				<img
					class="profile-photo__image"
					src={imageUrl}
					alt=""
					draggable="false"
					style:width="{shownWidth}px"
					style:height="{shownHeight}px"
					style:transform="translate({offsetX}px, {offsetY}px)"
				/>
				<span class="profile-photo__mask" aria-hidden="true"></span>
			</div>
			<div class="profile-photo__zoom">
				<span class="profile-photo__zoom-icon" aria-hidden="true">{@html zoomOutIcon}</span>
				<input
					type="range"
					aria-label="Zoom"
					min="1"
					max={MAX_ZOOM}
					step="0.01"
					value={zoom}
					disabled={Boolean(busy)}
					oninput={(event) => setZoom(Number(event.currentTarget.value))}
				/>
				<span class="profile-photo__zoom-icon" aria-hidden="true">{@html zoomInIcon}</span>
			</div>
			<Button
				size="small"
				variant="tertiary"
				disabled={Boolean(busy)}
				onclick={() => fileInput?.click()}>Choose a different photo</Button
			>
		{:else}
			<div class="profile-photo__current">
				<Avatar id={avatarId} {name} src={avatarUrl} size="xlarge" />
				<p id="profile-photo-hint" class="profile-photo__hint" tabindex="-1">
					{avatarUrl
						? 'Your teammates see this photo next to your name.'
						: 'Add a photo so your teammates can spot you at a glance.'}
				</p>
			</div>
		{/if}

		{#if error}<p class="profile-photo__error" role="alert">{error}</p>{/if}

		<div class="profile-photo__actions">
			{#if image}
				<span class="profile-photo__spacer"></span>
				<Button variant="secondary" variation="subtle" disabled={Boolean(busy)} onclick={reset}
					>Back</Button
				>
				<Button variant="primary" loading={busy === 'save'} onclick={() => void save()}
					>Save photo</Button
				>
			{:else}
				{#if avatarUrl}
					<Button
						variant="tertiary"
						variation="destructive"
						loading={busy === 'remove'}
						onclick={() => void remove()}>Remove</Button
					>
				{/if}
				<span class="profile-photo__spacer"></span>
				<Button variant="primary" disabled={Boolean(busy)} onclick={() => fileInput?.click()}>
					<span class="profile-photo__button-icon" aria-hidden="true">{@html photoIcon}</span>
					{avatarUrl ? 'Choose new photo' : 'Choose a photo'}
				</Button>
			{/if}
		</div>
	</div>
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.profile-photo {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-base);

		&__file {
			display: none;
		}

		&__current {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-base);
			padding: var(--space-base) 0;
			text-align: center;
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-align: center;

			// Only the dialog puts focus here, as a resting place; it is not a control.
			&:focus,
			&:focus-visible {
				outline: none;
				box-shadow: none;
			}
		}

		&__crop {
			position: relative;
			overflow: hidden;
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			cursor: grab;
			touch-action: none;
			user-select: none;

			&:active {
				cursor: grabbing;
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__image {
			position: absolute;
			top: 0;
			left: 0;
			max-width: none;
			pointer-events: none;
		}

		// Everything outside the circle is dimmed, so the person sees exactly what their avatar will show.
		&__mask {
			position: absolute;
			inset: 0;
			border-radius: var(--radius-circle);
			box-shadow:
				0 0 0 2px rgb(255 255 255 / 0.9),
				0 0 0 999px rgb(0 0 0 / 0.5);
			pointer-events: none;
		}

		&__zoom {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			width: 240px;

			input {
				flex: 1;
				accent-color: var(--color-interactive);
			}

			input:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__zoom-icon,
		&__button-icon {
			display: inline-flex;
			color: var(--color-text--secondary);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__button-icon {
			color: inherit;
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			width: 100%;
			margin-top: var(--space-small);
		}

		&__spacer {
			flex: 1;
		}
	}
</style>
