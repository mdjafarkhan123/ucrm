<script lang="ts">
	import { tick } from 'svelte';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import rotateIcon from '@tabler/icons/outline/rotate.svg?raw';
	import tagIcon from '@tabler/icons/outline/tag.svg?raw';
	import deviceDesktopIcon from '@tabler/icons/outline/device-desktop.svg?raw';
	import deviceMobileIcon from '@tabler/icons/outline/device-mobile.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	type TemplateKey =
		| 'received_page'
		| 'application_receipt'
		| 'password_setup'
		| 'account_created_contact'
		| 'organization_closure_started'
		| 'organization_closure_fourteen_day_reminder'
		| 'organization_closure_three_day_reminder'
		| 'organization_closure_completed';
	type Placeholder = { key: string; label: string; required: boolean };
	type TemplateSummary = {
		template_key: TemplateKey;
		published_version: number;
		published_at: string | null;
		published_by_owner_email: string | null;
		updated_at: string;
		placeholders: Placeholder[];
	};
	type TemplateDetail = {
		template_key: TemplateKey;
		subject_draft: string | null;
		body_draft: string;
		subject_published: string | null;
		body_published: string | null;
		published_version: number;
		published_at: string | null;
		published_by_owner_email: string | null;
	};
	type TemplateVersion = {
		version: number;
		subject: string | null;
		body: string;
		published_at: string;
		published_by_owner_email: string;
	};
	type ListResponse = { templates: TemplateSummary[]; error?: string };
	type DetailResponse = {
		template: TemplateDetail;
		versions: TemplateVersion[];
		placeholders: Placeholder[];
		error?: string;
	};
	type MutationResponse = {
		template?: TemplateDetail;
		error?: string;
		missing_placeholders?: string[];
	};

	const TEMPLATE_LABELS: Record<TemplateKey, string> = {
		received_page: 'Application received page',
		application_receipt: 'Application receipt email',
		password_setup: 'Password setup email',
		account_created_contact: 'Account created notice',
		organization_closure_started: 'Closure started notice',
		organization_closure_fourteen_day_reminder: 'Closure 14-day reminder',
		organization_closure_three_day_reminder: 'Closure 3-day reminder',
		organization_closure_completed: 'Closure completed notice'
	};
	const TEMPLATE_HAS_SUBJECT: Record<TemplateKey, boolean> = {
		received_page: false,
		application_receipt: true,
		password_setup: true,
		account_created_contact: true,
		organization_closure_started: true,
		organization_closure_fourteen_day_reminder: true,
		organization_closure_three_day_reminder: true,
		organization_closure_completed: true
	};

	let selectedKey = $state<TemplateKey | null>(null);
	let subjectDraft = $state('');
	let bodyDraft = $state('');
	let savedDraft = $state<{ subject: string | null; body: string } | null>(null);
	let previewMode = $state<'desktop' | 'mobile' | 'email'>('desktop');
	let actionError = $state('');
	let publishConfirmed = $state(false);
	let restoringVersion = $state<number | null>(null);
	let bodyTextareaEl = $state<HTMLTextAreaElement | undefined>();

	const list = createQuery<ListResponse>(() => ({
		queryKey: ['jafar', 'message-templates'],
		queryFn: async () => {
			const response = await fetch('/api/jafar/message-templates');
			const result = (await response.json()) as ListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Templates could not be loaded.');
			return result;
		}
	}));

	const detail = createQuery<DetailResponse>(() => ({
		queryKey: ['jafar', 'message-templates', selectedKey],
		queryFn: async () => {
			const response = await fetch(`/api/jafar/message-templates/${selectedKey}`);
			const result = (await response.json()) as DetailResponse;
			if (!response.ok) throw new Error(result.error ?? 'The template could not be loaded.');
			return result;
		},
		enabled: !!selectedKey
	}));

	$effect(() => {
		const template = detail.data?.template;
		if (template && template.template_key === selectedKey) {
			subjectDraft = template.subject_draft ?? '';
			bodyDraft = template.body_draft;
			savedDraft = { subject: template.subject_draft, body: template.body_draft };
		}
	});

	const isDirty = $derived(
		savedDraft !== null &&
			(savedDraft.subject !== (subjectDraft || null) || savedDraft.body !== bodyDraft)
	);

	const missingRequired = $derived(
		(detail.data?.placeholders ?? [])
			.filter((placeholder) => placeholder.required)
			.filter(
				(placeholder) => !`${subjectDraft}\n${bodyDraft}`.includes(`{{${placeholder.key}}}`)
			)
	);

	const saveDraft = createMutation<MutationResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!selectedKey) throw new Error('Choose a template first.');
			const response = await fetch(`/api/jafar/message-templates/${selectedKey}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					subject_draft: TEMPLATE_HAS_SUBJECT[selectedKey] ? subjectDraft || null : null,
					body_draft: bodyDraft
				})
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'The draft could not be saved.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: (result) => {
			toast.success('Draft saved.');
			if (result.template)
				savedDraft = { subject: result.template.subject_draft, body: result.template.body_draft };
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'message-templates'] });
		}
	}));

	const publish = createMutation<MutationResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!selectedKey) throw new Error('Choose a template first.');
			const response = await fetch(`/api/jafar/message-templates/${selectedKey}/publish`, {
				method: 'POST'
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) {
				if (result.missing_placeholders?.length) {
					actionError = `Add the required tags before publishing: ${result.missing_placeholders.join(', ')}.`;
					throw new Error(actionError);
				}
				throw new Error(result.error ?? 'The template could not be published.');
			}
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = actionError || error.message),
		onSuccess: () => {
			publishConfirmed = false;
			toast.success('Template published. It is now the live version.');
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'message-templates'] });
		}
	}));

	const restoreVersion = createMutation<MutationResponse, Error, number>(() => ({
		mutationFn: async (version) => {
			if (!selectedKey) throw new Error('Choose a template first.');
			const response = await fetch(
				`/api/jafar/message-templates/${selectedKey}/restore-version`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ version })
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'The draft could not be restored.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: (result) => {
			restoringVersion = null;
			toast.success('Draft restored. Review it, then publish when ready.');
			if (result.template) {
				subjectDraft = result.template.subject_draft ?? '';
				bodyDraft = result.template.body_draft;
				savedDraft = { subject: result.template.subject_draft, body: result.template.body_draft };
			}
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'message-templates'] });
		}
	}));

	function clearFeedback() {
		actionError = '';
	}

	function selectTemplate(key: TemplateKey) {
		clearFeedback();
		publishConfirmed = false;
		restoringVersion = null;
		selectedKey = key;
	}

	async function insertPlaceholder(key: string) {
		const tag = `{{${key}}}`;
		const el = bodyTextareaEl;
		const start = el?.selectionStart ?? bodyDraft.length;
		const end = el?.selectionEnd ?? bodyDraft.length;
		bodyDraft = bodyDraft.slice(0, start) + tag + bodyDraft.slice(end);
		await tick();
		el?.focus();
		el?.setSelectionRange(start + tag.length, start + tag.length);
	}

	function formatDate(value: string | null) {
		return value
			? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
					new Date(value)
				)
			: '—';
	}

	function hasUnpublishedChanges(summary: TemplateSummary) {
		if (!summary.published_at) return true;
		return new Date(summary.updated_at).getTime() > new Date(summary.published_at).getTime();
	}
</script>

<svelte:head><title>Message templates · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="templates">
	<header class="templates__header">
		<div>
			<p class="templates__eyebrow">Owner messaging</p>
			<h1>Message templates</h1>
			<p class="templates__description">
				The wording of every message the platform sends: the application-received page and the
				receipt, password-setup, and account-created emails.
			</p>
		</div>
	</header>

	{#if actionError}<p class="templates__feedback templates__feedback--error" role="alert">
			{actionError}
		</p>{/if}

	{#if list.isPending}
		<LoadingSkeleton variant="table" rows={4} label="Loading templates" />
	{:else if list.isError}
		<ErrorState
			title="Templates could not be loaded"
			description={list.error.message}
			retry={() => list.refetch()}
		/>
	{:else}
		<div class="templates__layout">
			<nav class="templates__list" aria-label="Message templates">
				{#each list.data?.templates ?? [] as summary (summary.template_key)}
					<button
						type="button"
						class="templates__list-item"
						class:templates__list-item--active={selectedKey === summary.template_key}
						onclick={() => selectTemplate(summary.template_key)}
					>
						<span class="templates__list-name">{TEMPLATE_LABELS[summary.template_key]}</span>
						<span class="templates__list-meta">
							<Badge status="success" size="small">v{summary.published_version}</Badge>
							{#if hasUnpublishedChanges(summary)}<Badge status="warning" size="small"
									>Unpublished changes</Badge
								>{/if}
						</span>
					</button>
				{/each}
			</nav>

			<section class="templates__editor" aria-live="polite">
				{#if !selectedKey}
					<p class="templates__empty">Choose a template on the left to edit it.</p>
				{:else if detail.isPending}
					<LoadingSkeleton variant="table" rows={6} label="Loading template" />
				{:else if detail.isError}
					<ErrorState
						title="The template could not be loaded"
						description={detail.error.message}
						retry={() => detail.refetch()}
					/>
				{:else if detail.data}
					{@const placeholders = detail.data.placeholders}
					<div class="templates__editor-grid">
						<form
							class="templates__form"
							onsubmit={(event) => {
								event.preventDefault();
								saveDraft.mutate();
							}}
						>
							<header>
								<h2>{TEMPLATE_LABELS[selectedKey]}</h2>
								<p>
									Published version {detail.data.template.published_version} · last published {formatDate(
										detail.data.template.published_at
									)}
								</p>
							</header>

							{#if TEMPLATE_HAS_SUBJECT[selectedKey]}
								<label
									><span>Subject line</span><input
										bind:value={subjectDraft}
										maxlength="300"
										placeholder="Email subject"
									/></label
								>
							{/if}

							<div class="templates__placeholders">
								<span class="templates__placeholders-label"
									><span aria-hidden="true">{@html tagIcon}</span>Insert a tag</span
								>
								{#each placeholders as placeholder (placeholder.key)}
									<Button
										type="button"
										variant="tertiary"
										size="small"
										onclick={() => insertPlaceholder(placeholder.key)}
										>{placeholder.label}{placeholder.required ? ' *' : ''}</Button
									>
								{/each}
							</div>

							<label class="templates__body-label"
								><span>Message body</span><textarea
									bind:this={bodyTextareaEl}
									bind:value={bodyDraft}
									required
									rows="14"
									spellcheck="false"
								></textarea></label
							>

							{#if missingRequired.length > 0}
								<p class="templates__hint templates__hint--warning">
									<span aria-hidden="true">{@html alertIcon}</span> Missing required tags: {missingRequired
										.map((placeholder) => placeholder.label)
										.join(', ')}
								</p>
							{/if}

							<footer class="templates__form-actions">
								<Button type="submit" variant="secondary" loading={saveDraft.isPending}
									>Save draft</Button
								>
								{#if isDirty}
									<p class="templates__hint">Save your draft before publishing.</p>
								{:else}
									<label class="templates__confirm"
										><input type="checkbox" bind:checked={publishConfirmed} />
										<span>I understand this becomes the live version.</span></label
									>
									<Button
										type="button"
										variation="learning"
										disabled={!publishConfirmed || missingRequired.length > 0}
										loading={publish.isPending}
										onclick={() => publish.mutate()}>Publish</Button
									>
								{/if}
							</footer>
						</form>

						<div class="templates__preview">
							<div class="templates__preview-toggle" role="group" aria-label="Preview width">
								<button
									type="button"
									class:templates__preview-toggle-btn--active={previewMode === 'desktop'}
									class="templates__preview-toggle-btn"
									onclick={() => (previewMode = 'desktop')}
									><span aria-hidden="true">{@html deviceDesktopIcon}</span>Desktop</button
								>
								<button
									type="button"
									class:templates__preview-toggle-btn--active={previewMode === 'mobile'}
									class="templates__preview-toggle-btn"
									onclick={() => (previewMode = 'mobile')}
									><span aria-hidden="true">{@html deviceMobileIcon}</span>Mobile</button
								>
								<button
									type="button"
									class:templates__preview-toggle-btn--active={previewMode === 'email'}
									class="templates__preview-toggle-btn"
									onclick={() => (previewMode = 'email')}
									><span aria-hidden="true">{@html mailIcon}</span>Email</button
								>
							</div>
							<div class={`templates__preview-frame templates__preview-frame--${previewMode}`}>
								{#if TEMPLATE_HAS_SUBJECT[selectedKey] && subjectDraft}
									<p class="templates__preview-subject">{subjectDraft}</p>
								{/if}
								<div class="templates__preview-body">{@html bodyDraft}</div>
							</div>
							<p class="templates__hint">
								Tags like <code>{'{{price}}'}</code> show as-is here. Real messages replace them with
								the actual value.
							</p>
						</div>
					</div>

					<section class="templates__history" aria-labelledby="template-history-title">
						<header>
							<div>
								<p class="templates__eyebrow">Immutable record</p>
								<h2 id="template-history-title">Version history</h2>
							</div>
							<Button
								variant="tertiary"
								onclick={() => (restoringVersion = 1)}
								disabled={restoreVersion.isPending}
								><span aria-hidden="true">{@html historyIcon}</span>Reset to default</Button
							>
						</header>

						{#if restoringVersion !== null}
							<div class="templates__restore-confirm" role="alertdialog" aria-live="assertive">
								<span aria-hidden="true">{@html alertIcon}</span>
								<p>
									Restore version <strong>{restoringVersion}</strong> into the draft? Any unsaved
									changes in the editor above will be lost. This does not publish anything by
									itself.
								</p>
								<div class="templates__restore-confirm-actions">
									<Button
										variant="tertiary"
										onclick={() => (restoringVersion = null)}
										disabled={restoreVersion.isPending}>Cancel</Button
									>
									<Button
										loading={restoreVersion.isPending}
										onclick={() => restoreVersion.mutate(restoringVersion ?? 1)}
										>Confirm restore</Button
									>
								</div>
							</div>
						{/if}

						<div class="templates__table-wrap">
							<table>
								<thead
									><tr
										><th scope="col">Version</th><th scope="col">Published</th><th scope="col"
											>Published by</th
										><th scope="col"></th></tr
									></thead
								><tbody
									>{#each detail.data.versions as version (version.version)}<tr
											><th scope="row"
												>v{version.version}{#if version.version === detail.data.template.published_version}
													<span aria-hidden="true">{@html checkIcon}</span> current
												{/if}</th
											><td>{formatDate(version.published_at)}</td><td
												>{version.published_by_owner_email}</td
											><td
												><Button
													variant="tertiary"
													size="small"
													onclick={() => (restoringVersion = version.version)}
													><span aria-hidden="true">{@html rotateIcon}</span>Restore</Button
												></td
											></tr
										>{/each}</tbody
								>
							</table>
						</div>
					</section>
				{/if}
			</section>
		</div>
	{/if}
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.templates {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}
	.templates__header {
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.templates__eyebrow {
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
	h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-tightest);
	}
	.templates__description {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
	}
	.templates__feedback {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
	}
	.templates__feedback--error {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.templates__layout {
		display: grid;
		grid-template-columns: 280px minmax(0, 1fr);
		gap: var(--space-large);
		align-items: start;
	}
	.templates__list {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}
	.templates__list-item {
		display: grid;
		gap: var(--space-smaller);
		padding: var(--space-small);
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: transparent;
		text-align: left;
		cursor: pointer;
	}
	.templates__list-item:hover {
		background: var(--color-surface--hover);
	}
	.templates__list-item--active {
		border-color: var(--color-brand);
		background: var(--color-informative--surface);
	}
	.templates__list-name {
		font-weight: 600;
		font-size: var(--typography--fontSize-small);
	}
	.templates__list-meta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-smaller);
	}
	.templates__editor {
		display: grid;
		gap: var(--space-large);
		min-width: 0;
	}
	.templates__empty {
		padding: var(--space-large);
		border: var(--border-base) dashed var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		text-align: center;
	}
	.templates__editor-grid {
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
		gap: var(--space-large);
	}
	.templates__form {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}
	.templates__form header p {
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	label {
		display: grid;
		gap: var(--space-small);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}
	input,
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
		min-height: 260px;
		font-family: var(--typography--fontFamily-mono, monospace);
		font-size: var(--typography--fontSize-small);
		resize: vertical;
	}
	input:focus-visible,
	textarea:focus-visible {
		outline: none;
		border-color: var(--color-interactive);
		box-shadow: var(--shadow-focus);
	}
	.templates__placeholders {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
		align-items: center;
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}
	.templates__placeholders-label {
		display: inline-flex;
		gap: var(--space-smaller);
		align-items: center;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.templates__placeholders-label :global(svg) {
		width: 16px;
		height: 16px;
	}
	.templates__body-label {
		gap: var(--space-small);
	}
	.templates__hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}
	.templates__hint code {
		padding: 1px 4px;
		border-radius: var(--radius-small);
		background: var(--color-surface--background--subtle);
	}
	.templates__hint--warning {
		display: flex;
		gap: var(--space-small);
		align-items: flex-start;
		padding: var(--space-small);
		border-radius: var(--radius-base);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.templates__hint--warning :global(svg) {
		width: 18px;
		height: 18px;
		flex: 0 0 18px;
	}
	.templates__form-actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-base);
	}
	.templates__confirm {
		display: flex;
		gap: var(--space-small);
		align-items: flex-start;
		margin-left: auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}
	.templates__confirm input {
		width: 20px;
		min-width: 20px;
		height: 20px;
		padding: 0;
	}
	.templates__preview {
		display: grid;
		gap: var(--space-small);
		align-content: start;
	}
	.templates__preview-toggle {
		display: inline-flex;
		gap: var(--space-smaller);
		padding: var(--space-smallest);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		width: fit-content;
	}
	.templates__preview-toggle-btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-smaller) var(--space-small);
		border: none;
		border-radius: var(--radius-small);
		color: var(--color-text--secondary);
		background: transparent;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		cursor: pointer;
	}
	.templates__preview-toggle-btn :global(svg) {
		width: 16px;
		height: 16px;
	}
	.templates__preview-toggle-btn--active {
		color: var(--color-interactive);
		background: var(--color-informative--surface);
	}
	.templates__preview-frame {
		box-sizing: border-box;
		max-width: 100%;
		margin: 0 auto;
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
		overflow-x: auto;
	}
	.templates__preview-frame--desktop {
		width: 100%;
	}
	.templates__preview-frame--mobile {
		width: 375px;
	}
	.templates__preview-frame--email {
		width: 600px;
	}
	.templates__preview-subject {
		margin-bottom: var(--space-base);
		padding-bottom: var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
		color: var(--color-heading);
		font-weight: 700;
	}
	.templates__preview-body :global(p) {
		margin: 0 0 var(--space-base);
		color: var(--color-text);
		line-height: var(--typography--lineHeight-large);
	}
	.templates__preview-body :global(a) {
		color: var(--color-interactive);
	}
	.templates__history {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}
	.templates__history header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-base);
	}
	.templates__history header :global(svg) {
		width: 16px;
		height: 16px;
	}
	.templates__restore-confirm {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-critical);
		border-radius: var(--radius-base);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
		font-size: var(--typography--fontSize-small);
	}
	.templates__restore-confirm span {
		color: var(--color-critical);
	}
	.templates__restore-confirm :global(svg) {
		width: 20px;
		height: 20px;
	}
	.templates__restore-confirm-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.templates__table-wrap {
		overflow-x: auto;
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
	th :global(svg) {
		width: 14px;
		height: 14px;
		color: var(--color-success);
		vertical-align: middle;
	}
	thead {
		background: var(--color-surface--background--subtle);
	}
	thead th {
		color: var(--color-text--secondary);
	}
	tbody tr:last-child th,
	tbody tr:last-child td {
		border-bottom: 0;
	}
	td :global(svg) {
		width: 14px;
		height: 14px;
	}
	@media (max-width: 1023px) {
		.templates__layout {
			grid-template-columns: 1fr;
		}
		.templates__editor-grid {
			grid-template-columns: 1fr;
		}
	}
	@media (max-width: 767px) {
		.templates__form-actions {
			align-items: stretch;
			flex-direction: column;
		}
		.templates__confirm {
			margin-left: 0;
		}
	}
</style>
