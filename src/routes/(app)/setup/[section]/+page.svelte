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
		SETUP_FACTS,
		sectionFacts,
		sectionStatus,
		setupSection,
		setupValueError,
		type SetupAnswer,
		type SetupAnswers,
		type SetupAvailability
	} from '$lib/setup/catalogue';
	import type { HttpError } from '$lib/http-error';
	import type { PageProps } from './$types';

	let { data: shell }: PageProps = $props();
	const userId = $derived(shell.user?.id ?? null);
	const sectionKey = $derived(page.params.section ?? '');
	const section = $derived(setupSection(sectionKey));

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: setupSectionKey(userId, sectionKey),
		queryFn: () => fetchSetupSection(sectionKey),
		enabled: Boolean(section)
	}));

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
				const suggestion = answer ? undefined : loaded.suggestions[fact.key];
				next[fact.key] = {
					value: answer?.value ?? suggestion ?? '',
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
		const value = field.value.trim();
		return value ? { availability: 'have', value, note: null } : undefined;
	}

	function sameAnswer(a: SetupAnswer | undefined, b: SetupAnswer | undefined) {
		return a?.availability === b?.availability && a?.value === b?.value && a?.note === b?.note;
	}

	let timer: ReturnType<typeof setTimeout> | undefined;
	let inFlight: Promise<void> | null = null;

	// Typing waits for a pause before saving, so a name is one save rather than one per letter.
	function edited(key: string) {
		touched.add(key);
		suggested[key] = false;
		if (errors[key]) delete errors[key];
		clearTimeout(timer);
		timer = setTimeout(() => void flush(), 900);
	}

	function committed(key: string) {
		touched.add(key);
		suggested[key] = false;
		clearTimeout(timer);
		void flush();
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
			const fact = SETUP_FACTS.get(key);
			if (!fact) continue;
			const draft = draftAnswer(key);
			if (sameAnswer(draft, saved[key])) continue;
			const problem = draft?.value ? setupValueError(fact, draft.value) : null;
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
						return { ...current, answers, status: sectionStatus(section, answers, markedDone) };
					}
				);
				void queryClient.invalidateQueries({ queryKey: setupSummaryKey(userId) });
			})
			.catch((error: SetupWriteFailure) => {
				saveState = 'failed';
				for (const [key, message] of Object.entries(error.fieldErrors ?? {}))
					if (SETUP_FACTS.has(key)) errors[key] = message;
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
			? sectionFacts(section).filter((fact) => fact.required && !draftAnswer(fact.key))
			: []
	);

	async function markDone() {
		if (!section || !fields || finishing) return;
		finishing = true;
		clearTimeout(timer);
		// Pressing this is the person confirming everything on the page, suggestions included.
		await flush({ everything: true });

		const missing = sectionFacts(section).filter((fact) => fact.required && !saved[fact.key]);
		for (const fact of missing)
			errors[fact.key] ??= fact.canDefer
				? 'Enter this, or tell us you don’t have it yet.'
				: 'This one still needs an answer.';
		const firstProblem = sectionFacts(section).find((fact) => errors[fact.key]);
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
				if (SETUP_FACTS.has(key)) errors[key] = message;
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
				? { ...current, status: sectionStatus(section, current.answers, markedDone) }
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

	const forbidden = $derived((query.error as HttpError | null)?.status === 403);
</script>

<svelte:head><title>{section?.title ?? 'Setup'} · Setup · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<div class="setup-section">
		<Breadcrumbs
			items={[{ label: 'Setup', href: resolve('/(app)/setup') }, { label: section?.title ?? '' }]}
		/>

		{#if !section}
			<ErrorState
				title="That part of setup doesn’t exist"
				description="Go back to your setup tasks to pick one."
			>
				{#snippet action()}
					<Button href={resolve('/(app)/setup')}>Back to setup tasks</Button>
				{/snippet}
			</ErrorState>
		{:else if query.isError}
			{#if forbidden}
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
		{:else if !fields}
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
				{/snippet}
			</PageHeader>

			{#if markedDone}
				<Banner type="success">
					This section is marked as done. You can still change any answer — it saves the same way.
				</Banner>
			{/if}

			{#each section.groups as group (group.title)}
				<SectionBlock title={group.title} hint={group.hint} form level={2}>
					{#each group.facts as fact (fact.key)}
						<SetupField
							{fact}
							bind:value={form[fact.key].value}
							bind:availability={form[fact.key].availability}
							bind:note={form[fact.key].note}
							error={errors[fact.key] ?? ''}
							suggested={suggested[fact.key] ?? false}
							onedit={() => edited(fact.key)}
							oncommit={() => committed(fact.key)}
						/>
					{/each}
				</SectionBlock>
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

		&__save {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-align: right;

			&--failed {
				color: var(--color-critical--onSurface);
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
