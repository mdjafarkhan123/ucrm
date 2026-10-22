<script lang="ts">
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { untrack } from 'svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import ImportStepper from '$lib/components/imports/ImportStepper.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchTollfreeCheck,
		startTollfreeCheck,
		saveTollfreeCheck,
		sendTollfreeCheck,
		removeTollfreePicture,
		tollfreeKey,
		type TollfreeDetail,
		type TollfreePicture
	} from '$lib/communications/sms-tollfree';
	import { numberReadinessKey } from '$lib/communications/number-readiness';
	import type { SmsRegistrationAnswers } from '$lib/server/validation/communications-sms-registration.schema';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import imageIcon from '@tabler/icons/outline/photo-plus.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';

	const senderId = $derived(page.params.senderId ?? '');
	const client = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: tollfreeKey(senderId),
		queryFn: () => fetchTollfreeCheck(senderId),
		refetchInterval: (state: { state: { data: TollfreeDetail | undefined } }) =>
			state.state.data?.check?.status === 'sending' ? 4000 : false
	}));
	const detail = $derived(query.data);
	const check = $derived(detail?.check);
	const editable = $derived(check?.status === 'draft' || check?.status === 'needs_fix');
	const numbersUrl = resolve('/(app)/settings/communications/sms');
	const steps = [
		{ n: 1, title: 'Business', hint: 'Your details', icon: buildingIcon },
		{ n: 2, title: 'Texting', hint: 'How you text', icon: messageIcon },
		{ n: 3, title: 'Proof of consent', hint: 'Add pictures', icon: imageIcon },
		{ n: 4, title: 'Check and send', hint: 'For review', icon: sendIcon }
	];
	const businessTypes = [
		{ value: 'sole_proprietorship', label: 'Sole proprietorship' },
		{ value: 'partnership', label: 'Partnership' },
		{ value: 'limited_liability_company', label: 'Limited liability company' },
		{ value: 'cooperative', label: 'Cooperative' },
		{ value: 'nonprofit_corporation', label: 'Nonprofit corporation' },
		{ value: 'corporation', label: 'Corporation' },
		{ value: 'other', label: 'Other' }
	];
	const consentMethods = [
		{ value: 'website_form', label: 'Website form' },
		{ value: 'paper_form', label: 'Paper form' },
		{ value: 'verbal', label: 'In person or on a call' },
		{ value: 'text_initiated', label: 'Customer texted us first' }
	];
	const volumes = [
		{ value: 'under_500', label: 'Under 500 a month' },
		{ value: '500_2000', label: '500–2,000 a month' },
		{ value: '2001_10000', label: '2,001–10,000 a month' },
		{ value: 'over_10000', label: 'Over 10,000 a month' }
	];

	function blank(): SmsRegistrationAnswers {
		return {
			legal_business_name: '',
			business_type: 'sole_proprietorship',
			business_registration_id_type: '',
			business_registration_id: '',
			website_url: '',
			business_address: {
				line1: '',
				line2: '',
				city: '',
				region: '',
				postal_code: '',
				country_code: 'US'
			},
			authorized_representative: {
				first_name: '',
				last_name: '',
				business_title: '',
				job_position: '',
				email: '',
				phone_number: ''
			},
			messaging: {
				description: '',
				consent_method: 'website_form',
				consent_description: '',
				sample_messages: ['', ''],
				privacy_policy_url: '',
				terms_url: '',
				estimated_monthly_messages: 'under_500'
			}
		};
	}
	let draft = $state<SmsRegistrationAnswers>(blank());
	let hydrated = $state<string | null>(null);
	let step = $state(1);
	let saving = $state(false);
	let starting = $state(false);
	let sending = $state(false);
	let removing = $state<string | null>(null);
	let uploading = $state(false);
	let uploadPercent = $state(0);
	let uploadError = $state('');
	let formError = $state('');
	let pictures = $state<TollfreePicture[]>([]);
	let revision = $state(1);
	let fileInput = $state<HTMLInputElement>();

	$effect(() => {
		const data = query.data;
		if (!data?.check || hydrated === data.check.id + ':' + data.check.revision) return;
		untrack(() => {
			const base = blank();
			const saved = data.check?.answers.business ?? {};
			draft = {
				...base,
				...saved,
				business_address: { ...base.business_address, ...saved.business_address },
				authorized_representative: {
					...base.authorized_representative,
					...saved.authorized_representative
				},
				messaging: {
					...base.messaging,
					...saved.messaging,
					sample_messages: saved.messaging?.sample_messages?.length
						? [...saved.messaging.sample_messages]
						: ['', '']
				}
			};
			pictures = data.pictures;
			revision = data.check.revision;
			hydrated = data.check.id + ':' + data.check.revision;
		});
	});

	async function refresh() {
		await client.invalidateQueries({ queryKey: tollfreeKey(senderId) });
		await client.invalidateQueries({ queryKey: numberReadinessKey });
	}

	async function start() {
		if (starting) return;
		starting = true;
		try {
			await startTollfreeCheck(senderId);
			await refresh();
		} catch (cause) {
			formError = cause instanceof Error ? cause.message : 'Could not start this check.';
		} finally {
			starting = false;
		}
	}

	async function save(): Promise<boolean> {
		if (!check || saving || !editable) return false;
		saving = true;
		formError = '';
		try {
			const result = await saveTollfreeCheck(senderId, revision, draft);
			revision = result.check?.revision ?? revision + 1;
			hydrated = result.check ? result.check.id + ':' + result.check.revision : null;
			client.setQueryData(tollfreeKey(senderId), result);
			return true;
		} catch (cause) {
			formError = cause instanceof Error ? cause.message : 'Could not save this draft.';
			return false;
		} finally {
			saving = false;
		}
	}

	async function continueStep() {
		if (await save()) step = Math.min(4, step + 1);
	}

	function upload(file: File) {
		if (!check || uploading) return;
		uploading = true;
		uploadPercent = 0;
		uploadError = '';
		const form = new FormData();
		form.set('picture', file);
		form.set('expected_revision', String(revision));
		const xhr = new XMLHttpRequest();
		xhr.open('POST', `/api/settings/communications/sms/toll-free/${senderId}/pictures`);
		xhr.upload.onprogress = (event) => {
			if (event.lengthComputable) uploadPercent = Math.round((event.loaded * 100) / event.total);
		};
		xhr.onload = () => {
			const result = JSON.parse(xhr.responseText || '{}');
			if (xhr.status >= 200 && xhr.status < 300) {
				pictures = result.pictures;
				revision = result.revision;
				hydrated = check.id + ':' + result.revision;
				void refresh();
			} else uploadError = result.error ?? 'That picture could not be uploaded.';
			uploading = false;
		};
		xhr.onerror = () => {
			uploadError = 'That picture could not be uploaded. Try again.';
			uploading = false;
		};
		xhr.send(form);
	}

	async function removePicture(id: string) {
		if (removing || !check) return;
		removing = id;
		try {
			const result = await removeTollfreePicture(senderId, id, revision);
			pictures = result.pictures;
			revision = result.revision;
			hydrated = check.id + ':' + result.revision;
			await refresh();
		} catch (cause) {
			uploadError = cause instanceof Error ? cause.message : 'Could not remove that picture.';
		} finally {
			removing = null;
		}
	}

	async function send() {
		if (!check || sending || !(await save())) return;
		sending = true;
		formError = '';
		try {
			await sendTollfreeCheck(senderId, revision);
			await refresh();
			toast.success('Sent for review. The answer will show on this number.');
		} catch (cause) {
			formError = cause instanceof Error ? cause.message : 'Could not send this check.';
		} finally {
			sending = false;
		}
	}
</script>

<div class="tollfree-form">
	<Breadcrumbs
		items={[
			{ label: 'Settings', href: resolve('/(app)/settings') },
			{ label: 'Phone & SMS', href: numbersUrl, icon: messageIcon },
			{ label: 'Toll-free business details', icon: buildingIcon }
		]}
	/>
	<header class="tollfree-form__header">
		<IconTile icon={buildingIcon} tone="conversation" />
		<div>
			<h1>Toll-free business details</h1>
			<p>
				{detail?.phone_number ?? 'Your toll-free number'} needs a carrier check before it can text.
			</p>
		</div>
	</header>
	{#if query.isPending}
		<LoadingSkeleton height="300px" />
	{:else if query.isError}
		<ErrorState title="Could not load this check" onRetry={() => query.refetch()} />
	{:else if !check}
		<SetupStepCard
			title="Start the carrier check"
			hint="Your saved business answers will carry over."
			icon={buildingIcon}
			tone="conversation"
		>
			<p>Carriers check who owns this number and how customers agree to texts.</p>
			{#snippet footer()}<a href={numbersUrl}>Back to numbers</a><Button
					loading={starting}
					onclick={start}>Add business details</Button
				>{/snippet}
		</SetupStepCard>
	{:else if !editable}
		<section
			class="tollfree-form__result"
			class:tollfree-form__result--approved={check.status === 'approved'}
		>
			<IconTile
				icon={check.status === 'approved' ? checkIcon : sendIcon}
				tone={check.status === 'approved' ? 'success' : 'informative'}
			/>
			<h2>
				{check.status === 'approved'
					? 'Approved'
					: check.status === 'sending'
						? 'Sending to carriers'
						: 'Under review'}
			</h2>
			<p>
				{check.status === 'approved'
					? 'This number is approved for texting.'
					: 'The carrier answer will show on your number card. You can leave this page.'}
			</p>
			<Button href={numbersUrl} variant="secondary">Back to numbers</Button>
		</section>
	{:else}
		{#if check.status === 'needs_fix'}
			<div class="tollfree-form__notice" role="alert">
				<IconTile icon={alertIcon} tone="critical" />
				<div>
					<strong>Carriers asked for a change</strong>
					<p>{check.failure_reason ?? 'Check your answers and proof pictures, then send again.'}</p>
				</div>
			</div>
		{/if}
		<ImportStepper current={step} {steps} label="Toll-free check steps" />
		{#if step === 1}
			<SetupStepCard
				title="Business"
				hint="Filled in from your texting registration. Check it before continuing."
				icon={buildingIcon}
				tone="conversation"
			>
				<div class="tollfree-form__fields">
					<Input
						id="tf-name"
						label="Legal business name"
						bind:value={draft.legal_business_name}
						required
					/>
					<Select
						id="tf-type"
						label="Business type"
						options={businessTypes}
						value={draft.business_type}
						onchange={(value) =>
							(draft.business_type = value as SmsRegistrationAnswers['business_type'])}
					/>
					<Input
						id="tf-registration-type"
						label="Registration number type"
						bind:value={draft.business_registration_id_type}
					/>
					<Input
						id="tf-registration-id"
						label="Registration number"
						bind:value={draft.business_registration_id}
					/>
					<Input
						id="tf-site"
						label="Business website"
						type="url"
						bind:value={draft.website_url}
						required
					/>
					<Input
						id="tf-street"
						label="Street address"
						bind:value={draft.business_address.line1}
						required
					/>
					<Input id="tf-city" label="City" bind:value={draft.business_address.city} required />
					<Input
						id="tf-region"
						label="State or region"
						bind:value={draft.business_address.region}
						required
					/>
					<Input
						id="tf-postal"
						label="Postal code"
						bind:value={draft.business_address.postal_code}
						required
					/>
					<Input
						id="tf-country"
						label="Country code"
						bind:value={draft.business_address.country_code}
						required
					/>
					<Input
						id="tf-first"
						label="Contact first name"
						bind:value={draft.authorized_representative.first_name}
						required
					/>
					<Input
						id="tf-last"
						label="Contact last name"
						bind:value={draft.authorized_representative.last_name}
						required
					/>
					<Input
						id="tf-title"
						label="Contact title"
						bind:value={draft.authorized_representative.business_title}
						required
					/>
					<Input
						id="tf-position"
						label="Contact position"
						bind:value={draft.authorized_representative.job_position}
						required
					/>
					<Input
						id="tf-email"
						label="Contact email"
						type="email"
						bind:value={draft.authorized_representative.email}
						required
					/>
					<Input
						id="tf-phone"
						label="Contact phone, including country code"
						type="tel"
						bind:value={draft.authorized_representative.phone_number}
						required
					/>
				</div>
				{#snippet footer()}<a href={numbersUrl}>Back to numbers</a><span
						class="tollfree-form__saved">{formError}</span
					><Button loading={saving} onclick={continueStep}>Continue</Button>{/snippet}
			</SetupStepCard>
		{:else if step === 2}
			<SetupStepCard
				title="Texting"
				hint="Tell carriers what customers will receive and how they agree."
				icon={messageIcon}
				tone="conversation"
			>
				<Textarea
					id="tf-purpose"
					label="What will you text customers about?"
					bind:value={draft.messaging.description}
					required
				/>
				<Select
					id="tf-consent"
					label="How do customers agree?"
					options={consentMethods}
					value={draft.messaging.consent_method}
					onchange={(value) =>
						(draft.messaging.consent_method =
							value as SmsRegistrationAnswers['messaging']['consent_method'])}
				/>
				<Textarea
					id="tf-consent-description"
					label="Explain how you collect agreement"
					bind:value={draft.messaging.consent_description}
					required
				/>
				<Select
					id="tf-volume"
					label="Estimated messages each month"
					options={volumes}
					value={draft.messaging.estimated_monthly_messages}
					onchange={(value) =>
						(draft.messaging.estimated_monthly_messages =
							value as SmsRegistrationAnswers['messaging']['estimated_monthly_messages'])}
				/>
				<div class="tollfree-form__fields">
					<Textarea
						id="tf-example-1"
						label="Example text 1"
						bind:value={draft.messaging.sample_messages[0]}
						required
					/><Textarea
						id="tf-example-2"
						label="Example text 2"
						bind:value={draft.messaging.sample_messages[1]}
						required
					/>
				</div>
				<div class="tollfree-form__fields">
					<Input
						id="tf-policy"
						label="Privacy policy link (optional)"
						type="url"
						bind:value={draft.messaging.privacy_policy_url}
					/><Input
						id="tf-terms"
						label="Terms link (optional)"
						type="url"
						bind:value={draft.messaging.terms_url}
					/>
				</div>
				{#snippet footer()}<Button variant="quiet" onclick={() => (step = 1)}>Back</Button><span
						class="tollfree-form__saved">{formError}</span
					><Button loading={saving} onclick={continueStep}>Continue</Button>{/snippet}
			</SetupStepCard>
		{:else if step === 3}
			<SetupStepCard
				title="Proof of consent"
				hint="Show carriers where customers agree to receive your texts."
				icon={imageIcon}
				tone="conversation"
			>
				<p class="tollfree-form__hint">
					Add a clear picture of the form, web page or sign customers see when they agree. Add up to
					five JPG or PNG pictures, 5 MB each.
				</p>
				<label class="tollfree-form__upload" class:tollfree-form__upload--busy={uploading}>
					<span aria-hidden="true">{@html imageIcon}</span>
					<strong>{uploading ? `Uploading ${uploadPercent}%` : 'Add a picture'}</strong>
					<small>JPG or PNG · up to five pictures</small>
					<input
						bind:this={fileInput}
						type="file"
						accept="image/jpeg,image/png"
						disabled={uploading || pictures.length >= 5}
						onchange={(event) => {
							const file = event.currentTarget.files?.[0];
							if (file) upload(file);
							event.currentTarget.value = '';
						}}
					/>
					{#if uploading}<progress
							value={uploadPercent}
							max="100"
							aria-label="Picture upload progress"
						></progress>{/if}
				</label>
				{#if uploadError}<p class="tollfree-form__error" role="alert">
						{uploadError}
						<Button variant="quiet" size="small" onclick={() => fileInput?.click()}
							>Try again</Button
						>
					</p>{/if}
				{#if pictures.length}<ul class="tollfree-form__pictures">
						{#each pictures as picture (picture.id)}<li>
								<span>{picture.file_name}</span><Button
									variant="quiet"
									size="small"
									loading={removing === picture.id}
									onclick={() => removePicture(picture.id)}>Remove</Button
								>
							</li>{/each}
					</ul>{/if}
				{#snippet footer()}<Button variant="quiet" onclick={() => (step = 2)}>Back</Button><span
						class="tollfree-form__saved">{formError}</span
					><Button loading={saving} disabled={uploading} onclick={continueStep}>Continue</Button
					>{/snippet}
			</SetupStepCard>
		{:else}
			<SetupStepCard
				title="Check and send"
				hint="Review the details carriers will check."
				icon={sendIcon}
				tone="conversation"
			>
				<div class="tollfree-form__review">
					<strong>Ready for carrier review</strong>
					<p>{draft.legal_business_name || 'Your business'} · {detail.phone_number}</p>
					<p>{pictures.length} proof {pictures.length === 1 ? 'picture' : 'pictures'} attached</p>
					<p>
						Carriers will review these details before this number can text. Their answer will show
						here.
					</p>
				</div>
				{#if formError}<p class="tollfree-form__error" role="alert">{formError}</p>{/if}
				{#snippet footer()}<Button variant="quiet" onclick={() => (step = 3)}>Back</Button><Button
						variant="secondary"
						loading={saving}
						onclick={async () => {
							if (await save()) toast.success('Draft saved.');
						}}>Save draft</Button
					><Button loading={sending || saving} onclick={send}>Send for review</Button>{/snippet}
			</SetupStepCard>
		{/if}
	{/if}
</div>

<style lang="scss">
	.tollfree-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		max-width: 760px;
		margin-inline: auto;
		padding: var(--space-large) var(--space-base);
		&__header {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			h1 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
			}
			p {
				margin: 0;
				color: var(--color-text--secondary);
			}
		}
		&__fields {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}
		&__saved {
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-smaller);
		}
		&__hint {
			margin: 0;
			padding: var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-informative--onSurface);
			background: var(--color-informative--surface);
		}
		&__upload {
			display: grid;
			justify-items: center;
			gap: var(--space-small);
			min-height: 160px;
			padding: var(--space-medium);
			border: var(--border-base) dashed var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface--background--subtle);
			cursor: pointer;
			input {
				position: absolute;
				width: 1px;
				height: 1px;
				opacity: 0;
			}
			:global(svg) {
				width: 28px;
				height: 28px;
				color: var(--color-conversation);
			}
			small {
				color: var(--color-text--secondary);
			}
			progress {
				width: 100%;
				accent-color: var(--color-conversation);
			}
			&:focus-within {
				outline: var(--border-base) solid var(--color-interactive);
			}
			&--busy {
				cursor: wait;
			}
		}
		&__pictures {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
			li {
				display: flex;
				align-items: center;
				justify-content: space-between;
				gap: var(--space-base);
				padding: var(--space-small);
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-base);
			}
		}
		&__error {
			margin: 0;
			color: var(--color-critical--onSurface);
		}
		&__review {
			padding: var(--space-medium);
			border-radius: var(--radius-base);
			color: var(--color-success--onSurface);
			background: var(--color-success--surface);
			p {
				margin-bottom: 0;
			}
		}
		&__notice {
			display: flex;
			gap: var(--space-base);
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			p {
				margin: var(--space-smallest) 0 0;
			}
		}
		&__result {
			display: grid;
			justify-items: center;
			gap: var(--space-base);
			padding: var(--space-largest);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
			text-align: center;
			h2,
			p {
				margin: 0;
			}
		}
		@media (max-width: 640px) {
			&__fields {
				grid-template-columns: 1fr;
			}
		}
	}
</style>
