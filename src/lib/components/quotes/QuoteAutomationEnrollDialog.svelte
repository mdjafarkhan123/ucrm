<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		previewEnrollment,
		manualEnroll,
		type EnrollableRecipe,
		type EnrollmentPreview
	} from '$lib/quotes/automation';
	import type { QuoteWriteError } from '$lib/quotes/api';

	// The manual-enroll flow, following the contract: pick an active recipe, see a plain preview (version,
	// first send time, message count, overlap), then confirm. Confirm mints a fresh idempotency key server-side
	// so a double-click replays the first enrollment rather than stacking a second.
	let {
		quoteId,
		recipes,
		onClose,
		onEnrolled
	}: {
		quoteId: string;
		recipes: EnrollableRecipe[];
		onClose: () => void;
		onEnrolled: () => void;
	} = $props();

	let selectedRecipeId = $state('');
	let preview = $state<EnrollmentPreview | null>(null);
	let previewing = $state(false);
	let previewError = $state('');
	let enrolling = $state(false);
	let enrollError = $state('');

	const recipeOptions = $derived(
		recipes.map((recipe) => ({ value: recipe.id, label: recipe.name }))
	);

	const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		hour: 'numeric',
		minute: '2-digit'
	});

	// A first due time within the next minute reads as "right away"; anything later shows the actual time.
	const firstDueLabel = $derived.by(() => {
		if (!preview?.first_due_at) return null;
		const due = new Date(preview.first_due_at);
		if (due.getTime() - Date.now() <= 60_000) return 'Right away';
		return dateTimeFormat.format(due);
	});

	const ineligibleReason = $derived.by(() => {
		if (!preview || preview.eligible) return null;
		switch (preview.reason) {
			case 'already_enrolled':
				return 'This quote is already in this automation.';
			case 'recipe_not_active':
				return 'This automation is no longer active.';
			case 'recipe_not_found':
				return 'This automation could not be found.';
			case 'unsupported_subject':
				return 'This automation cannot enrol a quote.';
			default:
				return 'This quote cannot be enrolled right now.';
		}
	});

	async function loadPreview(recipeId: string) {
		selectedRecipeId = recipeId;
		preview = null;
		enrollError = '';
		if (!recipeId) return;
		previewing = true;
		previewError = '';
		try {
			preview = await previewEnrollment(quoteId, recipeId);
		} catch (error) {
			previewError = (error as QuoteWriteError).message || 'That preview could not be loaded.';
		} finally {
			previewing = false;
		}
	}

	async function confirm() {
		if (!selectedRecipeId || !preview?.eligible || enrolling) return;
		enrolling = true;
		enrollError = '';
		try {
			await manualEnroll(quoteId, selectedRecipeId);
			onEnrolled();
		} catch (error) {
			enrollError = (error as QuoteWriteError).message || 'We could not enroll that quote.';
		} finally {
			enrolling = false;
		}
	}
</script>

<Dialog open title="Enrol this quote" size="small" {onClose}>
	<div class="enrol">
		{#if recipes.length === 0}
			<p class="enrol__empty">
				You have no active automations yet. Turn one on in Settings → Automation first.
			</p>
		{:else}
			<Select
				id="enrol-recipe"
				label="Automation"
				placeholder="Choose an automation"
				options={recipeOptions}
				value={selectedRecipeId}
				onchange={loadPreview}
			/>

			{#if previewing}
				<LoadingSkeleton variant="text" rows={3} label="Loading preview" />
			{:else if previewError}
				<p class="enrol__error" role="alert">{previewError}</p>
			{:else if preview}
				<dl class="enrol__facts">
					<div class="enrol__fact">
						<dt>Version</dt>
						<dd>v{preview.version_number}</dd>
					</div>
					{#if firstDueLabel}
						<div class="enrol__fact">
							<dt>First step</dt>
							<dd>{firstDueLabel}</dd>
						</div>
					{/if}
					<div class="enrol__fact">
						<dt>Customer messages</dt>
						<dd>Up to {preview.expected_message_count ?? 0}</dd>
					</div>
				</dl>

				{#if ineligibleReason}
					<p class="enrol__note enrol__note--warning" role="status">{ineligibleReason}</p>
				{:else if (preview.overlap_other_recipes ?? 0) > 0}
					<p class="enrol__note" role="status">
						This quote is also in {preview.overlap_other_recipes} other automation{(preview.overlap_other_recipes ??
							0) > 1
							? 's'
							: ''}.
					</p>
				{/if}
			{/if}

			{#if enrollError}
				<p class="enrol__error" role="alert">{enrollError}</p>
			{/if}
		{/if}
	</div>

	<div class="enrol__actions">
		<Button variant="tertiary" onclick={onClose}>Cancel</Button>
		<Button
			onclick={confirm}
			loading={enrolling}
			disabled={!preview?.eligible || previewing || enrolling}
		>
			Enrol quote
		</Button>
	</div>
</Dialog>

<style lang="scss">
	.enrol {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.enrol__empty {
		margin: 0;
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
	}

	.enrol__facts {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
	}

	.enrol__fact {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-base);

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		dd {
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}
	}

	.enrol__note {
		margin: 0;
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-surface--hover);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.enrol__note--warning {
		background: var(--color-critical--surface);
		color: var(--color-destructive);
	}

	.enrol__error {
		margin: 0;
		color: var(--color-destructive);
		font-size: var(--typography--fontSize-small);
	}

	.enrol__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-large);
	}
</style>
