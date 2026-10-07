<script lang="ts">
	import { untrack } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { CalendarDate } from '@internationalized/date';
	import buildingIcon from '@tabler/icons/outline/building-store.svg?raw';
	import addressBookIcon from '@tabler/icons/outline/address-book.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import targetIcon from '@tabler/icons/outline/target.svg?raw';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import FormNotesCard from '$lib/components/forms/FormNotesCard.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { TRADES } from '$lib/settings/trades';
	import {
		LEAD_SOURCES,
		LEAD_SOURCE_LABELS,
		LEAD_STATUSES,
		LEAD_STATUS_LABELS,
		type LeadSource,
		type LeadStatus
	} from '$lib/jafar/leads';
	import LeadDuplicateWarning from './LeadDuplicateWarning.svelte';
	import LeadContactRows, {
		contactRow,
		filledRows,
		type ContactRow
	} from './LeadContactRows.svelte';
	import { jafarLeadsKey } from '$lib/jafar/query-keys';

	// Jafar business management B1: adding one Lead -- the business, every way to reach it with where each
	// was found, how Uplift came across it, why it may fit, and the next step. While it is typed, anything
	// already on file that looks like the same business is shown; saving is never blocked by it.
	let {
		onSaved,
		onCancel
	}: {
		onSaved: (lead: { id: string; business_name: string }, andAnother: boolean) => void;
		onCancel: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	type FormState = {
		business_name: string;
		country_code: string;
		trade: string;
		website: string;
		contact_name: string;
		contact_methods: ContactRow[];
		source: LeadSource | '';
		source_detail: string;
		lead_status: LeadStatus;
		fit_notes: string;
		next_action: string;
		next_action_due_on: CalendarDate | undefined;
	};

	function blankForm(): FormState {
		return {
			business_name: '',
			country_code: '',
			trade: '',
			website: '',
			contact_name: '',
			contact_methods: [contactRow({ kind: 'email', value: '', found_at: '' })],
			source: '',
			source_detail: '',
			lead_status: 'new',
			fit_notes: '',
			next_action: '',
			next_action_due_on: undefined
		};
	}

	let form = $state<FormState>(blankForm());
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);
	let layout = $state<RecordFormLayout>();

	function snapshot(values: FormState) {
		return JSON.stringify({
			...values,
			contact_methods: filledRows(values.contact_methods).map(({ kind, value, found_at }) => ({
				kind,
				value,
				found_at
			})),
			next_action_due_on: values.next_action_due_on?.toString() ?? ''
		});
	}
	let baseline = $state(untrack(() => snapshot(form)));
	const isDirty = $derived(snapshot(form) !== baseline);

	// --- Saving ---------------------------------------------------------------------------------------

	function payload() {
		return {
			business_name: form.business_name,
			country_code: form.country_code,
			trade: form.trade,
			website: form.website,
			contact_name: form.contact_name,
			contact_methods: filledRows(form.contact_methods).map(({ kind, value, found_at }) => ({
				kind,
				value,
				found_at
			})),
			source: form.source || undefined,
			source_detail: form.source_detail,
			lead_status: form.lead_status,
			fit_notes: form.fit_notes,
			next_action: form.next_action,
			next_action_due_on: form.next_action_due_on?.toString() ?? null
		};
	}

	// The server names a contact row by its place among the filled rows; the form keys rows by `key`.
	function rowError(key: number, field: 'value' | 'found_at') {
		const index = filledRows(form.contact_methods).findIndex((row) => row.key === key);
		return index === -1 ? '' : (fieldErrors[`contact_methods.${index}.${field}`] ?? '');
	}

	async function submit(andAnother: boolean) {
		if (saving || !isDirty) return;
		saving = true;
		fieldErrors = {};
		formError = '';
		try {
			const response = await fetch('/api/jafar/leads', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(payload())
			});
			const result = (await response.json()) as {
				id?: string;
				error?: string;
				field_errors?: Record<string, string>;
			};
			if (!response.ok || !result.id) {
				fieldErrors = result.field_errors ?? {};
				formError = result.error ?? 'The Lead could not be saved.';
				return;
			}
			const saved = { id: result.id, business_name: form.business_name.trim() };
			await queryClient.invalidateQueries({ queryKey: jafarLeadsKey });
			if (andAnother) {
				toast.success(`${saved.business_name} added`, 'Here is a fresh form.');
				form = blankForm();
			} else {
				toast.success(`${saved.business_name} added`);
			}
			baseline = snapshot(form);
			onSaved(saved, andAnother);
		} catch {
			formError = 'The Lead could not be saved. Check your connection and try again.';
		} finally {
			saving = false;
		}
	}

	const sourceOptions = LEAD_SOURCES.map((source) => ({
		value: source,
		label: LEAD_SOURCE_LABELS[source]
	}));
	const statusOptions = LEAD_STATUSES.map((status) => ({
		value: status,
		label: LEAD_STATUS_LABELS[status]
	}));
	const tradeSuggestions = TRADES.filter((trade) => trade !== 'Other');
</script>

<form
	class="lead-form"
	novalidate
	onsubmit={(event) => {
		event.preventDefault();
		void submit(false).finally(() => layout?.revealError());
	}}
>
	<RecordFormLayout title="New Lead" icon={targetIcon} bind:this={layout} error={formError}>
		{#snippet main()}
			<SectionBlock title="Business" icon={buildingIcon} variant="filled" form>
				<div class="lead-form__grid">
					<div class="lead-form__grid-full">
						<Input
							id="lead-business-name"
							label="Business name"
							required
							bind:value={form.business_name}
							invalid={Boolean(fieldErrors.business_name)}
							errorMessage={fieldErrors.business_name ?? ''}
							autocomplete="off"
						/>
					</div>
					<div class="lead-form__field">
						<CountryPicker
							id="lead-country"
							label="Country"
							required
							bind:value={form.country_code}
							invalid={Boolean(fieldErrors.country_code)}
							errorMessage={fieldErrors.country_code ?? ''}
						/>
					</div>
					<Input
						id="lead-trade"
						label="Trade"
						required
						bind:value={form.trade}
						invalid={Boolean(fieldErrors.trade)}
						errorMessage={fieldErrors.trade ?? ''}
						list="lead-trade-suggestions"
						autocomplete="off"
					/>
					<datalist id="lead-trade-suggestions">
						{#each tradeSuggestions as trade (trade)}<option value={trade}></option>{/each}
					</datalist>
					<div class="lead-form__grid-full">
						<Input
							id="lead-website"
							label="Website (optional)"
							type="url"
							inputmode="url"
							placeholder="smithplumbing.co.uk"
							bind:value={form.website}
							invalid={Boolean(fieldErrors.website)}
							errorMessage={fieldErrors.website ?? ''}
							autocomplete="off"
						/>
					</div>
				</div>

				<LeadDuplicateWarning
					businessName={form.business_name}
					countryCode={form.country_code}
					website={form.website}
					contacts={form.contact_methods}
				/>
			</SectionBlock>

			<SectionBlock
				title="Contact details"
				icon={addressBookIcon}
				hint="Only details you have checked yourself, with where each one came from."
				form
			>
				<div class="lead-form__grid">
					<div class="lead-form__grid-full">
						<Input
							id="lead-contact-name"
							label="Contact person (optional)"
							bind:value={form.contact_name}
							invalid={Boolean(fieldErrors.contact_name)}
							errorMessage={fieldErrors.contact_name ?? ''}
							autocomplete="off"
						/>
					</div>
				</div>

				<LeadContactRows
					bind:rows={form.contact_methods}
					idPrefix="lead-contact"
					errorFor={rowError}
				/>
				<p class="lead-form__hint">
					A business with no contact details can still be researched; it just cannot be contacted.
				</p>
			</SectionBlock>

			<SectionBlock
				title="Next action"
				icon={calendarIcon}
				hint="What happens next with this business, and by when."
				form
			>
				<div class="lead-form__grid">
					<Input
						id="lead-next-action"
						label="Next action"
						placeholder="Check their reviews"
						bind:value={form.next_action}
						invalid={Boolean(fieldErrors.next_action)}
						errorMessage={fieldErrors.next_action ?? ''}
						autocomplete="off"
					/>
					<CalendarPicker
						id="lead-next-action-due"
						label="Due"
						bind:value={form.next_action_due_on}
						invalid={Boolean(fieldErrors.next_action_due_on)}
						errorMessage={fieldErrors.next_action_due_on ?? ''}
					/>
				</div>
			</SectionBlock>
		{/snippet}

		{#snippet rail()}
			<RailCard title="Status">
				<Select
					id="lead-status"
					ariaLabel="Status"
					options={statusOptions}
					bind:value={form.lead_status}
				/>
			</RailCard>

			<RailCard title="How you found them">
				<div class="lead-form__rail-fields">
					<Select
						id="lead-source"
						ariaLabel="How you found them"
						placeholder="Choose a source"
						options={sourceOptions}
						bind:value={form.source}
					/>
					{#if fieldErrors.source}<p class="lead-form__error">{fieldErrors.source}</p>{/if}
					<Input
						id="lead-source-detail"
						label="Details (optional)"
						placeholder="Who referred them, which directory…"
						bind:value={form.source_detail}
						invalid={Boolean(fieldErrors.source_detail)}
						errorMessage={fieldErrors.source_detail ?? ''}
						autocomplete="off"
					/>
				</div>
			</RailCard>

			<FormNotesCard
				id="lead-fit-notes"
				title="Why they may fit"
				label="Reviews, team size, services, anything useful"
				maxlength={4000}
				bind:value={form.fit_notes}
				error={fieldErrors.fit_notes ?? ''}
			/>
		{/snippet}

		{#snippet actions()}
			<Button variant="tertiary" onclick={onCancel} disabled={saving}>Cancel</Button>
			<div class="lead-form__actions-primary">
				<Button
					variant="secondary"
					onclick={() => void submit(true).finally(() => layout?.revealError())}
					disabled={saving || !isDirty}
				>
					Save & add another
				</Button>
				<Button variant="primary" type="submit" loading={saving} disabled={!isDirty}>
					Save Lead
				</Button>
			</div>
		{/snippet}
	</RecordFormLayout>
</form>

<style lang="scss">
	.lead-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__grid {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__grid-full {
			grid-column: 1 / -1;
		}

		&__field,
		&__rail-fields {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__error {
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__actions-primary {
			display: flex;
			gap: var(--space-small);
		}
	}

	@media (max-width: 767px) {
		.lead-form__grid {
			grid-template-columns: 1fr;
		}

		.lead-form__actions-primary {
			flex-direction: column;
		}
	}
</style>
