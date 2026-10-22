<script lang="ts">
	import { onDestroy, untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import StickyActionBar from '$lib/components/layout/StickyActionBar.svelte';
	import BrandPreview from '$lib/components/settings/branding/BrandPreview.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchSettingsBusiness,
		settingsBusinessKey,
		settingsHomeSummaryKey,
		saveBranding,
		isSaveConflict,
		uploadOrganizationLogo,
		removeOrganizationLogo,
		type SettingsBusiness
	} from '$lib/settings/api';
	import {
		BRAND_QUICK_PICKS,
		DEFAULT_BRAND_COLOUR,
		normaliseColourCode,
		readsClearlyWithWhite
	} from '$lib/settings/brand-colour';
	import paletteIcon from '@tabler/icons/outline/palette.svg?raw';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import photoPlusIcon from '@tabler/icons/outline/photo-plus.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import resetIcon from '@tabler/icons/outline/rotate.svg?raw';
	import undoIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';
	import pickerIcon from '@tabler/icons/outline/color-picker.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import checkCircleIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import pencilLineIcon from '@tabler/icons/outline/pencil.svg?raw';
	import compareIcon from '@tabler/icons/outline/git-compare.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// A saved logo now goes through the shared File Manager worker, so it lands as "still being checked"
	// rather than updating instantly. The page waits for it the same way RecordFilesCard.svelte waits for
	// any other upload: poll until the branding revision moves past what it was before Save, bounded so a
	// stalled check does not poll forever.
	let waitingForLogo = $state(false);
	let polling = $state(false);
	let pollTimer: ReturnType<typeof setTimeout> | undefined;
	let revisionBeforeSave = $state<number | null>(null);

	const query = createQuery(() => ({
		queryKey: settingsBusinessKey,
		queryFn: fetchSettingsBusiness,
		refetchInterval: polling ? 10_000 : false
	}));

	$effect(() => {
		if (!waitingForLogo || revisionBeforeSave === null) return;
		const business = query.data;
		if (!business || business.branding.revision <= revisionBeforeSave) return;
		logoUrl = business.branding.logo_url;
		waitingForLogo = false;
		polling = false;
		clearTimeout(pollTimer);
		revisionBeforeSave = null;
	});

	// Mirrors the server's LOGO_MIME_TYPES/LOGO_MAX_BYTES ($lib/server/validation/settings.schema) so a
	// picked file gets an immediate answer instead of waiting for Save to hit the server. The server stays
	// the real gate — this is early feedback only.
	const LOGO_ACCEPTED_TYPES = ['image/png', 'image/jpeg', 'image/webp'];
	const LOGO_MAX_BYTES = 2 * 1024 * 1024;

	let color = $state<string | null>(null);
	let savedColor = $state<string | null>(null);
	// What the colour code box shows while it is being typed; `color` only follows a complete code.
	let colourText = $state('');
	let logoUrl = $state<string | null>(null);
	let saving = $state(false);
	let checkingTheirs = $state(false);
	let errorMessage = $state('');
	let conflict = $state<{ editor_name: string | null; edited_at: string | null } | null>(null);
	let fileInput = $state<HTMLInputElement | null>(null);

	// What is waiting to be saved, the same house rule as `collaboration/AttachmentsCard.svelte`: picking
	// or removing a logo only stages the change, and this page's own Save/Cancel bar commits or discards it.
	let pendingLogoFile = $state<File | null>(null);
	let pendingLogoPreviewUrl = $state('');
	let pendingLogoRemove = $state(false);

	const displayLogoUrl = $derived(
		pendingLogoFile ? pendingLogoPreviewUrl : pendingLogoRemove ? null : logoUrl
	);

	$effect(() => {
		const business = query.data;
		if (!business) return;
		untrack(() => {
			if (color !== null) return;
			setColour(business.branding.brand_color ?? DEFAULT_BRAND_COLOUR);
			savedColor = color;
			logoUrl = business.branding.logo_url;
		});
	});

	const colourChanged = $derived(color !== null && savedColor !== null && color !== savedColor);
	const dirty = $derived(colourChanged || pendingLogoFile !== null || pendingLogoRemove);
	const codeInvalid = $derived(normaliseColourCode(colourText) === null);
	const colourReadable = $derived(color !== null && readsClearlyWithWhite(color));

	// The save bar's second line says what changed, so nobody saves a change they did not mean to.
	const changes = $derived(
		[
			pendingLogoFile ? 'New logo' : pendingLogoRemove ? 'Logo removed' : '',
			colourChanged && color ? `colour ${color.toUpperCase()}` : ''
		].filter(Boolean)
	);

	beforeNavigate((navigation) => {
		if (!dirty) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});
	$effect(() => {
		function handler(event: BeforeUnloadEvent) {
			if (!dirty) return;
			event.preventDefault();
		}
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	function setColour(next: string) {
		color = next;
		colourText = next.toUpperCase();
	}

	function typeColour(event: Event) {
		colourText = (event.currentTarget as HTMLInputElement).value;
		const code = normaliseColourCode(colourText);
		if (code) color = code;
	}

	function leaveColourBox() {
		// A half-typed code goes back to the colour the preview is showing.
		if (color) colourText = color.toUpperCase();
	}

	function discardPendingLogo() {
		if (pendingLogoPreviewUrl) URL.revokeObjectURL(pendingLogoPreviewUrl);
		pendingLogoFile = null;
		pendingLogoPreviewUrl = '';
	}

	onDestroy(() => {
		discardPendingLogo();
		clearTimeout(pollTimer);
	});

	function cancel() {
		if (savedColor) setColour(savedColor);
		conflict = null;
		errorMessage = '';
		discardPendingLogo();
		pendingLogoRemove = false;
	}

	// "See their version": drop what this person had and show what the other person saved.
	async function seeTheirs() {
		checkingTheirs = true;
		const fresh = await queryClient
			.fetchQuery({ queryKey: settingsBusinessKey, queryFn: fetchSettingsBusiness, staleTime: 0 })
			.catch(() => null);
		checkingTheirs = false;
		if (!fresh) {
			errorMessage = 'Their version could not be loaded. Try again.';
			return;
		}
		const theirs = fresh.branding.brand_color ?? DEFAULT_BRAND_COLOUR;
		setColour(theirs);
		savedColor = theirs;
		logoUrl = fresh.branding.logo_url;
		cancel();
	}

	function resetToDefault() {
		setColour(DEFAULT_BRAND_COLOUR);
	}

	function handleFileChosen(event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file) return;
		errorMessage = '';

		if (!LOGO_ACCEPTED_TYPES.includes(file.type)) {
			errorMessage = 'Upload a PNG, JPG, or WEBP image.';
			return;
		}
		if (file.size > LOGO_MAX_BYTES) {
			errorMessage = 'Logos have to be under 2 MB.';
			return;
		}

		discardPendingLogo();
		pendingLogoFile = file;
		pendingLogoPreviewUrl = URL.createObjectURL(file);
		pendingLogoRemove = false;
	}

	function removeLogo() {
		if (pendingLogoFile) {
			discardPendingLogo();
			return;
		}
		pendingLogoRemove = true;
	}

	function undoRemoveLogo() {
		pendingLogoRemove = false;
	}

	async function save() {
		if (!query.data || color === null) return;
		saving = true;
		errorMessage = '';
		conflict = null;
		let currentRevision = query.data.branding.revision;

		if (color !== savedColor) {
			const result = await saveBranding({
				expected_revision: query.data.branding.revision,
				brand_color: color
			}).catch((error: Error) => {
				errorMessage = error.message;
				return null;
			});
			if (!result) {
				saving = false;
				return;
			}
			if (isSaveConflict(result)) {
				conflict = { editor_name: result.editor_name, edited_at: result.edited_at };
				saving = false;
				return;
			}
			savedColor = color;
			currentRevision = result.branding_revision;
			queryClient.setQueryData(settingsBusinessKey, (current: SettingsBusiness | undefined) =>
				current
					? { ...current, branding: { ...current.branding, revision: result.branding_revision } }
					: current
			);
		}

		if (pendingLogoFile) {
			const organizationId = page.data.organization?.id;
			if (!organizationId) {
				errorMessage = 'The business could not be found.';
				saving = false;
				return;
			}
			try {
				await uploadOrganizationLogo(pendingLogoFile, organizationId);
				discardPendingLogo();
				revisionBeforeSave = currentRevision;
				waitingForLogo = true;
				polling = true;
				clearTimeout(pollTimer);
				pollTimer = setTimeout(() => {
					polling = false;
					waitingForLogo = false;
				}, 120_000);
			} catch (error) {
				errorMessage = error instanceof Error ? error.message : 'That logo could not be uploaded.';
				saving = false;
				return;
			}
		} else if (pendingLogoRemove) {
			try {
				const result = await removeOrganizationLogo();
				logoUrl = result.logo_url;
				pendingLogoRemove = false;
				queryClient.setQueryData(settingsBusinessKey, (current: SettingsBusiness | undefined) =>
					current
						? { ...current, branding: { ...current.branding, revision: result.branding_revision } }
						: current
				);
			} catch (error) {
				errorMessage = error instanceof Error ? error.message : 'That logo could not be removed.';
				saving = false;
				return;
			}
		}

		saving = false;
		toast.success('Branding saved.');
		await queryClient.invalidateQueries({ queryKey: settingsBusinessKey });
		void queryClient.invalidateQueries({ queryKey: settingsHomeSummaryKey });
	}

	function whenText(at: string | null): string {
		if (!at) return '';
		return new Intl.DateTimeFormat('en', {
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		}).format(new Date(at));
	}

	const lastChanged = $derived.by(() => {
		const editor = query.data?.branding.last_editor;
		if (!editor) return '';
		const at = editor.at
			? new Intl.DateTimeFormat('en', { month: 'short', day: 'numeric' }).format(
					new Date(editor.at)
				)
			: '';
		return `Last changed by ${editor.name ?? 'a teammate'}${at ? ` · ${at}` : ''}`;
	});
</script>

<svelte:head><title>Branding · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
	{#if query.isPending || color === null}
		{#if query.isError}
			<ErrorState description="Branding could not be loaded." retry={() => query.refetch()} />
		{:else}
			<LoadingSkeleton variant="card" rows={4} />
		{/if}
	{:else}
		{@const data = query.data!}
		{@const canEdit = data.permissions.edit}
		{@const editor = data.branding.last_editor}
		{@const colourNow = color}
		{@const place = [data.profile.trade, data.profile.city].filter(Boolean).join(' · ') || null}
		<div class="branding">
			<div class="branding__head">
				<Breadcrumbs
					items={[
						{ label: 'Settings', href: resolve('/(app)/settings') },
						{ label: 'Branding', icon: paletteIcon }
					]}
				/>
				<PageHeader
					icon={paletteIcon}
					tone="inactive"
					title="Branding"
					description="Your logo and brand colour. Customers see them on quotes, shared files and your website chat."
				>
					{#snippet actions()}
						{#if lastChanged}
							<p class="branding__changed">
								<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
								<span aria-hidden="true">{@html historyIcon}</span>{lastChanged}
							</p>
						{/if}
					{/snippet}
				</PageHeader>
			</div>

			{#if !canEdit}
				<Banner type="notice" icon={lockIcon}>
					{`Only owners and administrators can change this.${
						editor ? ` Last changed by ${editor.name ?? 'a teammate'}.` : ''
					}`}
				</Banner>
			{/if}
			{#if conflict}
				<Banner type="error" icon={usersIcon}>
					{conflict.editor_name ?? 'Someone else'} saved Branding{conflict.edited_at
						? ` ${whenText(conflict.edited_at)}`
						: ''}. Your changes were not saved. See their version first.
				</Banner>
			{:else if errorMessage}
				<Banner type="error">{errorMessage}</Banner>
			{/if}

			<div class="branding__columns">
				<div class="branding__controls">
					<Card
						heading="Logo"
						hint="Shown on quotes, shared files and in your sidebar"
						icon={photoIcon}
						tone="inactive"
					>
						<div
							class="branding__stage"
							class:branding__stage--empty={!displayLogoUrl && !pendingLogoRemove}
						>
							{#if displayLogoUrl || pendingLogoRemove}
								<div class="branding__paper" class:branding__paper--removed={pendingLogoRemove}>
									{#if displayLogoUrl}
										<img src={displayLogoUrl} alt="Business logo" />
									{:else if logoUrl}
										<img src={logoUrl} alt="Business logo, removed when you save" />
									{/if}
								</div>
								{#if pendingLogoFile}
									<span class="branding__state"
										><StatusBadge status="warning">Not saved yet</StatusBadge></span
									>
								{:else if pendingLogoRemove}
									<span class="branding__state">
										<StatusBadge status="critical">Removed on Save</StatusBadge>
										{#if canEdit}
											<Button variant="secondary" size="small" onclick={undoRemoveLogo}>
												<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
												<span aria-hidden="true">{@html undoIcon}</span>Undo
											</Button>
										{/if}
									</span>
								{:else if waitingForLogo}
									<span class="branding__state">
										<StatusBadge status="informative">Being checked</StatusBadge>
										<span class="branding__state-note"
											><span class="branding__spinner" aria-hidden="true"></span>It appears here
											when the safety check finishes.</span
										>
									</span>
								{/if}
							{:else}
								<IconTile icon={photoPlusIcon} tone="inactive" size={32} />
								<p class="branding__empty">
									{waitingForLogo
										? 'Your logo is being checked for safety. It appears here as soon as that finishes.'
										: 'No logo yet. Quotes show a leaf mark in your colour until you add one.'}
								</p>
								{#if canEdit && !waitingForLogo}
									<Button variant="secondary" onclick={() => fileInput?.click()}>
										<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
										<span aria-hidden="true">{@html uploadIcon}</span>Upload logo
									</Button>
								{/if}
							{/if}
						</div>

						{#if displayLogoUrl}
							<div class="branding__sizes">
								<span class="branding__sizes-label">Small sizes</span>
								{#each [[32, 'Quote top'], [28, 'Sidebar'], [24, 'Chat']] as [size, where] (size)}
									<span class="branding__size">
										<img src={displayLogoUrl} alt="" width={size} height={size} />{where} · {size}
									</span>
								{/each}
							</div>
						{/if}

						{#if canEdit && (displayLogoUrl || pendingLogoRemove)}
							<div class="branding__logo-actions">
								<Button
									variant="secondary"
									disabled={pendingLogoRemove}
									onclick={() => fileInput?.click()}
								>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
									<span aria-hidden="true">{@html uploadIcon}</span>Replace logo
								</Button>
								{#if !pendingLogoRemove}
									<Button variant="secondary" variation="destructive" onclick={removeLogo}>
										<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
										<span aria-hidden="true">{@html trashIcon}</span>Remove
									</Button>
								{/if}
								<span class="branding__hint">PNG, JPG or WEBP · up to 2 MB</span>
							</div>
						{:else if canEdit}
							<p class="branding__hint">PNG, JPG or WEBP · up to 2 MB</p>
						{/if}
						<input
							bind:this={fileInput}
							type="file"
							accept="image/png,image/jpeg,image/webp"
							class="branding__file-input"
							tabindex="-1"
							aria-label="Choose a logo file"
							onchange={handleFileChosen}
						/>
					</Card>

					<Card
						heading="Brand colour"
						hint="The top line and main button on customer pages, and your chat"
						icon={paletteIcon}
						tone="inactive"
					>
						<div class="branding__colour-row">
							<label class="branding__swatch" style:--swatch={colourNow}>
								<span class="branding__sr">Pick a colour</span>
								<input
									type="color"
									value={colourNow}
									disabled={!canEdit}
									oninput={(event) => setColour(event.currentTarget.value)}
								/>
								{#if canEdit}
									<span class="branding__pipette" aria-hidden="true">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
										{@html pickerIcon}
									</span>
								{/if}
							</label>
							<div class="branding__code">
								<Input
									id="branding-colour-code"
									label="Colour code"
									value={colourText}
									disabled={!canEdit}
									invalid={codeInvalid}
									errorMessage={codeInvalid ? 'Use a colour code like #0F766E.' : ''}
									oninput={typeColour}
									onblur={leaveColourBox}
									spellcheck="false"
									autocomplete="off"
									maxlength={7}
								/>
							</div>
							{#if canEdit}
								<Button variant="secondary" onclick={resetToDefault}>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
									<span aria-hidden="true">{@html resetIcon}</span>Reset to default
								</Button>
							{/if}
						</div>

						{#if canEdit}
							<div class="branding__picks" role="group" aria-label="Quick picks">
								<span class="branding__picks-label">Quick picks</span>
								<div>
									{#each BRAND_QUICK_PICKS as pick (pick)}
										<button
											type="button"
											class="branding__pick"
											class:branding__pick--chosen={colourNow === pick}
											style:--pick={pick}
											aria-label={`Use ${pick.toUpperCase()}`}
											aria-pressed={colourNow === pick}
											onclick={() => setColour(pick)}
										></button>
									{/each}
								</div>
							</div>
						{/if}

						<Banner
							type={colourReadable ? 'success' : 'warning'}
							icon={colourReadable ? checkCircleIcon : alertIcon}
						>
							{colourReadable
								? 'White words read clearly on this colour, so buttons on your quotes stay easy to read.'
								: 'White words are hard to read on this colour. Pick a deeper one so buttons on your quotes stay easy to read.'}
						</Banner>
					</Card>
				</div>

				<BrandPreview
					logoUrl={displayLogoUrl}
					colour={colourNow}
					name={data.profile.name}
					{place}
					businessName={data.profile.name}
				/>
			</div>
		</div>

		{#if canEdit && (dirty || conflict)}
			<StickyActionBar concept class="branding__bar">
				<IconTile
					icon={conflict ? compareIcon : pencilLineIcon}
					tone={conflict ? 'critical' : 'warning'}
					size={32}
				/>
				<div class="branding__bar-copy">
					<strong>
						{conflict
							? 'Your changes were not saved'
							: `${changes.length} change${changes.length === 1 ? '' : 's'} not saved`}
					</strong>
					<span>
						{conflict
							? 'Someone saved first. See their version before you save yours.'
							: `${changes.join(' · ')} · Sent quotes keep the old look`}
					</span>
				</div>
				{#if conflict}
					<Button variant="secondary" onclick={() => void seeTheirs()} loading={checkingTheirs}>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
						<span aria-hidden="true">{@html compareIcon}</span>See their version
					</Button>
				{:else}
					<Button variant="secondary" onclick={cancel} disabled={saving}>Cancel</Button>
				{/if}
				<Button onclick={() => void save()} loading={saving} disabled={saving || codeInvalid}>
					<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
					<span aria-hidden="true">{@html checkIcon}</span>Save branding
				</Button>
			</StickyActionBar>
		{/if}
	{/if}
</PageContainer>

<style lang="scss">
	.branding {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__head {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}
		&__changed {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__columns {
			display: grid;
			grid-template-columns: minmax(0, 520px) minmax(0, 1fr);
			align-items: start;
			gap: var(--space-large);
		}
		&__controls {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			min-width: 0;
		}

		// The stage holds the logo on a white sheet of paper, so a logo with a transparent background reads
		// the way it will on a quote. The paper stays white in dark mode.
		&__stage {
			display: flex;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			gap: var(--space-slim);
			min-height: 196px;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-tile-large);
			background: var(--color-surface--background--subtle);

			&--empty {
				border: 1.5px solid var(--color-border--interactive);
			}
		}
		&__paper {
			display: flex;
			align-items: center;
			justify-content: center;
			width: 320px;
			max-width: 100%;
			height: 128px;
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-white);
			box-shadow:
				0 1px 2px color-mix(in srgb, var(--color-black) 10%, transparent),
				0 6px 16px color-mix(in srgb, var(--color-black) 8%, transparent);

			img {
				max-width: 100%;
				max-height: 100%;
				object-fit: contain;
			}
			&--removed {
				opacity: 0.4;
			}
		}
		&__state {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}
		&__state-note {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}
		&__spinner {
			width: 14px;
			height: 14px;
			border: 2px solid var(--color-border);
			border-top-color: var(--color-informative);
			border-radius: var(--radius-circle);
			animation: branding-spin 0.8s linear infinite;
		}
		&__empty {
			max-width: 36ch;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			text-align: center;
		}
		&__sizes {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}
		&__sizes-label {
			margin-right: var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
		}
		&__size {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-smaller) var(--space-slim) var(--space-smaller) var(--space-smaller);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			background: var(--color-white);
			color: var(--color-base-blue--900);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;

			img {
				object-fit: contain;
				border-radius: var(--radius-small);
			}
		}
		&__logo-actions {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}
		&__logo-actions :global(svg),
		&__colour-row :global(.button svg) {
			width: 16px;
			height: 16px;
		}
		&__hint {
			margin: 0 0 0 auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}
		&__file-input,
		&__sr {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
		}

		&__colour-row {
			display: flex;
			align-items: flex-end;
			gap: var(--space-base);
		}
		&__swatch {
			position: relative;
			display: block;
			flex: 0 0 auto;
			width: 76px;
			height: 76px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--swatch);
			cursor: pointer;

			input {
				position: absolute;
				inset: 0;
				width: 100%;
				height: 100%;
				opacity: 0;
				cursor: pointer;
			}
			&:focus-within {
				box-shadow: var(--shadow-focus);
			}
		}
		&__pipette {
			position: absolute;
			right: var(--space-smaller);
			bottom: var(--space-smaller);
			display: flex;
			align-items: center;
			justify-content: center;
			width: 24px;
			height: 24px;
			border-radius: var(--radius-circle);
			color: var(--color-black);
			background: var(--color-white);
			box-shadow: var(--shadow-low);
			pointer-events: none;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
		&__code {
			flex: 1;
			min-width: 0;
		}
		&__picks {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);

			div {
				display: flex;
				flex-wrap: wrap;
				gap: var(--space-small);
			}
		}
		&__picks-label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		&__pick {
			width: 32px;
			height: 32px;
			padding: 3px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			cursor: pointer;

			&::before {
				content: '';
				display: block;
				width: 100%;
				height: 100%;
				border-radius: var(--radius-circle);
				background: var(--pick);
			}
			&:hover {
				border-color: var(--color-border--interactive);
			}
			&:focus-visible {
				box-shadow: var(--shadow-focus);
			}
			&--chosen {
				border: 2px solid var(--color-heading);
			}
		}

		&__bar-copy {
			display: flex;
			flex: 1;
			flex-direction: column;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}
		}
	}

	// The floating bar is a 720-wide card in the middle of the content, not a full-width strip.
	:global(.branding__bar) {
		width: 720px;
		max-width: calc(100% - 2 * var(--space-large));
		margin-inline: auto;
	}

	@keyframes branding-spin {
		to {
			transform: rotate(360deg);
		}
	}

	@media (max-width: 1079px) {
		.branding__columns {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
