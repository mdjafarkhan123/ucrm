<script lang="ts">
	import { onDestroy, untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchSettingsBusiness,
		settingsBusinessKey,
		saveBranding,
		isSaveConflict,
		uploadOrganizationLogo,
		removeOrganizationLogo,
		type SettingsBusiness
	} from '$lib/settings/api';
	import paletteIcon from '@tabler/icons/outline/palette.svg?raw';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsBusinessKey,
		queryFn: fetchSettingsBusiness
	}));

	const DEFAULT_COLOR = '#2c5cc5';
	// Mirrors the server's LOGO_MIME_TYPES/LOGO_MAX_BYTES ($lib/server/validation/settings.schema) so a
	// picked file gets an immediate answer instead of waiting for Save to hit the server. The server stays
	// the real gate — this is early feedback only.
	const LOGO_ACCEPTED_TYPES = ['image/png', 'image/jpeg', 'image/webp'];
	const LOGO_MAX_BYTES = 2 * 1024 * 1024;

	let color = $state<string | null>(null);
	let savedColor = $state<string | null>(null);
	let logoUrl = $state<string | null>(null);
	let saving = $state(false);
	let errorMessage = $state('');
	let conflict = $state<{ editor_name: string | null; edited_at: string | null } | null>(null);
	let fileInput = $state<HTMLInputElement | null>(null);
	let layout = $state<RecordFormLayout>();

	// One place the form shows why a save did not land — a plain error, or someone else getting there first.
	const saveError = $derived(
		conflict
			? `${conflict.editor_name ?? 'Someone else'} just changed this. Refresh the page to see their version before saving yours.`
			: errorMessage
	);

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
			color = business.branding.brand_color ?? DEFAULT_COLOR;
			savedColor = business.branding.brand_color ?? DEFAULT_COLOR;
			logoUrl = business.branding.logo_url;
		});
	});

	const dirty = $derived(
		(color !== null && savedColor !== null && color !== savedColor) ||
			pendingLogoFile !== null ||
			pendingLogoRemove
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

	function discardPendingLogo() {
		if (pendingLogoPreviewUrl) URL.revokeObjectURL(pendingLogoPreviewUrl);
		pendingLogoFile = null;
		pendingLogoPreviewUrl = '';
	}

	onDestroy(discardPendingLogo);

	function cancel() {
		color = savedColor;
		conflict = null;
		errorMessage = '';
		discardPendingLogo();
		pendingLogoRemove = false;
	}

	function resetToDefault() {
		color = DEFAULT_COLOR;
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
			queryClient.setQueryData(settingsBusinessKey, (current: SettingsBusiness | undefined) =>
				current
					? { ...current, branding: { ...current.branding, revision: result.branding_revision } }
					: current
			);
		}

		if (pendingLogoFile) {
			try {
				const result = await uploadOrganizationLogo(pendingLogoFile);
				logoUrl = result.logo_url;
				discardPendingLogo();
				queryClient.setQueryData(settingsBusinessKey, (current: SettingsBusiness | undefined) =>
					current
						? { ...current, branding: { ...current.branding, revision: result.branding_revision } }
						: current
				);
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
	}
</script>

<svelte:head><title>Branding · Settings · Contractor CRM</title></svelte:head>

{#if query.isPending || color === null}
	<LoadingSkeleton variant="card" rows={4} />
{:else if query.isError}
	<ErrorState description="Branding could not be loaded." retry={() => query.refetch()} />
{:else}
	{@const canEdit = query.data.permissions.edit}
	{@const editor = query.data.branding.last_editor}

	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Branding' }]}
	/>

	<RecordFormLayout title="Branding" icon={paletteIcon} bind:this={layout} error={saveError}>
		{#snippet main()}
			{#if !canEdit}
				<p class="branding__readonly">
					Only owners and administrators can change this. {#if editor}Last changed by {editor.name ??
							'a teammate'}.{/if}
				</p>
			{/if}

			<div class="branding__columns">
				<div class="branding__column">
					<SectionBlock
						title="Logo"
						hint="Shown on quotes, invoices, emails, and the client portal."
						level={3}
					>
						<div class="branding__logo">
							<div
								class="branding__logo-preview"
								class:branding__logo-preview--empty={!displayLogoUrl}
							>
								{#if displayLogoUrl}
									<img src={displayLogoUrl} alt="Business logo" />
								{:else}
									<span>No logo yet</span>
								{/if}
							</div>
							{#if pendingLogoFile}
								<p class="branding__logo-pending">Not saved yet</p>
							{:else if pendingLogoRemove}
								<p class="branding__logo-pending">
									Removed when you save. Quotes and invoices already sent to customers keep showing
									it.
								</p>
							{/if}
							{#if canEdit}
								<div class="branding__logo-actions">
									<Button variant="secondary" onclick={() => fileInput?.click()}
										><!-- eslint-disable-next-line svelte/no-at-html-tags -->
										<span aria-hidden="true">{@html uploadIcon}</span>{displayLogoUrl
											? 'Replace logo'
											: 'Upload logo'}</Button
									>
									{#if pendingLogoRemove}
										<Button variant="tertiary" onclick={undoRemoveLogo}>Undo</Button>
									{:else if displayLogoUrl}
										<Button variant="tertiary" variation="destructive" onclick={removeLogo}
											><!-- eslint-disable-next-line svelte/no-at-html-tags -->
											<span aria-hidden="true">{@html trashIcon}</span>Remove</Button
										>
									{/if}
									<input
										bind:this={fileInput}
										type="file"
										accept="image/png,image/jpeg,image/webp"
										class="branding__file-input"
										onchange={handleFileChosen}
									/>
								</div>
								<p class="branding__logo-hint">PNG, JPG, or WEBP. Up to 2 MB.</p>
							{/if}
						</div>
					</SectionBlock>
				</div>

				<div class="branding__column">
					{#if color}
						{@const c = color}
						<SectionBlock
							title="Brand color"
							hint="Colors quote and invoice headers, buttons, and the client portal."
							form
							level={3}
						>
							<div class="branding__color">
								<input
									id="branding-color"
									class="branding__color-swatch"
									type="color"
									bind:value={color}
									disabled={!canEdit}
								/>
								<div class="branding__color-preview" style={`--preview-color: ${c}`}>
									<span class="branding__color-code">{c.toUpperCase()}</span>
									<button class="branding__color-chip" type="button">Preview</button>
								</div>
								{#if canEdit}
									<Button variant="tertiary" onclick={resetToDefault}>Reset to default</Button>
								{/if}
							</div>
						</SectionBlock>
					{/if}
				</div>
			</div>
		{/snippet}

		{#snippet actions()}
			{#if canEdit}
				<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
				<Button
					onclick={() => void save().finally(() => layout?.revealError())}
					disabled={!dirty || saving}
					loading={saving}>Save</Button
				>
			{/if}
		{/snippet}
	</RecordFormLayout>
{/if}

<style lang="scss">
	.branding {
		&__readonly {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
		}
		&__columns {
			display: grid;
			grid-template-columns: 1fr 1fr;
			align-items: start;
			gap: var(--space-large);
		}
		&__column {
			min-width: 0;
		}
		&__logo {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}
		&__logo-preview {
			display: grid;
			width: 160px;
			height: 100px;
			place-items: center;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
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
		&__logo-pending {
			padding: var(--space-smaller) var(--space-small);
			border-radius: var(--radius-small);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-smaller);
		}
		&__logo-actions {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}
		&__logo-actions :global(svg) {
			width: 16px;
			height: 16px;
		}
		&__file-input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
		}
		&__logo-hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__color {
			display: flex;
			align-items: center;
			gap: var(--space-base);
		}
		&__color-swatch {
			width: 48px;
			height: 48px;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			cursor: pointer;
		}
		&__color-preview {
			display: flex;
			align-items: center;
			gap: var(--space-base);
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}
		&__color-code {
			color: var(--color-heading);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}
		&__color-chip {
			padding: var(--space-small) var(--space-base);
			border: 0;
			border-radius: var(--radius-base);
			color: #fff;
			background: var(--preview-color);
			font-weight: 600;
			cursor: default;
		}
	}
	@media (max-width: 1079px) {
		.branding__columns {
			grid-template-columns: 1fr;
		}
	}
</style>
