<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { fetchInboxEmail, inboxEmailKey, type InboxEmail } from '$lib/communications/inbox';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';

	let search = $state('');
	let searchDraft = $state('');
	let selectedId = $state<string | null>(null);
	const inboxQuery = createQuery(() => ({
		queryKey: inboxEmailKey(search),
		queryFn: () => fetchInboxEmail(search),
		staleTime: 15_000
	}));
	const emails = $derived(inboxQuery.data?.emails ?? []);
	const selected = $derived(emails.find((email) => email.id === selectedId) ?? emails[0] ?? null);

	function statusOf(email: InboxEmail): {
		label: string;
		tone: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
	} {
		if (email.status === 'submitted') return { label: 'Submitted', tone: 'success' };
		if (email.status === 'queued') return { label: 'Queued — not sent', tone: 'informative' };
		if (email.status === 'claimed') return { label: 'Preparing to send', tone: 'warning' };
		if (email.status === 'cancelled') return { label: 'Cancelled', tone: 'inactive' };
		if (email.status === 'failed') return { label: 'Retry scheduled', tone: 'critical' };
		return { label: 'Submission needs review', tone: 'warning' };
	}

	function formatWhen(value: string) {
		return new Intl.DateTimeFormat(undefined, {
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		}).format(new Date(value));
	}

	function preview(value: string) {
		return value.replace(/\s+/g, ' ').trim();
	}
</script>

<svelte:head><title>Communications · Contractor CRM</title></svelte:head>

<PageContainer variant="fill" class="communications">
	<header class="communications__header">
		<div>
			<p class="communications__eyebrow">Customer conversations</p>
			<h1>Inbox</h1>
			<p>
				Operational email history for your team. More channels will appear only when they are ready.
			</p>
		</div>
		<Badge status="informative" dot={false}>Email only</Badge>
	</header>

	{#if inboxQuery.isPending}
		<div class="communications__loading">
			<LoadingSkeleton variant="card" label="Loading inbox" /><LoadingSkeleton
				variant="card"
				label="Loading inbox"
			/><LoadingSkeleton variant="card" label="Loading inbox" />
		</div>
	{:else if inboxQuery.isError}
		<EmptyState
			title="Email history could not be loaded"
			description="Refresh the page and try again."
			icon={inboxIcon}
		/>
	{:else if emails.length === 0}
		<EmptyState
			title={inboxQuery.data?.view === 'assigned'
				? 'Nothing assigned to you yet'
				: 'No operational email yet'}
			description={inboxQuery.data?.view === 'assigned'
				? 'Team assignment arrives with the next Conversations slice. We will not expose the team inbox here.'
				: 'Queued and sent operational emails will appear here when they exist.'}
			icon={inboxIcon}
		/>
	{:else}
		<div class="communications__workspace">
			<aside class="communications__list" aria-label="Email history">
				<div class="communications__list-header">
					<h2>Team Inbox</h2>
					<span>{emails.length} recent</span>
				</div>
				<form
					class="communications__search"
					onsubmit={(event) => {
						event.preventDefault();
						search = searchDraft;
					}}
				>
					<label class="sr-only" for="communications-search">Search email history</label><input
						id="communications-search"
						bind:value={searchDraft}
						placeholder="Search email"
					/><Button size="small" variant="secondary" type="submit">Search</Button>
				</form>
				<div class="communications__rows">
					{#each emails as email (email.id)}
						<button
							class:communications__row--selected={selected?.id === email.id}
							class="communications__row"
							type="button"
							onclick={() => (selectedId = email.id)}
						>
							<Avatar id={email.client_id} name={email.client_name} size="base" />
							<span class="communications__row-copy"
								><strong>{email.client_name}</strong><span>{email.subject}</span><small
									>{preview(email.text_content)}</small
								></span
							><time datetime={email.created_at}>{formatWhen(email.created_at)}</time>
						</button>
					{/each}
				</div>
			</aside>

			{#if selected}
				<main class="communications__message" aria-label="Selected email">
					<header>
						<div class="communications__recipient">
							<Avatar id={selected.client_id} name={selected.client_name} size="medium" />
							<div>
								<h2>{selected.client_name}</h2>
								<a href={resolve('/(app)/clients/[id]', { id: selected.client_id })}
									>{selected.client_email}</a
								>
							</div>
						</div>
						<Badge status={statusOf(selected).tone}>{statusOf(selected).label}</Badge>
					</header>
					<div class="communications__message-meta">
						<span><strong>To</strong> {selected.client_email}</span><time
							datetime={selected.created_at}>{formatWhen(selected.created_at)}</time
						>
					</div>
					<article>
						<h3>{selected.subject}</h3>
						<p>{selected.text_content}</p>
					</article>
					{#if selected.failure_message}<p class="communications__notice" role="status">
							{selected.failure_message}
						</p>{/if}
					<footer>
						<span>Operational email</span><span
							>Sending and replies are not available in this first inbox release.</span
						>
					</footer>
				</main>
				<aside class="communications__context" aria-label="Customer context">
					<p class="communications__eyebrow">Customer context</p>
					<Avatar id={selected.client_id} name={selected.client_name} size="large" />
					<h2>{selected.client_name}</h2>
					<a href={resolve('/(app)/clients/[id]', { id: selected.client_id })}>View client</a>
					<dl>
						<div>
							<dt>Email</dt>
							<dd>{selected.client_email}</dd>
						</div>
						{#if selected.quote_id}<div>
								<dt>Related work</dt>
								<dd>
									<a href={resolve('/(app)/quotes/[id]', { id: selected.quote_id })}>View quote</a>
								</dd>
							</div>{/if}
					</dl>
				</aside>
			{/if}
		</div>
	{/if}
</PageContainer>

<style lang="scss">
	:global(.communications) {
		display: grid;
		gap: var(--space-large);
		min-height: calc(100vh - 160px);
	}
	.communications__header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-large);
	}
	.communications__header h1 {
		color: var(--color-heading);
	}
	.communications__header p:not(.communications__eyebrow) {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
	}
	.communications__eyebrow {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	.communications__loading {
		display: grid;
		grid-template-columns: 0.9fr 1.5fr 0.8fr;
		gap: var(--space-base);
	}
	.communications__loading :global(.skeleton) {
		min-height: 520px;
	}
	.communications__workspace {
		display: grid;
		grid-template-columns: minmax(260px, 0.9fr) minmax(360px, 1.5fr) minmax(240px, 0.75fr);
		min-height: 600px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		overflow: hidden;
		background: var(--color-surface);
	}
	.communications__list {
		border-right: var(--border-base) solid var(--color-border);
	}
	.communications__list-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.communications__list-header h2,
	.communications__message h2,
	.communications__context h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.communications__list-header span {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.communications__search {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: var(--space-base);
		padding: 0 var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
	}
	.communications__search :global(svg) {
		width: 18px;
		height: 18px;
	}
	.communications__search input {
		width: 100%;
		min-height: 36px;
		border: 0;
		outline: 0;
		color: var(--color-text);
		background: transparent;
	}
	.communications__rows {
		overflow-y: auto;
	}
	.communications__row {
		display: flex;
		width: 100%;
		gap: var(--space-small);
		padding: var(--space-base);
		border: 0;
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text);
		background: var(--color-surface);
		text-align: left;
		cursor: pointer;
	}
	.communications__row:hover,
	.communications__row--selected {
		background: var(--color-surface--hover);
	}
	.communications__row:focus-visible {
		outline: none;
		box-shadow: inset 0 0 0 2px var(--color-focus);
	}
	.communications__row-copy {
		display: grid;
		min-width: 0;
		flex: 1;
		gap: var(--space-smallest);
	}
	.communications__row-copy strong,
	.communications__row-copy span,
	.communications__row-copy small {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.communications__row-copy strong {
		color: var(--color-heading);
	}
	.communications__row-copy span,
	.communications__row-copy small {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.communications__row time {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		white-space: nowrap;
	}
	.communications__message {
		display: flex;
		min-width: 0;
		flex-direction: column;
	}
	.communications__message > header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.communications__recipient {
		display: flex;
		min-width: 0;
		align-items: center;
		gap: var(--space-small);
	}
	.communications__recipient a,
	.communications__context a {
		color: var(--color-interactive--subtle);
		font-size: var(--typography--fontSize-small);
		text-decoration: none;
	}
	.communications__recipient a:hover,
	.communications__context a:hover {
		text-decoration: underline;
	}
	.communications__message-meta {
		display: flex;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base) var(--space-large);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.communications__message article {
		flex: 1;
		padding: var(--space-large);
	}
	.communications__message article h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
	}
	.communications__message article p {
		margin-top: var(--space-large);
		white-space: pre-wrap;
		color: var(--color-text);
		line-height: var(--typography--lineHeight-large);
	}
	.communications__message footer {
		display: flex;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.communications__message footer span:first-child {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.communications__message footer :global(svg) {
		width: 16px;
		height: 16px;
	}
	.communications__notice {
		margin: 0 var(--space-large) var(--space-large);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.communications__context {
		padding: var(--space-large);
		border-left: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
	}
	.communications__context > :global(.avatar) {
		margin-top: var(--space-large);
	}
	.communications__context h2 {
		margin-top: var(--space-base);
	}
	.communications__context dl {
		display: grid;
		gap: var(--space-base);
		margin-top: var(--space-large);
	}
	.communications__context dl div {
		display: grid;
		gap: var(--space-smallest);
	}
	.communications__context dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.communications__context dd {
		margin: 0;
		color: var(--color-text);
		overflow-wrap: anywhere;
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
	}
	@media (max-width: 1050px) {
		.communications__workspace {
			grid-template-columns: minmax(240px, 0.8fr) minmax(0, 1.4fr);
		}
		.communications__context {
			display: none;
		}
	}
	@media (max-width: 700px) {
		.communications__header {
			display: grid;
		}
		.communications__loading,
		.communications__workspace {
			grid-template-columns: 1fr;
		}
		.communications__list {
			border-right: 0;
			border-bottom: var(--border-base) solid var(--color-border);
			max-height: 330px;
		}
		.communications__message {
			min-height: 460px;
		}
		.communications__message footer {
			display: grid;
		}
		.communications__message-meta {
			display: grid;
		}
	}
</style>
