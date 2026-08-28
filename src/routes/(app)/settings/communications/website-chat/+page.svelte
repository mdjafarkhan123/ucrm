<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		addWebsiteChatWidgetOrigin,
		createWebsiteChatWidget,
		fetchWebsiteChatWidgets,
		removeWebsiteChatWidgetOrigin,
		testWebsiteChatWidgetInstall,
		updateWebsiteChatWidget,
		websiteChatWidgetsKey,
		WebsiteChatWidgetWriteError,
		type WebsiteChatChannelOption,
		type WebsiteChatWidget
	} from '$lib/communications/website-chat';
	import messageCircleIcon from '@tabler/icons/outline/message-circle.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const widgetsQuery = createQuery(() => ({
		queryKey: websiteChatWidgetsKey,
		queryFn: fetchWebsiteChatWidgets,
		staleTime: 30_000
	}));

	type Draft = {
		name: string;
		launcher_position: string;
		teaser_text: string;
		greeting_text: string;
		contact_requirement: string;
		availability_visibility_mode: string;
		source_label: string;
		privacy_policy_url: string;
		whatsapp_enabled: boolean;
		whatsapp_destination: string;
		messenger_enabled: boolean;
		messenger_destination: string;
		published: boolean;
		disabled: boolean;
	};

	let dialogMode = $state<'create' | 'edit' | null>(null);
	let editingWidget = $state<WebsiteChatWidget | null>(null);
	let draft = $state<Draft>(emptyDraft());
	let saving = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	let newOrigin = $state('');
	let addingOrigin = $state(false);
	let originError = $state('');
	let removingOriginId = $state<string | null>(null);

	let testUrl = $state('');
	let testing = $state(false);
	let testResult = $state<{ origin: string; allowed: boolean } | null>(null);
	let testError = $state('');

	const launcherPositionOptions = [
		{ value: 'bottom_right', label: 'Bottom right' },
		{ value: 'bottom_left', label: 'Bottom left' }
	];
	const contactRequirementOptions = [
		{ value: 'either', label: 'Phone or email' },
		{ value: 'phone', label: 'Phone required' },
		{ value: 'email', label: 'Email required' }
	];
	const availabilityVisibilityOptions = [
		{ value: 'hidden', label: 'Hidden' },
		{ value: 'show_when_available', label: 'Show when available' },
		{ value: 'always', label: 'Always show' }
	];

	const limit = $derived(widgetsQuery.data?.limit);
	const widgetsUsed = $derived(widgetsQuery.data?.widgets_used ?? 0);
	const isEntitled = $derived(
		limit
			? limit.state !== 'not_included' && !(limit.state === 'numeric' && (limit.value ?? 0) === 0)
			: false
	);
	const atCap = $derived(
		limit && isEntitled ? !limit.is_unlimited && widgetsUsed >= (limit.value ?? 0) : false
	);
	const canCreate = $derived(isEntitled && !atCap);
	const isEditing = $derived(dialogMode === 'edit');
	const editingWidgetLive = $derived(
		editingWidget
			? (widgetsQuery.data?.widgets.find((widget) => widget.id === editingWidget!.id) ??
					editingWidget)
			: null
	);

	function emptyDraft(): Draft {
		return {
			name: '',
			launcher_position: 'bottom_right',
			teaser_text: '',
			greeting_text: '',
			contact_requirement: 'either',
			availability_visibility_mode: 'hidden',
			source_label: '',
			privacy_policy_url: '',
			whatsapp_enabled: false,
			whatsapp_destination: '',
			messenger_enabled: false,
			messenger_destination: '',
			published: false,
			disabled: false
		};
	}

	function draftFromWidget(widget: WebsiteChatWidget): Draft {
		const whatsapp = widget.channel_options.find((option) => option.type === 'whatsapp');
		const messenger = widget.channel_options.find((option) => option.type === 'messenger');
		return {
			name: widget.name,
			launcher_position: widget.launcher_position,
			teaser_text: widget.teaser_text ?? '',
			greeting_text: widget.greeting_text ?? '',
			contact_requirement: widget.contact_requirement,
			availability_visibility_mode: widget.availability_visibility_mode,
			source_label: widget.source_label ?? '',
			privacy_policy_url: widget.privacy_policy_url ?? '',
			whatsapp_enabled: Boolean(whatsapp),
			whatsapp_destination: whatsapp?.destination ?? '',
			messenger_enabled: Boolean(messenger),
			messenger_destination: messenger?.destination ?? '',
			published: widget.published,
			disabled: Boolean(widget.disabled_at)
		};
	}

	function toChannelOptions(source: Draft): WebsiteChatChannelOption[] {
		const options: WebsiteChatChannelOption[] = [];
		if (source.whatsapp_enabled && source.whatsapp_destination.trim())
			options.push({ type: 'whatsapp', destination: source.whatsapp_destination.trim() });
		if (source.messenger_enabled && source.messenger_destination.trim())
			options.push({ type: 'messenger', destination: source.messenger_destination.trim() });
		return options;
	}

	function status(widget: WebsiteChatWidget) {
		if (widget.disabled_at) return { label: 'Disabled', tone: 'inactive' as const };
		if (widget.published) return { label: 'Published', tone: 'success' as const };
		return { label: 'Draft', tone: 'warning' as const };
	}

	function resetDialogExtras() {
		newOrigin = '';
		originError = '';
		testUrl = '';
		testResult = null;
		testError = '';
	}

	function openCreate() {
		editingWidget = null;
		draft = emptyDraft();
		formError = '';
		fieldErrors = {};
		resetDialogExtras();
		dialogMode = 'create';
	}

	function openEdit(widget: WebsiteChatWidget) {
		editingWidget = widget;
		draft = draftFromWidget(widget);
		formError = '';
		fieldErrors = {};
		resetDialogExtras();
		dialogMode = 'edit';
	}

	function closeDialog() {
		if (saving) return;
		dialogMode = null;
		editingWidget = null;
	}

	async function invalidate() {
		await queryClient.invalidateQueries({ queryKey: websiteChatWidgetsKey });
	}

	async function submit() {
		if (saving || !dialogMode) return;
		saving = true;
		formError = '';
		fieldErrors = {};
		const payload = {
			name: draft.name,
			launcher_position: draft.launcher_position,
			teaser_text: draft.teaser_text.trim() ? draft.teaser_text.trim() : null,
			greeting_text: draft.greeting_text.trim() ? draft.greeting_text.trim() : null,
			contact_requirement: draft.contact_requirement,
			availability_visibility_mode: draft.availability_visibility_mode,
			source_label: draft.source_label.trim() ? draft.source_label.trim() : null,
			privacy_policy_url: draft.privacy_policy_url.trim() ? draft.privacy_policy_url.trim() : null,
			channel_options: toChannelOptions(draft)
		};
		try {
			if (isEditing && editingWidget) {
				const result = await updateWebsiteChatWidget(editingWidget.id, {
					...payload,
					expected_revision: (editingWidgetLive ?? editingWidget).revision,
					published: draft.published,
					disabled: draft.disabled
				});
				editingWidget = result.widget;
				await invalidate();
				toast.success('Widget saved.');
			} else {
				const result = await createWebsiteChatWidget(payload);
				editingWidget = result.widget;
				dialogMode = 'edit';
				await invalidate();
				toast.success('Widget created.');
			}
		} catch (cause) {
			if (cause instanceof WebsiteChatWidgetWriteError) {
				formError = cause.message;
				fieldErrors = cause.fieldErrors;
			} else formError = cause instanceof Error ? cause.message : 'The widget could not be saved.';
		} finally {
			saving = false;
		}
	}

	async function submitOrigin() {
		const widget = editingWidgetLive;
		if (!widget || addingOrigin) return;
		addingOrigin = true;
		originError = '';
		try {
			await addWebsiteChatWidgetOrigin(widget.id, newOrigin.trim());
			newOrigin = '';
			await invalidate();
			toast.success('Domain added.');
		} catch (cause) {
			originError =
				cause instanceof WebsiteChatWidgetWriteError
					? cause.message
					: 'The domain could not be added.';
		} finally {
			addingOrigin = false;
		}
	}

	async function removeOrigin(originId: string) {
		const widget = editingWidgetLive;
		if (!widget) return;
		removingOriginId = originId;
		try {
			await removeWebsiteChatWidgetOrigin(widget.id, originId);
			await invalidate();
			toast.success('Domain removed.');
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'The domain could not be removed.');
		} finally {
			removingOriginId = null;
		}
	}

	async function runInstallTest() {
		const widget = editingWidgetLive;
		if (!widget || testing || !testUrl.trim()) return;
		testing = true;
		testError = '';
		testResult = null;
		try {
			testResult = await testWebsiteChatWidgetInstall(widget.id, testUrl.trim());
		} catch (cause) {
			testError = cause instanceof Error ? cause.message : 'The install test could not run.';
		} finally {
			testing = false;
		}
	}
</script>

<svelte:head><title>Website Chat · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<div class="website-chat">
		<PageHeader
			eyebrow="Communications"
			title="Website Chat"
			description="The chat widgets your website can show customers."
		>
			{#snippet actions()}
				<Button href={resolve('/settings')} variant="secondary" variation="subtle"
					>Back to settings</Button
				>
			{/snippet}
		</PageHeader>

		{#if widgetsQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading Website Chat widgets" />
		{:else if widgetsQuery.isError}
			<ErrorState
				description="Website Chat widgets could not be loaded."
				retry={() => widgetsQuery.refetch()}
			/>
		{:else if !isEntitled}
			<EmptyState
				title="Website Chat isn't part of your plan"
				description="Ask your platform owner to add Website Chat to your plan."
			/>
		{:else}
			<SectionBlock
				title="Widgets"
				hint={limit?.is_unlimited
					? `${widgetsUsed} widget${widgetsUsed === 1 ? '' : 's'} · unlimited`
					: `${widgetsUsed} of ${limit?.value ?? 0} widgets used`}
				icon={messageCircleIcon}
				level={2}
			>
				{#snippet actions()}
					<Button disabled={!canCreate} onclick={openCreate}>New widget</Button>
				{/snippet}
				{#if atCap}
					<p class="website-chat__notice" role="status">
						You're using all {widgetsUsed} of your {limit?.value} widgets. Disable one to create another.
					</p>
				{/if}
				{#if !widgetsQuery.data?.widgets.length}
					<EmptyState
						title="No widgets yet"
						description="Create a widget to start chatting with customers from your website."
					>
						{#snippet action()}<Button onclick={openCreate}>New widget</Button>{/snippet}
					</EmptyState>
				{:else}
					<div class="website-chat__table-wrap">
						<table>
							<thead
								><tr
									><th scope="col">Widget</th><th scope="col">Launcher</th><th scope="col"
										>Domains</th
									><th scope="col">Status</th><th scope="col"
										><span class="website-chat__sr-only">Actions</span></th
									></tr
								></thead
							>
							<tbody>
								{#each widgetsQuery.data.widgets as widget (widget.id)}
									{@const widgetStatus = status(widget)}
									<tr>
										<th scope="row">{widget.name}</th>
										<td
											>{widget.launcher_position === 'bottom_left'
												? 'Bottom left'
												: 'Bottom right'}</td
										>
										<td>{widget.origins.length}</td>
										<td><Badge status={widgetStatus.tone}>{widgetStatus.label}</Badge></td>
										<td
											><Button
												size="small"
												variant="secondary"
												variation="subtle"
												onclick={() => openEdit(widget)}>Edit</Button
											></td
										>
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
				{/if}
			</SectionBlock>
		{/if}
	</div>
</PageContainer>

{#if dialogMode}
	<Dialog open title={isEditing ? 'Edit widget' : 'New widget'} onClose={closeDialog}>
		<form
			class="website-chat__form"
			onsubmit={(event) => {
				event.preventDefault();
				void submit();
			}}
		>
			{#if formError}<p class="website-chat__error" role="alert">{formError}</p>{/if}
			<Input
				id="widget-name"
				label="Widget name"
				required
				bind:value={draft.name}
				invalid={Boolean(fieldErrors.name)}
				errorMessage={fieldErrors.name}
			/>
			<Select
				id="widget-launcher-position"
				label="Launcher position"
				options={launcherPositionOptions}
				bind:value={draft.launcher_position}
			/>
			<Textarea
				id="widget-teaser"
				label="Teaser text"
				rows={2}
				maxlength={300}
				bind:value={draft.teaser_text}
			/>
			<Textarea
				id="widget-greeting"
				label="Greeting text"
				rows={2}
				maxlength={300}
				bind:value={draft.greeting_text}
			/>
			<Select
				id="widget-contact-requirement"
				label="Required identity"
				options={contactRequirementOptions}
				bind:value={draft.contact_requirement}
			/>
			<Select
				id="widget-availability-visibility"
				label="Availability visibility"
				options={availabilityVisibilityOptions}
				bind:value={draft.availability_visibility_mode}
			/>
			<Input id="widget-source-label" label="Source label" bind:value={draft.source_label} />
			<Input
				id="widget-privacy-policy-url"
				label="Privacy policy link"
				type="url"
				placeholder="https://example.com/privacy"
				invalid={Boolean(fieldErrors.privacy_policy_url)}
				errorMessage={fieldErrors.privacy_policy_url}
				bind:value={draft.privacy_policy_url}
			/>

			<div class="website-chat__channels">
				<span class="website-chat__group-label">Other channels</span>
				<Checkbox
					id="widget-whatsapp-enabled"
					label="WhatsApp"
					checked={draft.whatsapp_enabled}
					onchange={(checked) => (draft.whatsapp_enabled = checked)}
				/>
				{#if draft.whatsapp_enabled}
					<Input
						id="widget-whatsapp-destination"
						label="WhatsApp number or link"
						bind:value={draft.whatsapp_destination}
					/>
				{/if}
				<Checkbox
					id="widget-messenger-enabled"
					label="Messenger"
					checked={draft.messenger_enabled}
					onchange={(checked) => (draft.messenger_enabled = checked)}
				/>
				{#if draft.messenger_enabled}
					<Input
						id="widget-messenger-destination"
						label="Messenger link"
						bind:value={draft.messenger_destination}
					/>
				{/if}
			</div>

			{#if isEditing}
				<div class="website-chat__toggles">
					<Toggle
						id="widget-published"
						label="Published"
						description="Visible to customers when it has at least one allowed domain."
						checked={draft.published}
						onchange={(checked) => (draft.published = checked)}
					/>
					<Toggle
						id="widget-disabled"
						label="Paused"
						description="Temporarily hide this widget without losing its settings."
						checked={draft.disabled}
						onchange={(checked) => (draft.disabled = checked)}
					/>
				</div>
			{/if}

			<div class="website-chat__actions">
				<Button type="submit" loading={saving}
					>{isEditing ? 'Save changes' : 'Create widget'}</Button
				><Button
					type="button"
					variant="secondary"
					variation="subtle"
					disabled={saving}
					onclick={closeDialog}>Cancel</Button
				>
			</div>
		</form>

		{#if isEditing && editingWidgetLive}
			<div class="website-chat__section">
				<h3>Allowed domains</h3>
				{#if !editingWidgetLive.origins.length}
					<p class="website-chat__notice" role="status">
						No domains configured -- this widget won't work anywhere yet.
					</p>
				{:else}
					<ul class="website-chat__origins">
						{#each editingWidgetLive.origins as origin (origin.id)}
							<li>
								<span>{origin.origin}</span>
								<Button
									size="small"
									variant="secondary"
									variation="subtle"
									loading={removingOriginId === origin.id}
									onclick={() => removeOrigin(origin.id)}>Remove</Button
								>
							</li>
						{/each}
					</ul>
				{/if}
				<form
					class="website-chat__origin-form"
					onsubmit={(event) => {
						event.preventDefault();
						void submitOrigin();
					}}
				>
					<Input
						id="widget-new-origin"
						label="Add a domain"
						placeholder="https://example.com"
						bind:value={newOrigin}
						invalid={Boolean(originError)}
						errorMessage={originError}
					/>
					<Button type="submit" size="small" loading={addingOrigin}>Add</Button>
				</form>
			</div>

			<div class="website-chat__section">
				<h3>Test your installation</h3>
				<form
					class="website-chat__origin-form"
					onsubmit={(event) => {
						event.preventDefault();
						void runInstallTest();
					}}
				>
					<Input
						id="widget-install-test-url"
						label="Your page URL"
						placeholder="https://example.com/contact"
						bind:value={testUrl}
						invalid={Boolean(testError)}
						errorMessage={testError}
					/>
					<Button type="submit" size="small" variant="secondary" loading={testing}>Test</Button>
				</form>
				{#if testResult}
					<p class="website-chat__notice" role="status">
						{testResult.origin} is {testResult.allowed ? 'allowed' : 'not allowed'} for this widget.
					</p>
				{/if}
			</div>
		{/if}
	</Dialog>
{/if}

<style lang="scss">
	.website-chat {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}
	.website-chat :global(.section-block) {
		--section-block-notch: var(--color-surface);
	}
	.website-chat__notice {
		margin: 0 0 var(--space-base);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.website-chat__table-wrap {
		overflow-x: auto;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.website-chat table {
		width: 100%;
		min-width: 640px;
		border-collapse: collapse;
		color: var(--color-text);
	}
	.website-chat th,
	.website-chat td {
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		vertical-align: middle;
	}
	.website-chat thead th {
		background: var(--color-surface--background--subtle);
		color: var(--color-heading);
		font-weight: 700;
	}
	.website-chat tbody tr:last-child th,
	.website-chat tbody tr:last-child td {
		border-bottom: 0;
	}
	.website-chat__form,
	.website-chat__channels,
	.website-chat__toggles {
		display: grid;
		gap: var(--space-base);
	}
	.website-chat__group-label {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.website-chat__error {
		margin: 0;
		color: var(--color-critical);
	}
	.website-chat__actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.website-chat__section {
		margin-top: var(--space-large);
		padding-top: var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
	}
	.website-chat__section h3 {
		margin: 0 0 var(--space-base);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.website-chat__origins {
		display: grid;
		gap: var(--space-small);
		margin: 0 0 var(--space-base);
		padding: 0;
		list-style: none;
	}
	.website-chat__origins li {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.website-chat__origin-form {
		display: flex;
		align-items: flex-end;
		gap: var(--space-small);
	}
	.website-chat__origin-form :global(.input) {
		flex: 1 1 auto;
	}
	.website-chat__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}
	@media (max-width: 639px) {
		.website-chat {
			gap: var(--space-base);
		}
		.website-chat__actions {
			justify-content: flex-start;
		}
		.website-chat__origin-form {
			flex-direction: column;
			align-items: stretch;
		}
	}
</style>
