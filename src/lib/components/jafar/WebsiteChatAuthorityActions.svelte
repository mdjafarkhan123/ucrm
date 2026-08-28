<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	type Suspension = {
		event_id: string;
		reason: string;
		engaged_by: string;
		engaged_at: string;
	};
	type Widget = {
		id: string;
		name: string;
		published: boolean;
		disabled_at: string | null;
		suspended_at: string | null;
		revision: number;
		public_token: string;
		allowed_origin_count: number;
		updated_at: string;
	};
	type Authority = {
		suspension: Suspension | null;
		widgets: Widget[];
		widget_total_count: number;
		widgets_truncated: boolean;
	};
	type AuthorityResponse = { authority?: Authority; error?: string };
	type PendingAction =
		{ kind: 'suspend' | 'restore' } | { kind: 'rotate_token'; widget: Widget } | null;

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const authorityKey = $derived([
		'jafar',
		'organizations',
		organizationId,
		'website-chat-authority'
	]);
	const endpoint = $derived(
		`/api/jafar/organizations/${organizationId}/communications/website-chat-authority`
	);

	const authorityQuery = createQuery<AuthorityResponse>(() => ({
		queryKey: authorityKey,
		queryFn: async () => {
			const response = await fetch(endpoint);
			const result = (await response.json()) as AuthorityResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'Website Chat authority could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	let pendingAction = $state<PendingAction>(null);
	let reason = $state('');
	const reasonValid = $derived(reason.trim().length >= 3);

	function openAction(action: Exclude<PendingAction, null>) {
		pendingAction = action;
		reason = '';
	}

	function closeAction() {
		if (mutation.isPending) return;
		pendingAction = null;
		reason = '';
	}

	const mutation = createMutation<AuthorityResponse, Error, Record<string, unknown>>(() => ({
		mutationFn: async (body) => {
			const response = await fetch(endpoint, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			});
			const result = (await response.json()) as AuthorityResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'Website Chat authority could not be changed.');
			return result;
		},
		onSuccess: async (_result, variables) => {
			pendingAction = null;
			reason = '';
			toast.success(
				variables.action === 'suspend'
					? 'Website Chat is suspended for this organization.'
					: variables.action === 'restore'
						? 'Website Chat is restored for this organization.'
						: 'The widget token was rotated. Its installation code must be updated.'
			);
			await queryClient.invalidateQueries({ queryKey: authorityKey });
		},
		onError: (error) => toast.error(error.message)
	}));

	function confirmAction() {
		if (!pendingAction || !reasonValid || mutation.isPending) return;
		const base = { reason: reason.trim(), idempotency_key: crypto.randomUUID() };
		if (pendingAction.kind === 'rotate_token') {
			mutation.mutate({
				...base,
				action: 'rotate_token',
				widget_id: pendingAction.widget.id,
				expected_revision: pendingAction.widget.revision
			});
		} else mutation.mutate({ ...base, action: pendingAction.kind });
	}

	function formatDateTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}

	function widgetStatus(widget: Widget) {
		if (widget.suspended_at) return { label: 'Suspended', tone: 'critical' as const };
		if (widget.disabled_at) return { label: 'Disabled', tone: 'inactive' as const };
		if (!widget.published) return { label: 'Draft', tone: 'warning' as const };
		if (widget.allowed_origin_count === 0) return { label: 'No domains', tone: 'warning' as const };
		return { label: 'Live', tone: 'success' as const };
	}

	const dialogTitle = $derived(
		pendingAction?.kind === 'suspend'
			? 'Suspend Website Chat'
			: pendingAction?.kind === 'restore'
				? 'Restore Website Chat'
				: pendingAction?.kind === 'rotate_token'
					? `Rotate token for ${pendingAction.widget.name}`
					: 'Website Chat authority'
	);
</script>

<div class="website-chat-authority">
	<div class="website-chat-authority__heading">
		<div>
			<h3>Website Chat authority and health</h3>
			<p>
				Suspend every widget during an abuse or security investigation. Contractor settings and
				conversation history remain intact.
			</p>
		</div>
		{#if !authorityQuery.isPending && !authorityQuery.isError}
			<Badge status={authorityQuery.data?.authority?.suspension ? 'critical' : 'success'}>
				{authorityQuery.data?.authority?.suspension ? 'Suspended' : 'Available'}
			</Badge>
		{/if}
	</div>

	{#if authorityQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading Website Chat authority" />
	{:else if authorityQuery.isError}
		<ErrorState
			title="Website Chat authority could not be loaded"
			description={authorityQuery.error instanceof Error
				? authorityQuery.error.message
				: 'Try again.'}
			retry={() => authorityQuery.refetch()}
		/>
	{:else}
		{@const authority = authorityQuery.data?.authority}
		{#if authority?.suspension}
			<dl class="website-chat-authority__suspension">
				<div>
					<dt>Reason</dt>
					<dd>{authority.suspension.reason}</dd>
				</div>
				<div>
					<dt>Suspended by</dt>
					<dd>{authority.suspension.engaged_by}</dd>
				</div>
				<div>
					<dt>Since</dt>
					<dd>{formatDateTime(authority.suspension.engaged_at)}</dd>
				</div>
			</dl>
			<Button
				size="small"
				variant="secondary"
				variation="subtle"
				onclick={() => openAction({ kind: 'restore' })}
			>
				Restore Website Chat
			</Button>
		{:else}
			<Button
				size="small"
				variant="secondary"
				variation="destructive"
				onclick={() => openAction({ kind: 'suspend' })}
			>
				Suspend Website Chat
			</Button>
		{/if}

		<div class="website-chat-authority__widgets">
			<h4>Widget health ({authority?.widget_total_count ?? 0})</h4>
			{#if authority?.widgets_truncated}
				<p class="website-chat-authority__note">
					Showing the 100 most recently updated widgets. Older disabled widgets are omitted from
					this health view.
				</p>
			{/if}
			{#if (authority?.widgets.length ?? 0) === 0}
				<p class="website-chat-authority__empty">This organization has no Website Chat widgets.</p>
			{:else}
				<ul>
					{#each authority?.widgets ?? [] as widget (widget.id)}
						{@const state = widgetStatus(widget)}
						<li>
							<div class="website-chat-authority__widget-copy">
								<div>
									<strong>{widget.name}</strong><Badge status={state.tone}>{state.label}</Badge>
								</div>
								<small
									>{widget.allowed_origin_count} allowed {widget.allowed_origin_count === 1
										? 'domain'
										: 'domains'} · Updated {formatDateTime(widget.updated_at)}</small
								>
							</div>
							<Button
								size="small"
								variant="secondary"
								variation="subtle"
								onclick={() => openAction({ kind: 'rotate_token', widget })}
							>
								Rotate token
							</Button>
						</li>
					{/each}
				</ul>
			{/if}
		</div>
	{/if}
</div>

<ConfirmDialog
	open={Boolean(pendingAction)}
	title={dialogTitle}
	tone={pendingAction?.kind === 'suspend' || pendingAction?.kind === 'rotate_token'
		? 'critical'
		: 'success'}
	confirmLabel={pendingAction?.kind === 'suspend'
		? 'Suspend Website Chat'
		: pendingAction?.kind === 'restore'
			? 'Restore Website Chat'
			: 'Rotate token'}
	destructive={pendingAction?.kind === 'suspend' || pendingAction?.kind === 'rotate_token'}
	loading={mutation.isPending}
	confirmDisabled={!reasonValid || mutation.isPending}
	onConfirm={confirmAction}
	onClose={closeAction}
>
	<p>
		{pendingAction?.kind === 'suspend'
			? 'New visitor sessions stop immediately across every widget. Existing history stays available.'
			: pendingAction?.kind === 'restore'
				? 'Eligible published widgets can accept new visitor sessions again.'
				: 'The current installation code stops working immediately. Rotate only when the token may be exposed, then update the contractor website.'}
	</p>
	<Textarea
		id="website-chat-authority-reason"
		label="Reason (kept in the owner audit log)"
		bind:value={reason}
		rows={3}
		maxlength={500}
		required
	/>
</ConfirmDialog>

<style lang="scss">
	.website-chat-authority {
		display: grid;
		gap: var(--space-base);
	}
	.website-chat-authority__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.website-chat-authority__heading h3,
	.website-chat-authority__widgets h4 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.website-chat-authority__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.website-chat-authority__suspension {
		display: grid;
		grid-template-columns: 2fr 1fr 1fr;
		gap: var(--space-base);
		margin: 0;
	}
	.website-chat-authority__suspension > div {
		display: grid;
		gap: var(--space-smallest);
	}
	.website-chat-authority__suspension dt,
	.website-chat-authority__widgets small {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.website-chat-authority__suspension dd {
		margin: 0;
		overflow-wrap: anywhere;
	}
	.website-chat-authority__widgets {
		display: grid;
		gap: var(--space-small);
		padding-top: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
	}
	.website-chat-authority__widgets ul {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.website-chat-authority__widgets li {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-small) 0;
	}
	.website-chat-authority__widget-copy {
		display: grid;
		gap: var(--space-smallest);
		min-width: 0;
	}
	.website-chat-authority__widget-copy > div {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.website-chat-authority__empty {
		color: var(--color-text--secondary);
	}
	.website-chat-authority__note {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-informative--surface);
		color: var(--color-informative--onSurface);
		font-size: var(--typography--fontSize-small);
	}
	@media (max-width: 639px) {
		.website-chat-authority__heading,
		.website-chat-authority__widgets li {
			align-items: stretch;
			flex-direction: column;
		}
		.website-chat-authority__suspension {
			grid-template-columns: 1fr;
		}
	}
</style>
