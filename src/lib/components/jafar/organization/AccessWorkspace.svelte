<script lang="ts">
	import type { EffectiveAccess, CommercialState } from '$lib/components/jafar/organization/types';
	import type { CreateQueryResult } from '@tanstack/svelte-query';
	import type { OrganizationDetailPreview } from '$lib/jafar/organization-detail-preview';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import shieldIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import SmsCreditTopupActions from '$lib/components/jafar/SmsCreditTopupActions.svelte';
	import SmsHoldActions from '$lib/components/jafar/SmsHoldActions.svelte';
	import SmsPromotionalCreditActions from '$lib/components/jafar/SmsPromotionalCreditActions.svelte';
	import SmsAdjustmentRefundActions from '$lib/components/jafar/SmsAdjustmentRefundActions.svelte';
	import AccessExceptionsSection from './AccessExceptionsSection.svelte';
	import { formatCalendarDate, formatDateTime, formatPrice } from './format';

	// Package builder P8b: features, limits, and their exceptions live in `AccessExceptionsSection`; the
	// package itself changes on the Billing tab.
	let {
		access,
		preview,
		commercialQuery,
		organizationId
	}: {
		access: EffectiveAccess | null;
		preview: OrganizationDetailPreview | null;
		commercialQuery: CreateQueryResult<CommercialState, Error>;
		organizationId: string | undefined;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<TabPanel value="access">
	<div class="organization-workspace">
		{#if preview}
			<section class="organization-detail__section" aria-labelledby="commercial-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Commercial access</p>
					<h2 id="commercial-title">Package and access position</h2>
					<p>
						Review the commercial record before considering an access change. This preview does not
						infer or change live eligibility.
					</p>
				</div>
				<div class="organization-detail__commercial-grid">
					<Card class="organization-detail__commercial-card">
						<div class="organization-detail__card-icon organization-detail__card-icon--informative">
							{@html receiptIcon}
						</div>
						<div>
							<p class="organization-detail__card-label">Activated package</p>
							<h3>{preview?.commercial.packageName}</h3>
							<p>{preview?.commercial.packageVersion}</p>
						</div>
						<dl>
							<div>
								<dt>Paid through</dt>
								<dd>{preview?.commercial.paidThrough}</dd>
							</div>
							<div>
								<dt>Grace</dt>
								<dd>{preview?.commercial.grace}</dd>
							</div>
						</dl>
					</Card>
					<Card class="organization-detail__commercial-card">
						<div class="organization-detail__card-icon">{@html shieldIcon}</div>
						<div>
							<p class="organization-detail__card-label">Access arrangement</p>
							<h3>{preview?.commercial.freeAccess}</h3>
							<p>{preview?.commercial.exception}</p>
						</div>
						<span class="organization-detail__safe-label">Record changes are unavailable</span>
					</Card>
				</div>
				<Card class="organization-detail__commercial-explainer">
					<div>
						<h3>Capabilities and limits</h3>
						<p>
							Package rules, feature exceptions, and usage limits will appear here only after their
							secure enforcement and measurement are connected. This preview deliberately does not
							invent access values.
						</p>
					</div>
					<Badge status="inactive">Not connected</Badge>
				</Card>
			</section>
		{:else if access}
			<section class="organization-detail__section" aria-labelledby="commercial-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Commercial access</p>
					<h2 id="commercial-title">Package and access position</h2>
					<p>Review the package, paid-through and grace state, and exceptions.</p>
				</div>

				<div class="organization-detail__commercial-grid">
					<Card class="organization-detail__commercial-card">
						<div class="organization-detail__card-icon organization-detail__card-icon--informative">
							{@html receiptIcon}
						</div>
						<div>
							<p class="organization-detail__card-label">Package</p>
							<h3>{access.package?.name ?? 'No package'}</h3>
							<p>
								{access.package
									? `Edition ${access.package.edition_number} · ${formatPrice(
											access.package.agreed_price_usd_cents,
											access.package.currency,
											access.package.billing_interval
										)}`
									: 'Every capability is off until a package is agreed.'}
							</p>
						</div>
						<div>
							<Button size="small" variant="secondary" href="?tab=billing"
								>Change on the Billing tab</Button
							>
						</div>
					</Card>

					<Card class="organization-detail__commercial-card">
						<div class="organization-detail__card-icon">{@html calendarIcon}</div>
						<div>
							<p class="organization-detail__card-label">Paid-through and grace</p>
							<h3>{formatCalendarDate(access.billing.paid_through_date)}</h3>
							<p>
								{access.billing.is_in_grace
									? `In grace until ${formatDateTime(access.billing.grace_ends_at)}`
									: access.billing.is_overdue
										? 'Past the 7-day grace period'
										: 'Not in grace'}
							</p>
						</div>
						<Badge
							status={!access.billing.paid_through_date
								? 'warning'
								: access.billing.is_overdue && !access.billing.is_in_grace
									? 'critical'
									: access.billing.is_in_grace
										? 'warning'
										: 'success'}
							>{!access.billing.paid_through_date
								? 'Needs setup'
								: access.billing.is_overdue && !access.billing.is_in_grace
									? 'Past grace'
									: access.billing.is_in_grace
										? 'In grace'
										: 'Current'}</Badge
						>
						<dl>
							<div>
								<dt>Source</dt>
								<dd>{access.billing.paid_through_source ?? 'Not recorded'}</dd>
							</div>
							<div>
								<dt>Commercial timezone</dt>
								<dd>{commercialQuery.data?.settings?.commercial_timezone ?? 'Not recorded'}</dd>
							</div>
						</dl>
					</Card>
				</div>

				<Card class="organization-detail__commercial-explainer">
					<SmsCreditTopupActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<SmsHoldActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<SmsPromotionalCreditActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<SmsAdjustmentRefundActions organizationId={access.organization.id} />
				</Card>

				{#if organizationId}
					<AccessExceptionsSection {organizationId} />
				{/if}
			</section>
		{/if}
	</div>
</TabPanel>

<!-- eslint-enable svelte/no-at-html-tags -->
<style lang="scss">
	.organization-workspace {
		display: grid;
		gap: var(--space-larger);
		min-width: 0;
	}
	.organization-detail__eyebrow {
		margin: 0 0 var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h2,
	h3,
	p {
		margin: 0;
	}
	h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}
	h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		line-height: var(--typography--lineHeight-tight);
	}
	.organization-detail__section-heading > p:last-child {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}
	.organization-detail__section {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: var(--space-base);
		min-width: 0;
	}
	.organization-detail__section > * {
		min-width: 0;
	}
	.organization-detail__card-icon {
		display: grid;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.organization-detail__card-icon {
		width: 36px;
		height: 36px;
	}
	.organization-detail__card-icon :global(svg) {
		width: 20px;
		height: 20px;
	}
	.organization-detail__card-label {
		margin-bottom: var(--space-smallest);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	.organization-workspace dl {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-small);
		margin: 0;
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.organization-workspace dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.organization-workspace dd {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		overflow-wrap: anywhere;
	}
	.organization-detail__safe-label {
		width: fit-content;
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-large);
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail__commercial-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-workspace :global(.organization-detail__commercial-card) {
		display: grid;
		align-content: start;
		gap: var(--space-base);
	}
	.organization-workspace :global(.organization-detail__commercial-card p:last-child) {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-workspace :global(.organization-detail__commercial-explainer) {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.organization-workspace :global(.organization-detail__commercial-explainer > div) {
		flex: 1;
		min-width: 0;
		display: grid;
		gap: var(--space-base);
	}
	.organization-workspace :global(.organization-detail__commercial-explainer h3) {
		font-size: var(--typography--fontSize-large);
	}
	.organization-workspace :global(.organization-detail__commercial-explainer p) {
		max-width: 78ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	@media (max-width: 639px) {
		.organization-detail__commercial-grid {
			grid-template-columns: 1fr;
		}
		.organization-workspace :global(.organization-detail__commercial-explainer) {
			flex-direction: column;
		}
	}
</style>
