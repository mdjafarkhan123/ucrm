<script lang="ts">
	import { tick } from 'svelte';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	// Jafar's platform Email Templates library (docs/contractor-email-contract.md § "Templates, snippets, and
	// branding"). Not /jafar/message-templates -- that page is the 8 fixed-key system/security emails with a
	// draft/publish workflow. This page is a many-row content library organizations later copy from; the
	// org-side copy screen is a separate slice not yet built.
	const queryClient = useQueryClient();
	const toast = getToastManager();

	type PackageOption = { package_key: string; display_name: string };
	type TemplateRow = {
		id: string;
		name: string;
		folder: string | null;
		subject: string;
		body: string;
		version: number;
		updated_at: string;
		package_keys: string[];
	};
	type ListResponse = { templates: TemplateRow[]; packages: PackageOption[]; error?: string };
	type MutationResponse = {
		template?: TemplateRow;
		error?: string;
		field_errors?: Record<string, string>;
	};

	let selectedId = $state<string | 'new' | null>(null);
	let name = $state('');
	let folder = $state('');
	let subject = $state('');
	let body = $state('');
	let packageKeys = $state<string[]>([]);
	let formError = $state('');
	let deleteTarget = $state<TemplateRow | null>(null);

	const list = createQuery<ListResponse>(() => ({
		queryKey: ['jafar', 'email-templates'],
		queryFn: async () => {
			const response = await fetch('/api/jafar/email-templates');
			const result = (await response.json()) as ListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Email templates could not be loaded.');
			return result;
		},
		staleTime: 30_000
	}));

	const templates = $derived(list.data?.templates ?? []);
	const packages = $derived(list.data?.packages ?? []);
	const selected = $derived(templates.find((template) => template.id === selectedId) ?? null);

	function startCreate() {
		selectedId = 'new';
		name = '';
		folder = '';
		subject = '';
		body = '';
		packageKeys = [];
		formError = '';
	}

	function selectTemplate(template: TemplateRow) {
		selectedId = template.id;
		name = template.name;
		folder = template.folder ?? '';
		subject = template.subject;
		body = template.body;
		packageKeys = [...template.package_keys];
		formError = '';
	}

	function togglePackage(packageKey: string) {
		packageKeys = packageKeys.includes(packageKey)
			? packageKeys.filter((key) => key !== packageKey)
			: [...packageKeys, packageKey];
	}

	const save = createMutation<MutationResponse, Error, void>(() => ({
		mutationFn: async () => {
			const payload = { name, folder: folder || null, subject, body, package_keys: packageKeys };
			const isCreate = selectedId === 'new';
			const response = await fetch(
				isCreate ? '/api/jafar/email-templates' : `/api/jafar/email-templates/${selectedId}`,
				{
					method: isCreate ? 'POST' : 'PATCH',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(payload)
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) {
				formError = result.field_errors
					? Object.values(result.field_errors)[0]
					: (result.error ?? 'The template could not be saved.');
				throw new Error(formError);
			}
			return result;
		},
		onMutate: () => (formError = ''),
		onSuccess: async (result) => {
			toast.success(selectedId === 'new' ? 'Template created.' : 'Template saved.');
			await queryClient.invalidateQueries({ queryKey: ['jafar', 'email-templates'] });
			await tick();
			if (result.template) selectedId = result.template.id;
		}
	}));

	const remove = createMutation<{ ok?: boolean; error?: string }, Error, string>(() => ({
		mutationFn: async (id) => {
			const response = await fetch(`/api/jafar/email-templates/${id}`, { method: 'DELETE' });
			const result = (await response.json()) as { ok?: boolean; error?: string };
			if (!response.ok) throw new Error(result.error ?? 'The template could not be deleted.');
			return result;
		},
		onSuccess: async (_result, deletedId) => {
			toast.success('Template deleted.');
			deleteTarget = null;
			if (selectedId === deletedId) selectedId = null;
			await queryClient.invalidateQueries({ queryKey: ['jafar', 'email-templates'] });
		},
		onError: (error) => toast.error(error.message)
	}));
</script>

<svelte:head><title>Email templates · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="email-templates">
	<header class="email-templates__header">
		<div>
			<p class="email-templates__eyebrow">Owner content library</p>
			<h1>Email templates</h1>
			<p class="email-templates__description">
				Reusable content organizations can copy into their own communications. Visibility controls
				which package tiers can copy a template.
			</p>
		</div>
		<Button onclick={startCreate}
			><span aria-hidden="true">{@html plusIcon}</span>New template</Button
		>
	</header>

	{#if list.isPending}
		<LoadingSkeleton variant="table" rows={4} label="Loading email templates" />
	{:else if list.isError}
		<ErrorState
			title="Email templates could not be loaded"
			description={list.error.message}
			retry={() => list.refetch()}
		/>
	{:else}
		<div class="email-templates__layout">
			<div class="email-templates__table-wrap">
				{#if templates.length === 0}
					<p class="email-templates__empty">No templates yet. Create the first one.</p>
				{:else}
					<table>
						<thead>
							<tr>
								<th scope="col">Name</th>
								<th scope="col">Visibility</th>
								<th scope="col">Updated</th>
								<th scope="col"></th>
							</tr>
						</thead>
						<tbody>
							{#each templates as template (template.id)}
								<tr
									class:email-templates__row--active={selectedId === template.id}
									onclick={() => selectTemplate(template)}
								>
									<th scope="row">
										<span class="email-templates__name">{template.name}</span>
										{#if template.folder}<Badge size="small">{template.folder}</Badge>{/if}
									</th>
									<td>
										{#if template.package_keys.length === 0}
											<Badge status="informative" size="small">All packages</Badge>
										{:else}
											{#each template.package_keys as key (key)}<Badge size="small">{key}</Badge
												>{/each}
										{/if}
									</td>
									<td>{new Date(template.updated_at).toLocaleDateString()}</td>
									<td>
										<Button
											variant="tertiary"
											size="small"
											onclick={(event: MouseEvent) => {
												event.stopPropagation();
												deleteTarget = template;
											}}><span aria-hidden="true">{@html trashIcon}</span></Button
										>
									</td>
								</tr>
							{/each}
						</tbody>
					</table>
				{/if}
			</div>

			<section class="email-templates__editor" aria-live="polite">
				{#if selectedId === null}
					<p class="email-templates__empty">Choose a template on the left, or create a new one.</p>
				{:else}
					<form
						class="email-templates__form"
						onsubmit={(event) => {
							event.preventDefault();
							save.mutate();
						}}
					>
						<header>
							<h2>{selectedId === 'new' ? 'New template' : name}</h2>
							{#if selected}<p>Version {selected.version}</p>{/if}
						</header>

						{#if formError}<p class="email-templates__feedback" role="alert">{formError}</p>{/if}

						<label><span>Name</span><input bind:value={name} maxlength="120" required /></label>
						<label
							><span>Folder (optional)</span><input
								bind:value={folder}
								maxlength="60"
								placeholder="e.g. Follow-up"
							/></label
						>
						<label
							><span>Subject</span><input bind:value={subject} maxlength="300" required /></label
						>
						<label class="email-templates__body-label"
							><span>Body</span><textarea bind:value={body} rows="12" required></textarea></label
						>

						<div class="email-templates__visibility">
							<span class="email-templates__visibility-label"
								>Visible to (leave all unchecked for every package)</span
							>
							<div class="email-templates__visibility-options">
								{#each packages as pkg (pkg.package_key)}
									<label class="email-templates__checkbox">
										<input
											type="checkbox"
											checked={packageKeys.includes(pkg.package_key)}
											onchange={() => togglePackage(pkg.package_key)}
										/>
										<span>{pkg.display_name}</span>
									</label>
								{/each}
							</div>
						</div>

						<footer class="email-templates__form-actions">
							<Button type="submit" loading={save.isPending}>Save</Button>
						</footer>
					</form>
				{/if}
			</section>
		</div>
	{/if}
</main>
<!-- eslint-enable svelte/no-at-html-tags -->

<ConfirmDialog
	open={deleteTarget !== null}
	title="Delete this template?"
	tone="critical"
	destructive
	confirmLabel="Delete template"
	loading={remove.isPending}
	onConfirm={() => deleteTarget && remove.mutate(deleteTarget.id)}
	onClose={() => (deleteTarget = null)}
>
	{#if deleteTarget}
		<p>This can't be undone. "{deleteTarget.name}" will no longer be available to copy.</p>
	{/if}
</ConfirmDialog>

<style lang="scss">
	.email-templates {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}
	.email-templates__header {
		display: flex;
		justify-content: space-between;
		align-items: flex-end;
		gap: var(--space-base);
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.email-templates__eyebrow {
		margin: 0 0 var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h1,
	h2,
	p {
		margin: 0;
	}
	h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}
	.email-templates__description {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
	}
	.email-templates__layout {
		display: grid;
		grid-template-columns: minmax(0, 1.1fr) minmax(0, 1fr);
		gap: var(--space-large);
		align-items: start;
	}
	.email-templates__table-wrap {
		overflow-x: auto;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}
	table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
	}
	th,
	td {
		padding: var(--space-small) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		white-space: nowrap;
	}
	thead {
		background: var(--color-surface--background--subtle);
	}
	thead th {
		color: var(--color-text--secondary);
	}
	tbody tr {
		cursor: pointer;
	}
	tbody tr:hover {
		background: var(--color-surface--hover);
	}
	tbody tr:last-child th,
	tbody tr:last-child td {
		border-bottom: 0;
	}
	.email-templates__row--active {
		background: var(--color-informative--surface);
	}
	.email-templates__name {
		margin-right: var(--space-small);
		font-weight: 600;
	}
	.email-templates__empty {
		padding: var(--space-large);
		border: var(--border-base) dashed var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		text-align: center;
	}
	.email-templates__editor {
		min-width: 0;
	}
	.email-templates__form {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}
	.email-templates__feedback {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	label {
		display: grid;
		gap: var(--space-small);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}
	input:not([type='checkbox']),
	textarea {
		width: 100%;
		min-height: 40px;
		box-sizing: border-box;
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: var(--color-surface);
		font: inherit;
	}
	textarea {
		min-height: 220px;
		resize: vertical;
	}
	.email-templates__body-label {
		gap: var(--space-small);
	}
	.email-templates__visibility {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}
	.email-templates__visibility-label {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.email-templates__visibility-options {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-base);
	}
	.email-templates__checkbox {
		display: inline-flex;
		gap: var(--space-smaller);
		align-items: center;
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}
	.email-templates__checkbox input {
		width: 18px;
		height: 18px;
	}
	.email-templates__form-actions {
		display: flex;
		justify-content: flex-end;
	}
	@media (max-width: 1023px) {
		.email-templates__layout {
			grid-template-columns: 1fr;
		}
	}
</style>
