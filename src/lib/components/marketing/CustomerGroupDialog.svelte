<script lang="ts">
	import { onMount } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import CustomerGroupRuleBuilder from './CustomerGroupRuleBuilder.svelte';
	import CustomerGroupPreview from './CustomerGroupPreview.svelte';
	import {
		createCustomerGroupRequest,
		updateCustomerGroupRequest,
		fetchRuleLabels,
		StaleGroupError,
		type MarketingApiError,
		type RuleLabel
	} from '$lib/marketing/api';
	import {
		emptyMarketingGroupRules,
		type MarketingCustomerGroup,
		type MarketingGroupRules
	} from '$lib/marketing/customer-groups';

	// Create and edit share one dialog: an existing group's name, description, and rules just seed the same
	// form a new group starts blank. Matches jobber-08's pattern 2 -- a different record than the page you're
	// standing on opens in a modal with its own footer and its own endpoint.
	let {
		open,
		group = null,
		onClose,
		onSaved
	}: {
		open: boolean;
		group?: MarketingCustomerGroup | null;
		onClose: () => void;
		onSaved: (group: MarketingCustomerGroup) => void;
	} = $props();

	const mode = $derived(group ? 'edit' : 'create');

	function cloneRules(rules: MarketingGroupRules): MarketingGroupRules {
		return JSON.parse(JSON.stringify(rules));
	}

	// Seeded once when the dialog mounts -- SvelteKit mounts a fresh instance each time it opens (the list
	// keys it by group id), so there is nothing to resync later.
	// svelte-ignore state_referenced_locally
	let name = $state(group?.name ?? '');
	// svelte-ignore state_referenced_locally
	let description = $state(group?.description ?? '');
	// svelte-ignore state_referenced_locally
	let rules = $state<MarketingGroupRules>(cloneRules(group?.rules ?? emptyMarketingGroupRules));

	let labels = $state<{ catalog_items: RuleLabel[]; clients: RuleLabel[] }>({
		catalog_items: [],
		clients: []
	});

	onMount(() => {
		const catalogItemIds = group?.rules.services ?? [];
		const clientIds = [
			...(group?.rules.include_client_ids ?? []),
			...(group?.rules.exclude_client_ids ?? [])
		];
		if (catalogItemIds.length === 0 && clientIds.length === 0) return;
		void fetchRuleLabels(catalogItemIds, clientIds).then((result) => {
			labels = result;
		});
	});

	let nameError = $state('');
	let formError = $state('');
	let saving = $state(false);

	async function save() {
		nameError = '';
		formError = '';
		const trimmedName = name.trim();
		if (!trimmedName) {
			nameError = 'Give this group a name.';
			return;
		}

		saving = true;
		try {
			const input = { name: trimmedName, description: description.trim() || undefined, rules };
			const saved = group
				? await updateCustomerGroupRequest(group.id, group.revision, input)
				: await createCustomerGroupRequest(input);
			onSaved(saved);
		} catch (error) {
			if (error instanceof StaleGroupError) {
				formError =
					'Someone else changed this group while it was open. Close and reopen it to see their version.';
			} else {
				const apiError = error as MarketingApiError;
				const fieldError = apiError.field_errors?.name;
				if (fieldError) nameError = fieldError;
				else formError = apiError.message || 'That customer group could not be saved.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<Dialog
	{open}
	title={mode === 'create' ? 'New customer group' : 'Edit customer group'}
	size="large"
	initialFocusId="group-name"
	{onClose}
>
	<div class="group-dialog">
		<div class="group-dialog__identity">
			<Input
				id="group-name"
				label="Name"
				required
				bind:value={name}
				invalid={Boolean(nameError)}
				errorMessage={nameError}
			/>
			<Textarea
				id="group-description"
				label="Description (optional)"
				rows={2}
				maxlength={500}
				bind:value={description}
			/>
		</div>

		<CustomerGroupRuleBuilder bind:rules {labels} />
		<CustomerGroupPreview {rules} />

		{#if formError}
			<p class="group-dialog__error" role="alert">{formError}</p>
		{/if}
	</div>

	<div class="group-dialog__actions">
		<Button variant="secondary" variation="subtle" onclick={onClose} disabled={saving}
			>Cancel</Button
		>
		<Button onclick={save} loading={saving}
			>{mode === 'create' ? 'Save group' : 'Save changes'}</Button
		>
	</div>
</Dialog>

<style lang="scss">
	.group-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__identity {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__error {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: var(--typography--fontSize-small);
		}
	}

	.group-dialog__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
	}
</style>
