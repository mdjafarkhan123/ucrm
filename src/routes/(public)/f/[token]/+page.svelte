<script lang="ts">
	import { page } from '$app/state';
	import Button from '$lib/components/ui/Button.svelte';
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import { formatFileSize, formatFileType } from '$lib/files/api';
	import fileIcon from '@tabler/icons/outline/file.svg?raw';
	import pdfIcon from '@tabler/icons/outline/file-type-pdf.svg?raw';
	import videoIcon from '@tabler/icons/outline/movie.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import type { SharedFileForCustomer } from './+page.server';

	// The customer's page for files a business chose to share (Part 7D). Everything on it came from the token
	// in the URL, resolved on the server: the business, then each shared File under the name it had when
	// shared. Photos open full size, PDFs open in the browser, every File downloads on its own. A link that has
	// been turned off or has expired shows the business's phone and email instead, and nothing else.
	let { data } = $props();

	const token = $derived(page.params.token ?? '');
	const share = $derived(data.share);
	const business = $derived(data.share?.business ?? data.inactive!.business);
	const contact = $derived(data.inactive?.business ?? null);

	const photos = $derived(share?.files.filter((file) => file.kind === 'image') ?? []);
	const others = $derived(share?.files.filter((file) => file.kind !== 'image') ?? []);

	function fileHref(file: SharedFileForCustomer, variant: 'full' | 'thumb' | 'download' = 'full') {
		const base = `/f/${token}/files/${file.id}`;
		if (variant === 'thumb') return file.has_thumbnail ? `${base}?size=thumb` : base;
		if (variant === 'download') return `${base}?download=1`;
		return base;
	}

	const brandInitials = $derived.by(() => {
		const words = business.name.trim().split(/\s+/).filter(Boolean);
		if (words.length === 0) return '—';
		if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
		return (words[0][0] + words[words.length - 1][0]).toUpperCase();
	});

	const availableUntil = $derived(
		new Date(share?.expires_at ?? 0).toLocaleDateString(undefined, {
			month: 'long',
			day: 'numeric',
			year: 'numeric'
		})
	);

	const lightboxItems: LightboxItem[] = $derived(
		photos.map((file) => ({
			id: file.id,
			src: fileHref(file),
			thumbSrc: fileHref(file, 'thumb'),
			caption: file.name
		}))
	);
	let lightboxOpen = $state(false);
	let lightboxIndex = $state(0);

	function openPhoto(index: number) {
		lightboxIndex = index;
		lightboxOpen = true;
	}

	function downloadItem(item: LightboxItem) {
		const file = photos.find((photo) => photo.id === item.id);
		if (file) window.location.href = fileHref(file, 'download');
	}

	function iconFor(file: SharedFileForCustomer) {
		if (file.mime_type === 'application/pdf') return pdfIcon;
		if (file.kind === 'video') return videoIcon;
		return fileIcon;
	}

	// The view is recorded once the files are actually on this screen, so "opened" means a person saw them:
	// a mail scanner fetching the URL never runs this. Fire and forget.
	let viewedToken = '';

	$effect(() => {
		// A turned-off or expired link has nothing on screen to have been seen.
		if (!share || viewedToken === token) return;
		viewedToken = token;
		void fetch(`/api/public/files/share/${token}/view`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: '{}'
		}).catch(() => {});
	});
</script>

<svelte:head>
	<title>{share ? `Files from ${business.name}` : 'Link no longer active'}</title>
	<meta name="robots" content="noindex, nofollow" />
	<meta name="referrer" content="no-referrer" />
</svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="shared-files">
	<article class="shared-files__doc">
		<div class="shared-files__brandbar"></div>

		<header class="shared-files__head">
			{#if business.has_logo}
				<img class="shared-files__logo" src={`/f/${token}/logo`} alt={business.name} />
			{:else}
				<div class="shared-files__brand">
					<div class="shared-files__brand-mark" aria-hidden="true">{brandInitials}</div>
					<div class="shared-files__brand-name">{business.name}</div>
				</div>
			{/if}
		</header>

		{#if !share}
			<section class="shared-files__hero">
				<h1 class="shared-files__title">This link is no longer active</h1>
				<p class="shared-files__meta">
					{business.name} turned this link off, or it reached the date it was set to stop working.
					{#if contact?.phone || contact?.email}
						Get in touch with them if you still need the files.
					{:else}
						Contact them if you still need the files.
					{/if}
				</p>
			</section>
			{#if contact?.phone || contact?.email}
				<ul class="shared-files__contact" aria-label={`Contact ${business.name}`}>
					{#if contact.phone}
						<li>
							<a
								class="shared-files__contact-link"
								href={`tel:${contact.phone.replace(/[^+\d]/g, '')}`}
							>
								<span class="shared-files__contact-icon" aria-hidden="true">{@html phoneIcon}</span>
								<span class="shared-files__contact-text">
									<span class="shared-files__contact-label">Call</span>
									<span class="shared-files__contact-value">{contact.phone}</span>
								</span>
							</a>
						</li>
					{/if}
					{#if contact.email}
						<li>
							<a class="shared-files__contact-link" href={`mailto:${contact.email}`}>
								<span class="shared-files__contact-icon" aria-hidden="true">{@html mailIcon}</span>
								<span class="shared-files__contact-text">
									<span class="shared-files__contact-label">Email</span>
									<span class="shared-files__contact-value">{contact.email}</span>
								</span>
							</a>
						</li>
					{/if}
				</ul>
			{/if}
		{:else}
			<section class="shared-files__hero">
				<h1 class="shared-files__title">Files shared with you</h1>
				<p class="shared-files__meta">
					{business.name} shared {share.files.length}
					{share.files.length === 1 ? 'file' : 'files'} with you. This link works until {availableUntil}.
				</p>
			</section>

			{#if share.files.length === 0}
				<p class="shared-files__empty">
					These files are no longer available. Contact {business.name} if you still need them.
				</p>
			{/if}

			{#if photos.length > 0}
				<section class="shared-files__section" aria-labelledby="shared-photos-title">
					<h2 id="shared-photos-title" class="shared-files__section-title">Photos</h2>
					<ul class="shared-files__photos">
						{#each photos as file, index (file.id)}
							<li class="shared-files__photo">
								<button
									type="button"
									class="shared-files__photo-button"
									onclick={() => openPhoto(index)}
									aria-label={`Open ${file.name} full size`}
								>
									<img src={fileHref(file, 'thumb')} alt="" loading="lazy" />
								</button>
								<div class="shared-files__photo-foot">
									<span class="shared-files__name" title={file.name}>{file.name}</span>
									<button
										type="button"
										class="shared-files__icon-link"
										onclick={() => (window.location.href = fileHref(file, 'download'))}
										aria-label={`Download ${file.name}`}
										title="Download"
									>
										<span class="shared-files__icon" aria-hidden="true">{@html downloadIcon}</span>
									</button>
								</div>
							</li>
						{/each}
					</ul>
				</section>
			{/if}

			{#if others.length > 0}
				<section class="shared-files__section" aria-labelledby="shared-documents-title">
					<h2 id="shared-documents-title" class="shared-files__section-title">Documents</h2>
					<ul class="shared-files__list">
						{#each others as file (file.id)}
							<li class="shared-files__row">
								<span class="shared-files__row-icon" aria-hidden="true">{@html iconFor(file)}</span>
								<div class="shared-files__row-text">
									<span class="shared-files__name" title={file.name}>{file.name}</span>
									<span class="shared-files__row-meta">
										{formatFileType(file.mime_type, file.name)} · {formatFileSize(file.size_bytes)}
									</span>
								</div>
								<div class="shared-files__row-actions">
									{#if file.mime_type === 'application/pdf' || file.kind === 'video'}
										<Button variant="secondary" size="small" href={fileHref(file)} target="_blank">
											Open
										</Button>
									{/if}
									<Button variant="secondary" size="small" href={fileHref(file, 'download')}>
										Download
									</Button>
								</div>
							</li>
						{/each}
					</ul>
				</section>
			{/if}
		{/if}
	</article>
</div>

<Lightbox
	open={lightboxOpen}
	items={lightboxItems}
	bind:index={lightboxIndex}
	onClose={() => (lightboxOpen = false)}
	onDownload={downloadItem}
/>

<style lang="scss">
	.shared-files {
		min-height: 100vh;
		padding: 0 var(--space-base) var(--space-largest);
		background: var(--color-surface--background);
		color: var(--color-text);
		font-family: var(--typography--fontFamily-normal);
	}

	.shared-files__doc {
		max-width: 820px;
		margin: var(--space-large) auto var(--space-extravagant);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-high);
		overflow: hidden;
	}

	.shared-files__brandbar {
		height: 5px;
		background: linear-gradient(90deg, var(--color-job) 0%, var(--color-brand) 100%);
	}

	.shared-files__head {
		display: flex;
		align-items: center;
		padding: var(--space-larger) var(--space-largest) var(--space-base);
	}

	.shared-files__logo {
		display: block;
		max-width: 220px;
		max-height: 64px;
		object-fit: contain;
	}

	.shared-files__brand {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	.shared-files__brand-mark {
		display: grid;
		place-items: center;
		width: 46px;
		height: 46px;
		border-radius: var(--radius-base);
		background: var(--color-surface--reverse);
		color: var(--color-text--reverse);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-larger);
		font-weight: 800;
		letter-spacing: 0.02em;
	}

	.shared-files__brand-name {
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-larger);
		font-weight: 700;
		line-height: var(--typography--lineHeight-minuscule);
		color: var(--color-heading);
	}

	.shared-files__hero {
		padding: var(--space-smaller) var(--space-largest) var(--space-large);
	}

	.shared-files__title {
		margin: 0;
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-largest);
		font-weight: 600;
		line-height: var(--typography--lineHeight-base);
		color: var(--color-heading);
	}

	.shared-files__meta {
		margin: var(--space-small) 0 0;
		color: var(--color-text--secondary);
	}

	.shared-files__empty {
		margin: 0;
		padding: 0 var(--space-largest) var(--space-largest);
		color: var(--color-text--secondary);
	}

	.shared-files__contact {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
		gap: var(--space-base);
		margin: 0;
		padding: 0 var(--space-largest) var(--space-largest);
		list-style: none;
	}

	.shared-files__contact-link {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-base);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
		color: inherit;
		text-decoration: none;
		transition:
			border-color 150ms ease,
			background 150ms ease;

		&:hover {
			border-color: var(--color-border--interactive);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: 2px solid var(--color-focus);
			outline-offset: 1px;
		}
	}

	.shared-files__contact-icon {
		display: grid;
		flex: none;
		place-items: center;
		width: 40px;
		height: 40px;
		border-radius: var(--radius-circle);
		background: var(--color-surface--background);
		color: var(--color-interactive);

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.shared-files__contact-text {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}

	.shared-files__contact-label {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.shared-files__contact-value {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-weight: 600;
		color: var(--color-heading);
	}

	.shared-files__section {
		padding: var(--space-large) var(--space-largest);
		border-top: 1px solid var(--color-border);
	}

	.shared-files__section-title {
		margin: 0 0 var(--space-base);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--color-text--secondary);
	}

	.shared-files__photos {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.shared-files__photo {
		display: flex;
		flex-direction: column;
		min-width: 0;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
		overflow: hidden;
		background: var(--color-surface);
	}

	.shared-files__photo-button {
		display: block;
		aspect-ratio: 4 / 3;
		padding: 0;
		border: 0;
		background: var(--color-surface--background);
		cursor: zoom-in;

		img {
			display: block;
			width: 100%;
			height: 100%;
			object-fit: cover;
			transition: opacity 150ms ease;
		}

		&:hover img {
			opacity: 0.88;
		}

		&:focus-visible {
			outline: 2px solid var(--color-focus);
			outline-offset: -2px;
		}
	}

	.shared-files__photo-foot {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small) var(--space-small) var(--space-small) var(--space-base);
	}

	.shared-files__name {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-weight: 500;
		color: var(--color-heading);
	}

	.shared-files__icon-link {
		display: grid;
		padding: 0;
		border: 0;
		background: transparent;
		cursor: pointer;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: var(--radius-small);
		color: var(--color-text--secondary);

		&:hover {
			background: var(--color-surface--hover);
			color: var(--color-heading);
		}

		&:focus-visible {
			outline: 2px solid var(--color-focus);
			outline-offset: 1px;
		}
	}

	.shared-files__icon,
	.shared-files__row-icon {
		display: inline-flex;

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.shared-files__list {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.shared-files__row {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-small) var(--space-base);

		& + & {
			border-top: 1px solid var(--color-border);
		}
	}

	.shared-files__row-icon {
		display: grid;
		flex: none;
		place-items: center;
		width: 36px;
		height: 36px;
		border-radius: var(--radius-small);
		background: var(--color-surface--background);
		color: var(--color-text--secondary);
	}

	.shared-files__row-text {
		display: flex;
		flex: 1;
		flex-direction: column;
		min-width: 0;
	}

	.shared-files__row-meta {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.shared-files__row-actions {
		display: flex;
		flex: none;
		gap: var(--space-small);
	}

	@media (max-width: 560px) {
		.shared-files {
			padding: 0;
		}

		.shared-files__doc {
			margin: 0;
			border: 0;
			border-radius: 0;
			box-shadow: none;
		}

		.shared-files__head,
		.shared-files__hero,
		.shared-files__section {
			padding-inline: var(--space-base);
		}

		.shared-files__empty,
		.shared-files__contact {
			padding-inline: var(--space-base);
		}

		.shared-files__photos {
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-small);
		}

		.shared-files__row {
			flex-wrap: wrap;
		}

		.shared-files__row-actions {
			width: 100%;
			justify-content: flex-end;
		}
	}
</style>
