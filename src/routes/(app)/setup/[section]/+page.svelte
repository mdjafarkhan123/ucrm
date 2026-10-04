<script lang="ts">
	import { tick, untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate, goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import SetupField from '$lib/components/setup/SetupField.svelte';
	import {
		fetchSetupSection,
		saveSetupAnswers,
		setSetupSectionDone,
		setupSectionKey,
		setupSummaryKey,
		type SetupAnswerWrite,
		type SetupSectionData,
		type SetupWriteFailure
	} from '$lib/setup/api';
	import {
		sectionFacts,
		sectionStatus,
		setupAnswerGiven,
		setupAnswerShortfall,
		setupValueError,
		shownFacts,
		type SetupFact,
		type SetupAnswer,
		type SetupAnswers,
		type SetupAvailability
	} from '$lib/setup/catalogue';
	import { countryCurrency } from '$lib/settings/countries';
	import { setupListRows } from '$lib/setup/lists';
	import { keptSetupPickIds, setupPickIds } from '$lib/setup/picks';
	import { setupReuseSource } from '$lib/setup/reuse';
	import { setupAnswerLines } from '$lib/setup/answer-lines';
	import { getSupportAsk } from '$lib/support/ask';
	import askIcon from '@tabler/icons/outline/message-question.svg?raw';
	import type { HttpError } from '$lib/http-error';
	import type { PageProps } from './$types';

	let { data: shell }: PageProps = $props();
	const userId = $derived(shell.user?.id ?? null);
	const sectionKey = $derived(page.params.section ?? '');

	const queryClient = useQueryClient();
	const toast = getToastManager();
	// Ask Uplift (D6): a new support chat about this section, with the section attached.
	const askUplift = getSupportAsk();
	const query = createQuery(() => ({
		queryKey: setupSectionKey(userId, sectionKey),
		queryFn: () => fetchSetupSection(sectionKey)
	}));
	// The questions come with the answers, as the published setup version asks them now.
	const section = $derived(query.data?.section);
	const factsByKey = $derived<Record<string, SetupFact>>(
		Object.fromEntries(section ? sectionFacts(section).map((fact) => [fact.key, fact]) : [])
	);

	type Field = { value: string; availability: SetupAvailability; note: string };

	// What is on screen, what the server last accepted, and which questions the person has actually
	// touched. Autosave only ever sends touched questions, so a value suggested from the account is not
	// saved as their answer until they keep it — by editing it, or by marking the section done.
	let fields = $state<Record<string, Field> | null>(null);
	let saved = $state<SetupAnswers>({});
	let suggested = $state<Record<string, boolean>>({});
	let errors = $state<Record<string, string>>({});
	let markedDone = $state(false);
	let saveState = $state<'idle' | 'saving' | 'saved' | 'failed'>('idle');
	let finishing = $state(false);
	// Bookkeeping for autosave, never drawn, so a plain Set is right.
	// eslint-disable-next-line svelte/prefer-svelte-reactivity
	const touched = new Set<string>();

	$effect(() => {
		const loaded = query.data;
		const current = section;
		if (!loaded || !current) return;
		untrack(() => {
			if (fields) return;
			const next: Record<string, Field> = {};
			const fromAccount: Record<string, boolean> = {};
			for (const fact of sectionFacts(current)) {
				const answer = loaded.answers[fact.key];
				// Nothing knows the time zone better than the device in the person's hand, so that is the
				// starting suggestion when the account has no confirmed one.
				const suggestion = answer
					? undefined
					: (loaded.suggestions[fact.key] ??
						(fact.kind === 'timezone'
							? Intl.DateTimeFormat().resolvedOptions().timeZone
							: undefined));
				// A5g: a "Yes, use this" of an answer this client is no longer asked shows as unanswered.
				const stale =
					answer?.availability === 'have' &&
					setupReuseSource(answer.value) !== null &&
					!fact.reuseFrom;
				next[fact.key] = {
					value: stale ? '' : (answer?.value ?? suggestion ?? ''),
					availability: answer?.availability ?? 'have',
					note: answer?.note ?? ''
				};
				if (suggestion) fromAccount[fact.key] = true;
			}
			fields = next;
			saved = { ...loaded.answers };
			suggested = fromAccount;
			markedDone = loaded.status === 'done';
		});
	});

	// The answer a question would be saved as right now. `undefined` is "no answer".
	function draftAnswer(key: string): SetupAnswer | undefined {
		const field = fields?.[key];
		if (!field) return undefined;
		if (field.availability !== 'have')
			return { availability: field.availability, value: null, note: field.note.trim() || null };
		const fact = factsByKey[key];
		// A pick (A5f) leaves out rows its list no longer holds, as the server does.
		const value =
			fact?.kind === 'pick'
				? pickValue(keptSetupPickIds(setupPickIds(field.value), pickRows(fact)))
				: field.value.trim();
		return value ? { availability: 'have', value, note: null } : undefined;
	}

	const pickValue = (ids: string[]) => (ids.length ? JSON.stringify(ids) : '');

	// A pick's list rows as they stand now: on this page as typed, or as saved in an earlier section.
	function pickRows(fact: SetupFact) {
		const key = fact.pickFrom ?? '';
		const field = fields?.[key];
		if (field) return field.availability === 'have' ? setupListRows(field.value) : [];
		return setupListRows(earlier[key]?.value);
	}

	// Every answer a pick's or a reuse's rules may read: earlier sections' and this page's as they stand.
	function answersNow(): SetupAnswers {
		const now: SetupAnswers = { ...earlier };
		if (section && fields)
			for (const fact of sectionFacts(section)) now[fact.key] = draftAnswer(fact.key);
		return now;
	}

	// A5g: the earlier answer a reuse shows to confirm — on this page as typed, or as saved in an earlier
	// section — or null when there is none to show, and the question is asked as a plain one.
	function reuseOf(fact: SetupFact) {
		const key = fact.reuseFrom;
		if (!key || !section) return null;
		const here = Boolean(fields?.[key]);
		const answer = here ? draftAnswer(key) : earlier[key];
		if (answer?.availability !== 'have' || !answer.value) return null;
		const lines = setupAnswerLines(fact, answer.value).filter(Boolean);
		if (lines.length === 0) return null;
		return {
			lines,
			where: here
				? `You told us above, in “${fact.reuseLabel}”`
				: `You told us in ${fact.reuseSection?.title ?? 'an earlier section'}`,
			href: here
				? `#setup-${key.replace(/\./g, '-')}-field`
				: resolve('/(app)/setup/[section]', { section: fact.reuseSection?.key ?? '' })
		};
	}

	// A5g: when an answer on this page stops being given, a "Yes, use this" of it is cleared with it — the
	// server does the same — so the client is asked again rather than shown a confirmation of nothing.
	function clearReusesOf(key: string) {
		if (!section || !fields || draftAnswer(key)?.availability === 'have') return;
		for (const fact of sectionFacts(section)) {
			const field = fields[fact.key];
			if (fact.reuseFrom !== key || !setupReuseSource(field?.value)) continue;
			field.value = '';
			touched.add(fact.key);
		}
	}

	// "Show only if" (A5b): which questions are asked, judged against what is on screen now, so a question
	// appears the moment the answer it depends on is picked. Conditions on an earlier section read that
	// section's saved answers, which the server sends along.
	const earlier = $derived(query.data?.earlier_answers ?? {});

	const COUNTRY = 'business.country';
	const CURRENCY = 'business.currency';

	// Amount answers (A5d) follow the country and currency picked on this page, or else as already known.
	const currency = $derived(fields?.[CURRENCY]?.value || query.data?.currency || null);
	const country = $derived(fields?.[COUNTRY]?.value || query.data?.country || null);
	function shownWith(answers: SetupAnswers) {
		return section
			? shownFacts(sectionFacts(section), { ...earlier, ...answers }, new Set(Object.keys(earlier)))
			: new Set<string>();
	}
	const shown = $derived.by(() => {
		if (!section || !fields) return new Set<string>();
		const onScreen: SetupAnswers = {};
		for (const fact of sectionFacts(section)) onScreen[fact.key] = draftAnswer(fact.key);
		return shownWith(onScreen);
	});

	function sameAnswer(a: SetupAnswer | undefined, b: SetupAnswer | undefined) {
		return a?.availability === b?.availability && a?.value === b?.value && a?.note === b?.note;
	}

	let timer: ReturnType<typeof setTimeout> | undefined;
	let inFlight: Promise<void> | null = null;

	// Typing waits for a pause before saving, so a name is one save rather than one per letter.
	function edited(key: string) {
		touched.add(key);
		clearReusesOf(key);
		suggested[key] = false;
		if (errors[key]) delete errors[key];
		clearTimeout(timer);
		timer = setTimeout(() => void flush(), 900);
	}

	function committed(key: string) {
		touched.add(key);
		clearReusesOf(key);
		suggested[key] = false;
		if (key === COUNTRY) suggestCurrency();
		clearTimeout(timer);
		void flush();
	}

	// Picking a country offers that country's currency, as a suggestion like any other: it is shown, not
	// saved, until the person keeps it. An answer they already gave or touched is left alone.
	function suggestCurrency() {
		const currency = fields?.[CURRENCY];
		if (!fields || !currency || saved[CURRENCY] || touched.has(CURRENCY)) return;
		const code = countryCurrency(fields[COUNTRY]?.value);
		if (!code) return;
		currency.value = code;
		suggested[CURRENCY] = true;
	}

	// Saves every touched question whose answer differs from what the server has. An answer that would be
	// refused is not sent: its message goes under the field and the last saved answer stays put.
	async function flush(options: { everything?: boolean; keepalive?: boolean } = {}) {
		if (inFlight) await inFlight;
		if (!fields || !section) return;

		const keys = options.everything ? Object.keys(fields) : [...touched];
		const writes: SetupAnswerWrite[] = [];
		const sending: Record<string, SetupAnswer | undefined> = {};
		for (const key of keys) {
			const fact = factsByKey[key];
			if (!fact) continue;
			const draft = draftAnswer(key);
			if (sameAnswer(draft, saved[key])) continue;
			const problem = draft?.value ? setupValueError(fact, draft.value, answersNow()) : null;
			if (problem) {
				errors[key] = problem;
				continue;
			}
			sending[key] = draft;
			writes.push({
				fact_key: key,
				availability: draft?.availability ?? null,
				value: draft?.value ?? null,
				note: draft?.note ?? null
			});
		}
		if (writes.length === 0) return;

		saveState = 'saving';
		inFlight = saveSetupAnswers(writes, { keepalive: options.keepalive })
			.then(() => {
				saved = { ...saved, ...sending };
				for (const key of Object.keys(sending)) {
					suggested[key] = false;
					delete errors[key];
				}
				saveState = 'saved';
				// Keep the cached copy in step, so coming back to this page starts from what was saved rather
				// than from what was loaded before the edits.
				queryClient.setQueryData<SetupSectionData>(
					setupSectionKey(userId, sectionKey),
					(current) => {
						if (!current || !section) return current;
						const answers = { ...current.answers, ...sending };
						for (const key of Object.keys(sending)) if (!sending[key]) delete answers[key];
						return {
							...current,
							answers,
							status: sectionStatus(
								section,
								{ ...earlier, ...answers },
								markedDone,
								shownWith(answers)
							)
						};
					}
				);
				void queryClient.invalidateQueries({ queryKey: setupSummaryKey(userId) });
				// A later section may show these answers back to confirm (A5g), or ask a question because of them.
				void queryClient.invalidateQueries({
					queryKey: ['setup', 'section', userId],
					predicate: (cached) => cached.queryKey[3] !== sectionKey
				});
			})
			.catch((error: SetupWriteFailure) => {
				saveState = 'failed';
				for (const [key, message] of Object.entries(error.fieldErrors ?? {}))
					if (factsByKey[key]) errors[key] = message;
			})
			.finally(() => {
				inFlight = null;
			});
		await inFlight;
	}

	// Leaving the page — or a phone putting it in the background — sends whatever is still waiting.
	beforeNavigate(() => {
		clearTimeout(timer);
		void flush({ keepalive: true });
	});
	$effect(() => {
		const onHide = () => {
			if (document.visibilityState !== 'hidden') return;
			clearTimeout(timer);
			void flush({ keepalive: true });
		};
		document.addEventListener('visibilitychange', onHide);
		return () => document.removeEventListener('visibilitychange', onHide);
	});

	const unanswered = $derived(
		section && fields
			? sectionFacts(section).filter(
					(fact) => fact.required && shown.has(fact.key) && !draftAnswer(fact.key)
				)
			: []
	);

	async function markDone() {
		if (!section || !fields || finishing) return;
		finishing = true;
		clearTimeout(timer);
		// Pressing this is the person confirming everything on the page, suggestions included.
		await flush({ everything: true });

		// A question an answer hid is never required, and a message it still carries is not in the way.
		const asked = shownWith(saved);
		const now = { ...earlier, ...saved };
		const missing = sectionFacts(section).filter(
			(fact) => fact.required && asked.has(fact.key) && !setupAnswerGiven(fact, now)
		);
		for (const fact of sectionFacts(section)) {
			const shortfall = asked.has(fact.key) ? setupAnswerShortfall(fact, now) : null;
			if (shortfall) errors[fact.key] ??= shortfall;
		}
		for (const fact of missing)
			errors[fact.key] ??= fact.canDefer
				? 'Enter this, or tell us you don’t have it yet.'
				: 'This one still needs an answer.';
		const firstProblem = sectionFacts(section).find(
			(fact) => asked.has(fact.key) && errors[fact.key]
		);
		if (firstProblem || saveState === 'failed') {
			finishing = false;
			await tick();
			if (firstProblem)
				document
					.getElementById(`setup-${firstProblem.key.replace(/\./g, '-')}-field`)
					?.scrollIntoView({ behavior: 'smooth', block: 'center' });
			return;
		}

		try {
			await setSetupSectionDone(section.key, true);
			markedDone = true;
			syncDoneState();
			toast.success(`${section.title} is marked as done.`);
			await goto(resolve('/(app)/setup'));
		} catch (error) {
			const failure = error as SetupWriteFailure;
			for (const [key, message] of Object.entries(failure.fieldErrors ?? {}))
				if (factsByKey[key]) errors[key] = message;
			toast.error('Could not mark as done', failure.message);
		} finally {
			finishing = false;
		}
	}

	async function reopen() {
		if (!section || finishing) return;
		finishing = true;
		try {
			await setSetupSectionDone(section.key, false);
			markedDone = false;
			syncDoneState();
		} catch (error) {
			toast.error('Could not reopen this section', (error as Error).message);
		} finally {
			finishing = false;
		}
	}

	function syncDoneState() {
		queryClient.setQueryData<SetupSectionData>(setupSectionKey(userId, sectionKey), (current) =>
			current && section
				? {
						...current,
						status: sectionStatus(
							section,
							{ ...earlier, ...current.answers },
							markedDone,
							shownWith(current.answers)
						)
					}
				: current
		);
		void queryClient.invalidateQueries({ queryKey: setupSummaryKey(userId) });
	}

	const SAVE_TEXT = {
		idle: 'Answers save as you go',
		saving: 'Saving…',
		saved: 'All changes saved',
		failed: 'Couldn’t save — check your connection. We’ll try again when you change something.'
	};

	const errorStatus = $derived((query.error as HttpError | null)?.status);
</script>

<svelte:head
	><title>{section ? `${section.title} · Setup` : 'Setup'} · Contractor CRM</title></svelte:head
>

<PageContainer variant="fill">
	<div class="setup-section">
		<Breadcrumbs
			items={[{ label: 'Setup', href: resolve('/(app)/setup') }, { label: section?.title ?? '' }]}
		/>

		{#if errorStatus === 404}
			<ErrorState
				title="That part of setup doesn’t exist"
				description="Go back to your setup tasks to pick one."
			>
				{#snippet action()}
					<Button href={resolve('/(app)/setup')}>Back to setup tasks</Button>
				{/snippet}
			</ErrorState>
		{:else if query.isError}
			{#if errorStatus === 403}
				<ErrorState
					title="Setup is handled by your account owner"
					description="Only an owner or administrator fills in setup. The rest of the CRM is ready for you to use."
				/>
			{:else}
				<ErrorState
					description="This part of setup could not be loaded."
					retry={() => query.refetch()}
				/>
			{/if}
		{:else if !fields || !section}
			<LoadingSkeleton variant="card" rows={4} />
		{:else}
			{@const form = fields}
			<PageHeader title={section.title} description={section.description}>
				{#snippet actions()}
					<span
						class="setup-section__save"
						class:setup-section__save--failed={saveState === 'failed'}
						role="status"
						aria-live="polite">{SAVE_TEXT[saveState]}</span
					>
					<Button
						variant="secondary"
						size="small"
						onclick={() => askUplift({ section: section.key, title: section.title })}
					>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="setup-section__ask-icon" aria-hidden="true">{@html askIcon}</span>
						Ask Uplift
					</Button>
				{/snippet}
			</PageHeader>

			{#if markedDone}
				<Banner type="success">
					This section is marked as done. You can still change any answer — it saves the same way.
				</Banner>
			{/if}

			{#each section.groups as group, index (`${index}-${group.title}`)}
				{@const asked = group.facts.filter((fact) => shown.has(fact.key))}
				{#if asked.length > 0}
					<SectionBlock title={group.title} hint={group.hint} form level={2}>
						{#each asked as fact (fact.key)}
							<SetupField
								{fact}
								bind:value={form[fact.key].value}
								bind:availability={form[fact.key].availability}
								bind:note={form[fact.key].note}
								error={errors[fact.key] ?? ''}
								suggested={suggested[fact.key] ?? false}
								{currency}
								{country}
								{userId}
								pickRows={fact.kind === 'pick' ? pickRows(fact) : undefined}
								reuse={reuseOf(fact)}
								onedit={() => edited(fact.key)}
								oncommit={() => committed(fact.key)}
							/>
						{/each}
					</SectionBlock>
				{/if}
			{/each}

			<footer class="setup-section__footer">
				{#if markedDone}
					<Button href={resolve('/(app)/setup')}>Back to setup tasks</Button>
					<Button variant="tertiary" onclick={reopen} loading={finishing}>Mark as not done</Button>
				{:else}
					<Button onclick={markDone} loading={finishing}>Mark as done</Button>
					<Button variant="tertiary" href={resolve('/(app)/setup')}>Save and come back later</Button
					>
					{#if unanswered.length > 0}
						<span class="setup-section__remaining"
							>{unanswered.length}
							{unanswered.length === 1 ? 'question' : 'questions'} still to answer</span
						>
					{/if}
				{/if}
			</footer>
		{/if}
	</div>
</PageContainer>

<style lang="scss">
	.setup-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		max-width: 720px;
		margin-inline: auto;

		// PageHeader carries its own bottom margin; the column gap already spaces what follows.
		:global(.page-header) {
			margin-bottom: 0;
		}

		// A fieldset refuses to shrink below its widest child by default, which pushes long answers off
		// the side of a phone.
		:global(fieldset) {
			min-width: 0;
		}

		&__save {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-align: right;

			&--failed {
				color: var(--color-critical--onSurface);
			}
		}

		&__ask-icon {
			display: inline-flex;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__footer {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__remaining {
			margin-left: auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	@media (max-width: 767px) {
		.setup-section {
			:global(.page-header) {
				flex-direction: column;
				gap: var(--space-small);
			}

			&__save {
				text-align: left;
			}

			&__remaining {
				flex-basis: 100%;
				margin-left: 0;
			}
		}
	}
</style>
