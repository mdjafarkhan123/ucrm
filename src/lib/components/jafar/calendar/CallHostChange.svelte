<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import { calendarEntryKey, refreshCalendar } from '$lib/jafar/calendar';
	import { HOST_STATE_WORDS, type HostChoice, type HostChoices } from '$lib/jafar/booking';

	// Jafar business management E3: who hosts a call a prospect booked online, and handing it to another of its
	// meeting's hosts -- as Calendly's reassign: only someone free then (inside their weekly hours, nothing else on
	// their calendar) can take it, and the visitor is emailed. Calls staff booked show nothing here.
	let { entryId }: { entryId: string } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const hostsKey = $derived([...calendarEntryKey(entryId), 'host'] as const);
	const query = createQuery(() => ({
		queryKey: hostsKey,
		queryFn: async (): Promise<HostChoices | null> => {
			const response = await fetch(
				`/api/jafar/calendar/entries/${encodeURIComponent(entryId)}/host`
			);
			// Not booked online: the call simply has no hosts to choose from.
			if (response.status === 404) return null;
			const result = await response.json();
			if (!response.ok) throw new Error(result.error ?? 'The hosts could not be loaded.');
			return result;
		}
	}));

	let open = $state(false);
	let picked = $state<string | null | undefined>(undefined);
	let saving = $state(false);
	let error = $state('');

	const data = $derived(query.data);
	const current = $derived(data?.choices.find((choice) => choice.state === 'current'));
	const others = $derived(data?.choices.filter((choice) => choice.state !== 'current') ?? []);
	const key = (id: string | null) => id ?? 'jafar';

	const BADGE: Record<HostChoice['state'], 'success' | 'warning' | 'inactive' | 'informative'> = {
		current: 'informative',
		free: 'success',
		busy: 'warning',
		outside_hours: 'inactive',
		no_access: 'inactive',
		removed: 'inactive'
	};

	function start() {
		open = true;
		picked = undefined;
		error = '';
		void query.refetch();
	}

	async function hand() {
		if (picked === undefined || saving) return;
		saving = true;
		error = '';
		const result = await sendLeadWrite(
			`/api/jafar/calendar/entries/${encodeURIComponent(entryId)}/host`,
			'POST',
			{ member_id: picked }
		);
		saving = false;
		if (!result.ok) {
			error = result.error;
			void query.refetch();
			return;
		}
		const name = (result.data as { host_name?: string | null }).host_name;
		open = false;
		toast.success(
			`${name ?? 'The new host'} is hosting this call now. The visitor has been emailed.`
		);
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: hostsKey }),
			queryClient.invalidateQueries({ queryKey: calendarEntryKey(entryId) }),
			refreshCalendar(queryClient)
		]);
	}
</script>

{#if data}
	<section class="host-change" aria-labelledby={`host-${entryId}`}>
		<div class="host-change__head">
			<span class="host-change__icon" aria-hidden="true">{@html userIcon}</span>
			<p class="host-change__current" id={`host-${entryId}`}>
				Hosted by <strong>{current?.name ?? 'Jafar'}</strong>
				<span class="host-change__hint">· booked online</span>
			</p>
			{#if data.can_change && others.length > 0 && !open}
				<Button variant="tertiary" size="small" onclick={start}>Change host</Button>
			{/if}
		</div>

		{#if open}
			<fieldset class="host-change__choices">
				<legend class="host-change__legend">Hand this call to</legend>
				{#each others as choice (key(choice.member_id))}
					{@const available = choice.state === 'free'}
					<label
						class="host-change__choice"
						class:host-change__choice--off={!available}
						class:host-change__choice--picked={picked === choice.member_id}
					>
						<input
							type="radio"
							name={`host-${entryId}-choice`}
							disabled={!available || saving}
							checked={picked === choice.member_id}
							onchange={() => (picked = choice.member_id)}
						/>
						<span class="host-change__name">{choice.name}</span>
						<Badge status={BADGE[choice.state]}>{HOST_STATE_WORDS[choice.state]}</Badge>
					</label>
				{/each}
			</fieldset>
			<p class="host-change__hint">
				Only someone free then can take it. The time stays the same, and the visitor gets an email
				with their new host.
			</p>
			{#if error}<p class="host-change__error" role="alert">{error}</p>{/if}
			<div class="host-change__actions">
				<Button variant="secondary" size="small" onclick={() => (open = false)} disabled={saving}
					>Keep host</Button
				>
				<Button size="small" onclick={hand} disabled={picked === undefined} loading={saving}
					>Change host</Button
				>
			</div>
		{/if}
	</section>
{/if}

<style lang="scss">
	.host-change {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.host-change__head {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}

	.host-change__icon {
		display: inline-flex;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 1.125rem;
			height: 1.125rem;
		}
	}

	.host-change__current {
		flex: 1;
		margin: 0;
		color: var(--color-text);
	}

	.host-change__hint {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.host-change__choices {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}

	// Named for screen readers only: the panel's heading and hint already say what the list is for.
	.host-change__legend {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}

	.host-change__choice {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small) var(--space-base);
		cursor: pointer;

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}

		input {
			margin: 0;
			accent-color: var(--color-interactive);
		}

		// The states read as short phrases ("Free then"), not Title Case labels.
		:global(.badge) {
			text-transform: none;
		}
	}

	.host-change__choice--picked {
		background: var(--color-surface--background);
	}

	.host-change__choice--off {
		cursor: not-allowed;

		.host-change__name {
			color: var(--color-text--secondary);
		}
	}

	.host-change__name {
		flex: 1;
		min-width: 0;
		overflow-wrap: anywhere;
	}

	.host-change__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.host-change__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}
</style>
