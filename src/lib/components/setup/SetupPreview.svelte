<script lang="ts">
	import { untrack } from 'svelte';
	import { beforeNavigate } from '$app/navigation';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import presentationIcon from '@tabler/icons/outline/presentation.svg?raw';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import PreviewCardBody from './PreviewCardBody.svelte';
	import PreviewScreenshots from './PreviewScreenshots.svelte';
	import {
		fetchSetupPreview,
		saveSetupPreviewNote,
		sendSetupPreviewNotes,
		setupPreviewKey,
		setupPreviewScreenshotUrls as urls,
		setupSummaryKey
	} from '$lib/setup/api';
	import {
		PREVIEW_CHOICE_LABEL,
		PREVIEW_KIND_LABEL,
		PREVIEW_NOTE_MAX,
		PREVIEW_NOTE_PROMPT,
		previewChoices,
		type PreviewChoice,
		type PreviewKind,
		type PreviewNote,
		type PreviewScreenshotUpload,
		type PreviewVersion
	} from '$lib/setup/preview';

	// Client onboarding E3 (plan §6): the preview Uplift released, card by card. The client marks each card Looks
	// right or Needs a change with a note; notes save as drafts while they work, and one Send sends them all, once.
	// That send uses their one correction round; on a later preview a card can only report an Uplift mistake
	// (always fixed free) or ask for something new, which Uplift treats as a separate request. Industry reference:
	// Filestage and Ziflow proofing — a decision per item, then one Submit. The preview email links here (#preview).
	let { userId }: { userId: string | null } = $props();

	const queryClient = useQueryClient();
	const query = createQuery(() => ({
		queryKey: setupPreviewKey(userId),
		queryFn: fetchSetupPreview
	}));

	const current = $derived(query.data?.versions[0] ?? null);
	const older = $derived(query.data?.versions.slice(1) ?? []);
	const sent = $derived(Boolean(current?.notes_sent_at));

	type Draft = {
		choice: PreviewChoice | null;
		note: string;
		screenshots: PreviewScreenshotUpload[];
		state: 'idle' | 'saving' | 'saved' | 'error';
		error: string;
		uploading: boolean;
	};

	/** The client's work on the version shown, card by card. Loaded once per version so a refetch never
	 *  overwrites a note being typed. */
	let drafts = $state<Record<string, Draft>>({});
	let draftsFor = $state<number | null>(null);

	$effect(() => {
		const version = current;
		if (!version) return;
		untrack(() => {
			if (draftsFor === version.version) return;
			draftsFor = version.version;
			drafts = Object.fromEntries(
				version.cards.map((card) => {
					const saved = version.notes.find((note) => note.card_id === card.id);
					return [
						card.id,
						{
							choice: saved?.choice ?? null,
							note: saved?.note ?? '',
							screenshots: saved?.screenshots ?? [],
							state: 'idle',
							error: '',
							uploading: false
						} satisfies Draft
					];
				})
			);
		});
	});

	/** What the database holds for a card, so a save is sent only when something changed. */
	const savedNote = (cardId: string): PreviewNote | undefined =>
		current?.notes.find((note) => note.card_id === cardId);

	// One card's saves run one after another, so an older note can never land after a newer one.
	const saving: Record<string, Promise<void>> = {};
	const timers: Record<string, ReturnType<typeof setTimeout>> = {};

	function save(cardId: string, options: { keepalive?: boolean } = {}): Promise<void> {
		clearTimeout(timers[cardId]);
		const next = (saving[cardId] ?? Promise.resolve())
			.catch(() => {})
			.then(() => write(cardId, options));
		saving[cardId] = next;
		return next;
	}

	// Typing waits for a pause before saving, as the setup sections do, so a note is kept without leaving the box.
	function typed(cardId: string) {
		clearTimeout(timers[cardId]);
		timers[cardId] = setTimeout(() => void save(cardId), 900);
	}

	// Leaving the page — or a phone putting it in the background — sends whatever is still waiting.
	function saveAll() {
		for (const cardId of Object.keys(drafts)) void save(cardId, { keepalive: true });
	}
	beforeNavigate(saveAll);
	$effect(() => {
		const onHide = () => {
			if (document.visibilityState === 'hidden') saveAll();
		};
		document.addEventListener('visibilitychange', onHide);
		return () => {
			document.removeEventListener('visibilitychange', onHide);
			for (const timer of Object.values(timers)) clearTimeout(timer);
		};
	});

	async function write(cardId: string, options: { keepalive?: boolean }) {
		const version = current;
		const draft = drafts[cardId];
		if (!version || !draft || sent) return;
		const note = draft.note.trim();
		// A change without words yet is not ready to keep; the box asks for them.
		if (draft.choice && draft.choice !== 'looks_right' && !note) return;
		const saved = savedNote(cardId);
		if (
			saved?.choice === draft.choice &&
			(saved?.note ?? '') === (draft.choice === 'looks_right' ? '' : note) &&
			JSON.stringify(saved?.screenshots ?? []) === JSON.stringify(draft.screenshots)
		)
			return;
		if (!saved && draft.choice === null) return;

		draft.state = 'saving';
		draft.error = '';
		try {
			const result = await saveSetupPreviewNote(
				{
					version: version.version,
					card_id: cardId,
					choice: draft.choice,
					note: draft.choice === 'looks_right' ? null : note || null,
					screenshots: draft.choice === 'looks_right' ? [] : draft.screenshots
				},
				options
			);
			draft.state = 'saved';
			if (result.status === 'already_sent')
				draft.error = 'Your team already sent the notes on this preview.';
		} catch (error) {
			draft.state = 'error';
			draft.error = error instanceof Error ? error.message : 'Your note could not be saved.';
		}
		await queryClient.invalidateQueries({ queryKey: setupPreviewKey(userId) });
	}

	function choose(cardId: string, choice: PreviewChoice) {
		const draft = drafts[cardId];
		if (!draft) return;
		draft.choice = choice;
		void save(cardId);
	}

	const asking = $derived(
		current
			? current.cards.filter((card) => {
					const draft = drafts[card.id];
					return draft?.choice && draft.choice !== 'looks_right' && draft.note.trim();
				}).length
			: 0
	);
	const unanswered = $derived(
		current ? current.cards.filter((card) => !drafts[card.id]?.choice).length : 0
	);
	const busy = $derived(
		Object.values(drafts).some((draft) => draft.state === 'saving' || draft.uploading)
	);
	const unsaved = $derived(
		current
			? current.cards.some((card) => {
					const draft = drafts[card.id];
					const saved = savedNote(card.id);
					if (!draft?.choice || draft.choice === 'looks_right') return false;
					return (saved?.note ?? '') !== draft.note.trim() || saved?.choice !== draft.choice;
				})
			: false
	);

	let confirmSend = $state(false);
	let sendError = $state('');
	const send = createMutation(() => ({
		mutationFn: async () => {
			if (!current) throw new Error('Nothing to send.');
			// Notes still being typed are kept before the send.
			await Promise.all(current.cards.map((card) => save(card.id)));
			if (Object.values(drafts).some((draft) => draft.state === 'error'))
				throw new Error('A note could not be saved. Check the parts marked in red and try again.');
			return sendSetupPreviewNotes(current.version);
		},
		onMutate: () => (sendError = ''),
		onSuccess: () => (confirmSend = false),
		onError: (error) => {
			confirmSend = false;
			sendError = error.message;
		},
		onSettled: () =>
			Promise.all([
				queryClient.invalidateQueries({ queryKey: setupPreviewKey(userId) }),
				queryClient.invalidateQueries({ queryKey: setupSummaryKey(userId) })
			])
	}));

	const day = (value: string) =>
		new Date(value).toLocaleDateString(undefined, {
			weekday: 'short',
			day: 'numeric',
			month: 'short'
		});

	function kindTone(kind: PreviewKind | null) {
		if (kind === 'uplift_error') return 'success' as const;
		if (kind === 'new_request') return 'warning' as const;
		return 'informative' as const;
	}

	// The email links to #preview, which exists only once the answer has arrived.
	let scrolled = false;
	$effect(() => {
		if (!current || scrolled) return;
		scrolled = true;
		if (window.location.hash !== '#preview') return;
		requestAnimationFrame(() =>
			document.getElementById('preview')?.scrollIntoView({ behavior: 'smooth', block: 'start' })
		);
	});
</script>

{#snippet sentNotes(version: PreviewVersion)}
	<ol class="setup-preview__cards">
		{#each version.cards as card (card.id)}
			{@const note = version.notes.find((each) => each.card_id === card.id)}
			<li class="setup-preview__card">
				<h3 class="setup-preview__card-title">{card.title}</h3>
				<PreviewCardBody {card} {urls} />
				{#if note}
					<div
						class="setup-preview__answer"
						class:setup-preview__answer--fine={note.choice === 'looks_right'}
					>
						<div class="setup-preview__answer-head">
							<strong>You said: {PREVIEW_CHOICE_LABEL[note.choice]}</strong>
							{#if note.choice !== 'looks_right'}
								<StatusBadge status={kindTone(note.kind)}
									>{note.kind
										? PREVIEW_KIND_LABEL[note.kind]
										: 'Uplift is looking at this'}</StatusBadge
								>
							{/if}
						</div>
						{#if note.note}<p>{note.note}</p>{/if}
						<PreviewScreenshots value={note.screenshots} {urls} />
					</div>
				{/if}
			</li>
		{/each}
	</ol>
{/snippet}

{#if query.isPending}
	<LoadingSkeleton variant="card" label="Loading your preview" />
{:else if query.isError}
	<ErrorState
		title="Your preview could not be loaded"
		description={query.error.message}
		retry={() => query.refetch()}
	/>
{:else if current}
	<SectionBlock
		id="preview"
		title="Your preview"
		icon={presentationIcon}
		hint={current.version > 1
			? `Updated preview, sent ${day(current.released_at)}`
			: `Sent ${day(current.released_at)}`}
	>
		<div class="setup-preview">
			{#if sent}
				<Banner type="success">
					You sent your notes on {day(current.notes_sent_at ?? current.released_at)}. Uplift is
					working on them and will send you an updated preview. Each note shows how Uplift is
					treating it.
				</Banner>
				{@render sentNotes(current)}
			{:else}
				<p class="setup-preview__intro">
					{#if current.correction_round}
						Go through each part and mark it <strong>Looks right</strong> or
						<strong>Needs a change</strong>. Your notes are saved as you go. When you have been
						through them all, send them to Uplift together — your package includes one round of
						corrections, so put everything in this one.
					{:else}
						This preview includes the corrections you asked for. Mark each part
						<strong>Looks right</strong>. If Uplift got something wrong, choose
						<strong>Uplift made a mistake</strong> — mistakes are always fixed free. Anything else
						goes under <strong>Something new</strong>, and Uplift will talk with you about it
						separately.
					{/if}
				</p>

				<ol class="setup-preview__cards">
					{#each current.cards as card, index (card.id)}
						{@const draft = drafts[card.id]}
						<li class="setup-preview__card">
							<div class="setup-preview__card-head">
								<h3 class="setup-preview__card-title">
									<span class="setup-preview__number">{index + 1}</span>
									{card.title}
								</h3>
								{#if draft?.state === 'saving'}
									<span class="setup-preview__saved">Saving…</span>
								{:else if draft?.state === 'saved'}
									<span class="setup-preview__saved">Saved</span>
								{/if}
							</div>
							<PreviewCardBody {card} {urls} />
							{#if draft}
								<SegmentedControl
									ariaLabel="Your answer for {card.title}"
									options={previewChoices(current.correction_round).map((choice) => ({
										value: choice,
										label: PREVIEW_CHOICE_LABEL[choice]
									}))}
									value={draft.choice ?? ''}
									onchange={(choice) => choose(card.id, choice as PreviewChoice)}
								/>
								{#if draft.choice && draft.choice !== 'looks_right'}
									<div class="setup-preview__note">
										<Textarea
											id="preview-note-{card.id}"
											label={PREVIEW_NOTE_PROMPT[draft.choice]}
											rows={3}
											maxlength={PREVIEW_NOTE_MAX}
											bind:value={draft.note}
											oninput={() => typed(card.id)}
											onblur={() => save(card.id)}
										/>
										<PreviewScreenshots
											bind:value={
												() => draft.screenshots,
												(shots) => {
													draft.screenshots = shots;
													void save(card.id);
												}
											}
											{urls}
											editable
											onUploadingChange={(uploading) => (draft.uploading = uploading)}
										/>
									</div>
								{/if}
								{#if draft.error}
									<p class="setup-preview__error" role="alert">{draft.error}</p>
								{/if}
							{/if}
						</li>
					{/each}
				</ol>

				<div class="setup-preview__send">
					<p class="setup-preview__count">
						{#if asking === 0}
							Nothing to send yet. Mark a part that needs a change and say what.
						{:else}
							{asking === 1 ? '1 note' : `${asking} notes`} ready to send.
						{/if}
						{#if unanswered > 0}
							{unanswered === 1 ? '1 part' : `${unanswered} parts`} not looked at yet.
						{/if}
					</p>
					{#if sendError}
						<p class="setup-preview__error" role="alert">{sendError}</p>
					{/if}
					<Button
						disabled={asking === 0 || busy}
						onclick={() => {
							sendError = '';
							confirmSend = true;
						}}>{current.correction_round ? 'Send my corrections' : 'Send my notes'}</Button
					>
				</div>
			{/if}

			{#each older as version (version.version)}
				<details class="setup-preview__older">
					<summary>Earlier preview, sent {day(version.released_at)}</summary>
					{@render sentNotes(version)}
				</details>
			{/each}
		</div>
	</SectionBlock>

	<ConfirmDialog
		open={confirmSend}
		title={current.correction_round ? 'Send your corrections?' : 'Send your notes?'}
		confirmLabel="Send to Uplift"
		loading={send.isPending}
		onConfirm={() => send.mutate()}
		onClose={() => (confirmSend = false)}
	>
		<p>
			{asking === 1 ? 'Your note goes' : `All ${asking} notes go`} to Uplift together. You can only send
			once for this preview{current.correction_round
				? ', and it uses your one round of corrections'
				: ''}.
		</p>
		{#if unanswered > 0 || unsaved}
			<p>
				{unanswered > 0
					? `You have not looked at ${unanswered === 1 ? 'one part' : `${unanswered} parts`} yet.`
					: ''}
				Anything not sent now can only be reported later as a mistake or a new request.
			</p>
		{/if}
	</ConfirmDialog>
{/if}

<style lang="scss">
	.setup-preview {
		display: grid;
		gap: var(--space-base);

		&__intro {
			margin: 0;
			color: var(--color-text);
		}

		&__cards {
			display: grid;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__card {
			display: grid;
			gap: var(--space-small);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}

		&__card-head {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__card-title {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
		}

		&__number {
			display: inline-grid;
			place-items: center;
			flex: none;
			width: 24px;
			height: 24px;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__saved {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__note {
			display: grid;
			gap: var(--space-small);
		}

		&__answer {
			display: grid;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-base);
			border-left: 3px solid var(--color-warning);
			background: var(--color-surface--background);

			p {
				margin: 0;
				white-space: pre-line;
			}

			&--fine {
				border-left-color: var(--color-success);
			}
		}

		&__answer-head {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__send {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small) var(--space-base);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__count {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__older summary {
			color: var(--color-interactive);
			font-weight: 600;
			cursor: pointer;
		}

		&__older[open] summary {
			margin-bottom: var(--space-small);
		}
	}
</style>
