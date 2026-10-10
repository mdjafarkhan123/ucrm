<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import videoIcon from '@tabler/icons/outline/video.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import { calendarEntryKey } from '$lib/jafar/calendar';
	import { VIDEO_PROVIDER_WORDS, type CallVideoLink } from '$lib/jafar/booking';

	// Jafar business management E4a: a video call a prospect booked online, and its joining link. Until there is one
	// the visitor has been told the details will follow, so the panel asks the host to add it; adding or replacing it
	// emails the visitor (Calendly's "custom location", Cal.com's "link meeting"). Phone calls show nothing here.
	let { entryId }: { entryId: string } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const linkKey = $derived([...calendarEntryKey(entryId), 'video-link'] as const);
	const query = createQuery(() => ({
		queryKey: linkKey,
		queryFn: async (): Promise<CallVideoLink | null> => {
			const response = await fetch(
				`/api/jafar/calendar/entries/${encodeURIComponent(entryId)}/video-link`
			);
			// Not a video call booked online: nothing to show.
			if (response.status === 404) return null;
			const result = await response.json();
			if (!response.ok) throw new Error(result.error ?? 'The video link could not be loaded.');
			return result;
		}
	}));

	let open = $state(false);
	let url = $state('');
	let saving = $state(false);
	let error = $state('');

	const data = $derived(query.data);
	const provider = $derived(data ? VIDEO_PROVIDER_WORDS[data.location_kind] : '');
	const pending = $derived(Boolean(data && !data.video_join_url));

	function start() {
		open = true;
		url = '';
		error = '';
	}

	async function save() {
		if (saving) return;
		saving = true;
		error = '';
		const replacing = !pending;
		const result = await sendLeadWrite(
			`/api/jafar/calendar/entries/${encodeURIComponent(entryId)}/video-link`,
			'POST',
			{ url }
		);
		saving = false;
		if (!result.ok) {
			error = result.fieldErrors.url ?? result.error;
			return;
		}
		open = false;
		queryClient.setQueryData(linkKey, result.data as CallVideoLink);
		toast.success(
			replacing
				? 'Link replaced. The visitor has been emailed the new one.'
				: 'Link added. The visitor has been emailed it.'
		);
	}

	function onkeydown(event: KeyboardEvent) {
		// The panel sits inside the call's form: Enter saves the link, not the call.
		if (event.key !== 'Enter') return;
		event.preventDefault();
		void save();
	}
</script>

{#if data}
	<section
		class="video-link"
		class:video-link--pending={pending}
		aria-labelledby={`video-${entryId}`}
	>
		<div class="video-link__head">
			<span class="video-link__icon" aria-hidden="true"
				>{@html pending ? alertIcon : videoIcon}</span
			>
			<div class="video-link__text">
				<p class="video-link__title" id={`video-${entryId}`}>
					{#if pending}
						No {provider} link yet
					{:else}
						{provider} video call
					{/if}
				</p>
				{#if pending}
					<p class="video-link__hint">
						The visitor has been told the joining link will follow by email.
					</p>
				{:else if data.video_join_url}
					<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- the call's joining link, on the video provider's site. -->
					<a class="video-link__url" href={data.video_join_url} target="_blank" rel="noopener"
						>{data.video_join_url}</a
					>
				{/if}
			</div>
			{#if data.can_change && !open}
				<Button variant={pending ? 'primary' : 'tertiary'} size="small" onclick={start}>
					{pending ? 'Add link' : 'Replace link'}
				</Button>
			{/if}
		</div>

		{#if open}
			<Input
				id={`video-${entryId}-url`}
				label={`${provider} joining link`}
				type="url"
				inputmode="url"
				autocomplete="off"
				placeholder="https://zoom.us/j/…"
				bind:value={url}
				invalid={Boolean(error)}
				errorMessage={error}
				disabled={saving}
				{onkeydown}
			/>
			<p class="video-link__hint">
				The visitor gets an email with this link{pending ? '' : ' in place of the old one'}.
			</p>
			<div class="video-link__actions">
				<Button variant="secondary" size="small" onclick={() => (open = false)} disabled={saving}
					>Cancel</Button
				>
				<Button size="small" onclick={save} disabled={!url.trim()} loading={saving}>
					{pending ? 'Add and email' : 'Replace and email'}
				</Button>
			</div>
		{/if}
	</section>
{/if}

<style lang="scss">
	.video-link {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.video-link--pending {
		border-color: var(--color-warning);
		background: var(--color-warning--surface);
	}

	.video-link__head {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.video-link__icon {
		display: inline-flex;
		align-self: flex-start;
		padding-top: 2px;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 1.125rem;
			height: 1.125rem;
		}

		.video-link--pending & {
			color: var(--color-warning--onSurface);
		}
	}

	.video-link__text {
		display: flex;
		flex: 1;
		flex-direction: column;
		gap: var(--space-smallest);
		min-width: 0;
	}

	.video-link__title {
		margin: 0;
		color: var(--color-text);
		font-weight: 600;
	}

	.video-link__url {
		overflow: hidden;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.video-link__hint {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.video-link__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}
</style>
