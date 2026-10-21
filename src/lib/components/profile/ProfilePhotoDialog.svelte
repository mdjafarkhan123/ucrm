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
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import topBarIcon from '@tabler/icons/outline/layout-navbar.svg?raw';
	import scheduleIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import inboxIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';

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
	const firstName = $derived(name?.trim().split(/\s+/)[0] || 'You');

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
<!-- The previews show the person as teammates will: the saved photo, or the crop while it moves. -->
{#snippet face(px: number, size: 'small' | 'base')}
	{#if image && imageUrl}
		<span class="profile-photo__face" style:width="{px}px" style:height="{px}px">
			<img
				src={imageUrl}
				alt=""
				draggable="false"
				style:width="{(shownWidth * px) / VIEWPORT}px"
				style:height="{(shownHeight * px) / VIEWPORT}px"
				style:transform="translate({(offsetX * px) / VIEWPORT}px, {(offsetY * px) / VIEWPORT}px)"
			/>
		</span>
	{:else}
		<Avatar id={avatarId} {name} src={avatarUrl} {size} />
	{/if}
{/snippet}

<!-- Focus starts on the explanation, not on Remove: Enter on opening must never delete a photo. -->
<Dialog
	{open}
	title="Profile photo"
	subtitle="Shown next to your name across the app"
	icon={userIcon}
	iconTone="inactive"
	size="medium"
	initialFocusId="profile-photo-hint"
	onClose={close}
>
	<div class="profile-photo" class:profile-photo--busy={Boolean(busy)}>
		<input
			bind:this={fileInput}
			class="profile-photo__file"
			type="file"
			accept={ACCEPTED}
			tabindex="-1"
			aria-hidden="true"
			onchange={choose}
		/>

		<div class="profile-photo__studio">
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
				<div class="profile-photo__zoom profile-photo__fades">
					<span class="profile-photo__zoom-icon" aria-hidden="true">{@html zoomOutIcon}</span>
					<input
						type="range"
						aria-label="Zoom"
						min="1"
						max={MAX_ZOOM}
						step="0.01"
						value={zoom}
						style:--zoom-filled="{((zoom - 1) / (MAX_ZOOM - 1)) * 100}%"
						disabled={Boolean(busy)}
						oninput={(event) => setZoom(Number(event.currentTarget.value))}
					/>
					<span class="profile-photo__zoom-icon" aria-hidden="true">{@html zoomInIcon}</span>
				</div>
				<button
					type="button"
					class="profile-photo__another profile-photo__fades"
					disabled={Boolean(busy)}
					onclick={() => fileInput?.click()}>Choose a different photo</button
				>
			{:else}
				<div class="profile-photo__current">
					<Avatar id={avatarId} {name} src={avatarUrl} size="xlarge" />
				</div>
				<p id="profile-photo-hint" class="profile-photo__hint" tabindex="-1">
					{avatarUrl
						? 'Your teammates see this photo next to your name.'
						: 'Add a photo so your teammates can spot you at a glance.'}
				</p>
			{/if}
		</div>

		<div class="profile-photo__previews" aria-hidden="true">
			<div class="profile-photo__previews-head">
				<h3>How your teammates see you</h3>
				<p>
					{image ? 'Follows your photo as you move and zoom' : 'Your photo across the app'}
				</p>
			</div>

			<div class="profile-photo__preview">
				<span class="profile-photo__preview-label profile-photo__preview-label--top-bar"
					>{@html topBarIcon} Top bar</span
				>
				<div class="profile-photo__top-bar">
					<span class="profile-photo__search">{@html searchIcon} Search</span>
					<span class="profile-photo__account">
						{@render face(32, 'base')}
						<strong>{firstName}</strong>
						{@html chevronDownIcon}
					</span>
				</div>
			</div>

			<div class="profile-photo__preview">
				<span class="profile-photo__preview-label profile-photo__preview-label--schedule"
					>{@html scheduleIcon} Schedule</span
				>
				<div class="profile-photo__visit">
					<span class="profile-photo__lines">
						<strong>Gutter cleaning</strong>
						<span>9:00 – 11:00 AM · Hill Street</span>
					</span>
					{@render face(24, 'small')}
				</div>
			</div>

			<div class="profile-photo__preview">
				<span class="profile-photo__preview-label profile-photo__preview-label--inbox"
					>{@html inboxIcon} Inbox</span
				>
				<div class="profile-photo__conversation">
					<span class="profile-photo__client">SL</span>
					<span class="profile-photo__lines">
						<strong>Sarah Lee</strong>
						<span>Thanks, see you Tuesday!</span>
					</span>
					{@render face(24, 'small')}
				</div>
			</div>
		</div>
	</div>

	{#snippet footer()}
		{#if error}
			<p class="profile-photo__error" role="alert">{@html alertIcon}<span>{error}</span></p>
		{/if}
		<div class="profile-photo__actions">
			{#if image}
				<Button variant="secondary" disabled={Boolean(busy)} onclick={reset}>Back</Button>
				<Button variant="primary" loading={busy === 'save'} onclick={() => void save()}>
					{@html checkIcon} Save photo
				</Button>
			{:else}
				{#if avatarUrl}
					<Button
						variant="secondary"
						variation="destructive"
						loading={busy === 'remove'}
						onclick={() => void remove()}
					>
						{@html trashIcon} Remove
					</Button>
				{/if}
				{#if !error}<span class="profile-photo__spacer"></span>{/if}
				<Button variant="primary" disabled={Boolean(busy)} onclick={() => fileInput?.click()}>
					{@html photoIcon}
					{avatarUrl ? 'Choose new photo' : 'Choose a photo'}
				</Button>
			{/if}
		</div>
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.profile-photo {
		display: flex;
		min-height: 420px;
		// The studio and previews run edge to edge, under the header and over the footer.
		margin: calc(var(--space-medium) * -1);

		&__file {
			display: none;
		}

		&__studio {
			display: flex;
			flex: 0 0 320px;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			gap: 18px;
			box-sizing: border-box;
			padding: var(--space-large);
			background:
				radial-gradient(
					ellipse at 50% 0%,
					rgb(255 255 255 / 0.12),
					rgb(255 255 255 / 0) 70%
				),
				var(--color-photo-studio);
		}

		&__current {
			display: inline-flex;
			border-radius: var(--radius-circle);
			box-shadow:
				0 0 0 4px #ffffff,
				0 10px 28px rgb(0 0 0 / 0.35);

			:global(.avatar) {
				width: 176px;
				height: 176px;
				border: 0;
				font-size: 52px;
			}
		}

		&__hint {
			width: 200px;
			margin: 0;
			color: rgb(255 255 255 / 0.72);
			font-size: 13px;
			line-height: 1.45;
			text-align: center;

			// Only the dialog puts focus here, as a resting place; it is not a control.
			&:focus,
			&:focus-visible {
				outline: none;
				box-shadow: none;
			}
		}

		&__studio > &__hint:first-child {
			width: 240px;
		}

		&__crop {
			position: relative;
			flex: 0 0 auto;
			overflow: hidden;
			border-radius: 12px;
			background: rgb(255 255 255 / 0.06);
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

		&--busy &__fades {
			opacity: 0.45;
		}

		&__zoom {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			width: 240px;

			input {
				flex: 1;
				height: 16px;
				margin: 0;
				background: transparent;
				appearance: none;
				cursor: pointer;

				&:disabled {
					cursor: not-allowed;
				}

				&::-webkit-slider-runnable-track {
					height: 4px;
					border-radius: var(--radius-circle);
					background: linear-gradient(
						to right,
						var(--color-interactive) var(--zoom-filled),
						rgb(255 255 255 / 0.22) var(--zoom-filled)
					);
				}

				&::-moz-range-track {
					height: 4px;
					border-radius: var(--radius-circle);
					background: rgb(255 255 255 / 0.22);
				}

				&::-moz-range-progress {
					height: 4px;
					border-radius: var(--radius-circle);
					background: var(--color-interactive);
				}

				&::-webkit-slider-thumb {
					width: 16px;
					height: 16px;
					margin-top: -6px;
					box-sizing: border-box;
					border: 2px solid var(--color-interactive);
					border-radius: var(--radius-circle);
					background: #ffffff;
					appearance: none;
				}

				&::-moz-range-thumb {
					width: 16px;
					height: 16px;
					box-sizing: border-box;
					border: 2px solid var(--color-interactive);
					border-radius: var(--radius-circle);
					background: #ffffff;
				}

				&:focus-visible {
					outline: none;
				}

				&:focus-visible::-webkit-slider-thumb {
					box-shadow: var(--shadow-focus);
				}

				&:focus-visible::-moz-range-thumb {
					box-shadow: var(--shadow-focus);
				}
			}
		}

		&__zoom-icon {
			display: inline-flex;
			color: rgb(255 255 255 / 0.72);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__another {
			padding: var(--space-smaller) var(--space-small);
			border: 0;
			border-radius: var(--radius-base);
			color: #ffffff;
			background: transparent;
			font: inherit;
			font-size: 13px;
			font-weight: 600;
			cursor: pointer;

			&:hover:not(:disabled) {
				background: rgb(255 255 255 / 0.1);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				cursor: not-allowed;
			}
		}

		&__previews {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: var(--space-slim);
			box-sizing: border-box;
			min-width: 0;
			padding: 20px;
			border-left: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}

		&__previews-head {
			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			p {
				margin: 2px 0 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__preview {
			display: flex;
			flex-direction: column;
			gap: 10px;
			padding: var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: 12px;
			background: var(--color-surface);
		}

		&__preview-label {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			:global(svg) {
				width: 14px;
				height: 14px;
			}

			&--top-bar :global(svg) {
				color: var(--color-inactive);
			}

			&--schedule :global(svg) {
				color: var(--color-time);
			}

			&--inbox :global(svg) {
				color: var(--color-conversation);
			}
		}

		&__top-bar,
		&__visit,
		&__conversation {
			display: flex;
			align-items: center;
			gap: 10px;
		}

		&__search {
			display: inline-flex;
			flex: 1 1 auto;
			align-items: center;
			gap: 6px;
			min-width: 0;
			height: 32px;
			padding: 0 10px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background--subtle);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				width: 14px;
				height: 14px;
				color: var(--color-icon--secondary);
			}
		}

		&__account {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			color: var(--color-heading);
			font-size: 13px;

			:global(svg) {
				width: 14px;
				height: 14px;
				color: var(--color-icon--secondary);
			}
		}

		&__visit {
			padding: var(--space-small) 10px;
			border-left: 3px solid var(--color-job);
			border-radius: var(--radius-base);
			background: var(--color-job--surface);

			.profile-photo__lines strong,
			.profile-photo__lines span {
				color: var(--color-job--onSurface);
			}
		}

		&__lines {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 2px;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: 13px;
				font-weight: 600;
			}

			span {
				overflow: hidden;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				white-space: nowrap;
				text-overflow: ellipsis;
			}
		}

		&__client {
			display: inline-flex;
			flex: 0 0 32px;
			align-items: center;
			justify-content: center;
			height: 32px;
			border-radius: var(--radius-circle);
			color: var(--color-client--onSurface);
			background: var(--color-client--surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__face {
			position: relative;
			display: inline-block;
			flex: 0 0 auto;
			overflow: hidden;
			border-radius: var(--radius-circle);

			img {
				position: absolute;
				top: 0;
				left: 0;
				max-width: none;
				pointer-events: none;
			}
		}

		&__error {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			padding: 7px var(--space-slim);
			border: var(--border-base) solid var(--color-critical--surface-edge, var(--color-critical));
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: 13px;
			font-weight: 500;

			:global(svg) {
				flex: 0 0 auto;
				width: 16px;
				height: 16px;
				color: var(--color-critical);
			}
		}

		&__actions {
			display: flex;
			flex: 1 1 auto;
			align-items: center;
			justify-content: flex-end;
			gap: var(--space-small);
		}

		&__spacer {
			flex: 1;
		}
	}
</style>
