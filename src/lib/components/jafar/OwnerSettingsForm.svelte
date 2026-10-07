<script lang="ts" module>
	import type { OwnerSettings } from '$lib/jafar/owner-settings';

	export type OwnerSettingsDraft = Omit<OwnerSettings, 'updated_at'>;
</script>

<script lang="ts">
	import type { Snippet } from 'svelte';
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { jafarSettingsKey } from '$lib/jafar/query-keys';
	import {
		fetchOwnerSettings,
		saveOwnerSettings,
		OwnerSettingsSaveError,
		type OwnerSettingsField,
		type OwnerSettingsResponse
	} from '$lib/jafar/owner-settings';

	// One focused Settings section of the Jafar Panel: it edits only `fields`, explains what the change
	// affects beside the form, and writes nothing until Save is pressed. The other sections' values are
	// left alone on the server, so two sections can never overwrite each other.
	let {
		title,
		icon,
		fields,
		about,
		children
	}: {
		title: string;
		icon: string;
		fields: OwnerSettingsField[];
		/** Where the saved value shows up, in plain words, for the side panel. */
		about: Snippet;
		children: Snippet<[OwnerSettingsDraft, Record<string, string>]>;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({ queryKey: jafarSettingsKey, queryFn: fetchOwnerSettings }));

	let draft = $state<OwnerSettingsDraft | null>(null);
	let saved = $state('');
	let saving = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let layout = $state<RecordFormLayout>();

	// Blank alert-recipient rows are a typing aid, not a value, so they never count as a change.
	function picked(source: OwnerSettingsDraft) {
		return Object.fromEntries(
			fields.map((field) => {
				const value = source[field];
				return [
					field,
					Array.isArray(value) ? value.map((item) => item.trim()).filter(Boolean) : value
				];
			})
		) as Partial<OwnerSettingsDraft>;
	}

	function load(settings: OwnerSettings) {
		const { updated_at: _updatedAt, ...values } = settings;
		draft = {
			...values,
			alert_recipient_emails: values.alert_recipient_emails.length
				? [...values.alert_recipient_emails]
				: ['']
		};
		saved = JSON.stringify(picked(draft));
	}

	$effect(() => {
		const settings = query.data?.settings;
		if (settings) untrack(() => draft === null && load(settings));
	});

	const dirty = $derived(draft !== null && JSON.stringify(picked(draft)) !== saved);

	beforeNavigate((navigation) => {
		if (!dirty) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});
	$effect(() => {
		function handler(event: BeforeUnloadEvent) {
			if (dirty) event.preventDefault();
		}
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	function cancel() {
		if (query.data) load(query.data.settings);
		formError = '';
		fieldErrors = {};
	}

	async function save() {
		if (!draft || !dirty) return;
		saving = true;
		formError = '';
		fieldErrors = {};
		try {
			const settings = await saveOwnerSettings(picked(draft));
			queryClient.setQueryData<OwnerSettingsResponse>(jafarSettingsKey, (current) =>
				current ? { ...current, settings } : current
			);
			load(settings);
			toast.success(`${title} saved.`);
			void queryClient.invalidateQueries({ queryKey: jafarSettingsKey, exact: true });
		} catch (error) {
			formError = error instanceof Error ? error.message : 'Settings could not be saved.';
			if (error instanceof OwnerSettingsSaveError) fieldErrors = error.fieldErrors;
		} finally {
			saving = false;
		}
	}

	function formatDate(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}
</script>

<svelte:head><title>{title} · Settings · Control Room</title></svelte:head>

<Breadcrumbs items={[{ label: 'Settings', href: resolve('/jafar/settings') }, { label: title }]} />

{#if query.isError && !query.data}
	<ErrorState
		title="Settings could not be loaded"
		description={query.error.message}
		retry={() => query.refetch()}
	/>
{:else if !draft}
	<LoadingSkeleton variant="card" rows={2} label="Loading settings" />
{:else}
	<RecordFormLayout {title} {icon} bind:this={layout} error={formError}>
		{#snippet main()}
			<form
				class="owner-settings-form"
				novalidate
				onsubmit={(event) => {
					event.preventDefault();
					void save().finally(() => layout?.revealError());
				}}
			>
				{@render children(draft!, fieldErrors)}
				<button type="submit" hidden aria-hidden="true" tabindex="-1"></button>
			</form>
		{/snippet}

		{#snippet rail()}
			<Card heading="What this changes">
				<div class="owner-settings-form__about">
					{@render about()}
					{#if query.data}
						<p class="owner-settings-form__saved">
							Last saved {formatDate(query.data.settings.updated_at)}
						</p>
					{/if}
				</div>
			</Card>
		{/snippet}

		{#snippet actions()}
			<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
			<Button
				onclick={() => void save().finally(() => layout?.revealError())}
				disabled={!dirty || saving}
				loading={saving}>Save</Button
			>
		{/snippet}
	</RecordFormLayout>
{/if}

<style lang="scss">
	.owner-settings-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.owner-settings-form__about {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);

		:global(p) {
			margin: 0;
		}
	}

	.owner-settings-form__saved {
		padding-top: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
	}
</style>
