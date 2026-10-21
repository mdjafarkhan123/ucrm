<script lang="ts">
	import { onMount } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import CustomerGroupRuleBuilder from './CustomerGroupRuleBuilder.svelte';
	import CustomerGroupPreview from './CustomerGroupPreview.svelte';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';
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

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title={mode === 'create' ? 'New customer group' : 'Edit customer group'}
	icon={usersIcon}
	iconTone="growth"
	size="large"
	initialFocusId="group-name"
	{onClose}
>
	<div class="group-dialog">
		<div class="group-dialog__form">
			{#if formError}
				<p class="group-dialog__error" role="alert">{@html alertIcon}<span>{formError}</span></p>
			{/if}

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
		</div>

		<div class="group-dialog__recipients">
			<CustomerGroupPreview {rules} variant="panel" />
		</div>
	</div>

	{#snippet footer()}
		<div class="group-dialog__actions">
			<Button variant="secondary" onclick={onClose} disabled={saving}>Cancel</Button>
			<Button onclick={save} loading={saving}
				>{mode === 'create' ? 'Save group' : 'Save changes'}</Button
			>
		</div>
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.group-dialog {
		display: flex;
		align-items: stretch;
		min-height: 100%;
		// The recipients panel runs the full height beside the form, so the body's own padding moves inside.
		margin: calc(var(--space-medium) * -1);

		&__form {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 20px;
			min-width: 0;
			padding: 20px;
		}

		&__identity {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__recipients {
			flex: 0 0 300px;
		}

		&__actions {
			display: flex;
			gap: var(--space-small);
		}

		&__error {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-small) var(--space-slim);
			border: var(--border-base) solid var(--color-critical--surface-edge);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: var(--typography--fontSize-label);

			:global(svg) {
				flex: 0 0 auto;
				width: 16px;
				height: 16px;
				color: var(--color-critical);
			}
		}
	}
</style>
