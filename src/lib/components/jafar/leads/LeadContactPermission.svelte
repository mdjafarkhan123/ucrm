<script lang="ts">
	import { resolve } from '$app/paths';
	import { useQueryClient } from '@tanstack/svelte-query';
	import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import bellOffIcon from '@tabler/icons/outline/bell-off.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { approvalMethodLine, type LeadPage } from '$lib/jafar/lead-history';
	import { refreshLead, sendLeadWrite } from '$lib/jafar/lead-page-api';

	// Jafar business management B3: on a Lead's page, whether Uplift may contact this business -- approved
	// details, waiting for review, or Do not contact -- with the one or two actions that belong here. Approving
	// itself happens in the review queue, where the reasons are laid out side by side.
	let {
		data,
		canApprove,
		canMarkDoNotContact
	}: {
		data: LeadPage;
		/** "Approve who to contact": reviewing, and lifting Do not contact. */
		canApprove: boolean;
		/** Anyone who works on Leads can record an opt-out; it only ever stops contact. */
		canMarkDoNotContact: boolean;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const details = $derived(data.lead);
	const approved = $derived(data.contact_methods.filter((method) => method.approved_at));
	const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' });

	let dialog = $state<'set' | 'clear' | null>(null);
	let reason = $state('');
	let saving = $state(false);
	let error = $state('');

	function open(kind: 'set' | 'clear') {
		reason = '';
		error = '';
		dialog = kind;
	}

	async function confirm() {
		if (saving || !dialog) return;
		saving = true;
		error = '';
		const path = `/api/jafar/leads/${encodeURIComponent(details.id)}/do-not-contact${dialog === 'clear' ? '/clear' : ''}`;
		const result = await sendLeadWrite(path, 'POST', { reason: reason.trim() || null });
		if (result.ok) await refreshLead(queryClient, details.id);
		saving = false;
		if (!result.ok) {
			error = result.fieldErrors.reason ?? result.error;
			return;
		}
		toast.success(dialog === 'set' ? 'Marked Do not contact' : 'Contact allowed again');
		dialog = null;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<RailCard title="Who may contact them" icon={shieldCheckIcon}>
	{#if details.do_not_contact}
		<div class="permission permission--blocked">
			<span class="permission__icon" aria-hidden="true">{@html bellOffIcon}</span>
			<div>
				<p class="permission__title">Asked not to be contacted</p>
				<p class="permission__meta">
					Since {dateFormat.format(new Date(details.do_not_contact.at))}{details.do_not_contact
						.reason
						? ` · “${details.do_not_contact.reason}”`
						: ''}
				</p>
			</div>
		</div>
		{#if canApprove}
			<div>
				<Button variant="tertiary" size="small" onclick={() => open('clear')}
					>Allow contact again</Button
				>
			</div>
		{/if}
	{:else}
		{#if details.is_client}
			<p class="permission__text">
				Already a client — look after them through Onboarding and Support, not first contact.
			</p>
		{:else if details.lead_status === 'approved' && approved.length}
			<div class="permission permission--approved">
				<p class="permission__title">Approved for first contact</p>
				<ul class="permission__methods">
					{#each approved as method (method.id)}
						<li>{approvalMethodLine(method)}</li>
					{/each}
				</ul>
			</div>
		{:else if details.lead_status === 'ready_for_review'}
			<p class="permission__text">Waiting for a decision on who may be contacted.</p>
			{#if canApprove}
				<div>
					<Button
						href={`${resolve('/jafar/leads/review')}?lead=${encodeURIComponent(details.id)}`}
						variant="primary"
						size="small">Review now</Button
					>
				</div>
			{/if}
		{:else}
			<p class="permission__text">
				Not approved for contact. When research is done, set the status to Ready for review.
			</p>
		{/if}
		{#if canMarkDoNotContact}
			<div>
				<Button variant="tertiary" size="small" onclick={() => open('set')}>
					<span class="permission__button-icon" aria-hidden="true">{@html bellOffIcon}</span>They
					asked not to be contacted
				</Button>
			</div>
		{/if}
	{/if}
</RailCard>

{#if dialog}
	<ConfirmDialog
		open={true}
		title={dialog === 'set' ? 'Mark Do not contact?' : 'Allow contact again?'}
		tone={dialog === 'set' ? 'critical' : 'default'}
		confirmLabel={dialog === 'set' ? 'Mark Do not contact' : 'Allow contact again'}
		loading={saving}
		onConfirm={confirm}
		onClose={() => (dialog = null)}
	>
		<div class="permission__dialog">
			<p>
				{dialog === 'set'
					? `Nobody at Uplift may contact ${details.business_name}. Any approval and its first-contact task are removed.`
					: `${details.business_name} can be reviewed for contact again. Only do this if they asked to hear from Uplift.`}
			</p>
			<Textarea
				id="do-not-contact-reason"
				label={dialog === 'set' ? 'What they said (optional)' : 'Why (optional)'}
				rows={2}
				maxlength={500}
				invalid={Boolean(error)}
				errorMessage={error}
				bind:value={reason}
			/>
		</div>
	</ConfirmDialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.permission {
		display: flex;
		gap: var(--space-slim);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);

		p {
			margin: 0;
		}
	}

	.permission--blocked {
		background: var(--color-critical--surface);
		color: var(--color-critical--onSurface);
	}

	.permission--approved {
		flex-direction: column;
		gap: var(--space-smaller);
		background: var(--color-success--surface);
		color: var(--color-success--onSurface);
	}

	.permission__icon :global(svg) {
		width: 20px;
		height: 20px;
	}

	.permission__title {
		font-weight: 700;
	}

	.permission__meta {
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}

	.permission__methods {
		margin: 0;
		padding-left: var(--space-base);
		overflow-wrap: anywhere;
	}

	.permission__text {
		margin: 0;
		color: var(--color-text--secondary);
	}

	.permission__button-icon {
		display: inline-flex;
		margin-right: var(--space-smaller);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.permission__dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		p {
			margin: 0;
		}
	}
</style>
