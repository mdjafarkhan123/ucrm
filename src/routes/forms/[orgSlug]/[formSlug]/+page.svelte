<script lang="ts">
	import { page } from '$app/state';
	import Card from '$lib/components/ui/Card.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import {
		FORM_MAX_PHOTOS,
		isChoiceQuestion,
		type BookingSlot,
		type FormQuestion,
		type FormQuestionType
	} from '$lib/forms/types';
	import photoPlusIcon from '@tabler/icons/outline/photo-plus.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const formSlug = $derived(page.params.formSlug ?? '');

	type PhotoSlot = {
		id: string;
		previewUrl: string;
		objectKey: string | null;
		uploading: boolean;
		error: string;
	};
	type Status = 'form' | 'submitting' | 'submitted';

	const idempotencyKey = crypto.randomUUID();

	// --- Contact -------------------------------------------------------------------------------------

	let contactName = $state('');
	let contactEmail = $state('');
	let contactPhone = $state('');
	let contactCompany = $state('');
	let contactAddressLine1 = $state('');
	let contactAddressCity = $state('');
	let contactAddressStateRegion = $state('');
	let contactAddressPostalCode = $state('');
	let emailMarketingConsent = $state(false);
	let phoneMarketingConsent = $state(false);

	// --- Answers, keyed by question id ---------------------------------------------------------------

	function blankAnswer(type: FormQuestionType) {
		if (type === 'dropdown_multi' || type === 'checkbox' || type === 'image_upload')
			return [] as string[];
		if (type === 'yes_no') return null as boolean | null;
		return '';
	}

	function initialAnswers(): Record<string, unknown> {
		const out: Record<string, unknown> = {};
		if (!data.available) return out;
		for (const section of data.content.sections) {
			for (const question of section.questions) out[question.id] = blankAnswer(question.type);
		}
		return out;
	}

	let answers = $state<Record<string, unknown>>(initialAnswers());
	let topLevelPhotos = $state<PhotoSlot[]>([]);
	let questionPhotos = $state<Record<string, PhotoSlot[]>>({});

	function setTextAnswer(questionId: string, event: Event) {
		answers[questionId] = (event.currentTarget as HTMLInputElement | HTMLTextAreaElement).value;
	}

	function setNumberAnswer(questionId: string, event: Event) {
		const value = (event.currentTarget as HTMLInputElement).value;
		answers[questionId] = value === '' ? '' : Number(value);
	}

	// --- Booking (assessment/job forms only) ----------------------------------------------------------

	let selectedCatalogItemId = $state('');
	let selectedDate = $state('');
	let slots = $state<BookingSlot[]>([]);
	let slotsLoading = $state(false);
	let slotsError = $state('');
	let selectedSlot = $state<BookingSlot | null>(null);

	function nextDays(count: number) {
		const today = new Date();
		return Array.from({ length: count }, (_, i) => {
			const d = new Date(today);
			d.setDate(d.getDate() + i);
			const value = d.toISOString().slice(0, 10);
			const label = d.toLocaleDateString(undefined, {
				weekday: 'short',
				month: 'short',
				day: 'numeric'
			});
			return { value, label };
		});
	}
	const dateOptions = $derived(data.available && data.isBooking ? nextDays(14) : []);

	function formatTime(time: string) {
		return new Date(`1970-01-01T${time}`).toLocaleTimeString([], {
			hour: 'numeric',
			minute: '2-digit'
		});
	}

	function formatPrice(cents: number) {
		return `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 0 })}`;
	}

	async function chooseDate(date: string) {
		selectedDate = date;
		selectedSlot = null;
		slots = [];
		slotsError = '';
		slotsLoading = true;
		try {
			const params = new URLSearchParams({ range_start: date, range_end: date });
			const response = await fetch(
				`/api/public/forms/${data.available ? data.organizationSlug : ''}/${formSlug}/slots?${params}`
			);
			const result = await response.json().catch(() => []);
			if (!response.ok) {
				slotsError = (result as { error?: string }).error ?? 'Could not load available times.';
				return;
			}
			slots = result as BookingSlot[];
		} catch {
			slotsError = 'Could not load available times. Please try again.';
		} finally {
			slotsLoading = false;
		}
	}

	// --- Photo upload ----------------------------------------------------------------------------------

	const PHOTO_MAX_BYTES = 8 * 1024 * 1024;

	function readAsDataUrl(file: File): Promise<string> {
		return new Promise((resolvePromise, rejectPromise) => {
			const reader = new FileReader();
			reader.onload = () => resolvePromise(reader.result as string);
			reader.onerror = () => rejectPromise(new Error('Could not read that file.'));
			reader.readAsDataURL(file);
		});
	}

	async function uploadPhoto(file: File): Promise<PhotoSlot> {
		const id = crypto.randomUUID();
		const previewUrl = URL.createObjectURL(file);
		if (file.size > PHOTO_MAX_BYTES) {
			return {
				id,
				previewUrl,
				objectKey: null,
				uploading: false,
				error: 'That photo is larger than 8MB.'
			};
		}
		try {
			const dataUrl = await readAsDataUrl(file);
			const response = await fetch(
				`/api/public/forms/${data.available ? data.organizationSlug : ''}/${formSlug}/photos`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({
						idempotency_key: idempotencyKey,
						file_name: file.name,
						photo: dataUrl
					})
				}
			);
			const result = await response.json().catch(() => ({}));
			if (!response.ok) {
				return {
					id,
					previewUrl,
					objectKey: null,
					uploading: false,
					error: (result as { error?: string }).error ?? 'That photo could not be uploaded.'
				};
			}
			return {
				id,
				previewUrl,
				objectKey: (result as { object_key: string }).object_key,
				uploading: false,
				error: ''
			};
		} catch {
			return {
				id,
				previewUrl,
				objectKey: null,
				uploading: false,
				error: 'That photo could not be uploaded.'
			};
		}
	}

	async function addTopLevelPhotos(files: FileList | null) {
		if (!files || !data.available) return;
		const max = data.content.photos.max;
		const room = max - topLevelPhotos.length;
		const chosen = Array.from(files).slice(0, Math.max(room, 0));
		for (const file of chosen) {
			const placeholder: PhotoSlot = {
				id: crypto.randomUUID(),
				previewUrl: URL.createObjectURL(file),
				objectKey: null,
				uploading: true,
				error: ''
			};
			topLevelPhotos = [...topLevelPhotos, placeholder];
			const result = await uploadPhoto(file);
			topLevelPhotos = topLevelPhotos.map((p) =>
				p.id === placeholder.id ? { ...result, id: placeholder.id } : p
			);
		}
	}

	function removeTopLevelPhoto(id: string) {
		topLevelPhotos = topLevelPhotos.filter((p) => p.id !== id);
	}

	async function addQuestionPhotos(questionId: string, files: FileList | null) {
		if (!files) return;
		const existing = questionPhotos[questionId] ?? [];
		const room = FORM_MAX_PHOTOS - existing.length;
		const chosen = Array.from(files).slice(0, Math.max(room, 0));
		for (const file of chosen) {
			const placeholder: PhotoSlot = {
				id: crypto.randomUUID(),
				previewUrl: URL.createObjectURL(file),
				objectKey: null,
				uploading: true,
				error: ''
			};
			questionPhotos[questionId] = [...(questionPhotos[questionId] ?? []), placeholder];
			const result = await uploadPhoto(file);
			questionPhotos[questionId] = (questionPhotos[questionId] ?? []).map((p) =>
				p.id === placeholder.id ? { ...result, id: placeholder.id } : p
			);
		}
	}

	function removeQuestionPhoto(questionId: string, id: string) {
		questionPhotos[questionId] = (questionPhotos[questionId] ?? []).filter((p) => p.id !== id);
	}

	// --- Turnstile -------------------------------------------------------------------------------------

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

	$effect(() => {
		if (!data.available || !data.turnstileSiteKey) return;
		const script = document.createElement('script');
		script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js';
		script.async = true;
		script.defer = true;
		script.onload = () => {
			turnstileApi = (window as unknown as { turnstile?: TurnstileApi }).turnstile;
		};
		document.head.appendChild(script);
	});

	$effect(() => {
		if (!turnstileApi || !data.available) return;
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

	// --- Submit ----------------------------------------------------------------------------------------

	let status = $state<Status>('form');
	let errorMessage = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	function optionsOf(options: string[] | undefined): string[] {
		return options && options.length > 0 ? options : [];
	}

	function isAnswerEmpty(type: FormQuestionType, value: unknown): boolean {
		if (type === 'dropdown_multi' || type === 'checkbox' || type === 'image_upload') {
			return !Array.isArray(value) || value.length === 0;
		}
		if (type === 'yes_no') return value === null || value === undefined;
		return value === '' || value === null || value === undefined;
	}

	function validate(): string | null {
		if (!data.available) return 'This form is not available.';
		if (!contactName.trim()) return 'Enter your name.';
		if (
			data.content.contact.email.shown &&
			data.content.contact.email.required &&
			!contactEmail.trim()
		)
			return 'Enter your email address.';
		if (
			data.content.contact.phone.shown &&
			data.content.contact.phone.required &&
			!contactPhone.trim()
		)
			return 'Enter your phone number.';
		if (
			data.content.contact.company.shown &&
			data.content.contact.company.required &&
			!contactCompany.trim()
		)
			return 'Enter your company name.';
		if (
			data.content.contact.address.shown &&
			data.content.contact.address.required &&
			(!contactAddressLine1.trim() || !contactAddressCity.trim())
		)
			return 'Enter your address.';

		for (const section of data.content.sections) {
			for (const question of section.questions) {
				if (question.required && isAnswerEmpty(question.type, answers[question.id])) {
					return `“${question.label}” is required.`;
				}
			}
		}
		if (data.isBooking && !selectedSlot) return 'Choose a time for your visit.';
		if (data.turnstileSiteKey && !turnstileToken)
			return 'Please finish the quick “I am human” check before submitting.';
		return null;
	}

	function buildContactPayload() {
		if (!data.available) return {};
		const contact: Record<string, unknown> = { name: contactName.trim() };
		if (data.content.contact.email.shown) {
			contact.email = contactEmail.trim();
			if (data.content.contact.email.marketing_consent)
				contact.email_marketing_consent = emailMarketingConsent;
		}
		if (data.content.contact.phone.shown) {
			contact.phone = contactPhone.trim();
			if (data.content.contact.phone.marketing_consent)
				contact.phone_marketing_consent = phoneMarketingConsent;
		}
		if (data.content.contact.company.shown) contact.company = contactCompany.trim();
		if (data.content.contact.address.shown) {
			contact.address = {
				line1: contactAddressLine1.trim(),
				city: contactAddressCity.trim(),
				state_region: contactAddressStateRegion.trim(),
				postal_code: contactAddressPostalCode.trim()
			};
		}
		return contact;
	}

	function buildAnswersPayload() {
		if (!data.available) return {};
		const out: Record<string, unknown> = {};
		for (const section of data.content.sections) {
			for (const question of section.questions) {
				const value = answers[question.id];
				if (question.type === 'image_upload') {
					out[question.id] = (questionPhotos[question.id] ?? [])
						.map((p) => p.objectKey)
						.filter(Boolean);
					continue;
				}
				if (isAnswerEmpty(question.type, value)) continue;
				out[question.id] = value;
			}
		}
		return out;
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (!data.available) return;
		errorMessage = '';
		fieldErrors = {};
		const problem = validate();
		if (problem) {
			errorMessage = problem;
			return;
		}

		status = 'submitting';
		try {
			const photoObjectKeys = topLevelPhotos
				.map((p) => p.objectKey)
				.filter((k): k is string => Boolean(k));
			const response = await fetch(
				`/api/public/forms/${data.organizationSlug}/${formSlug}/submit`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({
						turnstile_token: turnstileToken,
						idempotency_key: idempotencyKey,
						contact: buildContactPayload(),
						answers: buildAnswersPayload(),
						photo_object_keys: photoObjectKeys,
						selected_catalog_item_id: data.isBooking ? selectedCatalogItemId || null : null,
						requested_starts_at: data.isBooking ? (selectedSlot?.starts_at ?? null) : null,
						requested_ends_at: data.isBooking ? (selectedSlot?.ends_at ?? null) : null
					})
				}
			);
			const result = await response.json().catch(() => ({}));
			if (!response.ok) {
				errorMessage = (result as { error?: string }).error ?? 'We could not save your submission.';
				fieldErrors = (result as { field_errors?: Record<string, string> }).field_errors ?? {};
				status = 'form';
				resetTurnstile();
				return;
			}
			status = 'submitted';
			if (data.content.confirmation.redirect_url) {
				setTimeout(() => {
					if (data.available) window.location.href = data.content.confirmation.redirect_url!;
				}, 3000);
			}
		} catch {
			errorMessage = 'We could not save your submission. Please try again.';
			status = 'form';
			resetTurnstile();
		}
	}
</script>

<svelte:head>
	<title>{data.available ? data.title : 'Form not available'}</title>
</svelte:head>

<main class="public-form">
	<div class="public-form__layout">
		{#if !data.available}
			<Card class="public-form__card">
				<div class="public-form__unavailable">
					<h1>This form isn’t available</h1>
					<p>
						The link may be out of date, or the business may no longer be accepting requests here.
					</p>
				</div>
			</Card>
		{:else if status === 'submitted'}
			<Card class="public-form__card">
				<div class="public-form__confirm">
					<span class="public-form__confirm-icon" aria-hidden="true">
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						{@html circleCheckIcon}
					</span>
					<h1>{data.content.confirmation.title || 'Thank you!'}</h1>
					<p>{data.content.confirmation.message}</p>
					{#if data.content.confirmation.redirect_url}
						<p class="public-form__redirect">Taking you to the next page…</p>
					{/if}
				</div>
			</Card>
		{:else}
			<Card class="public-form__card">
				<form onsubmit={submit}>
					<header class="public-form__head">
						<h1 class="public-form__title">{data.title}</h1>
						{#if data.description}<p class="public-form__description">{data.description}</p>{/if}
					</header>

					<section class="public-form__section">
						<h2 class="public-form__section-title">Your details</h2>
						<div class="public-form__fields">
							<Input id="contact-name" label="Full name" bind:value={contactName} required />
							{#if data.content.contact.email.shown}
								<Input
									id="contact-email"
									type="email"
									label="Email"
									bind:value={contactEmail}
									required={data.content.contact.email.required}
								/>
								{#if data.content.contact.email.marketing_consent}
									<Checkbox
										id="contact-email-consent"
										label="Send me occasional offers and updates by email"
										bind:checked={emailMarketingConsent}
									/>
								{/if}
							{/if}
							{#if data.content.contact.phone.shown}
								<Input
									id="contact-phone"
									type="tel"
									label="Phone"
									bind:value={contactPhone}
									required={data.content.contact.phone.required}
								/>
								{#if data.content.contact.phone.marketing_consent}
									<Checkbox
										id="contact-phone-consent"
										label="Send me occasional offers and updates by text"
										bind:checked={phoneMarketingConsent}
									/>
								{/if}
							{/if}
							{#if data.content.contact.company.shown}
								<Input
									id="contact-company"
									label="Company"
									bind:value={contactCompany}
									required={data.content.contact.company.required}
								/>
							{/if}
							{#if data.content.contact.address.shown}
								<Input
									id="contact-address-line1"
									label="Street address"
									bind:value={contactAddressLine1}
									required={data.content.contact.address.required}
									autocomplete="address-line1"
								/>
								<Input
									id="contact-address-city"
									label="City"
									bind:value={contactAddressCity}
									required={data.content.contact.address.required}
									autocomplete="address-level2"
								/>
								<Input
									id="contact-address-state"
									label="State or region"
									bind:value={contactAddressStateRegion}
									autocomplete="address-level1"
								/>
								<Input
									id="contact-address-postal"
									label="Postal code"
									bind:value={contactAddressPostalCode}
									autocomplete="postal-code"
								/>
							{/if}
						</div>
					</section>

					{#each data.content.sections as section (section.id)}
						<section class="public-form__section">
							<h2 class="public-form__section-title">{section.title}</h2>
							<div class="public-form__fields">
								{#each section.questions as question (question.id)}
									<div class="public-form__field">
										<span class="public-form__label">
											{question.label}{#if question.required}<em>*</em>{/if}
										</span>
										{#if question.help}<span class="public-form__help">{question.help}</span>{/if}

										{#if question.type === 'short_text'}
											<Input
												id={`q-${question.id}`}
												label=""
												value={(answers[question.id] as string) ?? ''}
												oninput={(event: Event) => setTextAnswer(question.id, event)}
											/>
										{:else if question.type === 'long_text'}
											<Textarea
												id={`q-${question.id}`}
												label=""
												rows={3}
												value={(answers[question.id] as string) ?? ''}
												oninput={(event: Event) => setTextAnswer(question.id, event)}
											/>
										{:else if question.type === 'number'}
											<Input
												id={`q-${question.id}`}
												label=""
												type="number"
												value={(answers[question.id] as number | '') ?? ''}
												oninput={(event: Event) => setNumberAnswer(question.id, event)}
											/>
										{:else if question.type === 'dropdown' || question.type === 'dropdown_multi'}
											{#if question.type === 'dropdown'}
												<Select
													id={`q-${question.id}`}
													ariaLabel={question.label}
													placeholder="Choose…"
													options={optionsOf(question.options).map((o) => ({ value: o, label: o }))}
													value={(answers[question.id] as string) ?? ''}
													onchange={(v) => (answers[question.id] = v)}
												/>
											{:else}
												<div class="public-form__choices">
													{#each optionsOf(question.options) as option (option)}
														{@const list = (answers[question.id] as string[]) ?? []}
														<label class="public-form__choice">
															<input
																type="checkbox"
																checked={list.includes(option)}
																onchange={(e) => {
																	const checked = (e.currentTarget as HTMLInputElement).checked;
																	const current = (answers[question.id] as string[]) ?? [];
																	answers[question.id] = checked
																		? [...current, option]
																		: current.filter((o) => o !== option);
																}}
															/>
															{option}
														</label>
													{/each}
												</div>
											{/if}
										{:else if question.type === 'radio'}
											<div class="public-form__choices">
												{#each optionsOf(question.options) as option (option)}
													<label class="public-form__choice">
														<input
															type="radio"
															name={`q-${question.id}`}
															value={option}
															checked={answers[question.id] === option}
															onchange={() => (answers[question.id] = option)}
														/>
														{option}
													</label>
												{/each}
											</div>
										{:else if question.type === 'checkbox'}
											<div class="public-form__choices">
												{#each optionsOf(question.options) as option (option)}
													{@const list = (answers[question.id] as string[]) ?? []}
													<label class="public-form__choice">
														<input
															type="checkbox"
															checked={list.includes(option)}
															onchange={(e) => {
																const checked = (e.currentTarget as HTMLInputElement).checked;
																const current = (answers[question.id] as string[]) ?? [];
																answers[question.id] = checked
																	? [...current, option]
																	: current.filter((o) => o !== option);
															}}
														/>
														{option}
													</label>
												{/each}
											</div>
										{:else if question.type === 'yes_no'}
											<div class="public-form__choices public-form__choices--row">
												<label class="public-form__choice">
													<input
														type="radio"
														name={`q-${question.id}`}
														checked={answers[question.id] === true}
														onchange={() => (answers[question.id] = true)}
													/>
													Yes
												</label>
												<label class="public-form__choice">
													<input
														type="radio"
														name={`q-${question.id}`}
														checked={answers[question.id] === false}
														onchange={() => (answers[question.id] = false)}
													/>
													No
												</label>
											</div>
										{:else if question.type === 'image_upload'}
											<div class="public-form__photos">
												{#each questionPhotos[question.id] ?? [] as photo (photo.id)}
													<div
														class="public-form__photo"
														class:public-form__photo--error={Boolean(photo.error)}
													>
														<img src={photo.previewUrl} alt="" />
														{#if photo.uploading}<span class="public-form__photo-status"
																>Uploading…</span
															>{/if}
														{#if photo.error}<span class="public-form__photo-status"
																>{photo.error}</span
															>{/if}
														<button
															type="button"
															class="public-form__photo-remove"
															aria-label="Remove photo"
															onclick={() => removeQuestionPhoto(question.id, photo.id)}
														>
															<!-- eslint-disable-next-line svelte/no-at-html-tags -->
															{@html xIcon}
														</button>
													</div>
												{/each}
												{#if (questionPhotos[question.id]?.length ?? 0) < FORM_MAX_PHOTOS}
													<label class="public-form__upload">
														<!-- eslint-disable-next-line svelte/no-at-html-tags -->
														{@html photoPlusIcon}
														<span>Add a photo</span>
														<input
															type="file"
															accept="image/png,image/jpeg,image/webp"
															multiple
															onchange={(e) => {
																void addQuestionPhotos(
																	question.id,
																	(e.currentTarget as HTMLInputElement).files
																);
																(e.currentTarget as HTMLInputElement).value = '';
															}}
														/>
													</label>
												{/if}
											</div>
										{/if}
									</div>
								{/each}
							</div>
						</section>
					{/each}

					{#if data.content.photos.enabled}
						<section class="public-form__section">
							<h2 class="public-form__section-title">Photos</h2>
							<div class="public-form__photos">
								{#each topLevelPhotos as photo (photo.id)}
									<div
										class="public-form__photo"
										class:public-form__photo--error={Boolean(photo.error)}
									>
										<img src={photo.previewUrl} alt="" />
										{#if photo.uploading}<span class="public-form__photo-status">Uploading…</span
											>{/if}
										{#if photo.error}<span class="public-form__photo-status">{photo.error}</span
											>{/if}
										<button
											type="button"
											class="public-form__photo-remove"
											aria-label="Remove photo"
											onclick={() => removeTopLevelPhoto(photo.id)}
										>
											<!-- eslint-disable-next-line svelte/no-at-html-tags -->
											{@html xIcon}
										</button>
									</div>
								{/each}
								{#if topLevelPhotos.length < data.content.photos.max}
									<label class="public-form__upload">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -->
										{@html photoPlusIcon}
										<span
											>Add up to {data.content.photos.max} photo{data.content.photos.max === 1
												? ''
												: 's'}</span
										>
										<input
											type="file"
											accept="image/png,image/jpeg,image/webp"
											multiple
											onchange={(e) => {
												void addTopLevelPhotos((e.currentTarget as HTMLInputElement).files);
												(e.currentTarget as HTMLInputElement).value = '';
											}}
										/>
									</label>
								{/if}
							</div>
						</section>
					{/if}

					{#if data.isBooking}
						<section class="public-form__section">
							<h2 class="public-form__section-title">Choose a time</h2>
							{#if data.services.length > 0}
								<Select
									id="booking-service"
									label="Service (optional)"
									placeholder="Not sure yet"
									options={data.services.map((s) => ({
										value: s.catalog_item_id,
										label: `${s.name} · ${formatPrice(s.unit_price_minor)}`
									}))}
									bind:value={selectedCatalogItemId}
								/>
							{/if}
							<div class="public-form__dates">
								{#each dateOptions as option (option.value)}
									<button
										type="button"
										class="public-form__date"
										class:public-form__date--selected={selectedDate === option.value}
										onclick={() => void chooseDate(option.value)}
									>
										{option.label}
									</button>
								{/each}
							</div>
							{#if slotsLoading}
								<p class="public-form__hint">Loading available times…</p>
							{:else if slotsError}
								<p class="public-form__hint">{slotsError}</p>
							{:else if selectedDate && slots.length === 0}
								<p class="public-form__hint">No times available on this day. Try another date.</p>
							{:else if slots.length > 0}
								<div class="public-form__slots">
									{#each slots as slot (slot.starts_at)}
										<button
											type="button"
											class="public-form__slot"
											class:public-form__slot--selected={selectedSlot?.starts_at === slot.starts_at}
											onclick={() => (selectedSlot = slot)}
										>
											{formatTime(slot.start_time)}
										</button>
									{/each}
								</div>
							{/if}
						</section>
					{/if}

					{#if errorMessage}<p class="public-form__error" role="alert">{errorMessage}</p>{/if}
					{#if Object.keys(fieldErrors).length > 0}
						<ul class="public-form__error-list">
							{#each Object.entries(fieldErrors) as [field, message] (field)}
								<li>{message}</li>
							{/each}
						</ul>
					{/if}

					{#if data.turnstileSiteKey}
						<div bind:this={turnstileContainer} class="public-form__turnstile"></div>
					{/if}

					<Button
						type="submit"
						fullWidth
						loading={status === 'submitting'}
						disabled={status === 'submitting'}
					>
						{status === 'submitting' ? 'Submitting…' : 'Submit'}
					</Button>
				</form>
			</Card>
		{/if}
	</div>
</main>

<style lang="scss">
	.public-form {
		display: flex;
		justify-content: center;
		min-height: 100vh;
		padding: var(--space-largest) var(--space-large);
		background: var(--color-surface--background);
	}

	.public-form__layout {
		width: 100%;
		max-width: 640px;
	}

	.public-form :global(.public-form__card) {
		box-shadow: var(--shadow-base);
	}

	.public-form__head {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin-bottom: var(--space-large);
	}

	.public-form__title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-jumbo);
		line-height: var(--typography--lineHeight-minuscule);
	}

	.public-form__description {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-base);
		white-space: pre-wrap;
	}

	.public-form__section {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding-top: var(--space-large);
		margin-top: var(--space-large);
		border-top: var(--border-base) solid var(--color-border);

		&:first-of-type {
			padding-top: 0;
			margin-top: 0;
			border-top: none;
		}
	}

	.public-form__section-title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.4px;
	}

	.public-form__fields {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.public-form__field {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
	}

	.public-form__label {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;

		em {
			margin-left: var(--space-smallest);
			color: var(--color-critical);
			font-style: normal;
		}
	}

	.public-form__help {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.public-form__choices {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&--row {
			flex-direction: row;
			gap: var(--space-large);
		}
	}

	.public-form__choice {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		cursor: pointer;
	}

	.public-form__photos {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-base);
	}

	.public-form__photo {
		position: relative;
		width: 88px;
		height: 88px;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);

		img {
			width: 100%;
			height: 100%;
			object-fit: cover;
		}

		&--error img {
			opacity: 0.4;
		}
	}

	.public-form__photo-status {
		position: absolute;
		inset: auto 0 0 0;
		padding: 2px var(--space-smaller);
		background: color-mix(in srgb, black 55%, transparent);
		color: white;
		font-size: 10px;
		text-align: center;
	}

	.public-form__photo-remove {
		position: absolute;
		top: 2px;
		right: 2px;
		display: grid;
		width: 20px;
		height: 20px;
		place-items: center;
		border: none;
		border-radius: var(--radius-circle);
		background: color-mix(in srgb, black 55%, transparent);
		color: white;
		cursor: pointer;

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.public-form__upload {
		display: flex;
		width: 88px;
		height: 88px;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-smaller);
		border: var(--border-base) dashed var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		text-align: center;
		cursor: pointer;

		input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			opacity: 0;
		}

		:global(svg) {
			width: 22px;
			height: 22px;
			color: var(--color-icon--secondary);
		}
	}

	.public-form__dates {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.public-form__date {
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-larger);
		color: var(--color-text);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-small);
		cursor: pointer;

		&--selected {
			border-color: var(--color-interactive);
			color: var(--color-interactive);
			background: var(--color-interactive--background);
			font-weight: 600;
		}
	}

	.public-form__slots {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.public-form__slot {
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-small);
		cursor: pointer;

		&--selected {
			border-color: var(--color-interactive);
			color: var(--color-surface);
			background: var(--color-interactive);
			font-weight: 600;
		}
	}

	.public-form__hint {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.public-form__error {
		margin: 0;
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-critical--surface);
		color: var(--color-critical--onSurface);
		font-size: var(--typography--fontSize-small);
	}

	.public-form__error-list {
		margin: 0;
		padding-left: var(--space-large);
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.public-form__turnstile {
		display: flex;
		justify-content: center;
	}

	.public-form :global(form) {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.public-form__unavailable {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-large) 0;
		text-align: center;

		h1 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
		}

		p {
			margin: 0;
			color: var(--color-text--secondary);
		}
	}

	.public-form__confirm {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-large) 0;
		text-align: center;

		h1 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
		}

		p {
			margin: 0;
			color: var(--color-text--secondary);
		}
	}

	.public-form__confirm-icon :global(svg) {
		width: 48px;
		height: 48px;
		color: var(--color-success);
	}

	.public-form__redirect {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	@media (max-width: 520px) {
		.public-form {
			padding: var(--space-base);
		}
	}
</style>
