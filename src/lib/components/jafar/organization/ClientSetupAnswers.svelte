<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import clipboardIcon from '@tabler/icons/outline/clipboard-check.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import SetupAnswerList from '$lib/components/setup/SetupAnswerList.svelte';
	import SetupReturnDialog from './SetupReturnDialog.svelte';
	import { iconForMimeType } from '$lib/collaboration/file-icons';
	import {
		organizationSetupQuery,
		organizationSetupRemindersUrl,
		organizationSetupReviewsUrl
	} from '$lib/jafar/organization-setup-queries';
	import { jafarOrganizationKey } from '$lib/jafar/query-keys';
	import { SETUP_CHECK_STATUS } from '$lib/setup/check';
	import { clientSetupRemindersText, type ClientSetupFile } from '$lib/setup/client-page';
	import { SETUP_REVIEW_STATE, type SetupSectionReview } from '$lib/setup/review';
	import { formatDateTime } from './format';

	// Client onboarding C2 (plan §8): the setup a client sent to Uplift, read back by task the way they saw it
	// on Check and send (GOV.UK "Check answers"), with each earlier send kept and selectable — the version
	// history pattern of Google Forms responses and Typeform's response view. Changed answers are marked
	// against the send before. Also the switch for the client's setup reminder emails (plan §5).
	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	/** The send on screen; null follows the newest. */
	let sendNumber = $state<number | null>(null);

	const query = createQuery(() => organizationSetupQuery(organizationId, sendNumber));
	const view = $derived(query.data);
	const send = $derived(view?.send ?? null);
	const newest = $derived(view?.sends[0]?.number ?? null);
	const isNewest = $derived(send !== null && send.number === newest);

	const sendOptions = $derived(
		(view?.sends ?? []).map((item) => ({
			value: String(item.number),
			label: `${item.number === newest ? 'Latest send' : `Send ${item.number}`} · ${formatDateTime(item.submitted_at)}`
		}))
	);

	function chooseSend(value: string) {
		const number = Number(value);
		sendNumber = number === newest ? null : number;
	}

	// Photos open full size; the Lightbox steps through every photo in the send.
	const fileHref = (fileId: string) =>
		`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/files/${encodeURIComponent(fileId)}`;
	const isPhoto = (file: ClientSetupFile) => file.state === 'ready' && Boolean(file.thumb_url);
	const photos = $derived(
		Object.values(send?.files ?? {}).flatMap((files) => files.filter(isPhoto))
	);
	const lightboxItems = $derived<LightboxItem[]>(
		photos.map((file) => ({
			id: file.id,
			src: fileHref(file.id),
			thumbSrc: file.thumb_url ?? fileHref(file.id),
			caption: file.name
		}))
	);
	let lightboxOpen = $state(false);
	let lightboxIndex = $state(0);

	function openPhoto(fileId: string) {
		lightboxIndex = Math.max(
			photos.findIndex((file) => file.id === fileId),
			0
		);
		lightboxOpen = true;
	}

	const protectedKeys = $derived(new Set(send?.protected_questions ?? []));

	let reminderError = $state('');
	const reminders = createMutation(() => ({
		mutationFn: async (paused: boolean) => {
			const response = await fetch(organizationSetupRemindersUrl(organizationId), {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ paused })
			});
			if (!response.ok) {
				const result = (await response.json().catch(() => ({}))) as { error?: string };
				throw new Error(result.error ?? 'The reminders could not be changed. Try again.');
			}
		},
		onMutate: () => {
			reminderError = '';
		},
		onError: (error) => {
			reminderError = error.message;
		},
		onSettled: () => {
			// Every send's view carries the reminders, and the change is in the Activity tab's history.
			void queryClient.invalidateQueries({ queryKey: jafarOrganizationKey(organizationId) });
		}
	}));

	const remindersOn = $derived(!view?.reminders?.paused_at);

	// C3 (plan §4): Accept or Send back one task of the newest send. The page holds the send number it showed,
	// so a decision on answers Jafar has not seen is refused and the newest send is loaded instead.
	type ReviewInput =
		| { decision: 'accepted'; section_key: string }
		| { decision: 'returned'; section_key: string; note: string; question_keys: string[] };

	let reviewError = $state<{ section: string; message: string } | null>(null);
	let returning = $state<{ key: string; title: string } | null>(null);

	const review = createMutation(() => ({
		mutationFn: async (input: ReviewInput) => {
			const response = await fetch(organizationSetupReviewsUrl(organizationId), {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ ...input, send: send?.number })
			});
			if (!response.ok) {
				const result = (await response.json().catch(() => ({}))) as {
					error?: string;
					field_errors?: Record<string, string>;
				};
				const message =
					Object.values(result.field_errors ?? {})[0] ??
					result.error ??
					'Your decision could not be saved. Try again.';
				throw new Error(message);
			}
		},
		onMutate: () => {
			reviewError = null;
		},
		onSuccess: (_data, input) => {
			if (input.decision === 'returned') returning = null;
		},
		onError: (error, input) => {
			reviewError = { section: input.section_key, message: error.message };
		},
		onSettled: () => {
			// The decision shows on this tab, and is in the Activity tab's history.
			void queryClient.invalidateQueries({ queryKey: jafarOrganizationKey(organizationId) });
		}
	}));

	const askHref = (sectionKey: string, title: string) =>
		`/jafar/support?${new URLSearchParams({ new: organizationId, section: sectionKey, about: title })}`;

	function reviewedLine(entry: SetupSectionReview): string {
		const decision = entry.decision;
		if (!decision) return '';
		const when = formatDateTime(decision.reviewed_at);
		if (entry.state === 'accepted') return `Accepted by ${decision.reviewed_by_email} on ${when}.`;
		if (entry.state === 'changed')
			return `You accepted send ${decision.submission_number}; the client has changed this task since.`;
		if (entry.state === 'resent')
			return `You sent it back on ${when}; the client has sent it again.`;
		return '';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if query.isPending}
	<LoadingSkeleton variant="card" rows={4} label="Loading the client’s setup" />
{:else if query.isError}
	<ErrorState
		title="The client’s setup could not be loaded"
		description={query.error.message}
		retry={() => query.refetch()}
	/>
{:else if view}
	<SectionBlock
		title="Sent to Uplift"
		icon={clipboardIcon}
		hint="What the client sent with Send to Uplift. Each send is kept as it was sent."
	>
		{#snippet actions()}
			{#if sendOptions.length > 1}
				<Select
					id="client-setup-send"
					ariaLabel="Which send to show"
					value={String(send?.number ?? newest)}
					options={sendOptions}
					onchange={chooseSend}
				/>
			{/if}
		{/snippet}
		{#if !send}
			<EmptyState
				title="Not sent to Uplift yet"
				description="The client’s answers appear here once they finish every setup task and press Send to Uplift. Their progress is on the Onboarding list."
				icon={clipboardIcon}
			/>
		{:else}
			<dl class="client-setup__facts">
				<div>
					<dt>Sent by</dt>
					<dd>
						{send.submitted_by_name}
						<span class="client-setup__muted">{send.submitted_by_email}</span>
					</dd>
				</div>
				<div>
					<dt>Sent on</dt>
					<dd>{formatDateTime(send.submitted_at)}</dd>
				</div>
				<div>
					<dt>Send</dt>
					<dd>
						{send.number} of {view.sends.length}
						{#if send.compared_with}
							<span class="client-setup__muted">
								{send.changed_count}
								{send.changed_count === 1 ? 'answer' : 'answers'} changed since send {send.compared_with}
							</span>
						{/if}
					</dd>
				</div>
			</dl>
			{#if !isNewest}
				<Banner type="notice">
					This is an earlier send. The client has sent their setup again since.
					{#snippet action()}
						<Button size="small" variant="secondary" onclick={() => (sendNumber = null)}
							>Show the latest</Button
						>
					{/snippet}
				</Banner>
			{:else if view.unsent_changes > 0}
				<Banner type="notice">
					The client has changed {view.unsent_changes}
					{view.unsent_changes === 1 ? 'answer' : 'answers'} since this send but has not sent
					{view.unsent_changes === 1 ? 'it' : 'them'} yet. You see them here once they press Send changes
					to Uplift.
				</Banner>
			{/if}
		{/if}
	</SectionBlock>

	{#if view.reminders}
		<SectionBlock
			title="Setup reminders"
			icon={bellIcon}
			hint="Emails after about 24 hours, 3 days and 7 days without setup activity, each linking to the next task."
		>
			{#if view.sends.length > 0 && remindersOn}
				<!-- Sent setup stops them by itself, so there is nothing to switch. -->
				<p class="client-setup__muted">
					{clientSetupRemindersText(view.reminders, true, formatDateTime)}
				</p>
			{:else}
				<Toggle
					id="client-setup-reminders"
					label="Send setup reminder emails"
					description={clientSetupRemindersText(
						view.reminders,
						view.sends.length > 0,
						formatDateTime
					)}
					checked={remindersOn}
					disabled={reminders.isPending}
					onchange={(on) => reminders.mutate(!on)}
				/>
			{/if}
			{#if reminderError}
				<p class="client-setup__error" role="alert">{reminderError}</p>
			{/if}
		</SectionBlock>
	{/if}

	{#if send}
		{#each send.sections as section (section.key)}
			{@const status = SETUP_CHECK_STATUS[section.status]}
			{@const entry = view.reviews?.[section.key] ?? null}
			{@const returned = entry?.state === 'returned' ? entry.decision : null}
			{@const deciding = review.isPending && review.variables?.section_key === section.key}
			<SectionBlock title={section.title}>
				<div class="client-setup__status">
					<Badge status={status.badge} size="small">{status.label}</Badge>
					{#if entry}
						{@const label = SETUP_REVIEW_STATE[entry.state]}
						<Badge status={label.badge} size="small">{label.label}</Badge>
					{/if}
				</div>
				{#if entry}
					<div class="client-setup__review">
						{#if returned}
							<div class="client-setup__returned">
								<p class="client-setup__muted">
									Sent back by {returned.reviewed_by_email} on {formatDateTime(
										returned.reviewed_at
									)}
								</p>
								<p>“{returned.note}”</p>
							</div>
						{:else if reviewedLine(entry)}
							<p class="client-setup__muted">{reviewedLine(entry)}</p>
						{/if}
						<div class="client-setup__review-actions">
							{#if entry.state !== 'accepted'}
								<Button
									size="small"
									variant={returned ? 'secondary' : 'primary'}
									loading={deciding && review.variables?.decision === 'accepted'}
									disabled={review.isPending}
									onclick={() => review.mutate({ decision: 'accepted', section_key: section.key })}
									>{returned ? 'Accept instead' : 'Accept'}</Button
								>
							{/if}
							<Button
								size="small"
								variant="secondary"
								disabled={review.isPending}
								onclick={() => {
									reviewError = null;
									returning = { key: section.key, title: section.title };
								}}>{returned ? 'Change what you asked' : 'Send back'}</Button
							>
							<Button size="small" variant="tertiary" href={askHref(section.key, section.title)}
								>Ask a question</Button
							>
						</div>
					</div>
					{#if reviewError?.section === section.key && !returning}
						<p class="client-setup__error" role="alert">{reviewError.message}</p>
					{/if}
				{/if}
				{#if section.items.length > 0}
					<SetupAnswerList
						items={section.items}
						audience="uplift"
						changedLabel={`Changed since send ${send.compared_with}`}
						flagged={returned ? new Set(returned.question_keys) : undefined}
					>
						{#snippet extra(item)}
							{@const files = send.files[item.key] ?? []}
							{#if files.length > 0}
								<ul class="client-setup__files">
									{#each files as file (file.id)}
										<li>
											{#if isPhoto(file)}
												<button
													type="button"
													class="client-setup__thumb"
													aria-label={`View ${file.name}`}
													onclick={() => openPhoto(file.id)}
												>
													<img src={file.thumb_url} alt="" loading="lazy" />
												</button>
											{:else if file.state === 'ready'}
												<!-- eslint-disable svelte/no-navigation-without-resolve -- a download route, not a page -->
												<a
													class="client-setup__file"
													href={fileHref(file.id)}
													target="_blank"
													rel="noopener noreferrer"
												>
													<span aria-hidden="true">{@html iconForMimeType(file.mime_type)}</span>
													{file.name}
												</a>
												<!-- eslint-enable svelte/no-navigation-without-resolve -->
											{:else}
												<span class="client-setup__file client-setup__muted">
													{file.name} — {file.state === 'checking'
														? 'being checked for viruses'
														: file.state === 'refused'
															? 'refused'
															: 'removed since'}
												</span>
											{/if}
										</li>
									{/each}
								</ul>
							{:else if protectedKeys.has(item.key)}
								<span class="client-setup__muted">Open them under Protected documents below.</span>
							{/if}
						{/snippet}
					</SetupAnswerList>
				{/if}
				{#if section.no_longer_asked.length > 0}
					<p class="client-setup__muted">
						Answered in send {send.compared_with} but no longer asked:
						{section.no_longer_asked.map((item) => item.label).join(', ')}.
					</p>
				{/if}
			</SectionBlock>
		{/each}

		<SectionBlock
			title="What they confirmed"
			hint={`Ticked by ${send.submitted_by_name} when sending · wording of ${send.confirmations_version}`}
		>
			<ul class="client-setup__confirmations">
				{#each send.confirmations as confirmation (confirmation.key)}
					<li>
						<span class="client-setup__tick" aria-hidden="true">{@html checkIcon}</span>
						{confirmation.wording}
					</li>
				{/each}
			</ul>
		</SectionBlock>
	{/if}
{/if}

{#if returning && send}
	{@const target = send.sections.find((section) => section.key === returning?.key)}
	{@const earlier = view?.reviews?.[returning.key]}
	{@const before = earlier?.state === 'returned' ? earlier.decision : null}
	<SetupReturnDialog
		sectionTitle={returning.title}
		items={target?.items ?? []}
		initialNote={before?.note ?? ''}
		initialKeys={before?.question_keys ?? []}
		pending={review.isPending}
		error={reviewError?.section === returning.key ? reviewError.message : ''}
		onSubmit={(input) =>
			returning && review.mutate({ decision: 'returned', section_key: returning.key, ...input })}
		onClose={() => (returning = null)}
	/>
{/if}

<Lightbox
	open={lightboxOpen}
	items={lightboxItems}
	bind:index={lightboxIndex}
	onClose={() => (lightboxOpen = false)}
/>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-setup {
		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical--onSurface);
		}

		&__facts {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: var(--space-base);
			margin: 0;

			div {
				display: flex;
				flex-direction: column;
				gap: var(--space-smallest);
				min-width: 0;
			}

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 700;
			}

			dd {
				display: flex;
				flex-direction: column;
				gap: var(--space-smallest);
				margin: 0;
				color: var(--color-heading);
				font-weight: 600;
				overflow-wrap: anywhere;
			}
		}

		&__status {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__review {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small) var(--space-base);

			> p {
				margin: 0;
			}
		}

		&__returned {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;
			max-width: 60ch;
			padding: var(--space-small) var(--space-base);
			border-left: 3px solid var(--color-warning);
			border-radius: var(--radius-base);
			background: var(--color-warning--surface);

			p {
				margin: 0;
				overflow-wrap: anywhere;
				white-space: pre-line;
			}
		}

		&__review-actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin-left: auto;
		}

		&__files {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin: var(--space-smallest) 0 0;
			padding: 0;
			list-style: none;
		}

		&__thumb {
			display: block;
			width: 72px;
			height: 72px;
			padding: 0;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			cursor: zoom-in;
			transition:
				border-color var(--timing-base),
				box-shadow var(--timing-base);

			img {
				display: block;
				width: 100%;
				height: 100%;
				object-fit: cover;
			}

			&:hover {
				border-color: var(--color-interactive);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__file {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			white-space: normal;

			span {
				display: inline-flex;
				width: 18px;
				height: 18px;
				color: var(--color-text--secondary);
			}

			:global(svg) {
				width: 100%;
				height: 100%;
			}
		}

		&__confirmations {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				align-items: flex-start;
				gap: var(--space-small);
				color: var(--color-text);
			}
		}

		&__tick {
			display: inline-flex;
			flex: none;
			width: 18px;
			height: 18px;
			margin-top: 2px;
			color: var(--color-success);

			:global(svg) {
				width: 100%;
				height: 100%;
			}
		}
	}

	@media (max-width: 767px) {
		.client-setup__facts {
			grid-template-columns: 1fr;
		}
	}
</style>
