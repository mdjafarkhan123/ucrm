<script lang="ts">
	import type { EffectiveAccess } from '$lib/components/jafar/organization/types';
	import type { OrganizationDetailPreview } from '$lib/jafar/organization-detail-preview';
	import plugIcon from '@tabler/icons/outline/plug-connected.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import EmailDomainActions from '$lib/components/jafar/EmailDomainActions.svelte';
	import EmailAllowanceActions from '$lib/components/jafar/EmailAllowanceActions.svelte';
	import EmailReputationActions from '$lib/components/jafar/EmailReputationActions.svelte';
	import EmailSendingPauseActions from '$lib/components/jafar/EmailSendingPauseActions.svelte';
	import WebsiteChatAllowanceActions from '$lib/components/jafar/WebsiteChatAllowanceActions.svelte';
	import WebsiteChatAuthorityActions from '$lib/components/jafar/WebsiteChatAuthorityActions.svelte';
	import AutomationAuthorityActions from '$lib/components/jafar/AutomationAuthorityActions.svelte';

	let {
		access,
		preview
	}: {
		access: EffectiveAccess | null;
		preview: OrganizationDetailPreview | null;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<TabPanel value="communications">
	<div class="organization-workspace">
		{#if preview}
			<section class="organization-detail__section" aria-labelledby="integrations-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Integrations</p>
					<h2 id="integrations-title">Effective provider readiness</h2>
					<p>
						Configured preferences and provider health remain separate. The state below is a safe
						development scenario, not a provider check.
					</p>
				</div>
				<div class="organization-detail__integration-grid">
					{#each preview?.integrations ?? [] as integration (integration.name)}
						<Card class="organization-detail__integration-card">
							<div class="organization-detail__integration-heading">
								<span
									class="organization-detail__card-icon organization-detail__card-icon--{integration.tone}"
									>{@html plugIcon}</span
								>
								<div>
									<h3>{integration.name}</h3>
									<Badge status={integration.tone}>{integration.state}</Badge>
								</div>
							</div>
							<p>{integration.detail}</p>
							<div class="organization-detail__integration-next">
								<span>Next safe step</span><strong>{integration.nextAction}</strong>
							</div>
						</Card>
					{/each}
				</div>
			</section>
		{:else if access}
			<section class="organization-detail__section" aria-labelledby="integrations-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Integrations</p>
					<h2 id="integrations-title">Effective provider readiness</h2>
				</div>
				<Card class="organization-detail__commercial-explainer">
					<EmailDomainActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<EmailSendingPauseActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<EmailReputationActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<EmailAllowanceActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<WebsiteChatAllowanceActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<WebsiteChatAuthorityActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<AutomationAuthorityActions organizationId={access.organization.id} />
				</Card>
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
	.organization-detail__card-icon--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.organization-detail__card-icon--warning {
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.organization-detail__card-icon--critical {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.organization-detail__card-icon--inactive {
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
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
	.organization-detail__integration-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-workspace :global(.organization-detail__integration-card) {
		display: grid;
		align-content: start;
		gap: var(--space-base);
	}
	.organization-detail__integration-heading {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
	}
	.organization-detail__integration-heading h3 {
		margin-bottom: var(--space-small);
		font-size: var(--typography--fontSize-large);
	}
	.organization-workspace :global(.organization-detail__integration-card > p) {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-detail__integration-next {
		display: grid;
		gap: var(--space-smallest);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.organization-detail__integration-next span {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail__integration-next strong {
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
	}
	@media (max-width: 1100px) {
		.organization-detail__integration-grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@media (max-width: 639px) {
		.organization-detail__integration-grid {
			grid-template-columns: 1fr;
		}
		.organization-workspace :global(.organization-detail__commercial-explainer) {
			flex-direction: column;
		}
	}
</style>
