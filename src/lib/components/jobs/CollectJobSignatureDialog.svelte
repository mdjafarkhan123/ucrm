<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import SignaturePad from '$lib/components/ui/SignaturePad.svelte';
	import { emptySignature } from '$lib/signatures/signature';
	import {
		SIGNATURE_STATEMENT_MAX,
		SIGNER_ROLE_MAX,
		type JobSignatureType
	} from '$lib/signatures/types';
	import type { JobLineItem, JobVisit } from '$lib/jobs/api';
	import { untrack } from 'svelte';

	// The crew holds the tablet out at the customer's door and the customer signs off on the work — either
	// authorising it before it starts or confirming it once it is done. Housecall Pro's model, not Jobber's:
	// the signature is its own record with a type on it, and it is bound to the priced job document exactly
	// as it reads on this screen right now.
	//
	// This dialog only shows what is about to be frozen. The freezing itself happens in the database, off
	// the job's own rows, so nothing shown here can talk the server into signing something different.
	//
	// No "send the client a copy" here. That is customer delivery, which Part 15e owns.

	let {
		open,
		clientName,
		lines,
		visits,
		totalMinor,
		currencyCode,
		locale,
		saving = false,
		onClose,
		onCollect
	}: {
		open: boolean;
		/** Pre-fills the name, because the person signing is almost always the client. */
		clientName: string | null;
		lines: JobLineItem[];
		visits: JobVisit[];
		/** Null when this person may not see the job's prices — the preview then shows work without money. */
		totalMinor: number | null;
		currencyCode: string;
		locale: string;
		saving?: boolean;
		onClose: () => void;
		onCollect: (input: {
			signature_type: JobSignatureType;
			signer_name: string;
			signer_role: string | null;
			statement: string;
			method: 'typed' | 'drawn';
			image?: string;
			visit_id: string | null;
		}) => Promise<void>;
	} = $props();

	// Fixed three, not a configurable library: the same set Housecall Pro settled on. Each carries the
	// sentence that sits above the signature line, which the collector can still rewrite for the job in
	// front of them.
	const SIGNATURE_TYPES: { value: JobSignatureType; label: string; statement: string }[] = [
		{
			value: 'work_authorization',
			label: 'Work authorization',
			statement: 'I authorize the work described above to proceed.'
		},
		{
			value: 'work_completion',
			label: 'Work completion',
			statement: 'I confirm the work described above has been completed to my satisfaction.'
		},
		{ value: 'other', label: 'Other', statement: '' }
	];

	// The dialog is mounted only while it is open, so every field starts fresh here rather than being reset
	// by an effect later, and the pad opens blank each time.
	let signatureType = $state<JobSignatureType>('work_completion');
	let statement = $state(
		SIGNATURE_TYPES.find((type) => type.value === 'work_completion')!.statement
	);
	let statementEdited = $state(false);
	let signerRole = $state('');
	let visitId = $state('');
	let signature = $state({ ...emptySignature(), name: untrack(() => clientName) ?? '' });
	let problem = $state('');

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const visitDateFormat = $derived(
		new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric', year: 'numeric' })
	);

	const typeOptions = SIGNATURE_TYPES.map((type) => ({ value: type.value, label: type.label }));

	// "Which visit were you on?" is context, not a requirement — a signature belongs to the job. Only
	// scheduled visits can be named; an unscheduled one has no date to pick it out by.
	const visitOptions = $derived([
		{ value: '', label: 'Not tied to a visit' },
		...visits
			.filter((visit) => visit.visit_date)
			.map((visit) => ({
				value: visit.id,
				label: `${visitDateFormat.format(new Date(`${visit.visit_date}T00:00:00`))}${visit.title ? ` · ${visit.title}` : ''}`
			}))
	]);

	// Switching type rewrites the sentence, unless the collector has already written their own — theirs is
	// the one that was meant.
	function chooseType(next: string) {
		signatureType = next as JobSignatureType;
		if (statementEdited) return;
		statement = SIGNATURE_TYPES.find((type) => type.value === signatureType)?.statement ?? '';
	}

	async function submit() {
		if (saving) return;
		const name = signature.name.trim();
		if (!name) {
			problem = 'Type the name of the person signing.';
			return;
		}
		if (!statement.trim()) {
			problem = 'Write what this signature is agreeing to.';
			return;
		}
		if (signature.method === 'drawn' && !signature.image) {
			problem = 'Ask them to sign, or switch to typing the name.';
			return;
		}

		problem = '';
		try {
			await onCollect({
				signature_type: signatureType,
				signer_name: name,
				signer_role: signerRole.trim() || null,
				statement: statement.trim(),
				method: signature.method,
				image: signature.image ?? undefined,
				visit_id: visitId || null
			});
			onClose();
		} catch (error) {
			problem = error instanceof Error ? error.message : 'That signature could not be recorded.';
		}
	}
</script>

<Dialog {open} title="Collect signature" onClose={() => onClose()}>
	<div class="collect-job-signature">
		<p class="collect-job-signature__lead">
			This saves a copy of the job exactly as it reads right now. Later changes to the work or the
			price cannot rewrite what was signed.
		</p>

		<Select
			id="job-signature-type"
			label="What is being signed"
			options={typeOptions}
			value={signatureType}
			disabled={saving}
			onchange={chooseType}
		/>

		<section class="collect-job-signature__document">
			<h3 class="collect-job-signature__document-title">What they are signing</h3>
			{#if lines.length === 0}
				<p class="collect-job-signature__empty">This job has no work listed on it yet.</p>
			{:else}
				<ul class="collect-job-signature__lines">
					{#each lines as line (line.id)}
						<li class="collect-job-signature__line">
							<span class="collect-job-signature__line-name">
								{line.name}
								{#if (line.quantity ?? 0) !== 1}
									<span class="collect-job-signature__line-quantity">
										× {line.quantity ?? 0}{line.unit_label ? ` ${line.unit_label}` : ''}
									</span>
								{/if}
							</span>
							{#if totalMinor !== null}
								<span class="collect-job-signature__line-amount">
									{money.format((line.line_total_minor ?? 0) / 100)}
								</span>
							{/if}
						</li>
					{/each}
				</ul>
			{/if}
			{#if totalMinor !== null}
				<p class="collect-job-signature__total">
					<span>Total</span>
					<span>{money.format(totalMinor / 100)}</span>
				</p>
			{/if}
		</section>

		<Textarea
			id="job-signature-statement"
			label="They are agreeing to"
			bind:value={statement}
			rows={2}
			maxlength={SIGNATURE_STATEMENT_MAX}
			disabled={saving}
			oninput={() => (statementEdited = true)}
		/>

		<SignaturePad bind:value={signature} idPrefix="job-signature" disabled={saving} />

		<div class="collect-job-signature__fields">
			<Input
				id="job-signature-role"
				label="Their role (optional)"
				bind:value={signerRole}
				maxlength={SIGNER_ROLE_MAX}
				placeholder="Homeowner"
				disabled={saving}
			/>
			{#if visitOptions.length > 1}
				<Select
					id="job-signature-visit"
					label="Visit (optional)"
					options={visitOptions}
					bind:value={visitId}
					disabled={saving}
				/>
			{/if}
		</div>

		{#if problem}
			<p class="collect-job-signature__problem" role="alert">{problem}</p>
		{/if}

		<footer class="collect-job-signature__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={() => onClose()}>
				Cancel
			</Button>
			<Button variant="primary" loading={saving} onclick={() => void submit()}
				>Save signature</Button
			>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	.collect-job-signature {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__lead {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}

		// The frozen document, shown the way it will be read back later: work first, money last.
		&__document {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__document-title {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-transform: uppercase;
			letter-spacing: 0.04em;
		}

		&__lines {
			display: grid;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__line {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__line-name {
			min-width: 0;
			color: var(--color-text);
		}

		&__line-quantity {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__line-amount {
			flex: 0 0 auto;
			font-variant-numeric: tabular-nums;
		}

		&__total {
			display: flex;
			justify-content: space-between;
			gap: var(--space-small);
			margin: 0;
			padding-top: var(--space-small);
			border-top: var(--border-base) solid var(--color-border);
			color: var(--color-heading);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}

		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__fields {
			display: grid;
			gap: var(--space-base);
			grid-template-columns: 1fr;

			@media (min-width: 640px) {
				grid-template-columns: 1fr 1fr;
			}
		}

		&__problem {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-base);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
