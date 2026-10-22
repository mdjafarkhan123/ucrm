<script lang="ts">
	import { onDestroy, untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import PaperworkFrame from '$lib/components/communications/paperwork/PaperworkFrame.svelte';
	import PaperworkDetailsStep from '$lib/components/communications/paperwork/PaperworkDetailsStep.svelte';
	import PaperworkDocumentsStep from '$lib/components/communications/paperwork/PaperworkDocumentsStep.svelte';
	import PaperworkCheckStep from '$lib/components/communications/paperwork/PaperworkCheckStep.svelte';
	import PaperworkOpened from '$lib/components/communications/paperwork/PaperworkOpened.svelte';
	import { PaperworkDraft } from '$lib/components/communications/paperwork/paperwork-draft.svelte';
	import {
		countryName,
		kindName,
		kindWord,
		paperworkStatus,
		shortDate,
		withArticle
	} from '$lib/components/communications/paperwork/paperwork-ui';
	import {
		fetchPaperwork,
		fetchPaperworkList,
		paperworkKeys,
		paperworkProblems,
		sendPaperwork,
		type PaperworkDetail,
		type PaperworkFix,
		type PaperworkRequestError
	} from '$lib/communications/number-paperwork';
	import cloudCheckIcon from '@tabler/icons/outline/cloud-check.svg?raw';
	import cloudUploadIcon from '@tabler/icons/outline/cloud-upload.svg?raw';
	import deviceFloppyIcon from '@tabler/icons/outline/device-floppy.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import filesIcon from '@tabler/icons/outline/files.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';

	// One paperwork set (Stage 10 Part 3, `concept.pen` board `A0URqF`). A draft, or a set being fixed after
	// the phone company sent it back, is the step form (`?step=details|documents|check`); otherwise the set
	// opens on its status. The set's files and its review answer arrive on their own, so the page checks
	// again every few seconds while something is on its way.
	type Step = 'details' | 'documents' | 'check';
	const STEP_NUMBERS: Record<Step, number> = { details: 2, documents: 3, check: 4 };

	const queryClient = useQueryClient();
	const id = $derived(page.params.id ?? '');
	const stepParam = $derived(page.url.searchParams.get('step') as Step | null);

	let draft = $state<PaperworkDraft | null>(null);
	let tried = $state<Record<Step, boolean>>({ details: false, documents: false, check: false });
	let continuing = $state(false);
	let sending = $state(false);
	let sent = $state(false);
	let sendProblems = $state<PaperworkFix[]>([]);
	let sendError = $state('');

	function waiting(detail: PaperworkDetail | undefined): boolean {
		if (!detail) return false;
		return (
			detail.status === 'sending' ||
			detail.documents.some((document) => document.file?.state === 'checking')
		);
	}

	const query = createQuery(() => ({
		queryKey: paperworkKeys.detail(id),
		queryFn: () => fetchPaperwork(id),
		refetchInterval: (current: { state: { data: PaperworkDetail | undefined } }) =>
			waiting(current.state.data) ? 4000 : false
	}));
	const listQuery = createQuery(() => ({
		queryKey: paperworkKeys.list(),
		queryFn: () => fetchPaperworkList()
	}));

	const detail = $derived(query.data);
	const businessName = $derived(listQuery.data?.reused.business_name ?? '');
	const editable = $derived(
		detail?.status === 'draft' || (detail?.status === 'needs_fix' && stepParam !== null)
	);
	const step = $derived<Step>(stepParam && stepParam in STEP_NUMBERS ? stepParam : 'details');

	// The draft starts from the first copy of the set; later copies (a file finished its checks) flow into it
	// without touching what is being typed.
	$effect(() => {
		const data = query.data;
		if (!data) return;
		untrack(() => {
			if (!draft || draft.detail.id !== data.id) {
				draft?.dispose();
				draft = new PaperworkDraft(data, saved);
			} else draft.refresh(data);
		});
	});

	function saved(next: PaperworkDetail) {
		queryClient.setQueryData(paperworkKeys.detail(next.id), next);
		void queryClient.invalidateQueries({ queryKey: paperworkKeys.list() });
	}

	onDestroy(() => draft?.dispose());

	$effect(() => {
		if (!draft?.dirty) return;
		const warn = (event: BeforeUnloadEvent) => event.preventDefault();
		window.addEventListener('beforeunload', warn);
		return () => window.removeEventListener('beforeunload', warn);
	});

	// Everything still missing, from what is typed here and the files' states.
	const problems = $derived.by(() => {
		if (!draft) return [];
		const current = draft;
		return paperworkProblems(current.detail.form, {
			answers: current.answers,
			address: current.address,
			documentChoices: current.documentChoices,
			documents: current.detail.documents.map((document) => {
				const local = current.uploads[document.document_type];
				const serverState = document.file?.state ?? null;
				return {
					documentType: document.document_type,
					fields: current.documentFields[document.document_type] ?? document.fields,
					fileState:
						local && !local.problem
							? 'uploading'
							: serverState === 'uploading' || serverState === 'deleted'
								? null
								: serverState
				};
			})
		});
	});

	function shown(which: 'details' | 'documents'): PaperworkFix[] {
		if (tried[which]) return problems.filter((fix) => fix.step === which);
		if (detail?.status === 'needs_fix') return detail.fixes.filter((fix) => fix.step === which);
		return [];
	}

	function stepHref(next: Step | null): string {
		const base = resolve('/(app)/settings/communications/sms/paperwork/[id=uuid]', { id });
		return next ? `${base}?step=${next}` : base;
	}

	async function goToStep(next: Step | null) {
		await goto(stepHref(next), { noScroll: false });
		window.scrollTo({ top: 0 });
	}

	function revealFirstProblem(which: 'details' | 'documents') {
		const first = problems.find((fix) => fix.step === which);
		if (!first) return;
		requestAnimationFrame(() => {
			const target =
				which === 'details'
					? first.target === 'address'
						? (document.getElementById('paperwork-street') ??
							document.getElementById('paperwork-address'))
						: document.getElementById(`paperwork-${first.target}`)
					: document.querySelector<HTMLElement>(`.document-box--error`);
			target?.scrollIntoView({ behavior: 'smooth', block: 'center' });
			if (target instanceof HTMLInputElement) target.focus({ preventScroll: true });
		});
	}

	async function continueFrom(which: 'details' | 'documents') {
		if (!draft) return;
		tried = { ...tried, [which]: true };
		if (problems.some((fix) => fix.step === which)) return revealFirstProblem(which);
		continuing = true;
		const ok = await draft.save();
		continuing = false;
		if (ok) await goToStep(which === 'details' ? 'documents' : 'check');
	}

	async function send() {
		if (!draft) return;
		sending = true;
		sendProblems = [];
		sendError = '';
		try {
			if (!(await draft.save())) throw new Error(draft.error);
			const result = await sendPaperwork(id, draft.revision);
			saved(result);
			sent = true;
			window.scrollTo({ top: 0 });
		} catch (error) {
			const refused = error as PaperworkRequestError;
			sendProblems = refused.problems ?? [];
			sendError = refused.message || 'The paperwork could not be sent.';
		} finally {
			sending = false;
		}
	}

	async function reload() {
		const fresh = await query.refetch();
		if (fresh.data && draft) draft.load(fresh.data);
	}

	const title = $derived(
		detail
			? `${countryName(detail.country_code)} · ${kindWord(detail.number_type).replace(/^./, (c) => c.toUpperCase())} paperwork`
			: 'Paperwork'
	);
	const description = $derived.by(() => {
		if (!detail) return '';
		if (editable)
			return `The phone company checks this before you can buy ${withArticle(`${countryName(detail.country_code)} ${kindWord(detail.number_type)}`)} number.`;
		const owner = detail.end_user_type === 'business' ? 'Business' : 'Just me';
		return [
			owner,
			businessName,
			detail.submitted_at ? `sent ${shortDate(detail.submitted_at)}` : ''
		]
			.filter(Boolean)
			.join(' · ');
	});
	const documentsToAdd = $derived(
		problems.filter((fix) => fix.step === 'documents' && !fix.target.slice(9).includes(':')).length
	);
	const stepHints = $derived<[string, string, string, string]>([
		detail
			? `${detail.country_code} · ${kindName(detail.number_type).replace(' numbers', '')}`
			: '',
		'Who you are',
		!detail?.form.requirements.some((requirement) =>
			requirement.kinds.some((kind) => kind.needsFile)
		)
			? 'Address only'
			: documentsToAdd
				? `${documentsToAdd} to add`
				: 'All added',
		'Last step'
	]);
</script>

<svelte:head><title>{title} · Contractor CRM</title></svelte:head>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
{#if query.isPending}
	<PaperworkFrame crumb="Paperwork" title="Paperwork" step={null}>
		<LoadingSkeleton variant="card" rows={5} label="Loading the paperwork" />
	</PaperworkFrame>
{:else if query.isError || !detail || !draft}
	<PaperworkFrame crumb="Paperwork" title="Paperwork" step={null}>
		<ErrorState
			title="This paperwork couldn’t load"
			description={(query.error as PaperworkRequestError | null)?.status === 404
				? 'It may have been deleted. Your other paperwork is safe.'
				: 'We couldn’t reach the phone company just now. Your paperwork is safe.'}
			retry={() => query.refetch()}
		/>
	</PaperworkFrame>
{:else if sent}
	<PaperworkFrame
		crumb={title.replace(' paperwork', '')}
		{title}
		flag={detail.country_code}
		step={null}
	>
		<section class="paperwork-sent" aria-labelledby="paperwork-sent-title">
			<IconTile icon={sendIcon} tone="success" />
			<h2 id="paperwork-sent-title">Sent for review</h2>
			<p>
				The phone company usually answers within 1 to 5 business days. The answer shows on Number
				paperwork.
			</p>
			<Button href={resolve('/(app)/settings/communications/sms/paperwork')}>
				<span aria-hidden="true">{@html filesIcon}</span>
				Back to paperwork
			</Button>
		</section>
	</PaperworkFrame>
{:else if editable}
	{@const current = draft}
	<PaperworkFrame
		crumb={detail.status === 'draft' ? 'New paperwork' : 'Fix and send again'}
		{title}
		{description}
		step={STEP_NUMBERS[step]}
		{stepHints}
	>
		{#snippet actions()}
			<span
				class={['paperwork-save', (current.saving || current.dirty) && 'paperwork-save--unsaved']}
				role="status"
			>
				<span class="paperwork-save__icon" aria-hidden="true"
					>{@html current.saving || current.dirty ? cloudUploadIcon : cloudCheckIcon}</span
				>
				{#if current.saving}Saving…{:else if current.dirty}Unsaved changes{:else}All changes saved{/if}
			</span>
			<Button
				variant="secondary"
				loading={current.saving}
				disabled={current.stale}
				onclick={() => void current.save()}
			>
				{#if !current.saving}<span aria-hidden="true">{@html deviceFloppyIcon}</span>{/if}
				Save draft
			</Button>
		{/snippet}

		{#if current.error}
			<Banner type="error">
				{current.error}
				{#snippet action()}
					{#if current.stale}
						<Button variant="secondary" size="small" onclick={reload}>
							<span aria-hidden="true">{@html refreshIcon}</span>
							Reload
						</Button>
					{/if}
				{/snippet}
			</Banner>
		{/if}

		{#if step === 'details'}
			<PaperworkDetailsStep
				draft={current}
				registrationAddress={listQuery.data?.reused.address_parts ?? null}
				problems={shown('details')}
				locked={Boolean(detail.status === 'needs_fix')}
				{continuing}
				onBack={() =>
					detail.status === 'needs_fix'
						? goToStep(null)
						: goto(resolve('/(app)/settings/communications/sms/paperwork'))}
				onContinue={() => continueFrom('details')}
			/>
		{:else if step === 'documents'}
			<PaperworkDocumentsStep
				draft={current}
				problems={shown('documents')}
				{continuing}
				uploaded={() => query.refetch()}
				onBack={() => goToStep('details')}
				onContinue={() => continueFrom('documents')}
			/>
		{:else}
			<PaperworkCheckStep
				detail={{
					...current.detail,
					answers: current.answers,
					address: current.address,
					document_choices: current.documentChoices,
					end_user_type: current.endUserType
				}}
				{businessName}
				problems={sendProblems}
				{sendError}
				{sending}
				onChange={(next) => goToStep(next)}
				onBack={() => goToStep('documents')}
				onSend={send}
			/>
		{/if}
	</PaperworkFrame>
{:else}
	{@const status = paperworkStatus(detail.status)}
	<PaperworkFrame
		crumb={title.replace(' paperwork', '')}
		{title}
		{description}
		flag={detail.country_code}
		step={null}
	>
		{#snippet actions()}
			<StatusBadge status={status.tone} size="large">{status.label}</StatusBadge>
		{/snippet}
		<PaperworkOpened {detail} {businessName} onFix={(next) => goToStep(next)} />
	</PaperworkFrame>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.paperwork-save {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 500;
		white-space: nowrap;

		&__icon {
			display: inline-flex;
			color: var(--color-success);

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			.paperwork-save--unsaved & {
				color: var(--color-warning--onSurface);
			}
		}
	}

	.paperwork-sent {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-larger) var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		text-align: center;

		h2 {
			margin: var(--space-smaller) 0 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
		}

		p {
			max-width: 420px;
			margin: 0 0 var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-large);
		}
	}
</style>
