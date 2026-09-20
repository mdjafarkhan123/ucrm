<script lang="ts">
	import Select from '$lib/components/ui/Select.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import CustomerGroupPreview from './CustomerGroupPreview.svelte';
	import {
		MARKETING_CTA_TYPES,
		MARKETING_CTA_TYPE_LABELS,
		type MarketingCampaignContent,
		type MarketingCtaType
	} from '$lib/marketing/campaign-content';
	import type { MarketingCustomerGroup } from '$lib/marketing/customer-groups';
	import type { MarketingDeliveryOptions } from '$lib/marketing/api';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import formsIcon from '@tabler/icons/outline/forms.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// Step 4 (blueprint §8 step 4): sender/reply and Marketing allowance are shown, not chosen here -- see
	// delivery-options.ts's comment on why a sender picker is out of scope until M4. The call to action is
	// the one real choice this step saves, onto `content.cta` (campaign-content.ts).
	let {
		content,
		customerGroupId,
		groups,
		options,
		isPending,
		isError,
		errorMessage = '',
		onRetry,
		onBack,
		onContinue
	}: {
		content: MarketingCampaignContent;
		customerGroupId: string | null;
		groups: MarketingCustomerGroup[];
		options: MarketingDeliveryOptions;
		isPending: boolean;
		isError: boolean;
		errorMessage?: string;
		onRetry: () => void;
		onBack: () => void;
		onContinue: () => void;
	} = $props();

	const ctaIcons: Record<MarketingCtaType, string> = {
		internal_form: formsIcon,
		website: worldIcon,
		phone: phoneIcon
	};

	const selectedGroup = $derived(groups.find((group) => group.id === customerGroupId) ?? null);

	const formOptions = $derived(options.forms.map((form) => ({ value: form.id, label: form.name })));
	const chosenFormId = $derived(content.cta?.type === 'internal_form' ? content.cta.form_id : '');
	// A form saved into an earlier draft can be unpublished or archived since -- the same "still exists"
	// check the blueprint asks for.
	const formNoLongerAvailable = $derived.by(() => {
		const cta = content.cta;
		return cta?.type === 'internal_form' && !options.forms.some((form) => form.id === cta.form_id);
	});

	function websiteHref(website: string) {
		return /^https?:\/\//i.test(website) ? website : `https://${website}`;
	}

	function chooseCtaType(type: MarketingCtaType) {
		if (type === 'internal_form') {
			const cta = content.cta;
			const keep =
				cta?.type === 'internal_form' && options.forms.some((form) => form.id === cta.form_id)
					? cta.form_id
					: (options.forms[0]?.id ?? '');
			content.cta = keep ? { type: 'internal_form', form_id: keep } : null;
		} else {
			content.cta = { type };
		}
	}

	function chooseForm(formId: string) {
		content.cta = { type: 'internal_form', form_id: formId };
	}
</script>

<section class="panel">
	<header class="panel__head">
		<h2>How should this campaign be delivered?</h2>
		<p>Your sending identity, what customers are asked to do, and who is eligible to receive it.</p>
	</header>

	<div class="panel__body">
		{#if isPending}
			<LoadingSkeleton variant="text" rows={4} label="Loading delivery options" />
		{:else if isError}
			<ErrorState description="Delivery options could not be loaded." retry={onRetry} />
		{:else}
			<div class="block">
				<h3>Sender &amp; replies</h3>
				{#if options.sender}
					<p class="sender">
						<b>{options.sender.display_name}</b>
						<span>&lt;{options.sender.email_address}&gt;</span>
					</p>
					<p class="hint">
						Replies land in your shared Conversations inbox, linked back to this campaign.
					</p>
				{:else}
					<p class="warning">
						You don't have a verified sender yet.
						<Button
							variant="secondary"
							variation="subtle"
							size="small"
							href="/settings/communications"
						>
							Set up a sender
						</Button>
					</p>
				{/if}
			</div>

			<div class="block">
				<h3>What should customers do?</h3>
				<div class="cta-options" role="radiogroup" aria-label="Call to action">
					{#each MARKETING_CTA_TYPES as type (type)}
						{@const disabledReason =
							type === 'internal_form' && options.forms.length === 0
								? 'No published forms yet.'
								: type === 'website' && !options.business_website
									? 'No website on file.'
									: type === 'phone' && !options.business_phone
										? 'No phone number on file.'
										: ''}
						<label class="cta-option" class:cta-option--disabled={Boolean(disabledReason)}>
							<input
								type="radio"
								name="campaign-cta"
								value={type}
								checked={content.cta?.type === type}
								disabled={Boolean(disabledReason)}
								onchange={() => chooseCtaType(type)}
							/>
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							<span class="cta-option__icon" aria-hidden="true">{@html ctaIcons[type]}</span>
							<span class="cta-option__label">
								{MARKETING_CTA_TYPE_LABELS[type]}
								{#if disabledReason}<span class="cta-option__reason">{disabledReason}</span>{/if}
							</span>
						</label>
					{/each}
				</div>

				{#if content.cta?.type === 'internal_form'}
					<div class="cta-detail">
						<Select
							id="campaign-cta-form"
							label="Form"
							value={chosenFormId}
							options={formOptions}
							placeholder="Choose a form"
							onchange={chooseForm}
						/>
						{#if formNoLongerAvailable}
							<p class="warning">This form is no longer available. Choose another.</p>
						{:else if chosenFormId}
							{@const slug = options.forms.find((form) => form.id === chosenFormId)?.public_slug}
							{#if slug}
								<Button
									variant="secondary"
									variation="subtle"
									size="small"
									href={`/forms/${options.organization_slug}/${slug}`}
									target="_blank"
								>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									<span class="btn-icon" aria-hidden="true">{@html externalLinkIcon}</span> Open form
								</Button>
							{/if}
						{/if}
					</div>
				{:else if content.cta?.type === 'website'}
					<div class="cta-detail">
						<Button
							variant="secondary"
							variation="subtle"
							size="small"
							href={websiteHref(options.business_website ?? '')}
							target="_blank"
						>
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							<span class="btn-icon" aria-hidden="true">{@html externalLinkIcon}</span>
							{options.business_website}
						</Button>
					</div>
				{:else if content.cta?.type === 'phone'}
					<div class="cta-detail">
						<p class="hint">Customers will be shown a Call button for {options.business_phone}.</p>
					</div>
				{/if}
			</div>

			<div class="block">
				<h3>Recipients &amp; allowance</h3>
				{#if selectedGroup}
					<CustomerGroupPreview rules={selectedGroup.rules} />
				{/if}
				<p class="hint">
					{#if options.allowance.is_unlimited}
						Your plan allows unlimited Marketing email.
					{:else if options.allowance.state === 'numeric' && options.allowance.value !== null}
						Your plan allows {options.allowance.value} Marketing emails per period.
					{:else}
						Marketing sending allowance isn't turned on for your plan yet.
					{/if}
				</p>
			</div>
		{/if}

		{#if errorMessage}
			<p class="panel__error" role="alert">{errorMessage}</p>
		{/if}
	</div>

	<footer class="panel__foot">
		<Button variant="secondary" variation="subtle" onclick={onBack}>
			<!-- eslint-disable-next-line svelte/no-at-html-tags -->
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		<div class="panel__foot-right">
			<span class="panel__foot-note">
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<span class="btn-icon" aria-hidden="true">{@html sendIcon}</span>
				Sending isn't turned on yet -- this only saves your plan for delivery.
			</span>
			<Button variant="primary" onclick={onContinue}>
				Continue
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
			</Button>
		</div>
	</footer>
</section>

<style lang="scss">
	.panel {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-base);
		overflow: hidden;

		&__head {
			padding: var(--space-large) var(--space-large) var(--space-base);
			border-bottom: 1px solid var(--color-border);

			h2 {
				font-family: var(--typography--fontFamily-display);
				font-size: var(--typography--fontSize-larger);
				font-weight: 600;
				color: var(--color-heading);
				margin: 0;
			}
			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
			}
		}

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-large);
		}

		&__error {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			flex-wrap: wrap;
			gap: var(--space-base);
			padding: var(--space-base) var(--space-large);
			border-top: 1px solid var(--color-border);
			background: var(--color-surface--background--subtle);

			&-right {
				display: flex;
				align-items: center;
				gap: var(--space-base);
				flex-wrap: wrap;
			}

			&-note {
				display: flex;
				align-items: center;
				gap: var(--space-smaller);
				font-size: var(--typography--fontSize-small);
				color: var(--color-text--secondary);
			}
		}
	}

	.block {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		h3 {
			font-family: var(--typography--fontFamily-display);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			color: var(--color-heading);
			margin: 0;
		}
	}

	.sender {
		display: flex;
		align-items: baseline;
		gap: var(--space-smaller);
		margin: 0;

		span {
			color: var(--color-text--secondary);
		}
	}

	.hint {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.warning {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: 0;
		color: var(--color-warning--onSurface);
	}

	.cta-options {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-small);
	}

	.cta-option {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small) var(--space-base);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
		cursor: pointer;

		&:has(input:checked) {
			border-color: var(--color-interactive);
			box-shadow: 0 0 0 1px var(--color-interactive);
		}

		&--disabled {
			opacity: 0.55;
			cursor: not-allowed;
		}

		input {
			flex: none;
		}

		&__icon {
			flex: none;
			display: grid;
			place-items: center;
			color: var(--color-interactive);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__label {
			display: flex;
			flex-direction: column;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			color: var(--color-heading);
		}

		&__reason {
			font-weight: 400;
			color: var(--color-text--secondary);
		}
	}

	.cta-detail {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		flex-wrap: wrap;
	}

	.btn-icon :global(svg) {
		width: 16px;
		height: 16px;
		display: block;
	}

	@media (max-width: 720px) {
		.cta-options {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 560px) {
		.panel__foot {
			flex-direction: column-reverse;
			align-items: stretch;
		}
		.panel__foot-right {
			flex-direction: column-reverse;
			align-items: stretch;
		}
	}
</style>
