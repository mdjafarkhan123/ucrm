<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Tabs from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import TaskQueue from '$lib/components/jafar/texting-setup/TaskQueue.svelte';
	import TaskPanel from '$lib/components/jafar/texting-setup/TaskPanel.svelte';
	import OptOutTaskPanel from '$lib/components/jafar/texting-setup/OptOutTaskPanel.svelte';
	import { OPT_OUT_LANGUAGES, languageName } from '$lib/communications/sms-opt-out-words';
	import CantTurnOnDialog from '$lib/components/jafar/texting-setup/CantTurnOnDialog.svelte';
	import WaitingOnTwilio from '$lib/components/jafar/texting-setup/WaitingOnTwilio.svelte';
	import CountriesPrices from '$lib/components/jafar/texting-setup/CountriesPrices.svelte';
	import ChangePriceDialog from '$lib/components/jafar/texting-setup/ChangePriceDialog.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import { relativeTime } from '$lib/collaboration/format';
	import {
		fetchTextingSetup,
		fetchWaitingOnTwilio,
		fetchPriceList,
		priceListKey,
		waitingOnTwilioKey,
		organizationDestinationsKey,
		textingSetupKey,
		whenAsked,
		type AlreadyFinished,
		type OptOutTask,
		type PriceListRow,
		type TextingTask
	} from '$lib/jafar/texting-setup';
	import messageIcon from '@tabler/icons/outline/message-2.svg?raw';
	import externalIcon from '@tabler/icons/outline/external-link.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import tagIcon from '@tabler/icons/outline/tag.svg?raw';
	import userCheckIcon from '@tabler/icons/outline/user-check.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building-store.svg?raw';

	// Platform Operations › Texting setup (Stage 10 Part 5b, `concept.pen` board `v6Jtu`): the Twilio work only
	// Uplift can do, for every business, in one queue. Pick a task and its panel walks through it.
	const queryClient = useQueryClient();
	const toast = getToastManager();

	const queue = createQuery(() => ({ queryKey: textingSetupKey, queryFn: fetchTextingSetup }));

	const tasks = $derived(queue.data?.tasks ?? []);
	// Part 5d: opt-out words tasks share the queue, oldest first with the countries.
	const optOutTasks = $derived(queue.data?.opt_out_tasks ?? []);
	type AnyTask = TextingTask | OptOutTask;
	const isOptOut = (task: AnyTask): task is OptOutTask => 'language' in task;
	const ordered = $derived(
		[...tasks, ...optOutTasks].sort((a, b) => a.requested_at.localeCompare(b.requested_at))
	);
	const summary = $derived(queue.data?.summary);

	// A business's Open task arrives with `?task=<id>`, opening that task first.
	let selectedId = $state<string | null>(page.url.searchParams.get('task'));
	const selected = $derived(ordered.find((task) => task.id === selectedId) ?? ordered[0] ?? null);
	// The task someone is working on: picked in the queue, or its box ticked. If it leaves the queue because a
	// teammate finished it, the panel says so instead of moving on to another task under their hand.
	let pinned = $state<AnyTask | null>(null);

	/** What the panel says once a task is finished here, or was finished by a teammate first. */
	type Result =
		| { kind: 'done'; task: AnyTask; who: string; at: string }
		| { kind: 'already'; task: AnyTask; finished: AlreadyFinished };
	let result = $state<Result | null>(null);
	const shown = $derived.by((): Result | null => {
		if (result) return result;
		if (!pinned || marking || closing || ordered.some((task) => task.id === pinned?.id))
			return null;
		const finished = queue.data?.recently_finished.find((row) => row.id === pinned?.id);
		return {
			kind: 'already',
			task: pinned,
			finished: finished ?? {
				kind: isOptOut(pinned) ? 'opt_out_added' : 'switched_on',
				at: new Date().toISOString(),
				who: null
			}
		};
	});

	let marking = $state(false);
	// A task's price step opens the same Change price pop-up as the Countries & prices tab.
	let pricing = $state<{ row: PriceListRow; listed: string[] } | null>(null);
	let loadingPrice = $state(false);

	async function openPrice(task: TextingTask) {
		loadingPrice = true;
		try {
			const list = await queryClient.fetchQuery({
				queryKey: priceListKey,
				queryFn: fetchPriceList
			});
			const row = list.countries.find((item) => item.country === task.country);
			if (row) pricing = { row, listed: list.countries.map((item) => item.country) };
			else toast.error('Couldn’t open the price', 'Try again from Countries & prices.');
		} catch {
			toast.error('Couldn’t load prices', 'Check your connection and try again.');
		} finally {
			loadingPrice = false;
		}
	}
	let closingTask = $state<TextingTask | null>(null);
	let closing = $state(false);
	let closeError = $state('');

	function select(id: string) {
		if (marking || closing) return;
		result = null;
		selectedId = id;
		pinned = ordered.find((task) => task.id === id) ?? null;
	}

	function nextTask() {
		result = null;
		selectedId = null;
		pinned = null;
	}

	async function refresh(task: AnyTask) {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: textingSetupKey }),
			queryClient.invalidateQueries({ queryKey: organizationDestinationsKey(task.organization_id) })
		]);
	}

	async function post(url: string, body?: unknown) {
		const response = await fetch(url, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body ?? {})
		});
		return { status: response.status, body: await response.json().catch(() => ({})) };
	}

	async function mark(task: TextingTask) {
		marking = true;
		try {
			const answer = await post(`/api/jafar/texting-setup/${task.id}/switch-on`);
			if (answer.status === 409 && answer.body.already_finished) {
				result = { kind: 'already', task, finished: answer.body.already_finished };
			} else if (answer.status >= 400) {
				toast.error(
					'Couldn’t mark it as turned on',
					answer.body.error ?? 'Nothing was changed. Try again.'
				);
				return;
			} else {
				result = {
					kind: 'done',
					task,
					who: answer.body.actor_name ?? 'you',
					at: answer.body.destination?.ready_at ?? new Date().toISOString()
				};
			}
			await refresh(task);
		} catch {
			toast.error('Couldn’t mark it as turned on', 'Check your connection. Nothing was changed.');
		} finally {
			marking = false;
		}
	}

	/** "Mark as done" on an opt-out words task: the words are in the business's Twilio Advanced Opt-Out. */
	async function markWords(task: OptOutTask) {
		marking = true;
		try {
			const answer = await post('/api/jafar/texting-setup/opt-out', {
				organization_id: task.organization_id,
				language: task.language
			});
			if (answer.status === 409 && answer.body.already_finished) {
				result = { kind: 'already', task, finished: answer.body.already_finished };
			} else if (answer.status >= 400) {
				toast.error(
					'Couldn’t mark it as done',
					answer.body.error ?? 'Nothing was changed. Try again.'
				);
				return;
			} else {
				result = {
					kind: 'done',
					task,
					who: answer.body.actor_name ?? 'you',
					at: answer.body.language?.added_at ?? new Date().toISOString()
				};
			}
			await refresh(task);
		} catch {
			toast.error('Couldn’t mark it as done', 'Check your connection. Nothing was changed.');
		} finally {
			marking = false;
		}
	}

	async function close(input: { reason: string; business_message: string }) {
		const task = closingTask;
		if (!task) return;
		closing = true;
		closeError = '';
		try {
			const answer = await post(`/api/jafar/texting-setup/${task.id}/close`, input);
			if (answer.status === 409 && answer.body.already_finished) {
				closingTask = null;
				result = { kind: 'already', task, finished: answer.body.already_finished };
			} else if (answer.status >= 400) {
				closeError = answer.body.error ?? 'The request could not be closed.';
				return;
			} else {
				closingTask = null;
				toast.success(
					`${countryDisplayName(task.country)} request closed`,
					`${task.organization_name} sees why in place of Setting up.`
				);
				nextTask();
			}
			await refresh(task);
		} catch {
			closeError = 'Check your connection. Nothing was changed.';
		} finally {
			closing = false;
		}
	}

	function businessHref(task: AnyTask) {
		return `${resolve('/jafar/(protected)/organizations/[organizationId]', { organizationId: task.organization_id })}?tab=communications&channel=texting`;
	}

	function doneTime(at: string) {
		const time = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(
			new Date(at)
		);
		return `${whenAsked(at)} at ${time}`;
	}

	const noPrice = $derived(summary?.countries_without_price ?? []);
	const noPriceNote = $derived.by(() => {
		const first = noPrice[0];
		if (!first) return 'Every asked country has a price';
		const asked = `${first.businesses} ${first.businesses === 1 ? 'business' : 'businesses'} asked`;
		const more = noPrice.length > 1 ? ` · +${noPrice.length - 1} more` : '';
		return `${countryDisplayName(first.country)} · ${asked}${more}`;
	});
</script>

<svelte:head><title>Texting setup · Control Room</title></svelte:head>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="texting-setup">
	<PageHeader
		title="Texting setup"
		description="The Twilio work only Uplift can do, so businesses can text, and the prices they pay."
		icon={messageIcon}
		tone="conversation"
		class="texting-setup__header"
	>
		{#snippet actions()}
			<Button variant="secondary" href="https://console.twilio.com/" target="_blank">
				<span aria-hidden="true">{@html externalIcon}</span>
				Open Twilio
			</Button>
		{/snippet}
	</PageHeader>

	<div class="texting-setup__numbers">
		<KpiCard
			label="To do"
			value={String(summary?.to_do ?? 0)}
			note={summary?.oldest_at ? `Oldest asked ${whenAsked(summary.oldest_at)}` : 'Nothing waiting'}
			icon={pencilIcon}
			tone="informative"
			loading={queue.isPending}
		/>
		<KpiCard
			label="Waiting on Twilio"
			value={String(summary?.waiting_on_twilio ?? 0)}
			note="Registrations under review"
			icon={hourglassIcon}
			tone="warning"
			loading={queue.isPending}
		/>
		<KpiCard
			label={summary?.countries_live === 1 ? 'Country live' : 'Countries live'}
			value={String(summary?.countries_live ?? 0)}
			note={`Across ${summary?.businesses_live ?? 0} ${summary?.businesses_live === 1 ? 'business' : 'businesses'}`}
			icon={circleCheckIcon}
			tone="success"
			loading={queue.isPending}
		/>
		<KpiCard
			label={noPrice.length === 1 ? 'Country with no price' : 'Countries with no price'}
			value={String(noPrice.length)}
			note={noPriceNote}
			icon={tagIcon}
			tone="warning"
			loading={queue.isPending}
		/>
	</div>

	<Tabs
		label="Texting setup sections"
		tabs={[
			{ value: 'to-do', label: 'To do', badge: String(summary?.to_do ?? 0) },
			{
				value: 'waiting',
				label: 'Waiting on Twilio',
				badge: String(summary?.waiting_on_twilio ?? 0),
				onhover: () =>
					void queryClient.prefetchQuery({
						queryKey: waitingOnTwilioKey,
						queryFn: fetchWaitingOnTwilio
					})
			},
			{
				value: 'prices',
				label: 'Countries & prices',
				onhover: () =>
					void queryClient.prefetchQuery({ queryKey: priceListKey, queryFn: fetchPriceList })
			}
		]}
	>
		<TabPanel value="to-do">
			{#if queue.isPending}
				<div class="texting-setup__work" aria-busy="true" aria-label="Loading the to-do list">
					<div class="texting-setup__skeleton texting-setup__skeleton--queue">
						{#each [140, 110, 150, 100] as width (width)}
							<div class="texting-setup__skeleton-row">
								<span class="texting-setup__skeleton-dot"></span>
								<span class="texting-setup__skeleton-lines">
									<span style:width={`${width}px`}></span>
									<span style:width={`${width - 60}px`}></span>
								</span>
							</div>
						{/each}
					</div>
					<div class="texting-setup__skeleton">
						<div class="texting-setup__skeleton-row">
							<span class="texting-setup__skeleton-dot texting-setup__skeleton-dot--big"></span>
							<span class="texting-setup__skeleton-lines">
								<span style:width="240px"></span>
								<span style:width="160px"></span>
							</span>
						</div>
						{#each [180, 150, 200] as width (width)}
							<div class="texting-setup__skeleton-row">
								<span class="texting-setup__skeleton-dot"></span>
								<span class="texting-setup__skeleton-lines">
									<span style:width={`${width}px`}></span>
									<span style:width="100%"></span>
								</span>
							</div>
						{/each}
					</div>
				</div>
			{:else if queue.isError}
				<div class="texting-setup__state">
					<ErrorState
						title="Couldn’t load the to-do list"
						description="Check your connection and try again. Nothing was changed."
						retry={() => queue.refetch()}
					/>
				</div>
			{:else if ordered.length === 0 && !shown}
				<div class="texting-setup__state">
					<EmptyState
						title="Nothing waits on Uplift"
						description="When a business asks for a new country, it lands here straight away."
						icon={circleCheckIcon}
						tone="success"
					/>
				</div>
			{:else}
				<div class="texting-setup__work">
					<TaskQueue
						{tasks}
						{optOutTasks}
						selectedId={shown ? null : (selected?.id ?? null)}
						onSelect={select}
					/>
					{#if shown && isOptOut(shown.task)}
						{@const words = shown.task}
						{@const language = languageName(words.language)}
						<section class="texting-setup__result" aria-live="polite">
							{#if shown.kind === 'done'}
								<IconTile icon={circleCheckIcon} tone="success" size={40} />
								<h2>{language} words are in for {words.organization_name}</h2>
								<p>
									Its customers can reply {OPT_OUT_LANGUAGES[words.language]?.stop[0]} to stop texts.
									We noted that {shown.who} did it, {doneTime(shown.at)}.
								</p>
							{:else}
								{@const who = shown.finished.who ?? 'A teammate'}
								<IconTile icon={userCheckIcon} tone="informative" size={40} />
								<h2>{who} already did this</h2>
								<p>
									{who} added the {language} opt-out words for {words.organization_name}
									{relativeTime(shown.finished.at).toLowerCase()}. Nothing else to do here.
								</p>
							{/if}
							<div class="texting-setup__result-actions">
								<Button variant="secondary" href={businessHref(words)}>
									<span aria-hidden="true">{@html buildingIcon}</span>
									Open {words.organization_name}
								</Button>
								{#if ordered.length}
									<Button onclick={nextTask}>
										<span aria-hidden="true">{@html arrowRightIcon}</span>
										Next task
									</Button>
								{/if}
							</div>
						</section>
					{:else if shown && !isOptOut(shown.task)}
						{@const task = shown.task}
						{@const country = countryDisplayName(task.country)}
						<section class="texting-setup__result" aria-live="polite">
							{#if shown.kind === 'done'}
								<IconTile icon={circleCheckIcon} tone="success" size={40} />
								<h2>{country} is on for {task.organization_name}</h2>
								<p>
									{task.organization_name} can text there now{task.price.segment
										? ' and sees Ready'
										: ', and sees Ready once it has a price'}. We noted that {shown.who} did it, {doneTime(
										shown.at
									)}.
								</p>
								<div class="texting-setup__result-actions">
									<Button variant="secondary" href={businessHref(task)}>
										<span aria-hidden="true">{@html buildingIcon}</span>
										Open {task.organization_name}
									</Button>
									{#if ordered.length}
										<Button onclick={nextTask}>
											<span aria-hidden="true">{@html arrowRightIcon}</span>
											Next task
										</Button>
									{/if}
								</div>
							{:else}
								{@const who = shown.finished.who ?? 'A teammate'}
								<IconTile icon={userCheckIcon} tone="informative" size={40} />
								<h2>{who} already did this</h2>
								<p>
									{who}
									{shown.finished.kind === 'closed' ? 'closed the request for' : 'marked'}
									{country}
									{shown.finished.kind === 'closed' ? 'from' : 'as turned on for'}
									{task.organization_name}
									{relativeTime(shown.finished.at).toLowerCase()}. Nothing else to do here.
								</p>
								{#if ordered.length}
									<div class="texting-setup__result-actions">
										<Button onclick={nextTask}>
											<span aria-hidden="true">{@html arrowRightIcon}</span>
											Next task
										</Button>
									</div>
								{/if}
							{/if}
						</section>
					{:else if selected && isOptOut(selected)}
						{#key selected.id}
							<OptOutTaskPanel
								task={selected}
								{marking}
								onTick={() => (pinned = selected)}
								onMark={() => markWords(selected)}
							/>
						{/key}
					{:else if selected}
						{#key selected.id}
							<TaskPanel
								task={selected}
								{marking}
								{closing}
								onTick={() => (pinned = selected)}
								onPrice={() => {
									if (!loadingPrice) void openPrice(selected);
								}}
								onMark={() => mark(selected)}
								onOptOut={(language) => select(`opt-out:${selected.organization_id}:${language}`)}
								onCantTurnOn={() => {
									closeError = '';
									closingTask = selected;
								}}
							/>
						{/key}
					{/if}
				</div>
			{/if}
		</TabPanel>
		<TabPanel value="waiting">
			<WaitingOnTwilio />
		</TabPanel>
		<TabPanel value="prices">
			<CountriesPrices />
		</TabPanel>
	</Tabs>
</div>

{#if pricing}
	<ChangePriceDialog row={pricing.row} listed={pricing.listed} onClose={() => (pricing = null)} />
{/if}

{#if closingTask}
	<CantTurnOnDialog
		task={closingTask}
		saving={closing}
		error={closeError}
		onClose={() => (closingTask = null)}
		onSubmit={close}
	/>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.texting-setup {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		min-width: 0;

		// The page's own gap spaces the header; PageHeader's margin would double it.
		:global(.texting-setup__header) {
			margin-bottom: 0;
		}

		&__numbers {
			display: grid;
			grid-template-columns: repeat(4, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__work {
			display: grid;
			grid-template-columns: 380px minmax(0, 1fr);
			align-items: stretch;
			gap: var(--space-large);
			min-height: 640px;
		}

		&__state {
			padding: var(--space-larger);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
		}

		&__result {
			display: flex;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			gap: var(--space-slim);
			padding: var(--space-larger);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
			text-align: center;

			h2 {
				margin: var(--space-small) 0 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
				font-weight: 700;
			}

			p {
				max-width: 420px;
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
			}
		}

		&__result-actions {
			display: flex;
			gap: var(--space-slim);
			margin-top: var(--space-small);
		}

		&__skeleton {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-medium);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
		}

		&__skeleton-row {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}

		&__skeleton-dot {
			flex: none;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);

			&--big {
				width: 40px;
				height: 40px;
			}
		}

		&__skeleton-lines {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);

			span {
				max-width: 100%;
				height: 10px;
				border-radius: var(--radius-small);
				background: var(--color-surface--background);
			}
		}
	}
</style>
