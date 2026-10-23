<script lang="ts">
	import { onDestroy, untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import PaperworkFrame from '$lib/components/communications/paperwork/PaperworkFrame.svelte';
	import TollfreeBusinessStep from '$lib/components/communications/toll-free/TollfreeBusinessStep.svelte';
	import TollfreeTextingStep from '$lib/components/communications/toll-free/TollfreeTextingStep.svelte';
	import TollfreeProofStep from '$lib/components/communications/toll-free/TollfreeProofStep.svelte';
	import TollfreeCheckStep from '$lib/components/communications/toll-free/TollfreeCheckStep.svelte';
	import { TollfreeDraft } from '$lib/components/communications/toll-free/tollfree-draft.svelte';
	import {
		fetchTollfreeCheck,
		sendTollfreeCheck,
		startTollfreeCheck,
		tollfreeKey,
		type TollfreeDetail,
		type TollfreeRequestError
	} from '$lib/communications/sms-tollfree';
	import { numberReadinessKey } from '$lib/communications/number-readiness';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import phoneCallIcon from '@tabler/icons/outline/phone-call.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import listIcon from '@tabler/icons/outline/list.svg?raw';
	import cloudCheckIcon from '@tabler/icons/outline/cloud-check.svg?raw';
	import cloudUploadIcon from '@tabler/icons/outline/cloud-upload.svg?raw';
	import floppyIcon from '@tabler/icons/outline/device-floppy.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';

	// A toll-free number's carrier check (Stage 10 Part 4c, `concept.pen` board `SCpaW`): four steps saved as
	// they are typed, then sent through Twilio. Under review and approved are read-only; a turned-down check opens
	// its saved answers to fix and send again.
	const senderId = $derived(page.params.senderId ?? '');
	const queryClient = useQueryClient();
	const toast = getToastManager();
	const numbersHref = resolve('/(app)/settings/communications/sms');

	const query = createQuery(() => ({
		queryKey: tollfreeKey(senderId),
		queryFn: () => fetchTollfreeCheck(senderId),
		// Twilio answers the send in seconds; the page follows it until the check is under review.
		refetchInterval: (current: { state: { data: TollfreeDetail | undefined } }) =>
			current.state.data?.check?.status === 'sending' ? 4000 : false
	}));
	const detail = $derived(query.data);
	const check = $derived(detail?.check ?? null);

	let draft = $state<TollfreeDraft | null>(null);
	let step = $state(1);
	let fixing = $state(false);
	let continuing = $state(false);
	let sending = $state(false);
	let starting = $state(false);
	let startError = $state('');
	let sendError = $state('');
	let fieldErrors = $state<{ field: string; message: string }[]>([]);

	const editable = $derived(check?.status === 'draft' || (check?.status === 'needs_fix' && fixing));

	const STEPS = [
		{ title: 'Business', icon: buildingIcon, crumb: 'Business details' },
		{ title: 'Texting', icon: messageIcon, crumb: 'Texting' },
		{ title: 'Proof of consent', icon: photoIcon, crumb: 'Proof of consent' },
		{ title: 'Check and send', icon: sendIcon, crumb: 'Check and send' }
	];
	const STEP_HINTS: [string, string, string, string] = [
		'Review',
		'Next',
		'Add a picture',
		'Last step'
	];

	// The check starts the first time the page opens for this number, with the registration answers in it.
	$effect(() => {
		if (query.data && !query.data.check && !starting && !startError) untrack(() => void start());
	});

	// The draft starts from the first copy of the check; later copies only replace it when nothing is unsaved.
	$effect(() => {
		const data = query.data;
		if (!data?.check) return;
		untrack(() => {
			if (!draft || draft.senderId !== senderId) {
				draft?.dispose();
				draft = new TollfreeDraft(senderId, data, saved);
			} else if (
				!draft.dirty &&
				!draft.saving &&
				!draft.upload &&
				data.check!.revision > draft.revision
			)
				draft.load(data);
		});
	});

	$effect(() => {
		if (!draft?.dirty) return;
		const warn = (event: BeforeUnloadEvent) => event.preventDefault();
		window.addEventListener('beforeunload', warn);
		return () => window.removeEventListener('beforeunload', warn);
	});

	onDestroy(() => draft?.dispose());

	function saved(next: TollfreeDetail) {
		queryClient.setQueryData(tollfreeKey(senderId), next);
	}

	async function start() {
		starting = true;
		startError = '';
		try {
			saved(await startTollfreeCheck(senderId));
			void queryClient.invalidateQueries({ queryKey: numberReadinessKey });
		} catch (error) {
			startError = (error as Error).message;
		} finally {
			starting = false;
		}
	}

	async function reload() {
		draft?.dispose();
		draft = null;
		await query.refetch();
	}

	function goTo(next: number) {
		step = next;
		window.scrollTo({ top: 0 });
	}

	async function continueFrom(current: number) {
		if (!draft) return;
		continuing = true;
		try {
			if (await draft.save()) goTo(current + 1);
		} finally {
			continuing = false;
		}
	}

	// The server's answer paths, without the `business.` they are filed under, so each box finds its own.
	const errors = $derived(
		Object.fromEntries(
			fieldErrors.map((issue) => [issue.field.replace(/^business\./, ''), issue.message])
		)
	);
	const pictureError = $derived(
		fieldErrors.find((issue) => issue.field.startsWith('opt_in_image_urls'))?.message ?? ''
	);

	function stepOf(field: string) {
		if (field.startsWith('opt_in_image_urls')) return 3;
		return field.startsWith('business.messaging') ? 2 : 1;
	}

	async function send() {
		if (!draft || sending) return;
		sending = true;
		sendError = '';
		fieldErrors = [];
		try {
			if (!(await draft.save())) throw new Error(draft.error || 'Your changes could not be saved.');
			await sendTollfreeCheck(senderId, draft.revision);
			fixing = false;
			toast.success('Sent for review. The answer will show on this number.');
		} catch (error) {
			const refused = error as TollfreeRequestError;
			if (refused.code === 'stale') draft.stale = true;
			fieldErrors = refused.fieldErrors ?? [];
			sendError = refused.message || 'This check could not be sent. Try again.';
		} finally {
			await queryClient.invalidateQueries({ queryKey: tollfreeKey(senderId) });
			void queryClient.invalidateQueries({ queryKey: numberReadinessKey });
			sending = false;
		}
	}

	const sendProblems = $derived(
		fieldErrors.map((issue) => `${STEPS[stepOf(issue.field) - 1].title}: ${issue.message}`)
	);
	const fixBy = $derived(
		check?.edit_expires_at
			? new Date(check.edit_expires_at).toLocaleDateString(undefined, {
					month: 'short',
					day: 'numeric'
				})
			: null
	);
</script>

<svelte:head><title>Verify your toll-free number · Contractor CRM</title></svelte:head>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<PaperworkFrame
	section={{
		label: 'Toll-free check',
		href: resolve('/(app)/settings/communications/sms/toll-free/[senderId]', { senderId }),
		icon: phoneCallIcon
	}}
	crumb={editable ? STEPS[step - 1].crumb : (detail?.phone_number ?? 'Toll-free number')}
	title="Verify your toll-free number"
	description="Check the business details we already have, then show how customers agree to your texts."
	step={editable && draft ? step : null}
	stepNames={STEPS}
	stepHints={STEP_HINTS}
>
	{#snippet actions()}
		{#if editable && draft}
			{@const current = draft}
			<span
				class={['tollfree-save', (current.saving || current.dirty) && 'tollfree-save--unsaved']}
				role="status"
			>
				<span class="tollfree-save__icon" aria-hidden="true"
					>{@html current.saving || current.dirty ? cloudUploadIcon : cloudCheckIcon}</span
				>
				{#if current.saving}Saving…{:else if current.dirty}Unsaved changes{:else}All changes saved{/if}
			</span>
			<Button
				variant="secondary"
				loading={current.saving}
				disabled={sending || current.stale || Boolean(current.upload && !current.upload.problem)}
				onclick={() => void current.save()}
			>
				{#if !current.saving}<span aria-hidden="true">{@html floppyIcon}</span>{/if}
				Save draft
			</Button>
		{/if}
	{/snippet}

	{#if query.isPending || (detail && !check && !startError)}
		<LoadingSkeleton variant="card" rows={5} label="Loading your toll-free check" />
	{:else if query.isError || !detail}
		<ErrorState
			title="This check couldn’t load"
			description={(query.error as TollfreeRequestError | null)?.status === 404
				? 'This toll-free number wasn’t found. It may have been released.'
				: 'Your answers are safe. Try again in a minute.'}
			retry={() => query.refetch()}
		/>
	{:else if !check}
		<ErrorState title="This check couldn’t start" description={startError} retry={start} />
	{:else if check.status === 'sending'}
		<section class="tollfree-result" role="status">
			<IconTile icon={sendIcon} tone="informative" />
			<h2>Sending for review…</h2>
			<p>We are sending your answers to the phone company. This takes a few seconds.</p>
		</section>
	{:else if check.status === 'under_review' || check.status === 'approved'}
		{@const approved = check.status === 'approved'}
		<section class="tollfree-result">
			<IconTile icon={approved ? circleCheckIcon : sendIcon} tone="success" />
			<h2>{approved ? 'Approved for texting' : 'Sent for review'}</h2>
			<p>
				{approved
					? 'The phone company approved this number. It can text customers once texting is on.'
					: 'The number remains unable to text. We will show the result on its number card.'}
			</p>
			<Button href={numbersHref}>
				<span aria-hidden="true">{@html listIcon}</span>
				Back to numbers
			</Button>
		</section>
		{#if draft}
			<TollfreeCheckStep business={draft.business} pictures={draft.pictures} />
		{/if}
	{:else if check.status === 'needs_fix' && !fixing}
		<section class="tollfree-result tollfree-result--fix" role="alert">
			<IconTile icon={alertIcon} tone="critical" />
			<h2>The phone company asked for a change</h2>
			<p>
				{check.failure_reason ?? 'Check your business details and how customers agree.'} Your saved answers
				are here to fix and send again{fixBy ? ` by ${fixBy}` : ''}.
			</p>
			<Button
				onclick={() => {
					fixing = true;
					goTo(1);
				}}
			>
				<span aria-hidden="true">{@html pencilIcon}</span>
				Fix and send again
			</Button>
		</section>
	{:else if draft}
		{@const current = draft}
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
		{#if check.status === 'needs_fix' && check.failure_reason}
			<Banner type="warning">{check.failure_reason}</Banner>
		{/if}

		{#if step === 1}
			<TollfreeBusinessStep
				draft={current}
				registrationAddress={detail.registration_address}
				{errors}
				{continuing}
				backHref={numbersHref}
				onContinue={() => continueFrom(1)}
			/>
		{:else if step === 2}
			<TollfreeTextingStep
				draft={current}
				{errors}
				{continuing}
				onBack={() => goTo(1)}
				onContinue={() => continueFrom(2)}
			/>
		{:else if step === 3}
			<TollfreeProofStep
				draft={current}
				error={pictureError}
				{continuing}
				onBack={() => goTo(2)}
				onContinue={() => continueFrom(3)}
			/>
		{:else}
			<TollfreeCheckStep
				business={current.business}
				pictures={current.pictures}
				problems={sendProblems}
				{sendError}
				saving={current.saving && !sending}
				{sending}
				blocked={current.stale || Boolean(current.upload && !current.upload.problem)}
				onChange={goTo}
				onBack={() => goTo(3)}
				onSave={async () => {
					if (await current.save()) toast.success('Draft saved.');
				}}
				onSend={send}
			/>
		{/if}
	{/if}
</PaperworkFrame>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.tollfree-save {
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

			.tollfree-save--unsaved & {
				color: var(--color-warning--onSurface);
			}
		}
	}

	.tollfree-result {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-larger) var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		text-align: center;

		&--fix {
			border-color: var(--color-critical--surface);
		}

		h2 {
			margin: var(--space-smaller) 0 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
		}

		p {
			max-width: 460px;
			margin: 0 0 var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-large);
		}
	}
</style>
