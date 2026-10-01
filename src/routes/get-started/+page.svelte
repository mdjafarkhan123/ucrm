<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import { goto, invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Input from '$lib/components/ui/Input.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import LocationPicker from '$lib/components/ui/LocationPicker.svelte';
	import TimezonePicker from '$lib/components/ui/TimezonePicker.svelte';
	import PackageCard from '$lib/components/packages/PackageCard.svelte';
	import PackageDetails from '$lib/components/packages/PackageDetails.svelte';
	import {
		offerHeadline,
		offerPriceSentence,
		offeredInterval,
		priceSentence,
		type BillingInterval,
		type PublicPackage
	} from '$lib/packages/public-package';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	// A visitor actively chooses a package; only a marketing-site link may choose one in advance. Read on
	// the server too, so the first paint already shows the linked package and billing.
	const link = untrack(() => data.linkChoice);
	const linked = untrack(() => data.packages.find((pkg) => pkg.edition_id === link.edition_id));

	type FormState = {
		business_name: string;
		main_contact_name: string;
		main_contact_email: string;
		main_contact_phone: string;
		is_administrator_same_as_contact: boolean;
		initial_administrator_name: string;
		initial_administrator_email: string;
		trade: string;
		city_country: string;
		time_zone: string;
		note: string;
		package_edition_id: string;
		privacy_policy_agreed: boolean;
	};
	let form = $state<FormState>({
		business_name: '',
		main_contact_name: '',
		main_contact_email: '',
		main_contact_phone: '',
		is_administrator_same_as_contact: true,
		initial_administrator_name: '',
		initial_administrator_email: '',
		trade: '',
		city_country: '',
		time_zone: '',
		note: '',
		package_edition_id: link.edition_id ?? '',
		privacy_policy_agreed: false
	});
	let wanted = $state<BillingInterval>(link.billing ?? 'month');
	let status = $state<'form' | 'submitting'>('form');
	let currentStep = $state(1);
	let errorMessage = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	// Shown on the package step: why a marketing link's choice could not be kept, or that terms changed.
	let packageNotice = $state(
		link.problem === 'unavailable'
			? 'The package from your link isn’t offered any more. Please choose one of the packages below.'
			: link.problem === 'interval_not_offered' && linked
				? `${linked.name} is only offered ${offeredInterval(linked, link.billing ?? 'month') === 'month' ? 'monthly' : 'yearly'}, so that is what we’ve selected.`
				: ''
	);
	let detailsFor = $state<string | null>(null);
	let turnstileToken = $state('');
	let turnstileContainer = $state<HTMLDivElement>();
	let turnstileApi = $state<TurnstileApi>();
	let turnstileWidgetId: string | undefined;
	type TurnstileOptions = {
		sitekey: string;
		callback: (token: string) => void;
		'expired-callback': () => void;
		'error-callback': () => void;
	};
	type TurnstileApi = {
		render: (container: HTMLElement, options: TurnstileOptions) => string | undefined;
		reset: (widgetId?: string) => void;
	};

	const selected = $derived(
		data.packages.find((pkg) => pkg.edition_id === form.package_edition_id) ?? null
	);
	const selectedInterval = $derived(selected ? offeredInterval(selected, wanted) : wanted);
	const detailsPackage = $derived(
		data.packages.find((pkg) => pkg.edition_id === detailsFor) ?? null
	);
	// The switch only matters when both billing choices exist somewhere in the list.
	const showBillingSwitch = $derived(
		data.packages.some((pkg) => pkg.monthly_price_usd_cents !== null) &&
			data.packages.some((pkg) => pkg.yearly_price_usd_cents !== null)
	);

	// The time zone starts as the visitor's own, which is wrong when someone fills this in for a business
	// elsewhere — and activation uses it to date the first paid period. Keep it when the chosen country
	// uses it; take the country's zone when it has only one; otherwise empty it so the visitor picks.
	function matchTimeZoneToCountry(countryTimeZones: string[]) {
		if (countryTimeZones.length === 0 || countryTimeZones.includes(form.time_zone)) return;
		form.time_zone = countryTimeZones.length === 1 ? countryTimeZones[0] : '';
	}

	onMount(() => {
		try {
			form.time_zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
		} catch {
			/* optional */
		}
		if (!data.turnstileSiteKey) return;
		const script = document.createElement('script');
		script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js';
		script.async = true;
		script.defer = true;
		script.onload = () => {
			turnstileApi = (window as unknown as { turnstile?: TurnstileApi }).turnstile;
		};
		document.head.appendChild(script);
	});

	/**
	 * The check sits on the review step, so its container does not exist yet when the page mounts
	 * and the script finishes loading. Draw the widget once both the script and the container are
	 * ready, and drop the token whenever the container goes away, expires, or errors -- a stale or
	 * spent token is rejected by Cloudflare exactly like no token at all.
	 */
	$effect(() => {
		if (!turnstileApi) return;
		const container = turnstileContainer;
		if (!container) {
			turnstileWidgetId = undefined;
			turnstileToken = '';
			return;
		}
		if (turnstileWidgetId !== undefined) return;
		turnstileWidgetId = turnstileApi.render(container, {
			sitekey: data.turnstileSiteKey,
			callback: (token) => (turnstileToken = token),
			'expired-callback': () => (turnstileToken = ''),
			'error-callback': () => (turnstileToken = '')
		});
	});

	function resetTurnstile() {
		turnstileToken = '';
		if (turnstileApi && turnstileWidgetId !== undefined) turnstileApi.reset(turnstileWidgetId);
	}

	const steps = [
		{ number: 1, label: 'Package', hint: 'Pick your plan' },
		{ number: 2, label: 'Business', hint: 'Your company' },
		{ number: 3, label: 'Contact', hint: 'People and access' },
		{ number: 4, label: 'Review', hint: 'Confirm details' }
	];
	const headings: Record<number, [string, string]> = {
		1: [
			'Choose your package',
			'Compare what each package includes, then pick the one that fits your business today.'
		],
		2: ['Tell us about your business', 'These details help us tailor your workspace.'],
		3: [
			'Who should we contact?',
			'We’ll use this information to follow up and set up account access.'
		],
		4: [
			'Review your application',
			'Everything look good? Submit your application and we’ll be in touch.'
		]
	};

	// Field errors are only shown on the step that owns the field, so a server-side error (a package
	// retired mid-application, for instance) has to send the visitor back to that step to be seen.
	const stepByField: Record<string, number> = {
		package_edition_id: 1,
		business_name: 2,
		trade: 2,
		city_country: 2,
		time_zone: 2,
		main_contact_name: 3,
		main_contact_email: 3,
		main_contact_phone: 3,
		initial_administrator_name: 3,
		initial_administrator_email: 3,
		privacy_policy_agreed: 4
	};
	function firstStepWithError(errors: Record<string, string>) {
		const found = Object.keys(errors)
			.map((field) => stepByField[field])
			.filter(Boolean);
		return found.length ? Math.min(...found) : null;
	}

	function validateStep(step: number) {
		const errors: Record<string, string> = {};
		if (step === 1 && !selected) errors.package_edition_id = 'Choose a package to continue.';
		if (step === 2) {
			if (!form.business_name.trim()) errors.business_name = 'Enter your business name.';
			if (!form.trade.trim()) errors.trade = 'Enter your trade.';
			if (!form.city_country.trim()) errors.city_country = 'Enter your city and country.';
			if (!form.time_zone.trim()) errors.time_zone = 'Enter your time zone.';
		}
		if (step === 3) {
			if (!form.main_contact_name.trim()) errors.main_contact_name = 'Enter a contact name.';
			if (!form.main_contact_email.trim()) errors.main_contact_email = 'Enter a contact email.';
			if (!form.main_contact_phone.trim()) errors.main_contact_phone = 'Enter a contact phone.';
			if (!form.is_administrator_same_as_contact) {
				if (!form.initial_administrator_name.trim())
					errors.initial_administrator_name = 'Enter an administrator name.';
				if (!form.initial_administrator_email.trim())
					errors.initial_administrator_email = 'Enter an administrator email.';
			}
		}
		fieldErrors = errors;
		return Object.keys(errors).length === 0;
	}
	function nextStep() {
		if (validateStep(currentStep)) currentStep = Math.min(currentStep + 1, 4);
	}
	function previousStep() {
		fieldErrors = {};
		currentStep = Math.max(currentStep - 1, 1);
	}
	function goToStep(step: number) {
		if (step < currentStep) {
			fieldErrors = {};
			currentStep = step;
		}
	}

	function chooseFromDetails(pkg: PublicPackage) {
		form.package_edition_id = pkg.edition_id;
		fieldErrors = {};
		detailsFor = null;
	}

	/**
	 * The package can be revised or withdrawn while the visitor fills in the form. Reload the list, keep
	 * everything they typed, and move them to the package's new edition when there is one, so they
	 * review the new terms before submitting instead of silently agreeing to them.
	 */
	async function refreshPackages() {
		const previousSlug = selected?.slug ?? null;
		await invalidateAll();
		const successor = data.packages.find((pkg) => pkg.slug === previousSlug);
		form.package_edition_id = successor?.edition_id ?? '';
		packageNotice = successor
			? `${successor.name} was just updated. Please look over its details before you submit.`
			: 'The package you chose is no longer offered. Please choose another one.';
		fieldErrors = {};
		errorMessage = '';
		currentStep = 1;
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		errorMessage = '';
		fieldErrors = {};
		for (const step of [1, 2, 3])
			if (!validateStep(step)) {
				currentStep = step;
				errorMessage = 'Please complete the highlighted fields before submitting.';
				return;
			}
		if (!form.privacy_policy_agreed) {
			currentStep = 4;
			fieldErrors = { privacy_policy_agreed: 'Please agree to the privacy policy.' };
			errorMessage = 'Please agree to the privacy policy to continue.';
			return;
		}
		if (data.turnstileSiteKey && !turnstileToken) {
			currentStep = 4;
			errorMessage =
				'Please finish the quick “I am human” check above. If you cannot see it, an ad blocker or privacy extension may be hiding it.';
			return;
		}
		status = 'submitting';
		try {
			const response = await fetch('/api/get-started', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					...form,
					billing_interval: selectedInterval,
					initial_administrator_name: form.is_administrator_same_as_contact
						? null
						: form.initial_administrator_name,
					initial_administrator_email: form.is_administrator_same_as_contact
						? null
						: form.initial_administrator_email,
					note: form.note || null,
					turnstile_token: turnstileToken
				})
			});
			const result: {
				error?: string;
				field_errors?: Record<string, string>;
				applicationId?: string;
			} = await response.json().catch(() => ({}));
			if (!response.ok) {
				status = 'form';
				resetTurnstile();
				if (result.field_errors?.package_edition_id) {
					await refreshPackages();
					return;
				}
				errorMessage = result.error ?? 'We could not save your application.';
				fieldErrors = result.field_errors ?? {};
				const errorStep = firstStepWithError(fieldErrors);
				if (errorStep) currentStep = errorStep;
				return;
			}
			await goto(
				resolve(`/get-started/received?app=${encodeURIComponent(result.applicationId ?? '')}`)
			);
		} catch {
			errorMessage = 'We could not save your application. Please try again.';
			status = 'form';
			resetTurnstile();
		}
	}
</script>

<svelte:head><title>Get started · UpliftContractor</title></svelte:head>

<main class="get-started">
	<div class="get-started__layout">
		<aside class="get-started__intro">
			<div class="get-started__brand">
				<span class="get-started__brand-mark">U</span> UpliftContractor
			</div>
			<h1>Set up your workspace in a few minutes.</h1>
			<nav class="get-started__steps" aria-label="Application progress">
				{#each steps as step (step.number)}
					<button
						type="button"
						class:get-started__step--active={currentStep === step.number}
						class:get-started__step--complete={currentStep > step.number}
						onclick={() => goToStep(step.number)}
						aria-current={currentStep === step.number ? 'step' : undefined}
					>
						<span class="get-started__step-number"
							>{currentStep > step.number ? '✓' : step.number}</span
						>
						<span><strong>{step.label}</strong><small>{step.hint}</small></span>
					</button>
				{/each}
			</nav>
		</aside>

		<section class="get-started__panel">
			<header class="get-started__header">
				<div class="get-started__mobile-progress">Step {currentStep} of {steps.length}</div>
				<h2>{headings[currentStep][0]}</h2>
				<p>{headings[currentStep][1]}</p>
			</header>
			<form onsubmit={submit}>
				{#if currentStep === 1}
					<section class="get-started__step-panel" aria-labelledby="package-heading">
						<div class="get-started__package-bar">
							<h3 id="package-heading">Choose a package</h3>
							{#if showBillingSwitch}
								<SegmentedControl
									bind:value={wanted}
									size="small"
									label="Billing"
									options={[
										{ value: 'month', label: 'Monthly' },
										{ value: 'year', label: 'Yearly' }
									]}
								/>
							{/if}
						</div>
						{#if packageNotice}<Banner type="warning">{packageNotice}</Banner>{/if}
						{#if data.packages.length === 0}
							<p class="get-started__note" role="status">
								No packages are open for sign-up right now. Please check back soon.
							</p>
						{/if}
						<div
							class="get-started__package-grid"
							role="radiogroup"
							aria-labelledby="package-heading"
						>
							{#each data.packages as pkg (pkg.edition_id)}
								<PackageCard
									{pkg}
									{wanted}
									interval={offeredInterval(pkg, wanted)}
									selected={form.package_edition_id === pkg.edition_id}
									bind:group={form.package_edition_id}
									onviewdetails={() => (detailsFor = pkg.edition_id)}
								/>
							{/each}
						</div>
						{#if fieldErrors.package_edition_id}
							<p class="get-started__error" role="alert">{fieldErrors.package_edition_id}</p>
						{/if}
						<p class="get-started__note">
							Payment is handled outside this form; we’ll send instructions after you apply. Text
							messages and extra email are paid separately from a prepaid balance.
						</p>
					</section>
				{:else if currentStep === 2}
					<section
						class="get-started__step-panel get-started__fields"
						aria-labelledby="details-heading"
					>
						<h3 id="details-heading">Your business</h3>
						<div class="get-started__field-grid">
							<Input
								id="business_name"
								label="Business name"
								bind:value={form.business_name}
								invalid={Boolean(fieldErrors.business_name)}
								errorMessage={fieldErrors.business_name}
								required
							/>
							<Input
								id="trade"
								label="Trade"
								bind:value={form.trade}
								invalid={Boolean(fieldErrors.trade)}
								errorMessage={fieldErrors.trade}
								required
							/>
							<div class="get-started__location-fields">
								<LocationPicker
									id="city_country"
									bind:value={form.city_country}
									oncountrychange={matchTimeZoneToCountry}
									invalid={Boolean(fieldErrors.city_country)}
									errorMessage={fieldErrors.city_country}
									required
								/>
								<TimezonePicker
									id="time_zone"
									bind:value={form.time_zone}
									invalid={Boolean(fieldErrors.time_zone)}
									errorMessage={fieldErrors.time_zone}
									required
								/>
							</div>
						</div>
					</section>
				{:else if currentStep === 3}
					<section
						class="get-started__step-panel get-started__fields"
						aria-labelledby="contact-heading"
					>
						<h3 id="contact-heading">Main contact</h3>
						<div class="get-started__field-grid">
							<Input
								id="main_contact_name"
								label="Contact name"
								bind:value={form.main_contact_name}
								invalid={Boolean(fieldErrors.main_contact_name)}
								errorMessage={fieldErrors.main_contact_name}
								required
							/>
							<Input
								id="main_contact_email"
								label="Contact email"
								type="email"
								bind:value={form.main_contact_email}
								invalid={Boolean(fieldErrors.main_contact_email)}
								errorMessage={fieldErrors.main_contact_email}
								required
							/>
							<Input
								id="main_contact_phone"
								label="Contact phone"
								type="tel"
								bind:value={form.main_contact_phone}
								invalid={Boolean(fieldErrors.main_contact_phone)}
								errorMessage={fieldErrors.main_contact_phone}
								required
							/>
						</div>
						<Checkbox
							id="is_administrator_same_as_contact"
							label="I'll be the one logging in and managing the account"
							bind:checked={form.is_administrator_same_as_contact}
						/>
						{#if !form.is_administrator_same_as_contact}
							<h3>Account administrator</h3>
							<div class="get-started__field-grid">
								<Input
									id="initial_administrator_name"
									label="Administrator name"
									bind:value={form.initial_administrator_name}
									invalid={Boolean(fieldErrors.initial_administrator_name)}
									errorMessage={fieldErrors.initial_administrator_name}
									required
								/>
								<Input
									id="initial_administrator_email"
									label="Administrator email"
									type="email"
									bind:value={form.initial_administrator_email}
									invalid={Boolean(fieldErrors.initial_administrator_email)}
									errorMessage={fieldErrors.initial_administrator_email}
									required
								/>
							</div>
						{/if}
					</section>
				{:else}
					<section
						class="get-started__step-panel get-started__review"
						aria-labelledby="review-heading"
					>
						<h3 id="review-heading">Your application</h3>
						<div class="get-started__review-card">
							<span>Package</span>
							<strong>{selected?.name ?? 'Not selected'}</strong>
							{#if selected}
								{@const offer = selected.offers[selectedInterval]}
								{#if offer}
									<p class="get-started__review-offer">{offerHeadline(offer)}</p>
									<p>
										{offerPriceSentence(offer)} · billed {selectedInterval === 'month'
											? 'monthly'
											: 'yearly'}
									</p>
								{:else}
									<p>
										{priceSentence(selected, selectedInterval)} · billed {selectedInterval ===
										'month'
											? 'monthly'
											: 'yearly'}
									</p>
								{/if}
								<button
									type="button"
									class="get-started__review-link"
									onclick={() => (detailsFor = selected.edition_id)}
								>
									See everything included
								</button>
							{/if}
							<button type="button" class="get-started__review-edit" onclick={() => goToStep(1)}
								>Edit</button
							>
						</div>
						<div class="get-started__review-card">
							<span>Business</span>
							<strong>{form.business_name || 'Not provided'}</strong>
							<p>{form.trade} · {form.city_country}</p>
							<button type="button" class="get-started__review-edit" onclick={() => goToStep(2)}
								>Edit</button
							>
						</div>
						<div class="get-started__review-card">
							<span>Contact</span>
							<strong>{form.main_contact_name || 'Not provided'}</strong>
							<p>{form.main_contact_email} · {form.main_contact_phone}</p>
							<button type="button" class="get-started__review-edit" onclick={() => goToStep(3)}
								>Edit</button
							>
						</div>
						<label class="get-started__label" for="note"
							>Anything else we should know? <span>(optional)</span></label
						>
						<textarea id="note" class="get-started__textarea" bind:value={form.note} rows="3"
						></textarea>
						{#if data.turnstileSiteKey}<div
								bind:this={turnstileContainer}
								class="get-started__turnstile"
							></div>{/if}
						<Checkbox
							id="privacy_policy_agreed"
							label={`I agree to the privacy policy${data.privacyPolicyVersion ? ` (version ${data.privacyPolicyVersion})` : ''}`}
							bind:checked={form.privacy_policy_agreed}
							invalid={Boolean(fieldErrors.privacy_policy_agreed)}
						/>
						{#if data.privacyPolicyUrl}
							<!-- eslint-disable svelte/no-navigation-without-resolve -- the policy lives on an external site. -->
							<a
								class="get-started__policy-link"
								href={data.privacyPolicyUrl}
								target="_blank"
								rel="noopener noreferrer">Read the privacy policy</a
							>
							<!-- eslint-enable svelte/no-navigation-without-resolve -->
						{/if}
					</section>
				{/if}
				{#if errorMessage}<p class="get-started__error" role="alert">{errorMessage}</p>{/if}
				<div class="get-started__actions">
					{#if currentStep > 1}<Button type="button" variant="secondary" onclick={previousStep}
							>Back</Button
						>{/if}
					{#if currentStep < 4}
						<Button type="button" fullWidth={currentStep === 1} onclick={nextStep}
							>Continue <span aria-hidden="true">→</span></Button
						>
					{:else}
						<Button
							type="submit"
							fullWidth
							loading={status === 'submitting'}
							disabled={status === 'submitting'}
							>{status === 'submitting' ? 'Submitting…' : 'Submit application'}</Button
						>
					{/if}
				</div>
			</form>
		</section>
	</div>
</main>

{#if detailsPackage}
	{@const pkg = detailsPackage}
	{@const interval = offeredInterval(pkg, wanted)}
	<Dialog open title={pkg.name} size="large" onClose={() => (detailsFor = null)}>
		<div class="get-started__details">
			<p class="get-started__details-lead">
				{#if pkg.promise}{pkg.promise}<br />{/if}<strong
					>{pkg.offers[interval]
						? offerPriceSentence(pkg.offers[interval])
						: priceSentence(pkg, interval)}</strong
				>
			</p>
			<PackageDetails {pkg} {interval} />
			<div class="get-started__details-actions">
				<Button type="button" variant="secondary" onclick={() => (detailsFor = null)}>Close</Button>
				{#if form.package_edition_id === pkg.edition_id}
					<Button type="button" onclick={() => (detailsFor = null)}>Keep this package</Button>
				{:else}
					<Button type="button" onclick={() => chooseFromDetails(pkg)}>Choose {pkg.name}</Button>
				{/if}
			</div>
		</div>
	</Dialog>
{/if}

<style lang="scss">
	.get-started {
		min-height: 100vh;
		padding: var(--space-largest) var(--space-large);
		color: var(--color-text);
		background: var(--color-surface--background);

		&__layout {
			max-width: 1320px;
			margin: 0 auto;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
			box-shadow: var(--shadow-base);
		}

		&__intro {
			padding: var(--space-large) var(--space-largest);
			color: var(--color-surface);
			background: var(--color-interactive-subtle, var(--color-interactive));

			h1 {
				max-width: 720px;
				margin: var(--space-largest) 0 0;
				color: var(--color-surface);
				font-size: var(--typography--fontSize-jumbo);
				line-height: var(--typography--lineHeight-minuscule);
			}
		}

		&__brand {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			font-weight: 700;
		}

		&__brand-mark {
			display: grid;
			width: 32px;
			height: 32px;
			place-items: center;
			border-radius: var(--radius-small);
			color: var(--color-interactive);
			background: var(--color-surface);
			font-weight: 900;
		}

		&__steps {
			display: grid;
			grid-template-columns: repeat(4, minmax(0, 1fr));
			gap: var(--space-small);
			margin-top: var(--space-largest);

			button {
				display: flex;
				align-items: center;
				gap: var(--space-small);
				min-height: 56px;
				padding: var(--space-small);
				border: 0;
				border-radius: var(--radius-base);
				color: inherit;
				background: transparent;
				text-align: left;
				cursor: pointer;

				&:hover {
					background: color-mix(in srgb, var(--color-surface) 12%, transparent);
				}
			}

			strong,
			small {
				display: block;
			}

			small {
				margin-top: 2px;
				color: color-mix(in srgb, var(--color-surface) 65%, transparent);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__step-number {
			display: grid;
			width: 30px;
			height: 30px;
			flex: 0 0 30px;
			place-items: center;
			border: var(--border-base) solid color-mix(in srgb, var(--color-surface) 45%, transparent);
			border-radius: var(--radius-circle);
			color: var(--color-surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__step--active &__step-number,
		&__step--complete &__step-number {
			color: var(--color-heading);
			border-color: var(--color-brand);
			background: var(--color-brand);
		}

		&__panel {
			padding: var(--space-largest);
		}

		&__header {
			max-width: 620px;
			margin-bottom: var(--space-largest);

			h2 {
				margin: var(--space-small) 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-jumbo);
				line-height: var(--typography--lineHeight-minuscule);
			}

			p {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-large);
				line-height: var(--typography--lineHeight-large);
			}
		}

		&__mobile-progress {
			display: none;
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			text-transform: uppercase;
		}

		&__step-panel {
			display: grid;
			gap: var(--space-base);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
			}
		}

		&__package-bar {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-end;
			justify-content: space-between;
			gap: var(--space-base);
		}

		&__package-grid {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
			gap: var(--space-base);
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__fields {
			gap: var(--space-large);
		}

		&__field-grid {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__location-fields {
			display: grid;
			grid-column: 1 / -1;
			grid-template-columns: minmax(0, 2fr) minmax(240px, 1fr);
			gap: var(--space-base);
			align-items: start;
		}

		&__label {
			margin-top: var(--space-base);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);

			span {
				color: var(--color-text--secondary);
			}
		}

		&__textarea {
			width: 100%;
			min-height: 96px;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-text);
			background: var(--color-surface);
			font: inherit;
			resize: vertical;

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__policy-link {
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-largest);

			:global(.button--full-width) {
				max-width: 260px;
			}
		}

		&__review {
			gap: var(--space-small);
		}

		&__review-card {
			position: relative;
			display: grid;
			gap: var(--space-smaller);
			justify-items: start;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			strong {
				color: var(--color-heading);
			}

			p {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__review-offer {
			padding: var(--space-smallest) var(--space-small);
			border-radius: var(--radius-small);
			color: var(--color-success--onSurface) !important;
			background: var(--color-success--surface);
			font-weight: 700;
		}

		&__review-edit,
		&__review-link {
			padding: 0;
			border: 0;
			color: var(--color-interactive);
			background: transparent;
			font: inherit;
			cursor: pointer;
			text-decoration: underline;
		}

		&__review-edit {
			position: absolute;
			top: var(--space-base);
			right: var(--space-base);
		}

		&__review-link {
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__details {
			display: grid;
			gap: var(--space-large);
		}

		&__details-lead {
			margin: 0;
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-large);

			strong {
				color: var(--color-heading);
			}
		}

		&__details-actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}

		@media (max-width: 900px) {
			padding: var(--space-base);

			&__intro {
				padding: var(--space-large);

				h1 {
					margin-top: var(--space-large);
					font-size: var(--typography--fontSize-largest);
				}
			}

			&__steps {
				gap: var(--space-smaller);
				margin-top: var(--space-large);

				button {
					display: block;
					padding: var(--space-small) var(--space-smaller);
					text-align: center;
				}

				small {
					display: none;
				}
			}

			&__step-number {
				margin: 0 auto var(--space-smaller);
			}

			&__panel {
				padding: var(--space-large);
			}

			&__header {
				margin-bottom: var(--space-large);

				h2 {
					font-size: var(--typography--fontSize-largest);
				}
			}

			&__mobile-progress {
				display: block;
			}
		}

		@media (max-width: 700px) {
			&__location-fields {
				grid-template-columns: 1fr;
			}
		}

		@media (max-width: 560px) {
			&__panel {
				padding: var(--space-base);
			}

			&__field-grid,
			&__package-grid {
				grid-template-columns: 1fr;
			}

			&__actions {
				margin-top: var(--space-large);

				:global(.button--full-width) {
					max-width: none;
				}
			}
		}
	}
</style>
