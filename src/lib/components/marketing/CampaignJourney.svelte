<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate, goto, replaceState } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import CampaignStepper from './CampaignStepper.svelte';
	import CampaignGoalStep from './CampaignGoalStep.svelte';
	import CampaignCustomersStep from './CampaignCustomersStep.svelte';
	import CampaignEmailStep from './CampaignEmailStep.svelte';
	import CampaignDeliveryStep from './CampaignDeliveryStep.svelte';
	import CampaignReviewStep from './CampaignReviewStep.svelte';
	import {
		fetchCustomerGroups,
		fetchMarketingDeliveryOptions,
		emptyMarketingDeliveryOptions,
		createCampaignRequest,
		updateCampaignRequest,
		launchCampaignRequest,
		fetchRuleLabels,
		StaleCampaignError,
		marketingCampaignsKey,
		marketingCampaignKey,
		marketingCustomerGroupsKey,
		marketingDeliveryOptionsKey,
		type MarketingApiError,
		type RuleLabel
	} from '$lib/marketing/api';
	import { startFileUpload, finishFileUpload, trashFile } from '$lib/files/api';
	import { uploadAttachmentFile } from '$lib/collaboration/api';
	import {
		cloneMarketingCampaignContent,
		describeMarketingContentProblem,
		emptyMarketingCampaignContent,
		type MarketingBlock,
		type MarketingBlockType,
		type MarketingCampaign,
		type MarketingCampaignContent,
		type MarketingGoal
	} from '$lib/marketing/campaign-content';

	// The five-step campaign draft journey (blueprint §8). Opening or changing the form never writes --
	// only Save draft (here) or the eventual Send/Schedule (M4) does. `initial` is the existing draft when
	// editing (routes/marketing/campaigns/[id=uuid]/edit); null when starting a new one
	// (routes/marketing/campaigns/new).
	let { initial }: { initial: MarketingCampaign | null } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const campaignsHref = resolve('/(app)/marketing') + '?tab=campaigns';

	// svelte-ignore state_referenced_locally
	let campaignId = $state(initial?.id ?? null);
	// svelte-ignore state_referenced_locally
	let revision = $state(initial?.revision ?? null);
	let step = $state(1);

	// svelte-ignore state_referenced_locally
	let name = $state(initial?.name ?? '');
	// svelte-ignore state_referenced_locally
	let goal = $state<MarketingGoal | null>(initial?.goal ?? null);
	// svelte-ignore state_referenced_locally
	let customerGroupId = $state<string | null>(initial?.customer_group_id ?? null);
	// Not edited by this slice's steps -- carried through unchanged so a later save never drops them.
	// svelte-ignore state_referenced_locally
	const templateId = initial?.template_id ?? null;
	// svelte-ignore state_referenced_locally
	let content = $state<MarketingCampaignContent>(
		cloneMarketingCampaignContent(initial?.content ?? emptyMarketingCampaignContent)
	);

	function snapshot() {
		return JSON.stringify({ name, goal, customerGroupId, content });
	}
	let savedSnapshot = $state(snapshot());
	const dirty = $derived(snapshot() !== savedSnapshot);

	let nameError = $state('');
	let goalError = $state('');
	let customersError = $state('');
	let contentError = $state('');
	let deliveryError = $state('');
	let saveError = $state('');
	let saving = $state(false);

	const groupsQuery = createQuery(() => ({
		queryKey: marketingCustomerGroupsKey,
		queryFn: fetchCustomerGroups
	}));

	// Loaded once the journey reaches Delivery -- earlier steps never need a sender, a form list, or the
	// Marketing allowance, so this stays off until then (CLAUDE.md rule 10).
	const deliveryOptionsQuery = createQuery(() => ({
		queryKey: marketingDeliveryOptionsKey,
		queryFn: fetchMarketingDeliveryOptions,
		enabled: step >= 4
	}));

	// Names for catalog item ids a reopened draft's service_summary blocks already hold, so their chips show
	// a name instead of a raw id -- same one-shot hydration CustomerGroupDialog uses for its own rule ids.
	let catalogLabels = $state<RuleLabel[]>([]);
	onMount(() => {
		const ids = (initial?.content.blocks ?? [])
			.filter((block) => block.type === 'service_summary')
			.flatMap((block) => (block.type === 'service_summary' ? block.catalog_item_ids : []));
		if (ids.length === 0) return;
		void fetchRuleLabels(ids, []).then((result) => (catalogLabels = result.catalog_items));
	});

	function blankBlock(type: MarketingBlockType): MarketingBlock {
		const id = crypto.randomUUID();
		switch (type) {
			case 'image':
				return { id, type, file_id: '', alt: '' };
			case 'heading':
				return { id, type, level: 'h2', text: '' };
			case 'text':
				return { id, type, text: '' };
			case 'button':
				return { id, type, label: '', url: '' };
			case 'divider':
				return { id, type };
			case 'service_summary':
				return { id, type, title: '', catalog_item_ids: [] };
		}
	}

	// Block array edits are owned here (not the step or its row editor) for the same reason form-builder
	// question edits are owned by its page: a child reassigning an array on a plain, non-$bindable prop
	// updates the underlying $state but doesn't re-render that child's own template.
	function addBlock(type: MarketingBlockType) {
		content.blocks = [...content.blocks, blankBlock(type)];
	}
	function moveBlock(index: number, by: number) {
		const target = index + by;
		if (target < 0 || target >= content.blocks.length) return;
		const next = [...content.blocks];
		[next[index], next[target]] = [next[target], next[index]];
		content.blocks = next;
	}
	function removeBlock(index: number) {
		content.blocks = content.blocks.filter((_, i) => i !== index);
	}

	// Image uploads made during this editing session that no save has claimed yet. A swap or a remove before
	// the next save trashes the old upload rather than leaving it sitting unused in the library -- the same
	// `uploadedThisSession` convention ProductsAndServicesBlock uses for a line photo. A File that was already
	// part of a saved draft before this session started is left alone here; the server's own sync (Part 6F's
	// migration on marketing_update_campaign_draft) drops its link once a save no longer references it.
	const uploadedThisSession = new Set<string>();

	async function discardOrphanedImage(fileId: string) {
		if (!uploadedThisSession.has(fileId)) return;
		uploadedThisSession.delete(fileId);
		try {
			await trashFile(fileId);
		} catch (caught) {
			console.error('Could not move an unsaved campaign image to Trash.', fileId, caught);
		}
	}

	// The id an image upload attaches to. Step 3 (where blocks are edited) is unreachable until
	// continueFromGoal has already required a name and a goal, so creating the draft here needs no field the
	// user has not already supplied -- the same silent "first meaningful action creates the row" moment
	// RequestForm's line photo upload relies on. A block still missing its file_id cannot pass the server's
	// own validation, so it is left out of this one create call; the real content (with the finished upload)
	// reaches the row moments later through the ordinary saveDraft/update path.
	async function ensureCampaignId(): Promise<string> {
		if (campaignId) return campaignId;
		const created = await createCampaignRequest({
			name: name.trim(),
			goal: goal as MarketingGoal,
			customer_group_id: customerGroupId,
			template_id: templateId,
			content: {
				...content,
				blocks: content.blocks.filter((block) => block.type !== 'image' || block.file_id)
			}
		});
		campaignId = created.id;
		revision = created.revision;
		replaceState(
			resolve('/(app)/marketing/campaigns/[id=uuid]/edit', { id: created.id }),
			page.state
		);
		await queryClient.invalidateQueries({ queryKey: marketingCampaignsKey });
		return created.id;
	}

	/** Uploads a campaign image block's photo, creating the draft first if this is its very first upload. */
	async function uploadCampaignImage(file: File): Promise<string> {
		const id = await ensureCampaignId();
		const started = await startFileUpload(file, {
			originType: 'marketing_campaign',
			originId: id,
			originRole: 'campaign_image'
		});
		await uploadAttachmentFile(started.upload_url, file);
		await finishFileUpload(started.file.id);
		uploadedThisSession.add(started.file.id);
		return started.file.id;
	}

	async function saveDraft() {
		saveError = '';
		const trimmedName = name.trim();
		if (!trimmedName || !goal) {
			step = 1;
			nameError = trimmedName ? '' : 'Give this campaign a name.';
			goalError = goal ? '' : 'Choose a goal.';
			return;
		}
		nameError = '';
		goalError = '';
		const problem = describeMarketingContentProblem(content);
		if (problem) {
			step = 3;
			contentError = problem;
			return;
		}
		contentError = '';
		saving = true;
		try {
			const input = {
				name: trimmedName,
				goal,
				customer_group_id: customerGroupId,
				template_id: templateId,
				content
			};
			if (campaignId && revision) {
				const result = await updateCampaignRequest(campaignId, revision, input);
				revision = result.revision;
			} else {
				const created = await createCampaignRequest(input);
				campaignId = created.id;
				revision = created.revision;
				replaceState(
					resolve('/(app)/marketing/campaigns/[id=uuid]/edit', { id: created.id }),
					page.state
				);
			}
			savedSnapshot = snapshot();
			uploadedThisSession.clear();
			await queryClient.invalidateQueries({ queryKey: marketingCampaignsKey });
			if (campaignId)
				await queryClient.invalidateQueries({ queryKey: marketingCampaignKey(campaignId) });
			toast.success('Campaign draft saved.');
		} catch (cause) {
			const fieldMessages = Object.values((cause as MarketingApiError)?.field_errors ?? {});
			saveError =
				cause instanceof StaleCampaignError
					? cause.message
					: fieldMessages.length > 0
						? fieldMessages[0]
						: cause instanceof Error
							? cause.message
							: 'That campaign could not be saved.';
		} finally {
			saving = false;
		}
	}

	// Same retry fingerprint as InvoiceLifecycleDialog.svelte: a key is reused only while the retried click's
	// content (the saved draft plus the chosen send time) is unchanged, so a genuine retry never double-sends
	// but picking a different time before retrying gets a fresh key.
	let sendIdempotencyKey = crypto.randomUUID();
	let lastSendFingerprint = '';

	function fingerprint(value: unknown): string {
		const json = JSON.stringify(value);
		let hash = 0x811c9dc5;
		for (let index = 0; index < json.length; index++) {
			hash ^= json.charCodeAt(index);
			hash = Math.imul(hash, 0x01000193);
		}
		return `v1:${(hash >>> 0).toString(16)}`;
	}

	async function onSend(sendAt: string | null) {
		if (dirty || !campaignId) {
			await saveDraft();
			if (dirty || !campaignId) throw new Error(saveError || 'This campaign could not be saved.');
		}

		const hash = fingerprint({ snapshot: snapshot(), sendAt });
		if (hash !== lastSendFingerprint) {
			sendIdempotencyKey = crypto.randomUUID();
			lastSendFingerprint = hash;
		}

		try {
			await launchCampaignRequest(campaignId, revision as number, sendAt, sendIdempotencyKey);
		} catch (cause) {
			if (cause instanceof StaleCampaignError) {
				throw new Error('Someone else changed this campaign while you were sending it. Reload it.');
			}
			throw cause;
		}

		await queryClient.invalidateQueries({ queryKey: marketingCampaignsKey });
		await queryClient.invalidateQueries({ queryKey: marketingCampaignKey(campaignId) });
		toast.success(sendAt ? 'Campaign scheduled.' : 'Campaign is sending.');
		await goto(campaignsHref);
	}

	function continueFromGoal() {
		nameError = name.trim() ? '' : 'Give this campaign a name.';
		goalError = goal ? '' : 'Choose a goal.';
		if (nameError || goalError) return;
		step = 2;
	}

	function continueFromCustomers() {
		customersError = customerGroupId ? '' : 'Choose a customer group to email.';
		if (customersError) return;
		step = 3;
	}

	function continueFromDelivery() {
		if (!content.cta) {
			deliveryError = 'Choose what this campaign should ask customers to do.';
			return;
		}
		if (content.cta.type === 'internal_form' && !content.cta.form_id) {
			deliveryError = 'Choose a form.';
			return;
		}
		deliveryError = '';
		step = 5;
	}

	onDestroy(() => {
		for (const fileId of [...uploadedThisSession]) void discardOrphanedImage(fileId);
	});

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
</script>

<svelte:head><title>{name || 'New campaign'} · Marketing · Contractor CRM</title></svelte:head>

<div class="journey">
	<header class="journey__head">
		<div class="journey__head-copy">
			<p class="journey__eyebrow">Marketing</p>
			<h1>{name || 'New campaign'}</h1>
		</div>
		<div class="journey__head-actions">
			<span class="journey__save-state" role="status">
				{#if saving}Saving…{:else if dirty}Unsaved changes{:else}All changes saved{/if}
			</span>
			<Button variant="secondary" variation="subtle" href={campaignsHref}>Back to campaigns</Button>
			<Button onclick={() => void saveDraft()} loading={saving}>Save draft</Button>
		</div>
	</header>

	{#if saveError}
		<p class="journey__error" role="alert">{saveError}</p>
	{/if}

	<CampaignStepper current={step} />

	{#if step === 1}
		<CampaignGoalStep
			bind:name
			bind:goal
			errorMessage={nameError || goalError}
			onContinue={continueFromGoal}
		/>
	{:else if step === 2}
		<CampaignCustomersStep
			bind:customerGroupId
			groups={groupsQuery.data ?? []}
			isPending={groupsQuery.isPending}
			isError={groupsQuery.isError}
			errorMessage={customersError}
			onRetry={() => groupsQuery.refetch()}
			onBack={() => (step = 1)}
			onContinue={continueFromCustomers}
		/>
	{:else if step === 3}
		<CampaignEmailStep
			{content}
			campaignName={name}
			errorMessage={contentError}
			{catalogLabels}
			onAddBlock={addBlock}
			onMoveBlock={moveBlock}
			onRemoveBlock={removeBlock}
			onUploadImage={uploadCampaignImage}
			onDiscardOrphanedImage={discardOrphanedImage}
			onBack={() => (step = 2)}
			onContinue={() => (step = 4)}
		/>
	{:else if step === 4}
		<CampaignDeliveryStep
			{content}
			{customerGroupId}
			groups={groupsQuery.data ?? []}
			options={deliveryOptionsQuery.data ?? emptyMarketingDeliveryOptions}
			isPending={deliveryOptionsQuery.isPending}
			isError={deliveryOptionsQuery.isError}
			errorMessage={deliveryError}
			onRetry={() => deliveryOptionsQuery.refetch()}
			onBack={() => (step = 3)}
			onContinue={continueFromDelivery}
		/>
	{:else}
		<CampaignReviewStep
			{content}
			{campaignId}
			{name}
			{goal}
			{customerGroupId}
			groups={groupsQuery.data ?? []}
			options={deliveryOptionsQuery.data ?? emptyMarketingDeliveryOptions}
			isPending={deliveryOptionsQuery.isPending}
			isError={deliveryOptionsQuery.isError}
			onRetry={() => deliveryOptionsQuery.refetch()}
			onBack={() => (step = 4)}
			{onSend}
		/>
	{/if}
</div>

<style lang="scss">
	.journey {
		max-width: 1040px;
		margin-inline: auto;
		padding-block: var(--space-large);
		padding-inline: var(--space-base);
	}

	.journey__head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		flex-wrap: wrap;
		gap: var(--space-base);
		margin-bottom: var(--space-large);
	}

	.journey__eyebrow {
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
		color: var(--color-interactive);
		margin: 0;
	}

	.journey__head h1 {
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-largest);
		font-weight: 600;
		color: var(--color-heading);
		margin: var(--space-smaller) 0 0;
	}

	.journey__head-actions {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		flex-wrap: wrap;
	}

	.journey__save-state {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.journey__error {
		margin: 0 0 var(--space-base);
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
</style>
