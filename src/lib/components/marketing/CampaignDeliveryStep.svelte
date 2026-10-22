<script lang="ts">
	import { tick } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import Select from '$lib/components/ui/Select.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import FormErrorSummary from '$lib/components/forms/FormErrorSummary.svelte';
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import {
		MARKETING_CTA_TYPES,
		MARKETING_FORM_CTA_LABELS,
		MARKETING_PHONE_CTA_LABEL,
		MARKETING_WEBSITE_CTA_LABEL,
		type MarketingCampaignContent,
		type MarketingCtaType
	} from '$lib/marketing/campaign-content';
	import {
		marketingGroupPreviewKey,
		type MarketingCustomerGroup
	} from '$lib/marketing/customer-groups';
	import { fetchGroupPreviewCounts, type MarketingDeliveryOptions } from '$lib/marketing/api';
	import type { FormOutcome } from '$lib/forms/types';
	import routeIcon from '@tabler/icons/outline/route.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import mailXIcon from '@tabler/icons/outline/mail-x.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import clickIcon from '@tabler/icons/outline/click.svg?raw';
	import clipboardListIcon from '@tabler/icons/outline/clipboard-list.svg?raw';
	import globeIcon from '@tabler/icons/outline/globe.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import gaugeIcon from '@tabler/icons/outline/gauge.svg?raw';
	import settingsIcon from '@tabler/icons/outline/settings.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// Step 4 (blueprint §8 step 4), design skill `layout.md` → New campaign · Delivery step: the path one email
	// takes, then where its button leads. Sender/reply and Marketing allowance are shown, not chosen here -- see
	// delivery-options.ts's comment on why a sender picker is out of scope until M4. The call to action is the
	// one real choice this step saves, onto `content.cta` (campaign-content.ts).
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

	type Destination = {
		title: string;
		icon: string;
		tone: string;
		/** The destination row's 12 quiet line: what it is, or why it can't be picked. */
		detail: string;
		button: string;
		disabled: boolean;
	};

	// What each form does once its answers arrive, for the form row and the path's last stop.
	const formOutcomeLines: Record<FormOutcome, { row: string; stop: string }> = {
		request: { row: 'Their answers become a new request in your CRM', stop: 'becomes a request' },
		assessment: {
			row: 'Their answers book an assessment in your CRM',
			stop: 'books an assessment'
		},
		job: { row: 'Their answers book a job in your CRM', stop: 'books a job' }
	};

	let errorCard = $state<FormErrorSummary>();

	const selectedGroup = $derived(groups.find((group) => group.id === customerGroupId) ?? null);

	// The Customers step's count query; its cache is usually warm by now.
	const countsQuery = createQuery(() => ({
		queryKey: marketingGroupPreviewKey(selectedGroup?.rules ?? { version: '1' }),
		queryFn: () => fetchGroupPreviewCounts(selectedGroup!.rules),
		enabled: selectedGroup !== null && !selectedGroup.description,
		staleTime: 10_000
	}));

	const groupLine = $derived.by(() => {
		if (selectedGroup?.description) return selectedGroup.description;
		const eligible = countsQuery.data?.eligible;
		if (eligible === undefined) return 'your customer group';
		return `${eligible.toLocaleString()} ${eligible === 1 ? 'customer' : 'customers'}`;
	});

	const formOptions = $derived(options.forms.map((form) => ({ value: form.id, label: form.name })));
	const chosenFormId = $derived(content.cta?.type === 'internal_form' ? content.cta.form_id : '');
	const chosenForm = $derived(options.forms.find((form) => form.id === chosenFormId) ?? null);
	// A form saved into an earlier draft can be unpublished or archived since -- the same "still exists"
	// check the blueprint asks for.
	const formNoLongerAvailable = $derived(content.cta?.type === 'internal_form' && !chosenForm);
	// The form row's button words follow the chosen form, or the first one before a pick.
	const rowForm = $derived(chosenForm ?? options.forms[0] ?? null);

	function outcomeOf(form: { outcome: string } | null): FormOutcome {
		return form && form.outcome in MARKETING_FORM_CTA_LABELS
			? (form.outcome as FormOutcome)
			: 'request';
	}

	function websiteHref(website: string) {
		return /^https?:\/\//i.test(website) ? website : `https://${website}`;
	}

	function websiteHost(website: string) {
		return website.replace(/^https?:\/\//i, '').replace(/\/$/, '');
	}

	const destinations = $derived<Record<MarketingCtaType, Destination>>({
		internal_form: {
			title: 'One of your forms',
			icon: clipboardListIcon,
			tone: 'request',
			detail:
				options.forms.length === 0
					? 'No published forms yet — publish one in Settings › Forms'
					: formOutcomeLines[outcomeOf(rowForm)].row,
			button: MARKETING_FORM_CTA_LABELS[outcomeOf(rowForm)],
			disabled: options.forms.length === 0
		},
		website: {
			title: 'Your website',
			icon: globeIcon,
			tone: 'informative',
			detail: options.business_website
				? websiteHost(options.business_website)
				: 'No website on file — add one in your business profile',
			button: MARKETING_WEBSITE_CTA_LABEL,
			disabled: !options.business_website
		},
		phone: {
			title: 'A phone call',
			icon: phoneIcon,
			tone: 'time',
			detail:
				options.business_phone ?? 'No phone number on file — add one in your business profile',
			button: MARKETING_PHONE_CTA_LABEL,
			disabled: !options.business_phone
		}
	});

	// The path's last stop: what the chosen button opens.
	const openStop = $derived.by(() => {
		const cta = content.cta;
		if (cta?.type === 'internal_form' && chosenForm)
			return {
				icon: clipboardListIcon,
				tone: 'request',
				value: chosenForm.name,
				line: formOutcomeLines[outcomeOf(chosenForm)].stop
			};
		if (cta?.type === 'website' && options.business_website)
			return {
				icon: globeIcon,
				tone: 'informative',
				value: websiteHost(options.business_website),
				line: 'your website'
			};
		if (cta?.type === 'phone' && options.business_phone)
			return {
				icon: phoneIcon,
				tone: 'time',
				value: options.business_phone,
				line: 'a call to you'
			};
		return null;
	});

	const pressedButton = $derived(
		openStop && content.cta ? destinations[content.cta.type].button : null
	);

	const allowance = $derived.by(() => {
		const { allowance } = options;
		if (allowance.is_unlimited)
			return { value: 'Unlimited marketing email', line: 'from your package', ok: true };
		if (allowance.state === 'numeric' && allowance.value !== null)
			return {
				value: `${allowance.value.toLocaleString()} marketing ${allowance.value === 1 ? 'email' : 'emails'}`,
				line: 'per period, from your package',
				ok: true
			};
		return {
			value: 'Not in your plan yet',
			line: 'your package has no marketing email',
			ok: false
		};
	});

	// The error stays only while its cause does: a pick (and a form, for the form option) clears it.
	const showError = $derived(
		Boolean(errorMessage) &&
			(!content.cta || (content.cta.type === 'internal_form' && !chosenForm))
	);

	// Points the error card at what is missing: the form select once the form option is picked, else the choices.
	const errorField = $derived(
		content.cta?.type === 'internal_form'
			? { anchor: 'campaign-cta-form', label: 'The form', message: errorMessage }
			: {
					anchor: 'campaign-cta-internal_form',
					label: 'The button in your email',
					message: errorMessage
				}
	);

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

	async function continueStep() {
		onContinue();
		await tick();
		if (showError) await errorCard?.reveal();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SetupStepCard
	title="Where does this email lead?"
	hint="Follow one email from your business to a new request. Choose where its button goes."
	icon={routeIcon}
	tone="growth"
>
	<div class="delivery">
		{#if isPending}
			<div
				class="delivery-bones"
				role="status"
				aria-label="Loading delivery options"
				aria-busy="true"
			>
				<div class="path path--bones">
					<span class="skeleton path__bone-head"></span>
					<div class="path__stops">
						{#each [0, 1, 2, 3] as stop (stop)}
							<div class="stop">
								<span class="skeleton delivery-bones__tile"></span>
								<span class="skeleton delivery-bones__line delivery-bones__line--short"></span>
								<span class="skeleton delivery-bones__line"></span>
								<span class="skeleton delivery-bones__line delivery-bones__line--mid"></span>
							</div>
						{/each}
					</div>
				</div>
				<div class="delivery-bones__head">
					<span class="skeleton delivery-bones__title"></span>
					<span class="skeleton delivery-bones__hint"></span>
				</div>
				{#each [0, 1, 2] as row (row)}
					<div class="delivery-bones__row">
						<span class="skeleton delivery-bones__radio"></span>
						<span class="skeleton delivery-bones__tile"></span>
						<span class="delivery-bones__lines">
							<span class="skeleton delivery-bones__line delivery-bones__line--mid"></span>
							<span class="skeleton delivery-bones__line delivery-bones__line--long"></span>
						</span>
						<span class="skeleton delivery-bones__line delivery-bones__line--mid"></span>
					</div>
				{/each}
				<div class="minis">
					<span class="skeleton delivery-bones__mini"></span>
					<span class="skeleton delivery-bones__mini"></span>
				</div>
			</div>
		{:else if isError}
			<ErrorState
				title="Delivery options couldn't load"
				description="Something went wrong on our side. Your campaign is safe — try again."
				retry={onRetry}
			/>
		{:else}
			<FormErrorSummary
				bind:this={errorCard}
				message={showError ? '1 thing to fix before you continue' : ''}
				hint="Your other choices are kept."
				fields={[errorField]}
			/>

			<section class="path" aria-labelledby="delivery-path-title">
				<h3 class="path__title" id="delivery-path-title">
					<span class="path__title-icon" aria-hidden="true">{@html routeIcon}</span>
					The path one email takes
				</h3>
				<ol class="path__stops">
					<li class={['stop', !options.sender && 'stop--warning']}>
						<span class="stop__top">
							{#if options.sender}
								<IconTile icon={mailIcon} tone="conversation" size={32} />
							{:else}
								<IconTile icon={mailXIcon} tone="warning" size={32} />
							{/if}
							<span class="stop__number">1</span>
						</span>
						<span class="stop__label">Sent from</span>
						<b class="stop__value">{options.sender?.display_name ?? 'No sender yet'}</b>
						<span class="stop__line"
							>{options.sender ? 'your verified sender' : 'needed to send'}</span
						>
					</li>
					<li class="stop__arrow" aria-hidden="true">{@html chevronRightIcon}</li>
					<li class="stop">
						<span class="stop__top">
							<IconTile icon={usersIcon} tone="growth" size={32} />
							<span class="stop__number">2</span>
						</span>
						<span class="stop__label">Reaches</span>
						<b class="stop__value">{selectedGroup?.name ?? 'No group yet'}</b>
						<span class="stop__line">{groupLine}</span>
					</li>
					<li class="stop__arrow" aria-hidden="true">{@html chevronRightIcon}</li>
					<li class={['stop', !pressedButton && 'stop--open']}>
						<span class="stop__top">
							<IconTile
								icon={clickIcon}
								tone={pressedButton ? 'informative' : 'inactive'}
								size={32}
								white={!pressedButton}
							/>
							<span class="stop__number">3</span>
						</span>
						<span class="stop__label">They press</span>
						{#if pressedButton}
							<span class="stop__button">{pressedButton}</span>
							<span class="stop__line">end of the email</span>
						{:else}
							<b class="stop__value stop__value--quiet">Not picked yet</b>
							<span class="stop__line">choose below</span>
						{/if}
					</li>
					<li class="stop__arrow" aria-hidden="true">{@html chevronRightIcon}</li>
					<li class={['stop', !openStop && 'stop--open']}>
						<span class="stop__top">
							{#if openStop}
								<IconTile icon={openStop.icon} tone={openStop.tone} size={32} />
							{:else}
								<IconTile icon={clipboardListIcon} tone="inactive" size={32} white />
							{/if}
							<span class="stop__number">4</span>
						</span>
						<span class="stop__label">It opens</span>
						<b class={['stop__value', !openStop && 'stop__value--quiet']}>
							{openStop?.value ?? 'Not picked yet'}
						</b>
						<span class="stop__line">{openStop?.line ?? 'follows your choice'}</span>
					</li>
				</ol>
			</section>

			{#if !options.sender}
				<Banner type="warning">
					You don't have a verified sender yet. Marketing email needs one before it can send — you
					can keep building meanwhile.
					{#snippet action()}
						<Button variant="secondary" href="/settings/communications">
							<span class="btn-icon" aria-hidden="true">{@html settingsIcon}</span> Set up a sender
						</Button>
					{/snippet}
				</Banner>
			{/if}

			<fieldset class="choices">
				<legend class="choices__head">
					<span class="choices__title">Where should the button take them?</span>
					<span class="choices__hint">
						{content.cta ? 'Stops 3 and 4 above change with your choice.' : 'Pick one to continue.'}
					</span>
				</legend>

				{#each MARKETING_CTA_TYPES as type (type)}
					{@const destination = destinations[type]}
					{@const chosen = content.cta?.type === type}
					<div
						class={[
							'choice',
							chosen && 'choice--chosen',
							destination.disabled && 'choice--disabled'
						]}
					>
						<label class="choice__row">
							<input
								class="choice__radio"
								type="radio"
								id={`campaign-cta-${type}`}
								name="campaign-cta"
								value={type}
								checked={chosen}
								disabled={destination.disabled}
								onchange={() => chooseCtaType(type)}
							/>
							<IconTile icon={destination.icon} tone={destination.tone} size={32} />
							<span class="choice__text">
								<span class="choice__title">{destination.title}</span>
								<span class="choice__detail">{destination.detail}</span>
							</span>
							<span class="choice__button">
								Button: <b>“{destination.button}”</b>
							</span>
						</label>

						{#if chosen && type === 'internal_form'}
							<div class="choice__more">
								<div class="choice__select">
									<Select
										id="campaign-cta-form"
										label="Form"
										value={chosenFormId}
										options={formOptions}
										placeholder="Choose a form"
										errorMessage={formNoLongerAvailable
											? 'This form is no longer available. Choose another.'
											: ''}
										onchange={chooseForm}
									/>
								</div>
								{#if chosenForm}
									<Button
										variant="secondary"
										href={`/forms/${options.organization_slug}/${chosenForm.public_slug}`}
										target="_blank"
									>
										<span class="btn-icon" aria-hidden="true">{@html externalLinkIcon}</span> Open form
									</Button>
								{/if}
							</div>
						{:else if chosen && type === 'website' && options.business_website}
							<div class="choice__more">
								<span class="choice__fixed">
									<span class="choice__fixed-icon" aria-hidden="true">{@html globeIcon}</span>
									<span class="choice__fixed-value">{websiteHref(options.business_website)}</span>
									<span class="choice__fixed-note">from your business profile</span>
								</span>
								<Button
									variant="secondary"
									href={websiteHref(options.business_website)}
									target="_blank"
								>
									<span class="btn-icon" aria-hidden="true">{@html externalLinkIcon}</span> Open website
								</Button>
							</div>
						{/if}
					</div>
				{/each}
			</fieldset>

			<div class="minis">
				<div class="mini">
					<IconTile icon={inboxIcon} tone="conversation" size={32} white />
					<span class="mini__text">
						<span class="mini__label">Replies</span>
						<b class="mini__value">Land in your shared Inbox</b>
						<span class="mini__line">Linked back to this campaign</span>
					</span>
					<span class="mini__mark mini__mark--ok" aria-hidden="true">{@html circleCheckIcon}</span>
				</div>
				<div class="mini">
					<IconTile icon={gaugeIcon} tone="growth" size={32} white />
					<span class="mini__text">
						<span class="mini__label">Your plan</span>
						<b class="mini__value">{allowance.value}</b>
						<span class="mini__line">{allowance.line}</span>
					</span>
					<span
						class={['mini__mark', allowance.ok ? 'mini__mark--ok' : 'mini__mark--warning']}
						aria-hidden="true">{@html allowance.ok ? circleCheckIcon : alertIcon}</span
					>
				</div>
			</div>
		{/if}
	</div>

	{#snippet footer()}
		<Button variant="secondary" onclick={onBack}>
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		{#if !isPending}
			<span class="foot-hint">Nothing sends yet — you send or schedule it on the next step.</span>
		{/if}
		<Button variant="primary" onclick={continueStep}>
			Continue <span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
	{/snippet}
</SetupStepCard>

<style lang="scss">
	.delivery {
		display: flex;
		flex-direction: column;
		gap: var(--space-medium);
	}

	// The path one email takes: four stops left to right, from the sender to what the button opens.
	.path {
		display: flex;
		flex-direction: column;
		gap: 14px;
		padding: var(--space-medium);
		border: var(--border-base) solid var(--color-growth--surface-edge);
		border-radius: var(--radius-large);
		background: var(--color-growth--surface);

		&__title {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-growth--onSurface);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__title-icon {
			display: inline-flex;
			color: var(--color-growth);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__stops {
			display: flex;
			align-items: center;
			gap: 6px;
			margin: 0;
			padding: 0;
			list-style: none;

			> .stop {
				align-self: stretch;
			}
		}

		&__bone-head {
			width: 200px;
			height: 14px;
		}
	}

	.stop {
		display: flex;
		flex: 1;
		flex-direction: column;
		min-width: 0;
		min-height: 124px;
		padding: 14px;
		border: var(--border-base) solid var(--color-border);
		border-radius: 12px;
		background: var(--color-surface);

		&__top {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			margin-bottom: 10px;
		}

		&__number {
			display: grid;
			place-items: center;
			width: 20px;
			height: 20px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
		}

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}

		&__value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			overflow-wrap: anywhere;

			&--quiet {
				color: var(--color-text--secondary);
			}
		}

		&__button {
			align-self: flex-start;
			margin: 2px 0;
			padding: 6px var(--space-slim);
			border-radius: 6px;
			background: var(--color-informative);
			color: var(--color-surface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 700;
		}

		&__line {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__arrow {
			display: inline-flex;
			flex: none;
			color: var(--color-growth);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		// A stop still waiting on the choice below.
		&--open {
			border-color: var(--color-border--interactive);
			background: var(--color-surface--background--subtle);
		}

		&--warning {
			border: 1.5px solid var(--color-warning);
		}
	}

	// Where the button goes: one row per destination, the chosen one opening its detail underneath.
	.choices {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		min-width: 0;
		margin: 0;
		padding: 0;
		border: 0;

		&__head {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			float: left;
			width: 100%;
			margin-bottom: var(--space-smaller);
			padding: 0;
		}

		&__title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}

		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}
	}

	.choice {
		border: var(--border-base) solid var(--color-border);
		border-radius: 12px;
		background: var(--color-surface);
		transition:
			border-color 0.15s ease,
			background-color 0.15s ease;

		&:not(&--disabled):not(&--chosen):hover {
			border-color: var(--color-interactive);
			background: var(--color-surface--hover);
		}

		&:has(.choice__radio:focus-visible) {
			outline: 2px solid var(--color-focus);
			outline-offset: 2px;
		}

		&--chosen {
			border-color: transparent;
			box-shadow: 0 0 0 1.5px var(--color-interactive);
		}

		&--disabled {
			opacity: 0.55;
		}

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 14px var(--space-base);
			cursor: pointer;

			.choice--disabled & {
				cursor: not-allowed;
			}
		}

		&__radio {
			flex: none;
			width: 18px;
			height: 18px;
			margin: 0;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			appearance: none;
			cursor: inherit;

			&:checked {
				border: 5px solid var(--color-interactive);
			}

			&:disabled {
				border-color: var(--color-disabled);
				background: var(--color-disabled--secondary);
			}

			&:focus-visible {
				outline: none;
			}
		}

		&__text {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: 2px;
			min-width: 0;
		}

		&__title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__detail {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__button {
			flex: none;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);

			b {
				margin-left: var(--space-smaller);
				color: var(--color-text);
				font-weight: 600;
			}
		}

		// Indented to the row's words: the radio, the tile and their gaps.
		&__more {
			display: flex;
			align-items: flex-end;
			gap: var(--space-slim);
			padding: 0 var(--space-base) var(--space-base) 74px;
		}

		&__select {
			flex: 1;
			min-width: 0;
		}

		&__fixed {
			display: flex;
			flex: 1;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;
			height: 40px;
			padding: 0 var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__fixed-icon {
			display: inline-flex;
			color: var(--color-informative);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__fixed-value {
			flex: 1;
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__fixed-note {
			flex: none;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}
	}

	// Replies and the plan: already set, shown so nothing about the send is a surprise.
	.minis {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-slim);
	}

	.mini {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		padding: 14px;
		border: var(--border-base) solid var(--color-border);
		border-radius: 12px;
		background: var(--color-surface--background--subtle);

		&__text {
			display: flex;
			flex: 1;
			flex-direction: column;
			min-width: 0;
		}

		&__label,
		&__line {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__label {
			font-weight: 500;
		}

		&__value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__mark {
			display: inline-flex;

			:global(svg) {
				width: 20px;
				height: 20px;
			}

			&--ok {
				color: var(--color-success);
			}

			&--warning {
				color: var(--color-warning--onSurface);
			}
		}
	}

	.delivery-bones {
		display: flex;
		flex-direction: column;
		gap: var(--space-medium);

		.path {
			gap: 14px;
		}

		&__head {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__title {
			width: 260px;
			height: 16px;
		}

		&__hint {
			width: 200px;
			height: 10px;
		}

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 14px var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: 12px;
		}

		&__radio {
			flex: none;
			width: 18px;
			height: 18px;
			border-radius: var(--radius-circle);
		}

		&__tile {
			flex: none;
			width: 32px;
			height: 32px;
			margin-bottom: var(--space-small);
			border-radius: var(--radius-base);

			.delivery-bones__row & {
				margin: 0;
			}
		}

		&__lines {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__line {
			width: 100px;
			height: 10px;
			margin-top: var(--space-small);

			&--short {
				width: 56px;
			}

			&--mid {
				width: 120px;
			}

			&--long {
				width: 220px;
			}

			.delivery-bones__lines &,
			.delivery-bones__row > & {
				margin: 0;
			}
		}

		&__mini {
			height: 72px;
			border-radius: 12px;
		}

	}

	.path--bones {
		.path__bone-head {
			background: var(--color-growth--surface-edge);
		}
	}

	.foot-hint {
		flex: 1;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: right;
	}

	.btn-icon {
		display: inline-flex;
	}

	.btn-icon :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
</style>
