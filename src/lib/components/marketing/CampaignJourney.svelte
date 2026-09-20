<script lang="ts">
	import { onMount } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate, replaceState } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import CampaignStepper from './CampaignStepper.svelte';
	import CampaignGoalStep from './CampaignGoalStep.svelte';
	import CampaignCustomersStep from './CampaignCustomersStep.svelte';
	import CampaignEmailStep from './CampaignEmailStep.svelte';
	import CampaignDeliveryStep from './CampaignDeliveryStep.svelte';
	import CampaignComingSoonStep from './CampaignComingSoonStep.svelte';
	import {
		fetchCustomerGroups,
		fetchMarketingDeliveryOptions,
		emptyMarketingDeliveryOptions,
		createCampaignRequest,
		updateCampaignRequest,
		fetchRuleLabels,
		StaleCampaignError,
		marketingCampaignsKey,
		marketingCampaignKey,
		marketingCustomerGroupsKey,
		marketingDeliveryOptionsKey,
		type MarketingApiError,
		type RuleLabel
	} from '$lib/marketing/api';
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
	// (routes/marketing/campaigns/new). Step 5 (Review) is not built yet -- see CampaignComingSoonStep.
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
				return { id, type, url: '', alt: '' };
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
		<CampaignComingSoonStep onBack={() => (step = 4)} />
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
