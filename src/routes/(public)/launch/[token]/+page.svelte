<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { page } from '$app/state';
	import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import LaunchChecksSummary from '$lib/components/setup/LaunchChecksSummary.svelte';
	import { LAUNCH_NOT_YET_NOTE_MAX } from '$lib/setup/launch-approval';

	// Client onboarding E4 (plan §6): the final approver's private link, for someone who may have no login. It
	// shows the preview's parts and the one sentence they agree to; they tick it and approve, or tell Uplift it is
	// not ready yet. Everything drawn came from the token, resolved on the server. Industry reference: DocuSign's
	// emailed signing page and Jobber's online quote approval.
	let { data } = $props();

	const doc = $derived(data.document);
	let agreed = $state(false);
	let showNotYet = $state(false);
	let note = $state('');
	let busy = $state<'approve' | 'not_yet' | null>(null);
	let error = $state('');
	let toldNotYet = $state(false);

	async function decide(decision: 'approve' | 'not_yet') {
		busy = decision;
		error = '';
		try {
			const response = await fetch(`/api/public/launch/${page.params.token}`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(
					decision === 'approve' ? { decision, agreed } : { decision, note: note.trim() || null }
				)
			});
			const result = (await response.json().catch(() => ({}))) as { error?: string };
			if (!response.ok)
				throw new Error(result.error ?? 'That could not be saved. Please try again.');
			if (decision === 'not_yet') {
				toldNotYet = true;
				showNotYet = false;
			}
			await invalidateAll();
		} catch (cause) {
			error = (cause as Error).message;
		} finally {
			busy = null;
		}
	}

	const moment = (value: string) =>
		new Date(value).toLocaleString(undefined, {
			day: 'numeric',
			month: 'long',
			year: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});
</script>

<svelte:head>
	<title>{doc ? `Approve ${doc.business_name}'s launch` : 'Link not available'}</title>
	<meta name="robots" content="noindex, nofollow" />
	<meta name="referrer" content="no-referrer" />
</svelte:head>

<main class="launch-link">
	{#if !doc}
		<div class="launch-link__panel launch-link__panel--center">
			<h1>This link is not available</h1>
			<p class="launch-link__muted">
				It may have been replaced by a newer link, or Uplift may have released an updated preview.
				Ask Uplift for a new link and they will send you one.
			</p>
		</div>
	{:else}
		<div class="launch-link__panel">
			<header class="launch-link__header">
				<span
					class="launch-link__icon"
					class:launch-link__icon--done={doc.status === 'approved'}
					aria-hidden="true"
				>
					<!-- eslint-disable-next-line svelte/no-at-html-tags -- a bundled Tabler icon -->
					{@html doc.status === 'approved' ? circleCheckIcon : rocketIcon}
				</span>
				<div>
					<p class="launch-link__eyebrow">{doc.business_name} · Preview version {doc.version}</p>
					<h1>
						{doc.status === 'approved' ? 'Approved for launch' : 'Approve your system to go live'}
					</h1>
				</div>
			</header>

			{#if doc.status === 'approved' && doc.approved_at}
				<p>
					{doc.approver_name} approved preview version {doc.version} on {moment(doc.approved_at)}.
				</p>
				<blockquote class="launch-link__wording">{doc.wording}</blockquote>
				<p class="launch-link__muted">
					A receipt has been emailed. Uplift is preparing the launch and will tell you when it is
					live.
				</p>
			{:else}
				<p>
					Hi {doc.approver_name}. Uplift has built and checked {doc.business_name}'s system. Look
					over each part below, then approve it to go live. Nothing goes live until you do.
				</p>

				{#if toldNotYet || doc.not_yet_at}
					<Banner type="notice">
						Uplift has been told it is not ready yet and will be in touch. You can still approve
						here when you are happy.
					</Banner>
				{/if}

				<ol class="launch-link__cards">
					{#each doc.cards as card, index (card.id)}
						<li class="launch-link__card">
							<h2><span class="launch-link__number">{index + 1}</span>{card.title}</h2>
							<p class="launch-link__summary">{card.summary}</p>
							{#if card.link}
								<a
									class="launch-link__open"
									href={card.link}
									target="_blank"
									rel="noopener noreferrer"
								>
									Open it
									<span aria-hidden="true">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -- a bundled Tabler icon -->
										{@html externalLinkIcon}
									</span>
								</a>
							{/if}
						</li>
					{/each}
				</ol>

				<LaunchChecksSummary checks={doc.launch_checks} askedAt={doc.requested_at} />

				<div class="launch-link__agree">
					<Checkbox
						id="launch-link-agree"
						label={doc.wording}
						checked={agreed}
						disabled={busy !== null}
						onchange={(checked) => (agreed = checked)}
					/>
				</div>

				{#if error}
					<Banner type="error">{error}</Banner>
				{/if}

				{#if showNotYet}
					<div class="launch-link__not-yet">
						<Textarea
							id="launch-link-note"
							label="What is not ready? (optional)"
							rows={3}
							maxlength={LAUNCH_NOT_YET_NOTE_MAX}
							bind:value={note}
						/>
						<div class="launch-link__actions">
							<Button
								variant="secondary"
								loading={busy === 'not_yet'}
								disabled={busy !== null}
								onclick={() => decide('not_yet')}>Tell Uplift</Button
							>
							<Button
								variant="tertiary"
								disabled={busy !== null}
								onclick={() => (showNotYet = false)}>Cancel</Button
							>
						</div>
					</div>
				{:else}
					<div class="launch-link__actions">
						<Button
							loading={busy === 'approve'}
							disabled={!agreed || busy !== null}
							onclick={() => decide('approve')}>Approve launch</Button
						>
						<Button variant="secondary" disabled={busy !== null} onclick={() => (showNotYet = true)}
							>Not yet — talk to Uplift</Button
						>
					</div>
				{/if}
			{/if}
		</div>
	{/if}
</main>

<style lang="scss">
	.launch-link {
		display: flex;
		align-items: flex-start;
		justify-content: center;
		min-height: 100vh;
		padding: var(--space-largest) var(--space-base);
		background: var(--color-surface--background);
		color: var(--color-text);

		&__panel {
			display: grid;
			gap: var(--space-base);
			align-content: start;
			width: 100%;
			max-width: 680px;
			padding: var(--space-large);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
			box-shadow: var(--shadow-base);

			p {
				margin: 0;
			}

			&--center {
				text-align: center;
				align-self: center;
			}
		}

		h1 {
			margin: 0;
			font-size: var(--typography--fontSize-largest);
			line-height: var(--typography--lineHeight-tightest);
			font-weight: 700;
			color: var(--color-heading);
		}

		&__header {
			display: flex;
			align-items: center;
			gap: var(--space-base);
		}

		&__icon {
			display: inline-grid;
			place-items: center;
			flex: none;
			width: 48px;
			height: 48px;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
			color: var(--color-interactive);

			:global(svg) {
				width: 26px;
				height: 26px;
			}

			&--done {
				color: var(--color-success);
			}
		}

		&__eyebrow {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__muted {
			color: var(--color-text--secondary);
		}

		&__cards {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__card {
			display: grid;
			gap: var(--space-smaller);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);

			h2 {
				display: flex;
				align-items: center;
				gap: var(--space-small);
				margin: 0;
				font-size: var(--typography--fontSize-base);
				color: var(--color-heading);
			}
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

		&__summary {
			white-space: pre-line;
		}

		&__open {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			justify-self: start;
			color: var(--color-interactive);
			font-weight: 600;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__agree {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__wording {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-left: 3px solid var(--color-success);
			background: var(--color-surface--background);
			color: var(--color-heading);
			font-style: italic;
		}

		&__not-yet {
			display: grid;
			gap: var(--space-small);
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}
	}

	@media (max-width: 600px) {
		.launch-link {
			padding: var(--space-base);

			&__panel {
				padding: var(--space-base);
			}
		}
	}
</style>
