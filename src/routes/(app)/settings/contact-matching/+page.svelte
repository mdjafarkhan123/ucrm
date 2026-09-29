<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchSettingsContactMatching,
		settingsContactMatchingKey,
		saveContactMatchingSettings,
		isSaveConflict,
		type ContactMatchPriority
	} from '$lib/settings/api';
	import usersGroupIcon from '@tabler/icons/outline/users-group.svg?raw';

	// Settings → Contact matching: HighLevel's Contact deduplication preference. When a website chat or form
	// arrives with a phone that belongs to one client and an email that belongs to another, this decides which
	// client it joins. Neither client is changed; two records that are really one person are merged by hand.

	const EXPLANATIONS: Record<ContactMatchPriority, string> = {
		email:
			'The chat or form goes to the client who has that email. The phone number is only used when the email matches nobody.',
		phone:
			'The chat or form goes to the client who has that phone number. The email is only used when the phone matches nobody.'
	};

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsContactMatchingKey,
		queryFn: fetchSettingsContactMatching
	}));

	let priority = $state<ContactMatchPriority | null>(null);
	let savedPriority = $state<ContactMatchPriority | null>(null);
	let saving = $state(false);
	let errorMessage = $state('');
	let conflict = $state<{ editor_name: string | null; edited_at: string | null } | null>(null);
	let layout = $state<RecordFormLayout>();

	// One place the form shows why a save did not land — a plain error, or someone else getting there first.
	const saveError = $derived(
		conflict
			? `${conflict.editor_name ?? 'Someone else'} just changed this. Refresh the page to see their version before saving yours.`
			: errorMessage
	);

	$effect(() => {
		const matching = query.data?.contact_matching;
		if (!matching) return;
		untrack(() => {
			if (priority !== null) return;
			priority = matching.priority;
			savedPriority = matching.priority;
		});
	});

	const dirty = $derived(priority !== null && savedPriority !== null && priority !== savedPriority);

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

	function cancel() {
		priority = savedPriority;
		conflict = null;
		errorMessage = '';
	}

	async function save() {
		if (!query.data || priority === null) return;
		saving = true;
		errorMessage = '';
		conflict = null;

		const result = await saveContactMatchingSettings({
			expected_revision: query.data.contact_matching.revision,
			priority
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

		savedPriority = priority;
		saving = false;
		toast.success('Contact matching saved.');
		await queryClient.invalidateQueries({ queryKey: settingsContactMatchingKey });
	}
</script>

<svelte:head><title>Contact matching · Settings · Contractor CRM</title></svelte:head>

{#if query.isPending || priority === null}
	<LoadingSkeleton variant="card" rows={2} />
{:else if query.isError}
	<ErrorState
		description="Contact matching settings could not be loaded."
		retry={() => query.refetch()}
	/>
{:else}
	{@const canEdit = query.data.permissions.edit}
	{@const editor = query.data.contact_matching.last_editor}

	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Contact matching' }]}
	/>

	<RecordFormLayout
		title="Contact matching"
		icon={usersGroupIcon}
		bind:this={layout}
		error={saveError}
	>
		{#snippet main()}
			{#if !canEdit}
				<p class="contact-matching__readonly">
					Only owners and administrators can change this. {#if editor}Last changed by {editor.name ??
							'a teammate'}.{/if}
				</p>
			{/if}

			{#if priority !== null}
				<SectionBlock
					title="When contact details point to two clients"
					hint="Sometimes a website chat or request form arrives with a phone number that belongs to one of your clients and an email that belongs to another. Choose which one wins."
					form
					level={3}
				>
					<SegmentedControl
						label="Match by"
						options={[
							{ value: 'email', label: 'Email first' },
							{ value: 'phone', label: 'Phone first' }
						]}
						bind:value={
							() => priority ?? 'email', (value) => (priority = value as ContactMatchPriority)
						}
						disabled={!canEdit}
					/>
					<p class="contact-matching__explanation">{EXPLANATIONS[priority]}</p>
					<p class="contact-matching__explanation">
						Neither client's details are changed. If the two clients are really the same person,
						merge them from either client's page.
					</p>
				</SectionBlock>
			{/if}
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
	.contact-matching {
		&__readonly {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
		}

		&__explanation {
			margin: var(--space-small) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
