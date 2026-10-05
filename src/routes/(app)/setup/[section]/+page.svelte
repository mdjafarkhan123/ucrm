<script lang="ts">
	import { tick, untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate, goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
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
		setupCheckKey,
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
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import type { HttpError } from '$lib/http-error';
	import type { PageProps } from './$types';

	let { data: shell }: PageProps = $props();
	const userId = $derived(shell.user?.id ?? null);
	const sectionKey = $derived(page.params.section ?? '');
	// B13: opened from Check and send's Edit link, the page goes back there, as GOV.UK's Change links do.
	const fromCheck = $derived(page.url.searchParams.get('from') === 'check');
	const checkHref: string = resolve('/(app)/setup/check-and-send');
	const tasksHref: string = resolve('/(app)/setup');
	const backHref = $derived(fromCheck ? checkHref : tasksHref);
	const backLabel = $derived(fromCheck ? 'Back to Check and send' : 'Back to setup tasks');

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
				? fieldHref(key)
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
				void queryClient.invalidateQueries({ queryKey: setupCheckKey(userId) });
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
			if (firstProblem) {
				jumpingToQuestion = true;
				// eslint-disable-next-line svelte/no-navigation-without-resolve -- stepHref builds on a resolve()d path.
				await goto(stepHref(stepOf(firstProblem.key)), { noScroll: true });
				toast.error(
					'A few answers are still needed',
					'The steps marked in red show where. Fill them in, then finish this task.'
				);
			}
			await tick();
			jumpingToQuestion = false;
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
			// eslint-disable-next-line svelte/no-navigation-without-resolve -- backHref is one of two resolve() paths.
			await goto(backHref);
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
		void queryClient.invalidateQueries({ queryKey: setupCheckKey(userId) });
	}

	const SAVE_TEXT = {
		idle: 'Answers save as you go',
		saving: 'Saving…',
		saved: 'All changes saved',
		failed: 'Couldn’t save — check your connection. We’ll try again when you change something.'
	};

	const errorStatus = $derived((query.error as HttpError | null)?.status);

	// C3b: what Uplift said about this task on the newest send. A returned task's questions to change are
	// highlighted until the client sends again.
	const review = $derived(query.data?.review ?? null);
	const flagged = $derived(new Set(review?.state === 'returned' ? review.question_keys : []));
	const reviewedOn = (at: string | null) =>
		at ? new Date(at).toLocaleDateString(undefined, { dateStyle: 'long' }) : '';

	// One topic per screen, as Stripe's and GOV.UK's long setups do: each group of questions is a step with
	// its own address, so the browser's Back button, a refresh and a "Question to change" link all land on
	// the same step. A step whose questions are all hidden by earlier answers is skipped. `?step` is the
	// group's place in the whole section, so it stays put when another step appears or disappears.
	const steps = $derived(
		section && fields
			? section.groups
					.map((group, index) => ({ group, index }))
					.filter(({ group }) => group.facts.some((fact) => shown.has(fact.key)))
			: []
	);
	const requestedStep = $derived(Number(page.url.searchParams.get('step') ?? '1') - 1);
	const current = $derived(
		steps.find((step) => step.index >= requestedStep) ?? steps[steps.length - 1]
	);
	const position = $derived(current ? steps.indexOf(current) : 0);
	const previousStep = $derived(position > 0 ? steps[position - 1] : null);
	const nextStep = $derived(position < steps.length - 1 ? steps[position + 1] : null);

	const sectionHref = $derived(resolve('/(app)/setup/[section]', { section: sectionKey }));
	const stepHref = (index: number) =>
		`${sectionHref}?step=${index + 1}${fromCheck ? '&from=check' : ''}`;
	const stepOf = (key: string) =>
		Math.max(
			section?.groups.findIndex((group) => group.facts.some((fact) => fact.key === key)) ?? 0,
			0
		);
	const fieldHref = (key: string) =>
		`${stepHref(stepOf(key))}#setup-${key.replace(/\./g, '-')}-field`;

	const stepAsked = (index: number) =>
		section?.groups[index].facts.filter((fact) => shown.has(fact.key)) ?? [];
	// A step is ticked once it has an answer and every question it asks that needs one has one.
	function stepComplete(index: number) {
		const asked = stepAsked(index);
		return (
			asked.some((fact) => draftAnswer(fact.key)) &&
			asked.every((fact) => !fact.required || draftAnswer(fact.key))
		);
	}
	// The app scrolls inside its own panel, so moving to another step brings that step's title into view
	// and puts the focus there itself, as a new page would. The first step shown needs neither.
	let shownStep: number | null = null;
	// Set while "Finish this task" opens the step holding a missing answer, which it scrolls to itself.
	let jumpingToQuestion = false;
	$effect(() => {
		const index = current?.index ?? null;
		if (index === null) return;
		untrack(() => {
			const moved = shownStep !== null && shownStep !== index;
			shownStep = index;
			if (!moved || page.url.hash || jumpingToQuestion) return;
			void tick().then(() => {
				const title = document.getElementById('setup-step-title');
				title?.focus({ preventScroll: true });
				document
					.querySelector('.setup-section')
					?.scrollIntoView({ behavior: 'smooth', block: 'start' });
			});
		});
	});

	const stepNeedsAttention = (index: number) =>
		stepAsked(index).some((fact) => errors[fact.key] || flagged.has(fact.key));
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

			{#if review?.state === 'returned'}
				{@const toChange = sectionFacts(section).filter(
					(fact) => flagged.has(fact.key) && shown.has(fact.key)
				)}
				<section aria-labelledby="setup-returned-heading">
					<Banner type="warning">
						<h2 id="setup-returned-heading" class="setup-section__returned-title">
							Uplift needs changes to this task
						</h2>
						<p class="setup-section__returned-note">{review.note}</p>
						{#if toChange.length > 0}
							<p class="setup-section__returned-label">
								{toChange.length === 1 ? 'Question to change' : 'Questions to change'}
							</p>
							<ul class="setup-section__returned-list">
								{#each toChange as fact (fact.key)}
									<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- an in-page anchor -->
									<li><a href={fieldHref(fact.key)}>{fact.label}</a></li>
								{/each}
							</ul>
						{/if}
						<p class="setup-section__returned-after">
							Sent back on {reviewedOn(review.reviewed_at)}. When you have made the change, send
							your setup again from Check and send. Not sure what Uplift means? Use Ask Uplift.
						</p>
					</Banner>
				</section>
			{:else if review?.state === 'accepted'}
				<Banner type="success">
					Accepted by Uplift on {reviewedOn(review.reviewed_at)}. If you change an answer here,
					Uplift looks at this task again the next time you send your setup.
				</Banner>
			{:else if review?.state === 'with_uplift'}
				<Banner type="notice">
					Uplift has this task and is looking it over. Changes you make here reach Uplift when you
					send your setup again.
				</Banner>
			{:else if markedDone}
				<Banner type="success">
					This section is marked as done. You can still change any answer — it saves the same way.
				</Banner>
			{/if}

			{#if current}
				{@const asked = current.group.facts.filter((fact) => shown.has(fact.key))}
				<div class="setup-section__body" class:setup-section__body--steps={steps.length > 1}>
					{#if steps.length > 1}
						<nav class="setup-steps" aria-label={`${section.title} steps`}>
							<p class="setup-steps__count">Step {position + 1} of {steps.length}</p>
							<div class="setup-steps__bar" aria-hidden="true">
								<span style:width={`${((position + 1) / steps.length) * 100}%`}></span>
							</div>
							<ol class="setup-steps__list">
								{#each steps as step, number (step.index)}
									{@const complete = stepComplete(step.index)}
									{@const attention = stepNeedsAttention(step.index)}
									<li>
										<!-- eslint-disable svelte/no-navigation-without-resolve -- stepHref builds on a resolve()d path. -->
										<a
											class="setup-steps__link"
											class:setup-steps__link--current={step === current}
											class:setup-steps__link--complete={complete && !attention}
											class:setup-steps__link--attention={attention}
											href={stepHref(step.index)}
											aria-current={step === current ? 'step' : undefined}
										>
											<span class="setup-steps__marker" aria-hidden="true">
												{#if complete && !attention}
													<!-- eslint-disable-next-line svelte/no-at-html-tags -->
													{@html checkIcon}
												{:else}
													{number + 1}
												{/if}
											</span>
											<span class="setup-steps__name">{step.group.title || section.title}</span>
											{#if attention}
												<span class="setup-steps__hidden">(needs attention)</span>
											{:else if complete}
												<span class="setup-steps__hidden">(done)</span>
											{/if}
										</a>
										<!-- eslint-enable svelte/no-navigation-without-resolve -->
									</li>
								{/each}
							</ol>
						</nav>
					{/if}

					<section class="setup-step" aria-labelledby="setup-step-title">
						<header class="setup-step__header">
							{#if steps.length > 1}
								<p class="setup-step__eyebrow">Step {position + 1} of {steps.length}</p>
							{/if}
							<h2 class="setup-step__title" id="setup-step-title" tabindex="-1">
								{current.group.title || section.title}
							</h2>
							{#if current.group.hint}<p class="setup-step__hint">{current.group.hint}</p>{/if}
						</header>

						<div class="setup-step__questions">
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
									flagged={flagged.has(fact.key)}
									helpAnswer={query.data?.help_answers?.[fact.key] ?? null}
									onedit={() => edited(fact.key)}
									oncommit={() => committed(fact.key)}
								/>
							{/each}
						</div>

						<footer class="setup-step__footer">
							{#if previousStep}
								<Button variant="secondary" href={stepHref(previousStep.index)}>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									<span class="setup-step__arrow" aria-hidden="true">{@html arrowLeftIcon}</span>
									Back
								</Button>
							{/if}
							<div class="setup-step__forward">
								{#if nextStep}
									<Button variant="tertiary" href={backHref}
										>{fromCheck ? 'Back to Check and send' : 'Save and come back later'}</Button
									>
									<Button href={stepHref(nextStep.index)}>
										Continue
										<!-- eslint-disable-next-line svelte/no-at-html-tags -->
										<span class="setup-step__arrow" aria-hidden="true">{@html arrowRightIcon}</span>
									</Button>
								{:else if markedDone && review?.state === 'returned'}
									<Button variant="tertiary" href={tasksHref}>Back to setup tasks</Button>
									<Button href={checkHref}>Go to Check and send</Button>
								{:else if markedDone}
									<Button variant="tertiary" onclick={reopen} loading={finishing}
										>Mark as not done</Button
									>
									<Button href={backHref}>{backLabel}</Button>
								{:else}
									<Button variant="tertiary" href={backHref}
										>{fromCheck ? 'Back to Check and send' : 'Save and come back later'}</Button
									>
									<Button onclick={markDone} loading={finishing}>Finish this task</Button>
								{/if}
							</div>
							{#if !nextStep && !markedDone && unanswered.length > 0}
								<p class="setup-step__remaining">
									{unanswered.length}
									{unanswered.length === 1 ? 'question' : 'questions'} in this task still to answer
								</p>
							{/if}
						</footer>
					</section>
				</div>
			{/if}
		{/if}
	</div>
</PageContainer>

<style lang="scss">
	.setup-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		max-width: 1040px;
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

		&__body {
			display: grid;
			max-width: 720px;

			&--steps {
				grid-template-columns: 240px minmax(0, 1fr);
				gap: var(--space-larger);
				align-items: start;
				max-width: none;
			}
		}

		&__returned-title {
			color: inherit;
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}

		&__returned-note {
			margin-top: var(--space-smaller);
			color: var(--color-text);
			white-space: pre-line;
			overflow-wrap: anywhere;
		}

		&__returned-label {
			margin-top: var(--space-small);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__returned-list {
			margin: var(--space-smallest) 0 0;
			padding-left: var(--space-large);

			a {
				color: inherit;
				text-decoration: underline;

				&:hover {
					color: var(--color-heading);
				}
			}
		}

		&__returned-after {
			margin-top: var(--space-small);
			font-size: var(--typography--fontSize-small);
		}
	}

	// The step list: where the client is in this task, and which topics already have their answers.
	.setup-steps {
		position: sticky;
		top: var(--space-base);
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		// Shown only where the list folds away; on a wide screen the step's own heading says where you are.
		&__count {
			display: none;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__bar {
			display: none;
			height: 4px;
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			overflow: hidden;

			span {
				display: block;
				height: 100%;
				border-radius: inherit;
				background: var(--color-interactive);
				transition: width var(--timing-base) ease-out;
			}
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__link {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-small);
			border-radius: var(--radius-base);
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			text-decoration: none;
			transition: background-color var(--timing-quick) ease-out;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&--current {
				background: var(--color-surface--background--subtle);
				color: var(--color-heading);
				font-weight: 600;
			}
		}

		&__marker {
			display: inline-flex;
			flex: none;
			align-items: center;
			justify-content: center;
			width: 26px;
			height: 26px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__link--current &__marker {
			border-color: var(--color-interactive);
			box-shadow: inset 0 0 0 1px var(--color-interactive);
			color: var(--color-interactive);
		}

		&__link--complete &__marker {
			border-color: var(--color-interactive);
			background: var(--color-interactive);
			color: var(--color-surface);
		}

		&__link--attention &__marker {
			border-color: var(--color-critical);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
		}

		&__name {
			min-width: 0;
			overflow-wrap: anywhere;
		}

		&__hidden {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}
	}

	// One topic's questions, spaced so each reads on its own.
	.setup-step {
		display: flex;
		flex-direction: column;
		gap: var(--space-larger);
		min-width: 0;
		padding: var(--space-larger);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);

		&__header {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			padding-bottom: var(--space-large);
			border-bottom: var(--border-base) solid var(--color-border);
		}

		&__eyebrow {
			margin: 0;
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__title {
			margin: 0;
			outline: none;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
			line-height: 1.25;
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			line-height: 1.5;
		}

		&__questions {
			display: flex;
			flex-direction: column;
			gap: var(--space-larger);
		}

		&__footer {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			padding-top: var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__forward {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin-left: auto;
		}

		&__arrow {
			display: inline-flex;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__remaining {
			flex-basis: 100%;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-align: right;
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
		}
	}

	// On a tablet or phone the step list folds into a count and a progress bar above the questions.
	@media (max-width: 900px) {
		.setup-section__body--steps {
			grid-template-columns: minmax(0, 1fr);
			gap: var(--space-base);
		}

		.setup-steps {
			position: static;

			&__count,
			&__bar {
				display: block;
			}

			&__list {
				display: none;
			}
		}

		.setup-step__eyebrow {
			display: none;
		}
	}

	@media (max-width: 560px) {
		.setup-step {
			padding: var(--space-base);
			border-radius: var(--radius-base);
		}

		.setup-step__forward {
			width: 100%;
			flex-direction: column-reverse;

			:global(.button) {
				width: 100%;
			}
		}

		.setup-step__footer > :global(.button) {
			width: 100%;
		}

		.setup-step__remaining {
			text-align: left;
		}
	}
</style>
