<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { jafarOrganizationReviewCampaignKey } from '$lib/jafar/query-keys';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import googleIcon from '@tabler/icons/outline/brand-google.svg?raw';
	import feedbackIcon from '@tabler/icons/outline/message-heart.svg?raw';

	type Campaign = {
		google_review_url: string | null;
		routing_enabled: boolean;
		routing_google_min_rating: number;
		routing_acknowledged_at: string | null;
		channel_readiness: { sms_ready: boolean; email_ready: boolean };
		updated_at: string | null;
		activity_30d: {
			asked: number;
			opened: number;
			went_to_google: number;
			private_feedback: number;
		};
	};
	type CampaignResponse = { campaign?: Campaign; error?: string };

	let { organizationId }: { organizationId: string } = $props();

	const campaignQuery = createQuery<CampaignResponse>(() => ({
		queryKey: jafarOrganizationReviewCampaignKey(organizationId),
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/reviews`
			);
			const result = (await response.json()) as CampaignResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'Review campaign status could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	function formatDateTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}

	function channelLabel(readiness: { sms_ready: boolean; email_ready: boolean }) {
		if (readiness.sms_ready && readiness.email_ready) return 'Email + text ready';
		if (readiness.email_ready) return 'Email ready';
		if (readiness.sms_ready) return 'Text ready';
		return 'Not ready — automatic asks can’t send';
	}
</script>

<div class="review-campaign-actions">
	<div class="review-campaign-actions__heading">
		<div>
			<h3>Google review campaign</h3>
			<p>
				Read-only. Jafar can see whether the review link and sending setup are healthy, not connect
				or change them — the link itself is contractor-owned.
			</p>
		</div>
		{#if !campaignQuery.isPending && !campaignQuery.isError}
			{@const campaign = campaignQuery.data?.campaign}
			{#if !campaign?.google_review_url}
				<Badge status="inactive">Not set up</Badge>
			{:else if !campaign.channel_readiness.sms_ready && !campaign.channel_readiness.email_ready}
				<Badge status="critical">No sending channel ready</Badge>
			{:else}
				<Badge status="success">Ready</Badge>
			{/if}
		{/if}
	</div>

	{#if campaignQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading the review campaign status" />
	{:else if campaignQuery.isError}
		<ErrorState
			title="Review campaign status could not be loaded"
			description={campaignQuery.error instanceof Error
				? campaignQuery.error.message
				: 'Try again.'}
			retry={() => campaignQuery.refetch()}
		/>
	{:else}
		{@const campaign = campaignQuery.data?.campaign}
		{#if !campaign?.google_review_url}
			<p class="review-campaign-actions__empty">
				This organization has not set up a Google review link yet.
			</p>
		{:else}
			<dl>
				<div>
					<dt>Google review link</dt>
					<dd>{campaign.google_review_url}</dd>
				</div>
				<div>
					<dt>Google routing</dt>
					<dd>
						{campaign.routing_enabled
							? `On — ${campaign.routing_google_min_rating}★ and up go to Google`
							: 'Off — all feedback stays private'}
					</dd>
				</div>
				<div>
					<dt>Sending channel</dt>
					<dd>{channelLabel(campaign.channel_readiness)}</dd>
				</div>
				<div>
					<dt>Settings last changed</dt>
					<dd>{campaign.updated_at ? formatDateTime(campaign.updated_at) : 'Never changed'}</dd>
				</div>
			</dl>
			<div class="review-campaign-actions__stats" aria-label="Last 30 days">
				<KpiCard
					label="Asked"
					value={String(campaign.activity_30d.asked)}
					note="Last 30 days"
					icon={sendIcon}
					variant="compact"
				/>
				<KpiCard
					label="Opened"
					value={String(campaign.activity_30d.opened)}
					note="Last 30 days"
					icon={eyeIcon}
					tone="informative"
					variant="compact"
				/>
				<KpiCard
					label="Went to Google"
					value={String(campaign.activity_30d.went_to_google)}
					note="Last 30 days"
					icon={googleIcon}
					tone="success"
					variant="compact"
				/>
				<KpiCard
					label="Private feedback"
					value={String(campaign.activity_30d.private_feedback)}
					note="Last 30 days"
					icon={feedbackIcon}
					variant="compact"
				/>
			</div>
		{/if}
	{/if}
</div>

<style lang="scss">
	.review-campaign-actions {
		display: grid;
		gap: var(--space-base);
	}
	.review-campaign-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.review-campaign-actions__heading h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.review-campaign-actions__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.review-campaign-actions__empty {
		color: var(--color-text--secondary);
	}
	.review-campaign-actions dl {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;
	}
	.review-campaign-actions dl > div {
		display: grid;
		gap: var(--space-smallest);
	}
	.review-campaign-actions dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.review-campaign-actions dd {
		margin: 0;
		overflow-wrap: anywhere;
	}
	.review-campaign-actions__stats {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.review-campaign-actions__heading {
			flex-direction: column;
		}
		.review-campaign-actions dl {
			grid-template-columns: 1fr;
		}
		.review-campaign-actions__stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
</style>
