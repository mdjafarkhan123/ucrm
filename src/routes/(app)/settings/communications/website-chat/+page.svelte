<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import SettingsPageHeader from '$lib/components/settings/SettingsPageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import WebsiteChatPreview from '$lib/components/communications/WebsiteChatPreview.svelte';
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
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';

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

	const widgetColumns: DataTableColumn[] = [
		{ key: 'widget', label: 'Widget' },
		{ key: 'launcher', label: 'Launcher' },
		{ key: 'domains', label: 'Domains' },
		{ key: 'status', label: 'Status' },
		{ key: 'actions', label: 'Actions', hideLabel: true }
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
	const conversationUsage = $derived(widgetsQuery.data?.conversation_usage);
	const conversationAtCap = $derived(
		conversationUsage?.state === 'numeric' &&
			conversationUsage.value !== null &&
			conversationUsage.accepted_count >= conversationUsage.value
	);
	const conversationUsagePercent = $derived(
		conversationUsage?.state === 'numeric' && conversationUsage.value
			? Math.min(
					100,
					Math.round((conversationUsage.accepted_count / conversationUsage.value) * 100)
				)
			: 0
	);
	const isEditing = $derived(dialogMode === 'edit');
	const editingWidgetLive = $derived(
		editingWidget
			? (widgetsQuery.data?.widgets.find((widget) => widget.id === editingWidget!.id) ??
					editingWidget)
			: null
	);
	const previewChannelOptions = $derived(toChannelOptions(draft));

	function formatPeriodEnd(value: string | null | undefined) {
		if (!value) return '';
		try {
			return new Intl.DateTimeFormat(undefined, {
				year: 'numeric',
				month: 'short',
				day: 'numeric',
				hour: 'numeric',
				minute: '2-digit',
				timeZone: widgetsQuery.data?.organization.timezone ?? 'UTC',
				timeZoneName: 'short'
			}).format(new Date(value));
		} catch {
			return new Intl.DateTimeFormat(undefined, {
				year: 'numeric',
				month: 'short',
				day: 'numeric',
				hour: 'numeric',
				minute: '2-digit'
			}).format(new Date(value));
		}
	}

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
		if (widget.suspended_at) return { label: 'Suspended', tone: 'critical' as const };
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

<!-- eslint-disable svelte/no-at-html-tags -->

<svelte:head><title>Website Chat · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
	<div class="website-chat record-detail--cards">
		<SettingsPageHeader
			title="Website Chat"
			description="The chat widgets your website can show customers."
			icon={messageCircleIcon}
			tone="task"
			presentation="communication"
		/>

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
				tone="inactive"
				title="Usage and availability"
				icon={messageCircleIcon}
				level={2}
			>
				<div class="website-chat__usage">
					<div class="website-chat__usage-copy">
						<span>Accepted conversations</span>
						<strong class="website-chat__usage-count"
							>{conversationUsage?.accepted_count ??
								0}{#if conversationUsage?.state === 'numeric'}<small
									>of {conversationUsage.value ?? 0}</small
								>{:else if conversationUsage?.state === 'unlimited'}<small>· unlimited</small
								>{/if}</strong
						>
						{#if conversationUsage?.period_ends_at}
							<small class="website-chat__usage-reset">
								<span class="website-chat__usage-reset-icon" aria-hidden="true"
									>{@html refreshIcon}</span
								>
								Resets {formatPeriodEnd(conversationUsage.period_ends_at)}
							</small>
						{/if}
					</div>
					{#if conversationUsage?.state === 'numeric'}
						<div
							class="website-chat__meter"
							role="progressbar"
							aria-valuemin={0}
							aria-valuemax={100}
							aria-valuenow={conversationUsagePercent}
							aria-label={`${conversationUsagePercent}% of Website Chat conversations used`}
						>
							<div
								class="website-chat__meter-fill"
								style="width: {conversationUsagePercent}%"
							></div>
						</div>
					{/if}
				</div>

				{#if widgetsQuery.data?.suspension.active}
					<p class="website-chat__notice website-chat__notice--critical" role="alert">
						Website Chat is suspended by the platform owner
						{widgetsQuery.data.suspension.reason ? `: ${widgetsQuery.data.suspension.reason}` : '.'}
						Your settings and conversation history are preserved.
					</p>
				{:else if conversationUsage?.state === 'not_included'}
					<p class="website-chat__notice website-chat__notice--warning" role="status">
						Your plan does not include new Website Chat conversations. Existing history remains
						available.
					</p>
				{:else if !conversationUsage?.period_ends_at}
					<p class="website-chat__notice website-chat__notice--warning" role="status">
						Website Chat is waiting for an active billing period. New conversations cannot start
						yet.
					</p>
				{:else if conversationAtCap}
					<p class="website-chat__notice website-chat__notice--warning" role="status">
						This period's conversation limit has been reached. Existing conversations stay open; new
						visitors can still use your configured external contact options.
					</p>
				{/if}
			</SectionBlock>

			<SectionBlock
				tone="inactive"
				class="section-block--flush"
				title="Widgets"
				hint={limit?.is_unlimited
					? `${widgetsUsed} widget${widgetsUsed === 1 ? '' : 's'} · unlimited`
					: `${widgetsUsed} of ${limit?.value ?? 0} widgets used`}
				icon={messageCircleIcon}
				level={2}
			>
				{#snippet actions()}
					<Button disabled={!canCreate} onclick={openCreate}>
						<span class="website-chat__action-icon" aria-hidden="true">{@html plusIcon}</span>
						New widget
					</Button>
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
					<DataTable
						columns={widgetColumns}
						items={widgetsQuery.data.widgets}
						rowId={(widget) => widget.id}
						caption="Website Chat widgets"
						variant="card"
					>
						{#snippet row(widget)}
							{@const widgetStatus = status(widget)}
							<th scope="row" class="website-chat__widget-cell">
								<div class="website-chat__widget">
									<span class="website-chat__widget-icon" aria-hidden="true"
										>{@html messageCircleIcon}</span
									>
									<span class="website-chat__widget-name">{widget.name}</span>
								</div>
							</th>
							<td>
								<div class="website-chat__launcher">
									<span class="website-chat__launcher-icon" aria-hidden="true"
										>{@html messageCircleIcon}</span
									>
									{widget.launcher_position === 'bottom_left' ? 'Bottom left' : 'Bottom right'}
								</div>
							</td>
							<td class="website-chat__origins-cell">{widget.origins.length}</td>
							<td>
								<StatusBadge status={widgetStatus.tone} size="compact"
									>{widgetStatus.label}</StatusBadge
								>
							</td>
							<td class="website-chat__edit-cell">
								<Button
									size="small"
									variant="secondary"
									variation="subtle"
									onclick={() => openEdit(widget)}>Edit</Button
								>
							</td>
						{/snippet}
					</DataTable>
				{/if}
			</SectionBlock>
		{/if}
	</div>
</PageContainer>

{#if dialogMode}
	<Dialog open title={isEditing ? 'Edit widget' : 'New widget'} size="large" onClose={closeDialog}>
		<div class="website-chat__dialog-grid">
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

			<WebsiteChatPreview
				businessName={widgetsQuery.data?.organization.name ?? 'Your business'}
				brandColor={widgetsQuery.data?.organization.brand_color}
				launcherPosition={draft.launcher_position}
				teaserText={draft.teaser_text}
				greetingText={draft.greeting_text}
				contactRequirement={draft.contact_requirement}
				privacyPolicyUrl={draft.privacy_policy_url}
				channelOptions={previewChannelOptions}
			/>
		</div>

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

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.website-chat {
		display: grid;
		gap: 20px;
		align-content: start;
	}
	/* App-look cards: each block is a white card on the app background. The shared card rules (the
	   `record-detail--cards` context) put the heading, hint and actions inside the card header; the page
	   only restores the framed icon tile and the spacing the approved frame shows. */
	.website-chat.record-detail--cards :global(.section-block) :global(.section-block__title) {
		gap: var(--space-slim);
	}
	.website-chat.record-detail--cards
		:global(.section-block:has(> .section-block__hint))
		> :global(.section-block__hint) {
		margin-left: calc(var(--space-large) + 36px + var(--space-slim));
	}
	.website-chat.record-detail--cards
		:global(.section-block:has(> .section-block__hint) > .section-block__title) {
		align-self: end;
	}
	.website-chat.record-detail--cards
		:global(.section-block:has(> .section-block__hint) > .section-block__hint) {
		align-self: start;
	}
	.website-chat__notice {
		margin: 0 0 var(--space-base);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.website-chat__notice--warning {
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.website-chat__notice--critical {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	/* The usage row sits in its own quiet tile, as the approved frame draws it. */
	.website-chat__usage {
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(200px, 40%);
		align-items: center;
		gap: var(--space-larger);
		padding: 18px 20px;
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}
	.website-chat__usage-copy {
		display: grid;
		gap: var(--space-smaller);

		> span,
		> small {
			color: var(--color-text--secondary);
		}

		> span {
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		> small {
			display: flex;
			align-items: center;
			gap: var(--space-smaller);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		strong {
			display: flex;
			align-items: baseline;
			gap: var(--space-smaller);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;

			small {
				color: var(--color-text--secondary);
				font-size: 15px;
				font-weight: 600;
			}
		}
	}
	.website-chat__usage-reset-icon {
		display: inline-flex;
		flex: 0 0 auto;

		:global(svg) {
			width: 12px;
			height: 12px;
		}
	}
	.website-chat__action-icon {
		display: inline-flex;
		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}
	.website-chat__meter {
		overflow: hidden;
		width: 100%;
		height: 8px;
		border-radius: var(--radius-base);
		background: var(--color-surface--background--hover);
	}
	.website-chat__meter-fill {
		height: 100%;
		border-radius: var(--radius-base);
		background: var(--color-interactive);
	}
	/* The card table owns its head, spacing and row lines; the page only sets its width floor and
	   drops the last row's line where the card closes. */
	.website-chat :global(.data-table) {
		--data-table-min-width: 640px;
	}
	.website-chat :global(.data-table--card tbody tr:last-child th),
	.website-chat :global(.data-table--card tbody tr:last-child td) {
		border-bottom: 0;
	}
	.website-chat__widget {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		min-width: 0;
	}
	.website-chat__widget-icon {
		display: inline-grid;
		flex: 0 0 auto;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: var(--color-surface--active);

		:global(svg) {
			width: 15px;
			height: 15px;
		}
	}
	.website-chat__widget-name {
		overflow: hidden;
		color: var(--color-heading);
		font-weight: 700;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.website-chat__launcher {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-text);
		font-weight: 500;
	}
	.website-chat__launcher-icon {
		display: inline-grid;
		flex: 0 0 auto;
		place-items: center;
		width: 24px;
		height: 24px;
		border-radius: var(--radius-small);
		color: var(--color-heading);
		background: var(--color-surface--active);

		:global(svg) {
			width: 12px;
			height: 12px;
		}
	}
	.website-chat__origins-cell {
		color: var(--color-heading);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.website-chat__edit-cell {
		text-align: end;
	}
	.website-chat__form,
	.website-chat__channels,
	.website-chat__toggles {
		display: grid;
		gap: var(--space-base);
	}
	.website-chat__dialog-grid {
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(320px, 0.9fr);
		align-items: start;
		gap: var(--space-large);
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
	@media (max-width: 1079px) {
		.website-chat__dialog-grid {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	@media (max-width: 639px) {
		.website-chat {
			gap: var(--space-base);
		}
		.website-chat__usage {
			grid-template-columns: minmax(0, 1fr);
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
