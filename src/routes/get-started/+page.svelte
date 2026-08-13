<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Card from '$lib/components/ui/Card.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LocationPicker from '$lib/components/ui/LocationPicker.svelte';
	import TimezonePicker from '$lib/components/ui/TimezonePicker.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
	type FormState = { business_name: string; main_contact_name: string; main_contact_email: string; main_contact_phone: string; is_administrator_same_as_contact: boolean; initial_administrator_name: string; initial_administrator_email: string; trade: string; city_country: string; time_zone: string; note: string; package_version_id: string; privacy_policy_agreed: boolean };
	let form = $state<FormState>({ business_name: '', main_contact_name: '', main_contact_email: '', main_contact_phone: '', is_administrator_same_as_contact: true, initial_administrator_name: '', initial_administrator_email: '', trade: '', city_country: '', time_zone: '', note: '', package_version_id: '', privacy_policy_agreed: false });
	let status = $state<'form' | 'submitting'>('form');
	let currentStep = $state(1);
	let errorMessage = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let turnstileToken = $state('');
	let turnstileContainer = $state<HTMLDivElement>();
	let turnstileApi = $state<TurnstileApi>();
	let turnstileWidgetId: string | undefined;
	type TurnstileOptions = { sitekey: string; callback: (token: string) => void; 'expired-callback': () => void; 'error-callback': () => void };
	type TurnstileApi = { render: (container: HTMLElement, options: TurnstileOptions) => string | undefined; reset: (widgetId?: string) => void };

	onMount(() => {
		form.package_version_id = data.packages[0]?.package_version_id ?? '';
		try { form.time_zone = Intl.DateTimeFormat().resolvedOptions().timeZone; } catch { /* optional */ }
		if (!data.turnstileSiteKey) return;
		const script = document.createElement('script');
		script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js'; script.async = true; script.defer = true;
		script.onload = () => { turnstileApi = (window as unknown as { turnstile?: TurnstileApi }).turnstile; };
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
		if (!container) { turnstileWidgetId = undefined; turnstileToken = ''; return; }
		if (turnstileWidgetId !== undefined) return;
		turnstileWidgetId = turnstileApi.render(container, { sitekey: data.turnstileSiteKey, callback: (token) => (turnstileToken = token), 'expired-callback': () => (turnstileToken = ''), 'error-callback': () => (turnstileToken = '') });
	});

	function resetTurnstile() { turnstileToken = ''; if (turnstileApi && turnstileWidgetId !== undefined) turnstileApi.reset(turnstileWidgetId); }

	const steps = [{ number: 1, label: 'Package', hint: 'Pick your plan' }, { number: 2, label: 'Business', hint: 'Your company' }, { number: 3, label: 'Contact', hint: 'People and access' }, { number: 4, label: 'Review', hint: 'Confirm details' }];
	function formatPrice(cents: number) { return `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 0 })}/mo`; }
	function seatLimitLabel(pkg: (typeof data.packages)[number]) { const limit = pkg.seat_limit; if (!limit || limit.limit_state === 'not_included') return null; if (limit.limit_state === 'unlimited') return 'Unlimited team seats'; return `Up to ${limit.limit_value} team seats`; }

	// Field errors are only shown on the step that owns the field, so a server-side error (a package
	// retired mid-application, for instance) has to send the visitor back to that step to be seen.
	const stepByField: Record<string, number> = { package_version_id: 1, business_name: 2, trade: 2, city_country: 2, time_zone: 2, main_contact_name: 3, main_contact_email: 3, main_contact_phone: 3, initial_administrator_name: 3, initial_administrator_email: 3, privacy_policy_agreed: 4 };
	function firstStepWithError(errors: Record<string, string>) { const steps = Object.keys(errors).map((field) => stepByField[field]).filter(Boolean); return steps.length ? Math.min(...steps) : null; }

	function validateStep(step: number) {
		const errors: Record<string, string> = {};
		if (step === 1 && !form.package_version_id) errors.package_version_id = 'Choose a package to continue.';
		if (step === 2) { if (!form.business_name.trim()) errors.business_name = 'Enter your business name.'; if (!form.trade.trim()) errors.trade = 'Enter your trade.'; if (!form.city_country.trim()) errors.city_country = 'Enter your city and country.'; if (!form.time_zone.trim()) errors.time_zone = 'Enter your time zone.'; }
		if (step === 3) { if (!form.main_contact_name.trim()) errors.main_contact_name = 'Enter a contact name.'; if (!form.main_contact_email.trim()) errors.main_contact_email = 'Enter a contact email.'; if (!form.main_contact_phone.trim()) errors.main_contact_phone = 'Enter a contact phone.'; if (!form.is_administrator_same_as_contact) { if (!form.initial_administrator_name.trim()) errors.initial_administrator_name = 'Enter an administrator name.'; if (!form.initial_administrator_email.trim()) errors.initial_administrator_email = 'Enter an administrator email.'; } }
		fieldErrors = errors; return Object.keys(errors).length === 0;
	}
	function nextStep() { if (validateStep(currentStep)) currentStep = Math.min(currentStep + 1, 4); }
	function previousStep() { fieldErrors = {}; currentStep = Math.max(currentStep - 1, 1); }
	function goToStep(step: number) { if (step < currentStep) { fieldErrors = {}; currentStep = step; } }

	async function submit(event: SubmitEvent) {
		event.preventDefault(); errorMessage = ''; fieldErrors = {};
		for (const step of [1, 2, 3]) if (!validateStep(step)) { currentStep = step; errorMessage = 'Please complete the highlighted fields before submitting.'; return; }
		if (!form.privacy_policy_agreed) { currentStep = 4; fieldErrors = { privacy_policy_agreed: 'Please agree to the privacy policy.' }; errorMessage = 'Please agree to the privacy policy to continue.'; return; }
		if (data.turnstileSiteKey && !turnstileToken) { currentStep = 4; errorMessage = 'Please finish the quick “I am human” check above. If you cannot see it, an ad blocker or privacy extension may be hiding it.'; return; }
		status = 'submitting';
		try {
			const response = await fetch('/api/get-started', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...form, initial_administrator_name: form.is_administrator_same_as_contact ? null : form.initial_administrator_name, initial_administrator_email: form.is_administrator_same_as_contact ? null : form.initial_administrator_email, note: form.note || null, turnstile_token: turnstileToken }) });
			const result: { error?: string; field_errors?: Record<string, string>; applicationId?: string } = await response.json().catch(() => ({}));
			if (!response.ok) { errorMessage = result.error ?? 'We could not save your application.'; fieldErrors = result.field_errors ?? {}; const errorStep = firstStepWithError(fieldErrors); if (errorStep) currentStep = errorStep; status = 'form'; resetTurnstile(); return; }
			await goto(resolve(`/get-started/received?app=${encodeURIComponent(result.applicationId ?? '')}`));
		} catch { errorMessage = 'We could not save your application. Please try again.'; status = 'form'; resetTurnstile(); }
	}
</script>

<svelte:head><title>Get started · UpliftContractor</title></svelte:head>

<main class="get-started">
	<div class="get-started__layout">
			<aside class="get-started__intro"><div class="get-started__brand"><span class="get-started__brand-mark">U</span> UpliftContractor</div><div class="get-started__intro-copy"><div class="get-started__eyebrow">Let’s get your business moving</div><h1>Set up your workspace in a few minutes.</h1><p>Tell us a little about your business and we’ll prepare the right UpliftContractor experience for your team.</p></div><nav class="get-started__steps" aria-label="Application progress">{#each steps as step}<button type="button" class:get-started__step--active={currentStep === step.number} class:get-started__step--complete={currentStep > step.number} onclick={() => goToStep(step.number)} aria-current={currentStep === step.number ? 'step' : undefined}><span class="get-started__step-number">{currentStep > step.number ? '✓' : step.number}</span><span><strong>{step.label}</strong><small>{step.hint}</small></span></button>{/each}</nav><p class="get-started__support">Need help? <a href="mailto:hello@upliftcontractor.com">Talk to our team</a></p></aside>

			<section class="get-started__panel"><header class="get-started__header"><div class="get-started__mobile-progress">Step {currentStep} of {steps.length}</div><h2>{currentStep === 1 ? 'Choose your package' : currentStep === 2 ? 'Tell us about your business' : currentStep === 3 ? 'Who should we contact?' : 'Review your application'}</h2><p>{currentStep === 1 ? 'Start with the plan that fits your team today. You can adjust as you grow.' : currentStep === 2 ? 'These details help us tailor your workspace.' : currentStep === 3 ? 'We’ll use this information to follow up and set up account access.' : 'Everything look good? Submit your application and we’ll be in touch.'}</p></header>
				<form onsubmit={submit}>
					{#if currentStep === 1}<section class="get-started__step-panel" aria-labelledby="package-heading"><h3 id="package-heading">Choose a package</h3><div class="get-started__package-grid" role="radiogroup" aria-labelledby="package-heading">{#each data.packages as pkg (pkg.package_version_id)}{@const isSelected = form.package_version_id === pkg.package_version_id}<label class="package-card" class:package-card--selected={isSelected}><input type="radio" name="package_version_id" value={pkg.package_version_id} bind:group={form.package_version_id} class="package-card__radio" /><Card class="package-card__inner"><div class="package-card__name">{pkg.display_name}</div><div class="package-card__price">{formatPrice(pkg.price_usd_cents)}</div><p class="package-card__description">{pkg.public_description}</p>{#if seatLimitLabel(pkg)}<p class="package-card__seats">{seatLimitLabel(pkg)}</p>{/if}{#if pkg.features.length}<ul class="package-card__features">{#each pkg.features as feature (feature)}<li>{feature}</li>{/each}</ul>{/if}</Card></label>{/each}</div>{#if fieldErrors.package_version_id}<p class="get-started__error" role="alert">{fieldErrors.package_version_id}</p>{/if}<p class="get-started__note">Provider fees, if any, are separate. Payment is handled outside this form; we'll send instructions after you submit.</p></section>
					{:else if currentStep === 2}<section class="get-started__step-panel get-started__fields" aria-labelledby="details-heading"><h3 id="details-heading">Your business</h3><div class="get-started__field-grid"><Input id="business_name" label="Business name" bind:value={form.business_name} invalid={Boolean(fieldErrors.business_name)} errorMessage={fieldErrors.business_name} required /><Input id="trade" label="Trade" bind:value={form.trade} invalid={Boolean(fieldErrors.trade)} errorMessage={fieldErrors.trade} required /><div class="get-started__location-fields"><LocationPicker id="city_country" bind:value={form.city_country} invalid={Boolean(fieldErrors.city_country)} errorMessage={fieldErrors.city_country} required /><TimezonePicker id="time_zone" bind:value={form.time_zone} invalid={Boolean(fieldErrors.time_zone)} errorMessage={fieldErrors.time_zone} required /></div></div></section>
					{:else if currentStep === 3}<section class="get-started__step-panel get-started__fields" aria-labelledby="contact-heading"><h3 id="contact-heading">Main contact</h3><div class="get-started__field-grid"><Input id="main_contact_name" label="Contact name" bind:value={form.main_contact_name} invalid={Boolean(fieldErrors.main_contact_name)} errorMessage={fieldErrors.main_contact_name} required /><Input id="main_contact_email" label="Contact email" type="email" bind:value={form.main_contact_email} invalid={Boolean(fieldErrors.main_contact_email)} errorMessage={fieldErrors.main_contact_email} required /><Input id="main_contact_phone" label="Contact phone" type="tel" bind:value={form.main_contact_phone} invalid={Boolean(fieldErrors.main_contact_phone)} errorMessage={fieldErrors.main_contact_phone} required /></div><Checkbox id="is_administrator_same_as_contact" label="I'll be the one logging in and managing the account" bind:checked={form.is_administrator_same_as_contact} />{#if !form.is_administrator_same_as_contact}<h3>Account administrator</h3><div class="get-started__field-grid"><Input id="initial_administrator_name" label="Administrator name" bind:value={form.initial_administrator_name} invalid={Boolean(fieldErrors.initial_administrator_name)} errorMessage={fieldErrors.initial_administrator_name} required /><Input id="initial_administrator_email" label="Administrator email" type="email" bind:value={form.initial_administrator_email} invalid={Boolean(fieldErrors.initial_administrator_email)} errorMessage={fieldErrors.initial_administrator_email} required /></div>{/if}</section>
					{:else}<section class="get-started__step-panel get-started__review" aria-labelledby="review-heading"><h3 id="review-heading">Your application</h3><div class="get-started__review-card"><span>Package</span><strong>{data.packages.find((pkg) => pkg.package_version_id === form.package_version_id)?.display_name ?? 'Not selected'}</strong><button type="button" onclick={() => goToStep(1)}>Edit</button></div><div class="get-started__review-card"><span>Business</span><strong>{form.business_name || 'Not provided'}</strong><p>{form.trade} · {form.city_country}</p><button type="button" onclick={() => goToStep(2)}>Edit</button></div><div class="get-started__review-card"><span>Contact</span><strong>{form.main_contact_name || 'Not provided'}</strong><p>{form.main_contact_email} · {form.main_contact_phone}</p><button type="button" onclick={() => goToStep(3)}>Edit</button></div><label class="get-started__label" for="note">Anything else we should know? <span>(optional)</span></label><textarea id="note" class="get-started__textarea" bind:value={form.note} rows="3"></textarea>{#if data.turnstileSiteKey}<div bind:this={turnstileContainer} class="get-started__turnstile"></div>{/if}<Checkbox id="privacy_policy_agreed" label={`I agree to the privacy policy${data.privacyPolicyVersion ? ` (version ${data.privacyPolicyVersion})` : ''}`} bind:checked={form.privacy_policy_agreed} invalid={Boolean(fieldErrors.privacy_policy_agreed)} />{#if data.privacyPolicyUrl}<a class="get-started__policy-link" href={data.privacyPolicyUrl} target="_blank" rel="noopener noreferrer">Read the privacy policy</a>{/if}</section>{/if}
					{#if errorMessage}<p class="get-started__error" role="alert">{errorMessage}</p>{/if}<div class="get-started__actions">{#if currentStep > 1}<Button type="button" variant="secondary" onclick={previousStep}>Back</Button>{/if}{#if currentStep < 4}<Button type="button" fullWidth={currentStep === 1} onclick={nextStep}>Continue <span aria-hidden="true">→</span></Button>{:else}<Button type="submit" fullWidth loading={status === 'submitting'} disabled={status === 'submitting'}>{status === 'submitting' ? 'Submitting…' : 'Submit application'}</Button>{/if}</div>
				</form></section>
	</div>
</main>

<style lang="scss">
	.get-started { min-height: 100vh; padding: var(--space-largest) var(--space-large); background: var(--color-surface--background); color: var(--color-text); }
	.get-started__layout { display: grid; grid-template-columns: minmax(280px, 0.72fr) minmax(560px, 1.28fr); max-width: 1180px; min-height: 720px; margin: 0 auto; overflow: hidden; border: var(--border-base) solid var(--color-border); border-radius: var(--radius-large); background: var(--color-surface); box-shadow: var(--shadow-base); }
	.get-started__intro { display: flex; flex-direction: column; padding: var(--space-largest); color: var(--color-surface); background: var(--color-interactive-subtle, var(--color-interactive)); }
	.get-started__brand { display: flex; align-items: center; gap: var(--space-small); font-weight: 700; }
	.get-started__brand-mark { display: grid; width: 32px; height: 32px; place-items: center; border-radius: var(--radius-small); color: var(--color-interactive); background: var(--color-surface); font-weight: 900; }
	.get-started__intro-copy { margin: auto 0; max-width: 360px; }.get-started__intro h1 { margin: var(--space-base) 0; color: var(--color-surface); font-size: var(--typography--fontSize-jumbo); line-height: var(--typography--lineHeight-minuscule); }.get-started__intro p { color: color-mix(in srgb, var(--color-surface) 76%, transparent); font-size: var(--typography--fontSize-large); line-height: var(--typography--lineHeight-large); }
	.get-started__eyebrow { color: var(--color-brand); font-size: var(--typography--fontSize-small); font-weight: 700; letter-spacing: var(--typography--letterSpacing-loose); text-transform: uppercase; }.get-started__intro .get-started__eyebrow { color: var(--color-brand--highlight); }
	.get-started__steps { display: grid; gap: var(--space-small); }.get-started__steps button { display: flex; align-items: center; gap: var(--space-small); padding: var(--space-small); border: 0; border-radius: var(--radius-base); color: inherit; background: transparent; text-align: left; cursor: pointer; }.get-started__steps button:not(:disabled):hover { background: color-mix(in srgb, var(--color-surface) 12%, transparent); }.get-started__step-number { display: grid; width: 30px; height: 30px; flex: 0 0 30px; place-items: center; border: var(--border-base) solid color-mix(in srgb, var(--color-surface) 45%, transparent); border-radius: var(--radius-circle); font-size: var(--typography--fontSize-small); font-weight: 700; }.get-started__step--active .get-started__step-number, .get-started__step--complete .get-started__step-number { color: var(--color-interactive); border-color: var(--color-brand--highlight); background: var(--color-brand--highlight); }.get-started__steps strong, .get-started__steps small { display: block; }.get-started__steps small { margin-top: 2px; color: color-mix(in srgb, var(--color-surface) 65%, transparent); font-size: var(--typography--fontSize-small); }.get-started__support { margin: var(--space-largest) 0 0; color: color-mix(in srgb, var(--color-surface) 65%, transparent); font-size: var(--typography--fontSize-small) !important; }.get-started__support a { color: var(--color-surface); }
	.get-started__panel { padding: var(--space-largest); }.get-started__header { max-width: 620px; margin-bottom: var(--space-largest); }.get-started__header h2 { margin: var(--space-small) 0; color: var(--color-heading); font-size: var(--typography--fontSize-jumbo); line-height: var(--typography--lineHeight-minuscule); }.get-started__header p { color: var(--color-text--secondary); font-size: var(--typography--fontSize-large); line-height: var(--typography--lineHeight-large); }.get-started__mobile-progress { display: none; color: var(--color-interactive); font-size: var(--typography--fontSize-small); font-weight: 700; text-transform: uppercase; }
	.get-started__step-panel h3 { margin-bottom: var(--space-base); color: var(--color-heading); font-size: var(--typography--fontSize-larger); }.get-started__package-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: var(--space-base); }.package-card { display: block; cursor: pointer; }.package-card__radio { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }.package-card :global(.package-card__inner) { height: 100%; border-color: var(--color-border); transition: border-color var(--timing-quick) ease-out, box-shadow var(--timing-quick) ease-out; }.package-card:hover :global(.package-card__inner) { border-color: var(--color-interactive); }.package-card:has(.package-card__radio:focus-visible) :global(.package-card__inner), .package-card--selected :global(.package-card__inner) { border-color: var(--color-interactive); box-shadow: var(--shadow-focus); }.package-card__name { color: var(--color-heading); font-size: var(--typography--fontSize-large); font-weight: 700; }.package-card__price { margin: var(--space-small) 0; color: var(--color-interactive); font-size: var(--typography--fontSize-larger); font-weight: 700; }.package-card__description, .package-card__seats, .package-card__features { color: var(--color-text--secondary); font-size: var(--typography--fontSize-small); }.package-card__description { min-height: 34px; }.package-card__seats { color: var(--color-text); font-weight: 700; }.package-card__features { display: grid; gap: var(--space-smaller); margin: var(--space-base) 0 0; padding-left: var(--space-base); }.get-started__note { margin-top: var(--space-base); color: var(--color-text--secondary); font-size: var(--typography--fontSize-small); }
	.get-started__fields { display: grid; gap: var(--space-large); }.get-started__field-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: var(--space-base); }.get-started__location-fields { display: grid; grid-column: 1 / -1; grid-template-columns: minmax(0, 2fr) minmax(240px, 1fr); gap: var(--space-base); align-items: start; }.get-started__label { color: var(--color-heading); font-size: var(--typography--fontSize-base); }.get-started__label span { color: var(--color-text--secondary); }.get-started__textarea { width: 100%; min-height: 96px; padding: var(--space-base); border: var(--border-base) solid var(--color-border--interactive); border-radius: var(--radius-base); color: var(--color-text); background: var(--color-surface); font: inherit; resize: vertical; }.get-started__textarea:focus-visible { outline: none; box-shadow: var(--shadow-focus); }.get-started__policy-link { color: var(--color-interactive); font-size: var(--typography--fontSize-small); }.get-started__error { color: var(--color-critical); font-size: var(--typography--fontSize-small); }.get-started__actions { display: flex; justify-content: flex-end; gap: var(--space-small); margin-top: var(--space-largest); }.get-started__actions :global(.button--full-width) { max-width: 260px; }
	.get-started__review { display: grid; gap: var(--space-small); }.get-started__review-card { position: relative; display: grid; gap: var(--space-smaller); padding: var(--space-base); border: var(--border-base) solid var(--color-border); border-radius: var(--radius-base); }.get-started__review-card span { color: var(--color-text--secondary); font-size: var(--typography--fontSize-small); }.get-started__review-card strong { color: var(--color-heading); }.get-started__review-card p { margin: 0; color: var(--color-text--secondary); font-size: var(--typography--fontSize-small); }.get-started__review-card button { position: absolute; top: var(--space-base); right: var(--space-base); border: 0; color: var(--color-interactive); background: transparent; cursor: pointer; text-decoration: underline; }.get-started__review .get-started__label { margin-top: var(--space-base); }
	@media (max-width: 900px) { .get-started { padding: var(--space-base); }.get-started__layout { grid-template-columns: 1fr; min-height: auto; }.get-started__intro { padding: var(--space-large); }.get-started__intro-copy { margin: var(--space-largest) 0; }.get-started__intro h1 { font-size: var(--typography--fontSize-largest); }.get-started__steps { grid-template-columns: repeat(4, 1fr); gap: var(--space-smaller); }.get-started__steps button { display: block; padding: var(--space-small) var(--space-smaller); text-align: center; }.get-started__step-number { margin: 0 auto var(--space-smaller); }.get-started__steps small { display: none; }.get-started__support { display: none; }.get-started__panel { padding: var(--space-large); }.get-started__header { margin-bottom: var(--space-large); }.get-started__header h2 { font-size: var(--typography--fontSize-largest); }.get-started__mobile-progress { display: block; } }
	@media (max-width: 700px) { .get-started__location-fields { grid-template-columns: 1fr; } }
	@media (max-width: 560px) { .get-started__panel { padding: var(--space-base); }.get-started__field-grid { grid-template-columns: 1fr; }.get-started__package-grid { grid-template-columns: 1fr; }.get-started__actions { margin-top: var(--space-large); }.get-started__actions :global(.button--full-width) { max-width: none; } }
	.get-started__intro-copy { margin: var(--space-extravagant) 0 var(--space-largest); }
	.get-started__step-number { color: var(--color-surface); }
	.get-started__step--active .get-started__step-number, .get-started__step--complete .get-started__step-number { color: var(--color-heading); border-color: var(--color-brand); background: var(--color-brand); }
	.get-started__package-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); }
	.get-started__layout { max-width: 1320px; grid-template-columns: minmax(320px, 0.55fr) minmax(760px, 1.45fr); }
	.package-card__description, .package-card__seats, .package-card__features { font-size: var(--typography--fontSize-base); }
	.package-card__description, .package-card__features li { line-height: var(--typography--lineHeight-large); }
	.package-card__seats { line-height: var(--typography--lineHeight-base); }
	.package-card :global(.package-card__inner) { position: relative; min-height: 390px; padding: var(--space-large); box-shadow: none; transition: border-color var(--timing-quick) ease-out, box-shadow var(--timing-quick) ease-out, transform var(--timing-quick) ease-out; }
	.package-card:hover :global(.package-card__inner) { box-shadow: var(--shadow-low); transform: translateY(-2px); }
	.package-card--selected :global(.package-card__inner)::before { position: absolute; top: 0; right: var(--space-large); left: var(--space-large); height: 3px; border-radius: 0 0 var(--radius-small) var(--radius-small); background: var(--color-brand); content: ''; }
	.package-card--selected :global(.package-card__inner)::after { position: absolute; top: var(--space-base); right: var(--space-base); padding: var(--space-smaller) var(--space-small); border-radius: var(--radius-larger); color: var(--color-success--onSurface); background: var(--color-success--surface); content: 'Selected'; font-size: var(--typography--fontSize-smaller); font-weight: 700; }
	.package-card__name { padding-right: var(--space-largest); }
	.package-card__price { margin: var(--space-small) 0 var(--space-base); font-size: var(--typography--fontSize-largest); line-height: 1; }
	.package-card__description { min-height: 52px; line-height: var(--typography--lineHeight-large); }
	.package-card__features { gap: var(--space-small); margin-top: var(--space-large); padding: var(--space-large) 0 0; border-top: var(--border-base) solid var(--color-border); list-style: none; }
	.package-card__features li { position: relative; padding-left: var(--space-large); line-height: var(--typography--lineHeight-large); }
	.package-card__features li::before { position: absolute; top: 0; left: 0; color: var(--color-interactive); content: '✓'; font-weight: 800; }
	@media (max-width: 960px) { .get-started__package-grid { grid-template-columns: 1fr; }.package-card :global(.package-card__inner) { min-height: 0; } }
	@media (min-width: 901px) {
		.get-started__layout { display: block; max-width: 1320px; min-height: 0; }
		.get-started__intro { padding: var(--space-large) var(--space-largest); }
		.get-started__intro-copy { max-width: 760px; margin: var(--space-largest) 0; }
		.get-started__intro h1 { max-width: 720px; }
		.get-started__steps { grid-template-columns: repeat(4, minmax(0, 1fr)); gap: var(--space-small); }
		.get-started__steps button { min-height: 56px; }
		.get-started__support { display: none; }
		.get-started__panel { padding: var(--space-largest); }
		.get-started__package-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); }
		.package-card :global(.package-card__inner) { min-height: 430px; }
	}
	.get-started__intro-copy { display: block; margin: var(--space-largest) 0 var(--space-large); }
	.get-started__intro-copy .get-started__eyebrow, .get-started__intro-copy p { display: none; }
	.get-started__intro-copy h1 { margin: 0; }
	.get-started__intro { padding-top: var(--space-large); padding-bottom: var(--space-large); }
	.get-started__steps { margin-top: var(--space-largest); }
	@media (max-width: 900px) { .get-started__steps { margin-top: var(--space-large); }.get-started__layout { grid-template-columns: minmax(0, 1fr); } }
</style>
