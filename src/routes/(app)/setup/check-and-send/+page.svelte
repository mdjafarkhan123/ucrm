<script lang="ts">
	import { SvelteSet } from 'svelte/reactivity';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchSetupCheck,
		fetchSetupSection,
		sendSetupToUplift,
		setupCheckKey,
		setupSectionKey,
		setupSummaryKey,
		type SetupWriteFailure
	} from '$lib/setup/api';
	import { SETUP_CHECK_TITLE, type SetupCheckItem, type SetupCheckStatus } from '$lib/setup/check';
	import type { HttpError } from '$lib/http-error';
	import type { PageProps } from './$types';

	// Client onboarding B13: Check and send to Uplift (plan §3.10, blueprint stage 12). Every task read back with
	// an Edit link, what still stops the send, what Uplift will follow up, and the confirmations. GOV.UK "Check
	// answers" is the pattern.

	let { data: shell }: PageProps = $props();
	const userId = $derived(shell.user?.id ?? null);

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: setupCheckKey(userId),
		queryFn: fetchSetupCheck
	}));
	const check = $derived(query.data);

	const STATUS: Record<
		SetupCheckStatus,
		{ label: string; badge: 'success' | 'warning' | 'critical' | 'inactive' | 'informative' }
	> = {
		unfinished: { label: 'Not finished', badge: 'critical' },
		needs_help: { label: 'Needs help', badge: 'warning' },
		waiting: { label: 'Waiting for item', badge: 'informative' },
		optional_skipped: { label: 'Optional items skipped', badge: 'inactive' },
		complete: { label: 'Complete', badge: 'success' }
	};

	const unfinished = $derived(
		check?.sections.filter((section) => section.status === 'unfinished') ?? []
	);
	// What Uplift continues without: answers given as "not yet" or "need help", by task.
	const followUps = $derived(
		check?.sections.flatMap((section) =>
			section.items
				.filter((item) => item.state === 'need_help' || item.state === 'not_yet')
				.map((item) => ({ section, item }))
		) ?? []
	);

	const ticked = new SvelteSet<string>();
	let confirmErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let sending = $state(false);

	const sentBefore = $derived(check?.sent ?? null);
	const nothingChanged = $derived(sentBefore !== null && check?.changed_count === 0);

	function warmSection(key: string) {
		void queryClient.prefetchQuery({
			queryKey: setupSectionKey(userId, key),
			queryFn: () => fetchSetupSection(key),
			staleTime: 30_000
		});
	}

	const editHref = (key: string) =>
		`${resolve('/(app)/setup/[section]', { section: key })}?from=check`;

	async function send() {
		if (!check || sending) return;
		formError = '';
		confirmErrors = {};
		for (const confirmation of check.confirmations)
			if (!ticked.has(confirmation.key)) confirmErrors[confirmation.key] = 'Tick this to send.';
		if (Object.keys(confirmErrors).length > 0) {
			document
				.getElementById('setup-confirmations')
				?.scrollIntoView({ behavior: 'smooth', block: 'start' });
			return;
		}

		sending = true;
		try {
			await sendSetupToUplift([...ticked], check.sent?.number ?? 0);
			ticked.clear();
			toast.success(
				sentBefore ? 'Your changes were sent to Uplift.' : 'Your setup was sent to Uplift.'
			);
			window.scrollTo({ top: 0, behavior: 'smooth' });
		} catch (error) {
			const failure = error as SetupWriteFailure;
			const { form, ...fields } = failure.fieldErrors ?? {};
			confirmErrors = fields;
			formError = form ?? (Object.keys(fields).length ? '' : failure.message);
		} finally {
			sending = false;
			void queryClient.invalidateQueries({ queryKey: setupCheckKey(userId) });
			void queryClient.invalidateQueries({ queryKey: setupSummaryKey(userId) });
		}
	}

	function itemText(item: SetupCheckItem): string {
		if (item.state === 'need_help') return 'You asked for Uplift’s help';
		if (item.state === 'not_yet') return 'You don’t have this yet';
		return 'Not answered';
	}

	const dateTime = (iso: string) =>
		new Date(iso).toLocaleString(undefined, { dateStyle: 'long', timeStyle: 'short' });

	const errorStatus = $derived((query.error as HttpError | null)?.status);
</script>

<svelte:head><title>{SETUP_CHECK_TITLE} · Setup · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<div class="setup-check">
		<Breadcrumbs
			items={[{ label: 'Setup', href: resolve('/(app)/setup') }, { label: 'Check and send' }]}
		/>

		{#if query.isError}
			{#if errorStatus === 403}
				<ErrorState
					title="Setup is handled by your account owner"
					description="Only an owner or administrator fills in setup. The rest of the CRM is ready for you to use."
				/>
			{:else}
				<ErrorState description="Your answers could not be loaded." retry={() => query.refetch()} />
			{/if}
		{:else if !check}
			<LoadingSkeleton variant="card" rows={4} />
		{:else}
			<PageHeader
				title={SETUP_CHECK_TITLE}
				description="Look over your answers. Change anything that isn’t right, then confirm and send. Uplift builds from what you send."
			/>

			{#if sentBefore}
				<Banner type="success">
					Sent to Uplift on {dateTime(sentBefore.submitted_at)} by {sentBefore.submitted_by_name}.
					{#if check.changed_count > 0}
						You have changed {check.changed_count}
						{check.changed_count === 1 ? 'answer' : 'answers'} since then — they are marked
						<strong>Changed</strong> below. Send them so Uplift works from the latest.
					{:else}
						You can still change any answer; send the changes from here.
					{/if}
				</Banner>
			{/if}

			{#if unfinished.length > 0}
				<Banner type="warning">
					<strong
						>Finish {unfinished.length === 1 ? 'this task' : 'these tasks'} before you send</strong
					>
					<ul class="setup-check__blockers">
						{#each unfinished as section (section.key)}
							<li>
								<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- editHref() resolves the path; only the query string is added. -->
								<a href={editHref(section.key)} onpointerenter={() => warmSection(section.key)}
									>{section.title}</a
								>
								— {section.problem}
							</li>
						{/each}
					</ul>
				</Banner>
			{/if}

			{#if followUps.length > 0}
				<SectionBlock
					title="Uplift will follow up on these"
					hint="They don’t stop you sending. Uplift carries on with everything else and gets back to you about each one."
					variant="filled"
				>
					<ul class="setup-check__follow-ups">
						{#each followUps as { section, item } (item.key)}
							<li>
								<span>
									<strong>{item.label}</strong>
									<span class="setup-check__muted">{section.title}</span>
								</span>
								<Badge status={item.state === 'need_help' ? 'warning' : 'informative'} size="small"
									>{item.state === 'need_help' ? 'Needs help' : 'Waiting for item'}</Badge
								>
							</li>
						{/each}
					</ul>
				</SectionBlock>
			{/if}

			{#each check.sections as section (section.key)}
				{@const status = STATUS[section.status]}
				<SectionBlock title={section.title}>
					{#snippet actions()}
						<Button
							variant="tertiary"
							size="small"
							href={editHref(section.key)}
							onhover={() => warmSection(section.key)}>Edit</Button
						>
					{/snippet}
					<div class="setup-check__status">
						<Badge status={status.badge} size="small">{status.label}</Badge>
						{#if section.problem}<span class="setup-check__muted">{section.problem}</span>{/if}
					</div>
					{#if section.items.length > 0}
						<dl class="setup-check__answers">
							{#each section.items as item (item.key)}
								<div class="setup-check__row" class:setup-check__row--changed={item.changed}>
									<dt>
										{item.label}
										{#if item.changed}<Badge status="informative" size="small">Changed</Badge>{/if}
									</dt>
									<dd>
										{#if item.state === 'answered'}
											{#if item.same_as}
												<span class="setup-check__muted">Same as “{item.same_as}”</span>
											{/if}
											{#each item.lines as line, index (index)}
												<span class="setup-check__line">{line}</span>
											{/each}
										{:else}
											<span
												class="setup-check__muted"
												class:setup-check__missing={item.state === 'skipped' && item.required}
												>{item.state === 'skipped' && item.required
													? 'Still needs an answer'
													: itemText(item)}</span
											>
											{#if item.note}<span class="setup-check__line">“{item.note}”</span>{/if}
										{/if}
									</dd>
								</div>
							{/each}
						</dl>
					{/if}
					{#if section.no_longer_asked.length > 0}
						<p class="setup-check__muted">
							No longer asked because of a changed answer:
							{section.no_longer_asked.map((item) => item.label).join(', ')}.
						</p>
					{/if}
				</SectionBlock>
			{/each}

			{#if nothingChanged}
				<p class="setup-check__muted setup-check__end">
					Nothing has changed since you sent your setup. Change an answer above and you can send it
					from here.
				</p>
			{:else}
				<div id="setup-confirmations" class="setup-check__confirm">
					<SectionBlock
						title="Before you send"
						hint="Tick each one to confirm. Uplift keeps a record of what you confirmed, who sent it and when."
						form
					>
						{#each check.confirmations as confirmation (confirmation.key)}
							<Checkbox
								id="setup-confirm-{confirmation.key}"
								label={confirmation.wording}
								checked={ticked.has(confirmation.key)}
								invalid={Boolean(confirmErrors[confirmation.key])}
								description={confirmErrors[confirmation.key] ?? ''}
								onchange={(on) => {
									if (on) ticked.add(confirmation.key);
									else ticked.delete(confirmation.key);
									delete confirmErrors[confirmation.key];
								}}
							/>
						{/each}
					</SectionBlock>

					{#if formError}<Banner type="error">{formError}</Banner>{/if}

					<footer class="setup-check__footer">
						<Button onclick={send} loading={sending} disabled={!check.can_send}
							>{sentBefore ? 'Send changes to Uplift' : 'Send to Uplift'}</Button
						>
						{#if unfinished.length > 0}
							<span class="setup-check__muted"
								>Finish {unfinished.length}
								{unfinished.length === 1 ? 'task' : 'tasks'} first.</span
							>
						{/if}
					</footer>
				</div>
			{/if}
		{/if}
	</div>
</PageContainer>

<style lang="scss">
	.setup-check {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		max-width: 880px;
		margin-inline: auto;

		:global(.page-header) {
			margin-bottom: 0;
		}

		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__missing {
			color: var(--color-critical);
			font-weight: 700;
		}

		&__blockers {
			margin: var(--space-small) 0 0;
			padding-left: var(--space-large);

			li + li {
				margin-top: var(--space-smallest);
			}

			a {
				color: inherit;
				font-weight: 700;
			}
		}

		&__follow-ups {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				align-items: center;
				justify-content: space-between;
				gap: var(--space-base);
				padding-block: var(--space-small);
			}

			li + li {
				border-top: var(--border-base) solid var(--color-border);
			}

			li > span {
				display: flex;
				flex-direction: column;
				gap: var(--space-smallest);
				min-width: 0;
			}

			strong {
				color: var(--color-heading);
			}
		}

		&__status {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__answers {
			display: flex;
			flex-direction: column;
			margin: 0;
		}

		&__row {
			display: grid;
			grid-template-columns: minmax(0, 2fr) minmax(0, 3fr);
			gap: var(--space-base);
			padding: var(--space-slim) var(--space-small);
			border-top: var(--border-base) solid var(--color-border);

			dt {
				display: flex;
				flex-wrap: wrap;
				align-items: center;
				gap: var(--space-small);
				color: var(--color-heading);
				font-weight: 700;
			}

			dd {
				display: flex;
				flex-direction: column;
				gap: var(--space-smallest);
				margin: 0;
				color: var(--color-text);
				overflow-wrap: anywhere;
				white-space: pre-line;
			}

			&--changed {
				border-radius: var(--radius-base);
				background: var(--color-surface--background);
			}
		}

		&__confirm {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			scroll-margin-top: var(--space-large);
		}

		&__footer {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-base);
		}

		&__end {
			text-align: center;
		}
	}

	@media (max-width: 767px) {
		.setup-check__row {
			grid-template-columns: 1fr;
			gap: var(--space-smallest);
			padding-inline: 0;
		}
	}
</style>
