<script lang="ts">
	import { untrack } from 'svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import { TRADES } from '$lib/settings/trades';
	import type { LeadDetail } from '$lib/jafar/lead-history';
	import LeadBlockEditor from './LeadBlockEditor.svelte';
	import LeadDuplicateWarning from './LeadDuplicateWarning.svelte';

	// Jafar business management B2b: the business itself -- name, country, trade, website and contact person --
	// edited in place at the top of the Lead page. Only what changed is sent.
	let {
		lead,
		saving = false,
		error = '',
		fieldErrors = {},
		onSave,
		onCancel
	}: {
		lead: LeadDetail;
		saving?: boolean;
		error?: string;
		fieldErrors?: Record<string, string>;
		onSave: (fields: Record<string, string>) => void;
		onCancel: () => void;
	} = $props();

	type Draft = {
		business_name: string;
		country_code: string;
		trade: string;
		website: string;
		contact_name: string;
	};

	function draftOf(source: LeadDetail): Draft {
		return {
			business_name: source.business_name,
			country_code: source.country_code,
			trade: source.trade,
			website: source.website ?? '',
			contact_name: source.contact_name ?? ''
		};
	}

	// Taken once on mount; the page mounts this fresh each time it opens.
	const saved = untrack(() => draftOf(lead));
	let draft = $state<Draft>({ ...saved });

	const changes = $derived(
		Object.fromEntries(
			(Object.keys(saved) as (keyof Draft)[])
				.filter((key) => draft[key].trim() !== saved[key])
				.map((key) => [key, draft[key]])
		)
	);

	const error_ = (key: keyof Draft) => fieldErrors[`fields.${key}`] ?? '';
	const tradeSuggestions = TRADES.filter((trade) => trade !== 'Other');
</script>

<LeadBlockEditor
	label="Edit business details"
	dirty={Object.keys(changes).length > 0}
	{saving}
	{error}
	onSave={() => onSave(changes)}
	{onCancel}
>
	<div class="lead-business-editor">
		<div class="lead-business-editor__full">
			<Input
				id="lead-edit-business-name"
				label="Business name"
				required
				bind:value={draft.business_name}
				invalid={Boolean(error_('business_name'))}
				errorMessage={error_('business_name')}
				autocomplete="off"
			/>
		</div>
		<div class="lead-business-editor__field">
			<CountryPicker
				id="lead-edit-country"
				label="Country"
				required
				bind:value={draft.country_code}
				invalid={Boolean(error_('country_code'))}
				errorMessage={error_('country_code')}
			/>
		</div>
		<Input
			id="lead-edit-trade"
			label="Trade"
			required
			bind:value={draft.trade}
			invalid={Boolean(error_('trade'))}
			errorMessage={error_('trade')}
			list="lead-edit-trade-suggestions"
			autocomplete="off"
		/>
		<datalist id="lead-edit-trade-suggestions">
			{#each tradeSuggestions as trade (trade)}<option value={trade}></option>{/each}
		</datalist>
		<Input
			id="lead-edit-website"
			label="Website (optional)"
			type="url"
			inputmode="url"
			placeholder="smithplumbing.co.uk"
			bind:value={draft.website}
			invalid={Boolean(error_('website'))}
			errorMessage={error_('website')}
			autocomplete="off"
		/>
		<Input
			id="lead-edit-contact-name"
			label="Contact person (optional)"
			bind:value={draft.contact_name}
			invalid={Boolean(error_('contact_name'))}
			errorMessage={error_('contact_name')}
			autocomplete="off"
		/>
	</div>

	<!-- Only what is being changed is checked: the Lead's existing name and website were checked when added. -->
	<LeadDuplicateWarning
		businessName={changes.business_name ?? ''}
		countryCode={draft.country_code}
		website={changes.website ?? ''}
		contacts={[]}
		excludeId={lead.id}
	/>
</LeadBlockEditor>

<style lang="scss">
	.lead-business-editor {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);

		&__full {
			grid-column: 1 / -1;
		}

		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}
	}

	@media (max-width: 767px) {
		.lead-business-editor {
			grid-template-columns: 1fr;
		}
	}
</style>
