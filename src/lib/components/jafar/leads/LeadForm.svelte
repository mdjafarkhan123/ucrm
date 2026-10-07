<script lang="ts">
	import { untrack } from 'svelte';
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { CalendarDate } from '@internationalized/date';
	import buildingIcon from '@tabler/icons/outline/building-store.svg?raw';
	import addressBookIcon from '@tabler/icons/outline/address-book.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import targetIcon from '@tabler/icons/outline/target.svg?raw';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import FormNotesCard from '$lib/components/forms/FormNotesCard.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { COUNTRIES } from '$lib/settings/countries';
	import { TRADES } from '$lib/settings/trades';
	import {
		CONTACT_METHOD_KINDS,
		CONTACT_METHOD_LABELS,
		LEAD_CONTACT_METHODS_MAX,
		LEAD_SOURCES,
		LEAD_SOURCE_LABELS,
		LEAD_STATUSES,
		LEAD_STATUS_LABELS,
		countryName,
		type ContactMethodKind,
		type LeadDuplicate,
		type LeadSource,
		type LeadStatus
	} from '$lib/jafar/leads';
	import { applicationHref } from '$lib/jafar/lead-history';
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

	type ContactRow = { key: number; kind: ContactMethodKind; value: string; found_at: string };
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

	let rowKey = 0;
	function blankRow(kind: ContactMethodKind = 'email'): ContactRow {
		rowKey += 1;
		return { key: rowKey, kind, value: '', found_at: '' };
	}

	function blankForm(): FormState {
		return {
			business_name: '',
			country_code: '',
			trade: '',
			website: '',
			contact_name: '',
			contact_methods: [blankRow()],
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

	// An empty contact row is the starting prompt, not a detail: it is left out when comparing and saving.
	function filledRows(rows: ContactRow[]) {
		return rows.filter((row) => row.value.trim() || row.found_at.trim());
	}

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

	function addRow() {
		if (form.contact_methods.length >= LEAD_CONTACT_METHODS_MAX) return;
		// A second detail is usually a phone after an email.
		const used = new Set(form.contact_methods.map((row) => row.kind));
		form.contact_methods.push(
			blankRow(used.has('email') && !used.has('phone') ? 'phone' : 'email')
		);
	}

	function removeRow(key: number) {
		form.contact_methods = form.contact_methods.filter((row) => row.key !== key);
	}

	// --- Possible duplicates --------------------------------------------------------------------------

	type Probe = {
		business_name: string;
		country_code: string;
		website: string;
		emails: string[];
		phones: string[];
	};
	let probe = $state<Probe>({
		business_name: '',
		country_code: '',
		website: '',
		emails: [],
		phones: []
	});

	// Waits for a pause in typing before asking, so a half-typed website does not fire a lookup per keystroke.
	$effect(() => {
		const name = form.business_name.trim();
		const next: Probe = {
			business_name: name.length >= 3 ? name : '',
			country_code: form.country_code,
			website: form.website.trim(),
			emails: form.contact_methods
				.filter((row) => row.kind === 'email' && row.value.includes('@'))
				.map((row) => row.value.trim()),
			phones: form.contact_methods
				.filter(
					(row) =>
						(row.kind === 'phone' || row.kind === 'whatsapp') &&
						row.value.replace(/\D/g, '').length >= 7
				)
				.map((row) => row.value.trim())
		};
		const handle = setTimeout(() => (probe = next), 500);
		return () => clearTimeout(handle);
	});

	const probeHasInput = $derived(
		Boolean(probe.business_name || probe.website || probe.emails.length || probe.phones.length)
	);

	const duplicates = createQuery(() => ({
		queryKey: [...jafarLeadsKey, 'duplicates', probe] as const,
		queryFn: async () => {
			const response = await fetch('/api/jafar/leads/duplicates', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(probe)
			});
			const result = (await response.json()) as { duplicates?: LeadDuplicate[]; error?: string };
			if (!response.ok) throw new Error(result.error ?? 'The duplicate check is unavailable.');
			return result.duplicates ?? [];
		},
		enabled: probeHasInput,
		staleTime: 30_000,
		gcTime: 60_000
	}));

	const duplicateList = $derived(probeHasInput ? (duplicates.data ?? []) : []);

	const MATCH_WORDS = { website: 'website', email: 'email', phone: 'phone', name: 'name' } as const;
	function matchSentence(match: LeadDuplicate) {
		const words = match.matched_on.map((field) => MATCH_WORDS[field]);
		return words.length > 1
			? `Same ${words.slice(0, -1).join(', ')} and ${words.at(-1)}`
			: `Same ${words[0]}`;
	}
	function kindLabel(match: LeadDuplicate) {
		if (match.kind === 'application') return 'Application';
		if (match.kind === 'organization') return 'Client';
		return 'Lead';
	}

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

	const countryOptions = COUNTRIES;
	const kindOptions = CONTACT_METHOD_KINDS.map((kind) => ({
		value: kind,
		label: CONTACT_METHOD_LABELS[kind]
	}));
	const sourceOptions = LEAD_SOURCES.map((source) => ({
		value: source,
		label: LEAD_SOURCE_LABELS[source]
	}));
	const statusOptions = LEAD_STATUSES.map((status) => ({
		value: status,
		label: LEAD_STATUS_LABELS[status]
	}));
	const tradeSuggestions = TRADES.filter((trade) => trade !== 'Other');

	const VALUE_LABELS: Record<ContactMethodKind, string> = {
		email: 'Email address',
		phone: 'Phone number, with country code',
		whatsapp: 'WhatsApp number, with country code',
		instagram: 'Instagram profile or @handle',
		facebook: 'Facebook page link',
		linkedin: 'LinkedIn profile link',
		contact_form: 'Contact form page link',
		other: 'Contact detail'
	};
	const VALUE_TYPES: Partial<Record<ContactMethodKind, string>> = {
		email: 'email',
		phone: 'tel',
		whatsapp: 'tel'
	};
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
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
						<Select
							id="lead-country"
							label="Country"
							placeholder="Choose the country"
							required
							options={countryOptions}
							bind:value={form.country_code}
						/>
						{#if fieldErrors.country_code}
							<p class="lead-form__error">{fieldErrors.country_code}</p>
						{/if}
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

				{#if duplicateList.length > 0}
					<div class="lead-form__duplicates" role="status">
						<p class="lead-form__duplicates-title">
							<span aria-hidden="true">{@html alertTriangleIcon}</span>
							{duplicateList.length === 1
								? 'This may already be on file'
								: `This may already be on file ${duplicateList.length} times`}
						</p>
						<ul>
							{#each duplicateList as match (match.kind + match.id)}
								<li>
									<span class="lead-form__duplicate-kind">{kindLabel(match)}</span>
									{#if match.kind === 'organization'}
										<a
											href={resolve('/jafar/(protected)/organizations/[organizationId]', {
												organizationId: match.id
											})}>{match.name}</a
										>
									{:else if match.kind === 'lead'}
										<a href={resolve('/jafar/(protected)/leads/[id]', { id: match.id })}
											>{match.name}</a
										>
									{:else}
										<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- applicationHref resolves the path. -->
										<a href={applicationHref(match.id)}>{match.name}</a>
									{/if}
									{#if match.country_code}<span>· {countryName(match.country_code)}</span>{/if}
									<span class="lead-form__duplicate-why">{matchSentence(match)}</span>
								</li>
							{/each}
						</ul>
						<p class="lead-form__duplicates-hint">
							Nothing is merged. Save anyway if this is a different business.
						</p>
					</div>
				{/if}
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

				{#each form.contact_methods as row, index (row.key)}
					<div class="lead-form__contact-row">
						<div class="lead-form__contact-kind">
							<Select
								id={`lead-contact-kind-${row.key}`}
								label="Type"
								options={kindOptions}
								bind:value={row.kind}
							/>
						</div>
						<Input
							id={`lead-contact-value-${row.key}`}
							label={VALUE_LABELS[row.kind]}
							type={VALUE_TYPES[row.kind] ?? 'text'}
							bind:value={row.value}
							invalid={Boolean(rowError(row.key, 'value'))}
							errorMessage={rowError(row.key, 'value')}
							autocomplete="off"
						/>
						<Input
							id={`lead-contact-found-${row.key}`}
							label="Where you found it"
							placeholder="Contact page of their website"
							bind:value={row.found_at}
							invalid={Boolean(rowError(row.key, 'found_at'))}
							errorMessage={rowError(row.key, 'found_at')}
							autocomplete="off"
						/>
						<button
							type="button"
							class="lead-form__remove"
							aria-label={`Remove contact detail ${index + 1}`}
							title="Remove"
							onclick={() => removeRow(row.key)}
						>
							<span aria-hidden="true">{@html trashIcon}</span>
						</button>
					</div>
				{/each}

				{#if form.contact_methods.length < LEAD_CONTACT_METHODS_MAX}
					<div>
						<Button type="button" variant="secondary" size="small" onclick={addRow}>
							<span class="lead-form__button-icon" aria-hidden="true">{@html plusIcon}</span>Add
							contact detail
						</Button>
					</div>
				{/if}
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

<!-- eslint-enable svelte/no-at-html-tags -->

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

		&__contact-row {
			display: grid;
			grid-template-columns: minmax(150px, 0.8fr) minmax(0, 1.3fr) minmax(0, 1.3fr) auto;
			align-items: start;
			gap: var(--space-small);
		}

		&__remove {
			display: grid;
			width: 44px;
			height: 44px;
			place-items: center;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: transparent;
			cursor: pointer;

			&:hover {
				color: var(--color-critical);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__button-icon {
			display: inline-flex;
			margin-right: var(--space-smaller);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__duplicates {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-warning);
			border-radius: var(--radius-base);
			background: var(--color-warning--surface);
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);

			ul {
				display: flex;
				flex-direction: column;
				gap: var(--space-smaller);
				margin: 0;
				padding: 0;
				list-style: none;
			}

			li {
				display: flex;
				flex-wrap: wrap;
				align-items: baseline;
				gap: var(--space-smaller) var(--space-small);
			}

			a {
				color: var(--color-interactive);
				font-weight: 700;
			}
		}

		&__duplicates-title {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;

			:global(svg) {
				display: block;
				width: 18px;
				height: 18px;
			}
		}

		&__duplicate-kind {
			padding: 0 var(--space-small);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: var(--color-text--secondary);
			font-weight: 600;
		}

		// Full-strength text: secondary grey is too faint on the warning tint.
		&__duplicate-why,
		&__duplicates-hint {
			color: var(--color-text);
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

		// On a phone each contact detail is its own small card: type and remove on one line, then the fields.
		.lead-form__contact-row {
			grid-template-columns: minmax(0, 1fr) auto;
			padding: var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);

			> :global(:not(.lead-form__contact-kind):not(.lead-form__remove)) {
				grid-column: 1 / -1;
			}
		}

		.lead-form__remove {
			grid-row: 1;
			grid-column: 2;
		}

		.lead-form__actions-primary {
			flex-direction: column;
		}
	}
</style>
