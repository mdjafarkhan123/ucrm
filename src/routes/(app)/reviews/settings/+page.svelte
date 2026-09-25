<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import ReviewRoutingSection from '$lib/components/reviews/ReviewRoutingSection.svelte';
	import ReviewFeedbackFormEditor from '$lib/components/reviews/ReviewFeedbackFormEditor.svelte';
	import ReviewMessageStylesEditor from '$lib/components/reviews/ReviewMessageStylesEditor.svelte';
	import {
		fetchReviewSettings,
		reviewSettingsKey,
		saveReviewSettings,
		type ReviewSettingsSaveError
	} from '$lib/reviews/api';
	import {
		isGoogleReviewUrl,
		type ReviewFeedbackForm,
		type ReviewMessageStyles,
		type ReviewSettingsView
	} from '$lib/reviews/settings';
	import { settingsHomeKey } from '$lib/settings/api';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import brandGoogleIcon from '@tabler/icons/outline/brand-google.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import circleIcon from '@tabler/icons/outline/circle-dashed.svg?raw';

	// Google review setup (docs/google-review-campaign-owner-brief.md): the Google link, what the review page
	// shows, the private-feedback form and the request wording. Nothing writes until Save.
	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: reviewSettingsKey,
		queryFn: fetchReviewSettings
	}));

	type Draft = {
		google_review_url: string;
		routing_enabled: boolean;
		routing_google_min_rating: number;
		feedback_form: ReviewFeedbackForm;
		message_styles: ReviewMessageStyles;
	};

	let draft = $state<Draft | null>(null);
	let savedSnapshot = $state('');
	let revision = $state(0);
	let routingAcknowledged = $state(false);
	let saving = $state(false);
	let errorMessage = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let layout = $state<RecordFormLayout>();

	function seed(view: ReviewSettingsView) {
		const next: Draft = {
			google_review_url: view.google_review_url ?? '',
			routing_enabled: view.routing_enabled,
			routing_google_min_rating: view.routing_google_min_rating,
			feedback_form: structuredClone(view.feedback_form),
			message_styles: structuredClone(view.message_styles)
		};
		draft = next;
		savedSnapshot = JSON.stringify(next);
		revision = view.revision;
		routingAcknowledged = false;
		fieldErrors = {};
	}

	$effect(() => {
		const data = query.data;
		if (!data) return;
		untrack(() => {
			if (draft === null) seed(data);
		});
	});

	const dirty = $derived(draft !== null && JSON.stringify(draft) !== savedSnapshot);

	const trimmedUrl = $derived(draft?.google_review_url.trim() ?? '');
	const urlValid = $derived(trimmedUrl === '' || isGoogleReviewUrl(trimmedUrl));
	const urlError = $derived(
		fieldErrors.google_review_url ??
			(urlValid
				? ''
				: 'This does not look like a Google review link. Copy it from your Google Business Profile.')
	);

	beforeNavigate((navigation) => {
		if (!dirty) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});
	$effect(() => {
		function handler(event: BeforeUnloadEvent) {
			if (!dirty) return;
			event.preventDefault();
		}
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	function cancel() {
		if (query.data) seed(query.data);
		errorMessage = '';
	}

	async function reloadLatest() {
		const fresh = await queryClient.fetchQuery({
			queryKey: reviewSettingsKey,
			queryFn: fetchReviewSettings,
			staleTime: 0
		});
		seed(fresh);
		errorMessage = '';
	}

	async function save() {
		if (!draft) return;
		saving = true;
		errorMessage = '';
		fieldErrors = {};
		try {
			const result = await saveReviewSettings({
				expected_revision: revision,
				google_review_url: trimmedUrl === '' ? null : trimmedUrl,
				routing_enabled: draft.routing_enabled,
				routing_google_min_rating: draft.routing_google_min_rating,
				acknowledge_routing: routingAcknowledged,
				feedback_form: draft.feedback_form,
				message_styles: draft.message_styles
			});
			queryClient.setQueryData(reviewSettingsKey, result);
			seed(result);
			toast.success('Review settings saved.');
			void queryClient.invalidateQueries({ queryKey: settingsHomeKey });
		} catch (error) {
			const saveError = error as ReviewSettingsSaveError;
			fieldErrors = saveError.fieldErrors ?? {};
			errorMessage = saveError.message ?? 'Review settings could not be saved.';
		} finally {
			saving = false;
		}
	}

	const routingError = $derived(fieldErrors.routing_enabled ?? '');
</script>

<svelte:head><title>Google reviews · Settings · Contractor CRM</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if query.isError}
	<ErrorState
		description={query.error?.message ?? 'Review settings could not be loaded.'}
		retry={() => query.refetch()}
	/>
{:else if query.isPending || draft === null}
	<LoadingSkeleton variant="card" rows={4} />
{:else}
	{@const view = query.data}
	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Google reviews' }]}
	/>

	<RecordFormLayout title="Google reviews" icon={starIcon} bind:this={layout} error={errorMessage}>
		{#snippet main()}
			{#if draft}
				<p class="review-settings__intro">
					After you finish a job, UCRM can ask your customer how it went. They tap a link, land on a
					page with your branding, and can leave you a Google review or tell you privately if
					something went wrong.
				</p>

				{#if errorMessage.startsWith('Someone else saved')}
					<div class="review-settings__conflict" role="alert">
						<p>{errorMessage}</p>
						<Button variant="secondary" size="small" onclick={() => void reloadLatest()}>
							Load the latest settings
						</Button>
					</div>
				{/if}

				<SectionBlock
					title="Google review link"
					hint="Where customers go to leave you a public review."
					icon={brandGoogleIcon}
					form
					level={3}
				>
					<div class="review-settings__link">
						<Input
							id="review-google-url"
							label="Your Google review link"
							type="url"
							placeholder="https://g.page/r/…/review"
							bind:value={draft.google_review_url}
							invalid={urlError !== ''}
							errorMessage={urlError}
							disabled={saving}
						/>
						<div class="review-settings__link-actions">
							<Button
								variant="secondary"
								size="small"
								href={trimmedUrl && urlValid ? trimmedUrl : undefined}
								target="_blank"
								disabled={!trimmedUrl || !urlValid}
							>
								<span class="review-settings__button-icon" aria-hidden="true"
									>{@html externalLinkIcon}</span
								>
								Test this link
							</Button>
						</div>
						<ol class="review-settings__steps">
							<li>Open your Google Business Profile (search your business name on Google).</li>
							<li>
								Choose <strong>Ask for reviews</strong> (or <strong>Get more reviews</strong>).
							</li>
							<li>Copy the link and paste it here.</li>
						</ol>
					</div>
				</SectionBlock>

				<ReviewRoutingSection
					bind:enabled={draft.routing_enabled}
					bind:minRating={draft.routing_google_min_rating}
					bind:acknowledged={routingAcknowledged}
					hasGoogleLink={trimmedUrl !== '' && urlValid}
					disabled={saving}
					errorMessage={routingError}
				/>

				<ReviewFeedbackFormEditor bind:form={draft.feedback_form} disabled={saving} {fieldErrors} />

				<ReviewMessageStylesEditor
					bind:styles={draft.message_styles}
					disabled={saving}
					{fieldErrors}
				/>
			{/if}
		{/snippet}

		{#snippet rail()}
			<RailCard title="Setup checklist">
				<ul class="review-settings__checklist">
					<li class="review-settings__check">
						<span
							class="review-settings__check-icon"
							class:review-settings__check-icon--done={Boolean(view.google_review_url)}
							aria-hidden="true">{@html view.google_review_url ? checkIcon : circleIcon}</span
						>
						<div>
							<p class="review-settings__check-title">Google review link</p>
							<p class="review-settings__check-detail">
								{view.google_review_url ? 'Saved.' : 'Paste and save your link.'}
							</p>
						</div>
					</li>
					<li class="review-settings__check">
						<span
							class="review-settings__check-icon"
							class:review-settings__check-icon--done={view.readiness.sms_ready}
							aria-hidden="true">{@html view.readiness.sms_ready ? checkIcon : circleIcon}</span
						>
						<div>
							<p class="review-settings__check-title">Text messages</p>
							<p class="review-settings__check-detail">
								{#if view.readiness.sms_ready}
									Ready to send.
								{:else}
									Not ready yet. <a href={resolve('/(app)/settings/communications/sms')}
										>Set up texting</a
									>
								{/if}
							</p>
						</div>
					</li>
					<li class="review-settings__check">
						<span
							class="review-settings__check-icon"
							class:review-settings__check-icon--done={view.readiness.email_ready}
							aria-hidden="true">{@html view.readiness.email_ready ? checkIcon : circleIcon}</span
						>
						<div>
							<p class="review-settings__check-title">Email</p>
							<p class="review-settings__check-detail">
								{#if view.readiness.email_ready}
									Ready to send.
								{:else}
									Not ready yet. <a href={resolve('/(app)/settings/communications/email')}
										>Set up email</a
									>
								{/if}
							</p>
						</div>
					</li>
				</ul>
				<p class="review-settings__check-note">
					Review requests need your Google link and at least one ready channel.
				</p>
			</RailCard>
		{/snippet}

		{#snippet actions()}
			<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
			<Button
				onclick={() => void save().finally(() => layout?.revealError())}
				disabled={!dirty || saving || !urlValid}
				loading={saving}>Save</Button
			>
		{/snippet}
	</RecordFormLayout>
{/if}

<style lang="scss">
	.review-settings {
		&__intro {
			margin: 0;
			color: var(--color-text--secondary);
		}

		&__conflict {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);

			p {
				margin: 0;
			}
		}

		&__link {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
		}

		&__link-actions {
			display: flex;
		}

		&__button-icon {
			display: inline-grid;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__steps {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0;
			padding-left: var(--space-large);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__checklist {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__check {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);

			p {
				margin: 0;
			}
		}

		&__check-icon {
			display: inline-grid;
			flex: 0 0 auto;
			color: var(--color-disabled);

			&--done {
				color: var(--color-success);
			}

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}

		&__check-title {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__check-detail,
		&__check-note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__check-note {
			margin-top: var(--space-base);
		}
	}
</style>
