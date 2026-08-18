<script lang="ts" module>
	export type LightboxItem = {
		id: string;
		/** Full-size image, shown in the main view. */
		src: string;
		/** Small copy, shown in the filmstrip along the bottom. */
		thumbSrc: string;
		caption: string;
	};
</script>

<script lang="ts">
	import { Dialog as DialogPrimitive } from 'bits-ui';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';
	import chevronLeftIcon from '@tabler/icons/outline/chevron-left.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';

	// The big view of a photo, opened by clicking one in a grid. Arrows and the arrow keys step through the
	// rest, and the strip along the bottom jumps straight to any of them.
	let {
		open,
		items,
		index = $bindable(0),
		onClose,
		onDownload
	}: {
		open: boolean;
		items: LightboxItem[];
		/** Which photo is showing. Bindable so the opener can say which one was clicked. */
		index?: number;
		onClose: () => void;
		/** Left out when the office may look but not keep a copy. */
		onDownload?: (item: LightboxItem) => void;
	} = $props();

	const current = $derived(items[index]);
	const hasMany = $derived(items.length > 1);

	// Wraps around, so holding an arrow key never dead-ends on the last photo.
	function step(by: number) {
		if (items.length === 0) return;
		index = (index + by + items.length) % items.length;
	}

	function onKeydown(event: KeyboardEvent) {
		if (!open || !hasMany) return;
		if (event.key === 'ArrowLeft') {
			event.preventDefault();
			step(-1);
		} else if (event.key === 'ArrowRight') {
			event.preventDefault();
			step(1);
		}
	}

	// Keeps the strip scrolled to whichever photo is showing, however it was reached — click, arrow button
	// or arrow key.
	let stripEl: HTMLDivElement | undefined = $state();
	$effect(() => {
		// Named so the effect actually re-runs on a step; the lookup below reads the DOM, not state.
		const showing = index;
		if (!open || showing < 0) return;
		const active = stripEl?.querySelector<HTMLElement>('[data-active="true"]');
		active?.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' });
	});

	// The photo either side is almost certainly the next one wanted, so it is fetched while this one is
	// being looked at and the step feels instant.
	const neighbours = $derived(
		hasMany
			? [items[(index + 1) % items.length], items[(index - 1 + items.length) % items.length]]
			: []
	);
</script>

<svelte:window onkeydown={onKeydown} />

<!-- eslint-disable svelte/no-at-html-tags -->
<DialogPrimitive.Root
	{open}
	onOpenChange={(next) => {
		if (!next) onClose();
	}}
>
	<DialogPrimitive.Portal>
		<DialogPrimitive.Overlay class="lightbox__overlay" />
		<DialogPrimitive.Content class="lightbox">
			{#if current}
				<!-- The visible name sits in the bar below; this is what a screen reader announces on open. -->
				<DialogPrimitive.Title class="lightbox__sr-only">
					Photo viewer: {current.caption}
				</DialogPrimitive.Title>

				<header class="lightbox__bar">
					<div class="lightbox__title">
						<span class="lightbox__name">{current.caption}</span>
						{#if hasMany}
							<span class="lightbox__count">{index + 1} of {items.length}</span>
						{/if}
					</div>
					<div class="lightbox__bar-actions">
						{#if onDownload}
							<button
								type="button"
								class="lightbox__icon-button"
								aria-label={`Download ${current.caption}`}
								onclick={() => onDownload(current)}
							>
								{@html downloadIcon}
							</button>
						{/if}
						<DialogPrimitive.Close class="lightbox__icon-button" aria-label="Close photo viewer">
							{@html closeIcon}
						</DialogPrimitive.Close>
					</div>
				</header>

				<div class="lightbox__stage">
					{#if hasMany}
						<button
							type="button"
							class="lightbox__step lightbox__step--previous"
							aria-label="Previous photo"
							onclick={() => step(-1)}
						>
							{@html chevronLeftIcon}
						</button>
					{/if}

					<!-- Keyed so stepping swaps the image instead of leaving the old one up while the next
					     one loads. -->
					{#key current.id}
						<img class="lightbox__image" src={current.src} alt={current.caption} />
					{/key}

					{#if hasMany}
						<button
							type="button"
							class="lightbox__step lightbox__step--next"
							aria-label="Next photo"
							onclick={() => step(1)}
						>
							{@html chevronRightIcon}
						</button>
					{/if}
				</div>

				{#if hasMany}
					<div class="lightbox__strip" bind:this={stripEl}>
						{#each items as item, position (item.id)}
							<button
								type="button"
								class="lightbox__thumb"
								class:lightbox__thumb--active={position === index}
								data-active={position === index}
								aria-label={`Show ${item.caption}`}
								aria-current={position === index}
								onclick={() => (index = position)}
							>
								<img src={item.thumbSrc} alt="" loading="lazy" />
							</button>
						{/each}
					</div>
				{/if}

				<!-- Fetched but never shown, so stepping to the next photo has nothing left to wait for. -->
				<div class="lightbox__preload" aria-hidden="true">
					{#each neighbours as neighbour (neighbour.id)}
						<img src={neighbour.src} alt="" />
					{/each}
				</div>
			{/if}
		</DialogPrimitive.Content>
	</DialogPrimitive.Portal>
</DialogPrimitive.Root>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// A photo viewer wants the page out of the way, so this overlay is far darker than a dialog's and the
	// content sits directly on it rather than inside a card.
	:global(.lightbox__overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: rgba(0, 0, 0, 0.88);
	}

	:global(.lightbox) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		display: flex;
		box-sizing: border-box;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-base);
	}

	:global(.lightbox__sr-only) {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}

	.lightbox {
		&__bar {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
		}

		&__title {
			display: flex;
			min-width: 0;
			flex-direction: column;
		}

		&__name {
			overflow: hidden;
			color: #fff;
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__count {
			color: rgba(255, 255, 255, 0.66);
			font-size: var(--typography--fontSize-small);
		}

		&__bar-actions {
			display: flex;
			flex: 0 0 auto;
			gap: var(--space-small);
		}

		&__stage {
			position: relative;
			display: flex;
			min-height: 0;
			flex: 1 1 auto;
			align-items: center;
			justify-content: center;
		}

		&__image {
			max-width: 100%;
			max-height: 100%;
			object-fit: contain;
		}

		&__step {
			position: absolute;
			top: 50%;
			display: grid;
			width: 44px;
			height: 44px;
			place-items: center;
			border: 0;
			border-radius: var(--radius-circle);
			color: #fff;
			background: rgba(255, 255, 255, 0.14);
			cursor: pointer;
			transform: translateY(-50%);
			transition: background-color var(--timing-quick);

			&:hover {
				background: rgba(255, 255, 255, 0.28);
			}

			&:focus-visible {
				outline: none;
				box-shadow: 0 0 0 3px rgba(255, 255, 255, 0.6);
			}

			&--previous {
				left: 0;
			}
			&--next {
				right: 0;
			}

			:global(svg) {
				display: block;
				width: 24px;
				height: 24px;
			}
		}

		&__strip {
			display: flex;
			flex: 0 0 auto;
			gap: var(--space-small);
			overflow-x: auto;
			padding-bottom: var(--space-smaller);
			scrollbar-width: thin;
		}

		&__thumb {
			width: 72px;
			height: 56px;
			flex: 0 0 auto;
			overflow: hidden;
			padding: 0;
			border: 2px solid transparent;
			border-radius: var(--radius-small);
			background: rgba(255, 255, 255, 0.08);
			cursor: pointer;
			opacity: 0.55;
			transition:
				opacity var(--timing-quick),
				border-color var(--timing-quick);

			&:hover {
				opacity: 1;
			}

			&:focus-visible {
				outline: none;
				border-color: #fff;
				opacity: 1;
			}

			&--active {
				border-color: #fff;
				opacity: 1;
			}

			img {
				display: block;
				width: 100%;
				height: 100%;
				object-fit: cover;
			}
		}

		&__icon-button {
			display: grid;
			width: 36px;
			height: 36px;
			place-items: center;
			border: 0;
			border-radius: var(--radius-circle);
			color: #fff;
			background: rgba(255, 255, 255, 0.14);
			cursor: pointer;
			transition: background-color var(--timing-quick);

			&:hover {
				background: rgba(255, 255, 255, 0.28);
			}

			&:focus-visible {
				outline: none;
				box-shadow: 0 0 0 3px rgba(255, 255, 255, 0.6);
			}

			:global(svg) {
				display: block;
				width: 18px;
				height: 18px;
			}
		}

		&__preload {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			opacity: 0;
			pointer-events: none;
		}
	}

	// The arrows would sit on top of the photo on a narrow screen, so they move onto the backdrop edges.
	@media (max-width: 767px) {
		.lightbox__step {
			width: 36px;
			height: 36px;

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}
	}
</style>
