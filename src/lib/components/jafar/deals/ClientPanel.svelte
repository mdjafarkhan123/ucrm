<script lang="ts">
	import { resolve } from '$app/paths';
	import { useQueryClient } from '@tanstack/svelte-query';
	import userStarIcon from '@tabler/icons/outline/user-star.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import messagesIcon from '@tabler/icons/outline/messages.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import OwnerPicker from '$lib/components/jafar/OwnerPicker.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { formatUsd } from '$lib/jafar/packages';
	import { applicationHref } from '$lib/jafar/lead-history';
	import { sendLeadWrite, refreshLead } from '$lib/jafar/lead-page-api';
	import { jafarSetupOwnerChoicesKey } from '$lib/jafar/query-keys';
	import type { BusinessClient } from '$lib/jafar/deals';
	import { onboardingNextActionLabel, onboardingStage } from '$lib/setup/onboarding-list';

	// Jafar business management B5: the Client box on a business's page (plan § 5). Once payment is confirmed the
	// business is a client: what they paid for, the payments, the account made for them, where their setup stands,
	// unread support, and who looks after setup -- Jafar unless he hands it to a teammate with Onboarding access.
	let {
		relationshipId,
		client,
		canSeeOnboarding,
		canSeeSupport,
		canChangeSetupOwner
	}: {
		relationshipId: string;
		client: BusinessClient;
		canSeeOnboarding: boolean;
		canSeeSupport: boolean;
		/** Jafar only. */
		canChangeSetupOwner: boolean;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' });

	function formatDay(day: string) {
		const [year, month, date] = day.split('-').map(Number);
		return dateFormat.format(new Date(year, month - 1, date));
	}

	const application = $derived(client.application);
	const reversedAt = $derived(application?.payment_reversed_at ?? null);
	const organizationId = $derived(
		client.account?.status === 'succeeded' ? client.account.organization_id : null
	);
	const onboarding = $derived(client.onboarding);
	const stage = $derived(onboarding ? onboardingStage(onboarding) : null);

	const priceLine = $derived.by(() => {
		if (!application) return null;
		const yearly = application.billing_interval === 'year';
		const cents = yearly ? application.yearly_price_usd_cents : application.monthly_price_usd_cents;
		return cents === null ? null : `${formatUsd(cents)} a ${yearly ? 'year' : 'month'}`;
	});

	// A client who has sent their setup opens on its Setup tab, where the answers are -- as the onboarding list does.
	function organizationHref(id: string | null): string | null {
		if (!id) return null;
		return resolve('/jafar/(protected)/organizations/[organizationId]', { organizationId: id });
	}
	const accountHref = $derived(organizationHref(organizationId));
	const setupHref = $derived(
		accountHref && onboarding?.sent_number ? `${accountHref}?tab=setup` : accountHref
	);

	// --- Who looks after setup ---------------------------------------------------------------------------

	let savingOwner = $state(false);

	async function setOwner(memberId: string | null, name: string) {
		savingOwner = true;
		const result = await sendLeadWrite(
			`/api/jafar/leads/${encodeURIComponent(relationshipId)}/setup-owner`,
			'POST',
			{ member_id: memberId }
		);
		if (result.ok) await refreshLead(queryClient, relationshipId);
		savingOwner = false;
		if (result.ok) toast.success(`${name} now looks after their setup`);
		else toast.error('That could not be changed.', result.error);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<RailCard title="Client" icon={userStarIcon} class="client-panel">
	<div class="client-panel__status">
		<Badge status="success" dot={false}>Client</Badge>
		<span class="client-panel__muted">since {dateFormat.format(new Date(client.won_at))}</span>
	</div>

	{#if reversedAt}
		<p class="client-panel__warning" role="status">
			<span aria-hidden="true">{@html alertIcon}</span>
			Payment reversed {dateFormat.format(new Date(reversedAt))}. Setup is on hold until it is
			sorted out.
		</p>
	{/if}

	{#if application}
		<dl class="client-panel__facts">
			<div>
				<dt>Package</dt>
				<dd>
					{application.package_name ?? 'Package'}{#if priceLine}{' '}<span
							class="client-panel__muted">· {priceLine}</span
						>{/if}
				</dd>
			</div>
		</dl>

		{#if client.payments.length}
			<section class="client-panel__section" aria-label="Payments">
				<h3>Payments</h3>
				<ul class="client-panel__payments">
					{#each client.payments as payment (payment.id)}
						<li class={[payment.reversed_at && 'client-panel__payment--reversed']}>
							<strong>{formatUsd(payment.amount_usd_cents)}</strong>
							<span class="client-panel__muted"
								>{formatDay(payment.received_on)}{payment.method
									? ` · ${payment.method}`
									: ''}</span
							>
							{#if payment.reversed_at}
								<Badge size="small" status="critical" dot={false}>Reversed</Badge>
							{/if}
						</li>
					{/each}
				</ul>
			</section>
		{/if}
	{/if}

	<section class="client-panel__section" aria-label="Account and setup">
		<h3>Account and setup</h3>
		{#if accountHref}
			<p class="client-panel__line">
				<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- accountHref comes from resolve(). -->
				<a href={accountHref}>{client.account?.organization_name ?? 'Their account'}</a>
				{#if client.account?.lifecycle_status && client.account.lifecycle_status !== 'active'}
					<Badge size="small" status="inactive" dot={false}>Paused</Badge>
				{/if}
			</p>
			{#if onboarding && stage}
				<div class="client-panel__stage">
					<Badge size="small" status={stage.tone} dot={false}>{stage.label}</Badge>
					<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- setupHref is resolved; only the tab is added. -->
					<a href={setupHref}>Open setup</a>
				</div>
				<p class="client-panel__muted">Next: {onboardingNextActionLabel(onboarding)}</p>
				{#if onboarding.unread_support > 0}
					<p class="client-panel__line">
						<span class="client-panel__icon" aria-hidden="true">{@html messagesIcon}</span>
						{#if canSeeSupport}
							<a href={resolve('/jafar/support')}
								>{onboarding.unread_support} unread support {onboarding.unread_support === 1
									? 'chat'
									: 'chats'}</a
							>
						{:else}
							{onboarding.unread_support} unread support {onboarding.unread_support === 1
								? 'chat'
								: 'chats'}
						{/if}
					</p>
				{/if}
			{:else if canSeeOnboarding}
				<p class="client-panel__muted">Their setup has not started yet.</p>
			{/if}
		{:else}
			<p class="client-panel__muted">
				Their account has not been created yet.
				{#if application}
					<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- applicationHref resolves the path. -->
					<a href={applicationHref(application.id)}>Open the Application</a> to set it up.
				{/if}
			</p>
		{/if}
	</section>

	<section class="client-panel__section" aria-label="Who looks after setup">
		<h3>Setup looked after by</h3>
		<OwnerPicker
			current={client.setup_owner}
			choicesUrl={`/api/jafar/leads/${encodeURIComponent(relationshipId)}/setup-owner`}
			choicesKey={jafarSetupOwnerChoicesKey}
			canChange={canChangeSetupOwner}
			saving={savingOwner}
			changeLabel="Change who looks after their setup"
			noTeammatesLabel="No teammate has Onboarding access"
			onChoose={(memberId, name) => void setOwner(memberId, name)}
		/>
	</section>
</RailCard>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-panel {
		&__status,
		&__stage,
		&__line {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__line {
			margin: 0;
		}

		&__warning {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			margin: var(--space-small) 0 0;
			padding: var(--space-small);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			span {
				display: inline-flex;
				flex: none;
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__facts {
			margin: var(--space-small) 0 0;

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 700;
			}

			dd {
				margin: 2px 0 0;
				color: var(--color-text);
				overflow-wrap: anywhere;
			}
		}

		&__section {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin-top: var(--space-base);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 700;
			}

			a {
				color: var(--color-interactive);
				font-weight: 600;
				text-decoration: underline;
				text-underline-offset: 3px;

				&:focus-visible {
					outline: none;
					box-shadow: var(--shadow-focus);
				}
			}
		}

		&__payments {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				flex-wrap: wrap;
				align-items: center;
				gap: var(--space-small);
				padding: var(--space-small);
				border-radius: var(--radius-base);
				background: var(--color-surface--background--subtle);

				strong {
					color: var(--color-heading);
				}
			}
		}

		&__payment--reversed strong {
			color: var(--color-text--secondary);
			text-decoration: line-through;
		}

		&__icon {
			display: inline-flex;
			color: var(--color-text--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
