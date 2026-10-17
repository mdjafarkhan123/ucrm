<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		changeSmsStop,
		conversationMessagingKey,
		fetchConversationMessaging,
		textStopNotesKey,
		type ConversationMessagingPhone
	} from '$lib/communications/inbox';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import messageOffIcon from '@tabler/icons/outline/message-circle-off.svg?raw';
	import messageCheckIcon from '@tabler/icons/outline/message-circle-check.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';

	// Whether this customer can be texted, and their marketing-email standing, in the Contact tab. Stopping
	// texts follows the industry pattern: a staff member records "the customer asked me to stop", it blocks
	// every text to that number, and it shows here with who and when. The customer's own STOP reply is locked
	// -- only their START lifts it -- while a staff stop can be taken back if it was a mistake.
	let { clientId }: { clientId: string } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const query = createQuery(() => ({
		queryKey: conversationMessagingKey(clientId),
		queryFn: () => fetchConversationMessaging(clientId),
		staleTime: 30_000
	}));

	const phones = $derived(query.data?.phones ?? []);
	const canManage = $derived(query.data?.can_manage ?? false);
	const marketing = $derived(query.data?.marketing_email ?? null);

	let pending = $state<{ phone: ConversationMessagingPhone; action: 'stop' | 'undo' } | null>(null);
	let note = $state('');
	let error = $state('');

	const change = createMutation(() => ({
		mutationFn: (input: { contact_method_id: string; action: 'stop' | 'undo'; note?: string }) =>
			changeSmsStop(clientId, input),
		onSuccess: async (_data, input) => {
			toast.success(input.action === 'stop' ? 'Texts stopped' : 'Texts turned back on');
			pending = null;
			// The thread's composer reads the same standing, and the thread shows this change as a line.
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: conversationMessagingKey(clientId) }),
				queryClient.invalidateQueries({ queryKey: textStopNotesKey(clientId) })
			]);
		},
		onError: (caught) => {
			error = caught instanceof Error ? caught.message : 'That change could not be saved.';
		}
	}));

	function ask(phone: ConversationMessagingPhone, action: 'stop' | 'undo') {
		pending = { phone, action };
		note = '';
		error = '';
	}

	function confirm() {
		if (!pending) return;
		change.mutate({
			contact_method_id: pending.phone.contact_method_id,
			action: pending.action,
			...(pending.action === 'stop' && note.trim() ? { note: note.trim() } : {})
		});
	}

	function formatDay(value: string | null) {
		if (!value) return '';
		const date = new Date(value);
		return new Intl.DateTimeFormat(undefined, {
			month: 'short',
			day: 'numeric',
			year: date.getFullYear() === new Date().getFullYear() ? undefined : 'numeric'
		}).format(date);
	}

	function stoppedLine(phone: ConversationMessagingPhone) {
		const when = formatDay(phone.stopped_at);
		if (phone.stopped_by === 'customer') {
			return `The customer replied STOP${when ? ` on ${when}` : ''}. Only they can turn texts back on, by replying START.`;
		}
		const who = phone.stopped_by_name ? ` by ${phone.stopped_by_name}` : '';
		const line = `Stopped${who}${when ? ` on ${when}` : ''}.`;
		return phone.can_undo
			? line
			: `${line} There is no earlier permission on file, so there is nothing to turn back on.`;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="messaging" aria-label="Messaging">
	<h4 class="messaging__label">Messaging</h4>

	{#if query.isPending}
		<LoadingSkeleton variant="card" label="Loading messaging status" />
	{:else if query.isError}
		<p class="messaging__note">Messaging status could not be loaded.</p>
	{:else}
		<div class="messaging__card">
			{#each phones as phone (phone.contact_method_id)}
				<div class="messaging__row">
					<div class="messaging__head">
						<div class="messaging__what">
							<span class="messaging__kind messaging__kind--text"
								><span class="messaging__kind-icon" aria-hidden="true">{@html messageIcon}</span
								>Texts</span
							>
							<span class="messaging__value">{phone.value}</span>
						</div>
						{#if phone.state === 'opted_in'}
							<Badge size="small" status="success">Can text</Badge>
						{:else if phone.state === 'opted_out'}
							<Badge size="small" status="critical">Texts stopped</Badge>
						{:else}
							<Badge size="small" status="inactive">No permission yet</Badge>
						{/if}
					</div>

					{#if phone.state === 'opted_out'}
						<p class="messaging__note">{stoppedLine(phone)}</p>
						{#if phone.stopped_by === 'staff' && phone.note}
							<p class="messaging__quote">“{phone.note}”</p>
						{/if}
						{#if canManage && phone.can_undo}
							<Button variant="secondary" size="small" onclick={() => ask(phone, 'undo')}>
								{@html messageCheckIcon}Turn texts back on
							</Button>
						{/if}
					{:else if phone.state === 'unknown'}
						<p class="messaging__note">
							Texts cannot be sent until the customer has agreed to them.
						</p>
					{:else if canManage}
						<Button
							variant="secondary"
							variation="destructive"
							size="small"
							onclick={() => ask(phone, 'stop')}
						>
							{@html messageOffIcon}Stop texts
						</Button>
					{/if}
				</div>
			{:else}
				<div class="messaging__row">
					<div class="messaging__head">
						<div class="messaging__what">
							<span class="messaging__kind messaging__kind--text"
								><span class="messaging__kind-icon" aria-hidden="true">{@html messageIcon}</span
								>Texts</span
							>
							<span class="messaging__value">No phone number</span>
						</div>
					</div>
				</div>
			{/each}

			{#if marketing}
				<div class="messaging__row">
					<div class="messaging__head">
						<div class="messaging__what">
							<span class="messaging__kind messaging__kind--email"
								><span class="messaging__kind-icon" aria-hidden="true">{@html mailIcon}</span
								>Marketing email</span
							>
							<span class="messaging__value">{marketing.email}</span>
						</div>
						{#if marketing.state === 'opted_in'}
							<Badge size="small" status="success">Subscribed</Badge>
						{:else if marketing.state === 'opted_out'}
							<Badge size="small" status="critical">Unsubscribed</Badge>
						{:else}
							<Badge size="small" status="inactive">Not subscribed</Badge>
						{/if}
					</div>
					<p class="messaging__note">
						Only marketing emails follow this. Quotes, invoices and other needed emails still send.
					</p>
				</div>
			{/if}
		</div>
	{/if}
</section>

<ConfirmDialog
	open={pending !== null}
	title={pending?.action === 'stop' ? 'Stop texts to this customer?' : 'Turn texts back on?'}
	tone={pending?.action === 'stop' ? 'critical' : 'default'}
	confirmLabel={pending?.action === 'stop' ? 'Stop texts' : 'Turn texts back on'}
	destructive={pending?.action === 'stop'}
	loading={change.isPending}
	onConfirm={confirm}
	onClose={() => (pending = null)}
>
	{#if pending?.action === 'stop'}
		<p class="messaging__dialog-text">
			No one on your team will be able to text {pending.phone.value} until you turn texts back on here.
			Use this when the customer asked you to stop.
		</p>
		<Textarea
			id="messaging-stop-note"
			label="Note (optional)"
			bind:value={note}
			rows={3}
			maxlength={500}
			showCount={false}
			placeholder="For example: asked on the phone"
		/>
	{:else if pending}
		<p class="messaging__dialog-text">
			Texts to {pending.phone.value} will start working again, with the same permission the customer had
			before the stop. Only do this if the stop was a mistake or the customer asked to be texted again.
		</p>
	{/if}
	{#if error}<p class="messaging__error" role="alert">{error}</p>{/if}
</ConfirmDialog>

<style lang="scss">
	.messaging {
		display: grid;
		gap: var(--space-small);
	}

	.messaging__label {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
	}

	.messaging__card {
		display: grid;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: 14px;
		background: var(--color-surface);
	}

	.messaging__row {
		display: grid;
		gap: var(--space-smaller);
		padding: var(--space-slim) 14px;

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}

		// A button in the row keeps its own width instead of stretching across the grid.
		> :global(.button) {
			justify-self: start;
		}
	}

	/* The kind and its status pill share the top line; the number or address gets the full width below. */
	.messaging__head {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		align-items: center;
		gap: var(--space-smallest) var(--space-small);
	}

	.messaging__what {
		display: contents;
	}

	.messaging__kind {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--color-text--secondary);
		font-size: 11px;
		font-weight: 500;
		white-space: nowrap;
	}

	.messaging__kind-icon {
		display: inline-flex;

		:global(svg) {
			width: 13px;
			height: 13px;
		}
	}

	.messaging__kind--text .messaging__kind-icon {
		color: var(--color-interactive);
	}

	.messaging__kind--email .messaging__kind-icon {
		color: var(--color-informative--onSurface);
	}

	.messaging__value {
		grid-column: 1 / -1;
		grid-row: 2;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		overflow-wrap: anywhere;
	}

	.messaging__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: 12px;
		line-height: 1.45;
	}

	.messaging__quote {
		margin: 0;
		padding-left: var(--space-small);
		border-left: 2px solid var(--color-border);
		color: var(--color-text);
		font-size: 12px;
		overflow-wrap: anywhere;
	}

	.messaging__dialog-text {
		margin: 0 0 var(--space-base);
		color: var(--color-text);
	}

	.messaging__error {
		margin: var(--space-small) 0 0;
		color: var(--color-critical--onSurface);
		font-size: var(--typography--fontSize-small);
	}
</style>
