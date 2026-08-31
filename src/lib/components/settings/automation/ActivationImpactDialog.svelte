<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		automationActivationPreviewKey,
		fetchActivationPreview,
		activateRecipe,
		StaleDraftError,
		type ActivateResult
	} from '$lib/settings/automation-lifecycle';
	import type { AutomationLimit } from '$lib/settings/automation';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// The activation impact review (docs/automation-behavior-contract.md § Activation impact review). Opened
	// only from a saved draft, it reads a fresh impact preview each time it opens (revalidate on open) and
	// re-runs the same checks on the server when the user confirms (revalidate on confirm — the activate
	// route reads and re-validates the recipe's OWN draft, so nothing here is trusted as the definition). It
	// shows future-only behavior, the effective limits, and active-recipe headroom, and blocks Activate on any
	// blocking finding or over-limit.
	let {
		open,
		recipeId,
		onClose,
		onActivated
	}: {
		open: boolean;
		recipeId: string;
		onClose: () => void;
		onActivated: (result: ActivateResult) => Promise<void>;
	} = $props();

	// Fresh each open: enabled only while open and never cached stale, so re-opening always re-reads the
	// current draft, revision, and headroom rather than an earlier snapshot.
	const previewQuery = createQuery(() => ({
		queryKey: automationActivationPreviewKey(recipeId),
		queryFn: () => fetchActivationPreview(recipeId),
		enabled: open,
		staleTime: 0,
		gcTime: 0
	}));

	let activating = $state(false);
	let submitError = $state('');

	const preview = $derived(previewQuery.data);

	function limitText(limit: AutomationLimit): string {
		if (limit.is_unlimited || limit.state === 'unlimited') return 'No limit';
		if (limit.state === 'numeric' && limit.value !== null) return String(limit.value);
		return 'Not included';
	}

	async function confirm() {
		if (activating || !preview || !preview.valid) return;
		activating = true;
		submitError = '';
		try {
			const result = await activateRecipe(recipeId, preview.draft_revision);
			// Awaited so the dialog's own loading state holds until the parent has refreshed its cached data —
			// otherwise this call returns as soon as it starts and the dialog closes before the detail page
			// underneath has caught up.
			await onActivated(result);
		} catch (error) {
			if (error instanceof StaleDraftError) {
				// Someone changed this automation between opening and confirming. Re-read so the dialog shows the
				// current state instead of overwriting their work; the user can then confirm against the fresh
				// revision.
				submitError =
					'This automation just changed. We’ve refreshed the impact below — review it and try again.';
				await previewQuery.refetch();
			} else {
				submitError =
					error instanceof Error ? error.message : 'We could not activate that automation.';
			}
		} finally {
			activating = false;
		}
	}
</script>

{#if open}
	<Dialog {open} title="Turn this automation on" {onClose}>
		{#if previewQuery.isPending}
			<LoadingSkeleton variant="card" rows={3} />
		{:else if previewQuery.isError}
			<ErrorState
				description="We couldn’t check this automation. Close this and try again."
				retry={() => previewQuery.refetch()}
			/>
		{:else if preview}
			<div class="activation">
				<p class="activation__lead">
					Turning this on only affects customers <strong>from now on</strong>. Nobody already in a
					previous run is changed.
				</p>

				{#if preview.blocking.length > 0}
					<div class="activation__block" role="alert">
						<span class="activation__block-icon" aria-hidden="true">
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							{@html alertTriangleIcon}
						</span>
						<div>
							<p class="activation__block-title">Fix these first</p>
							<ul class="activation__block-list">
								{#each preview.blocking as reason (reason)}
									<li>{reason}</li>
								{/each}
							</ul>
						</div>
					</div>
				{/if}

				{#if preview.active_recipes.over_limit}
					<div class="activation__block" role="alert">
						<span class="activation__block-icon" aria-hidden="true">
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							{@html alertTriangleIcon}
						</span>
						<div>
							<p class="activation__block-title">You’re at your active-automation limit</p>
							<p class="activation__block-text">
								{preview.active_recipes.count} of {preview.active_recipes.limit} automations are already
								on. Pause or turn off another one, or talk to us about a higher plan.
							</p>
						</div>
					</div>
				{/if}

				{#if preview.summary}
					<dl class="activation__facts">
						<div class="activation__fact">
							<dt>When it runs</dt>
							<dd>{preview.summary.trigger_label}</dd>
						</div>
						<div class="activation__fact">
							<dt>Most emails one customer could get</dt>
							<dd>{preview.summary.max_messages}</dd>
						</div>
						<div class="activation__fact">
							<dt>Steps</dt>
							<dd>{preview.summary.step_count}</dd>
						</div>
						<div class="activation__fact">
							<dt>Stop conditions</dt>
							<dd>{preview.summary.stop_count}</dd>
						</div>
					</dl>

					<div class="activation__limits">
						<p class="activation__limits-title">Your plan’s safety limits</p>
						<dl class="activation__facts activation__facts--tight">
							<div class="activation__fact">
								<dt>Max emails per customer</dt>
								<dd>
									{limitText(
										preview.effective_limits.automation_max_customer_messages_per_enrollment
									)}
								</dd>
							</div>
							<div class="activation__fact">
								<dt>Min minutes between emails</dt>
								<dd>
									{limitText(
										preview.effective_limits.automation_min_customer_message_spacing_minutes
									)}
								</dd>
							</div>
							<div class="activation__fact">
								<dt>Longest wait (days)</dt>
								<dd>{limitText(preview.effective_limits.automation_max_delay_days)}</dd>
							</div>
							<div class="activation__fact">
								<dt>Longest run (days)</dt>
								<dd>
									{limitText(preview.effective_limits.automation_max_enrollment_duration_days)}
								</dd>
							</div>
						</dl>
					</div>
				{/if}

				{#if submitError}
					<p class="activation__error" role="alert">{submitError}</p>
				{/if}
			</div>

			<div class="activation__actions">
				<Button variant="secondary" variation="subtle" onclick={onClose} disabled={activating}>
					Cancel
				</Button>
				<Button variation="work" onclick={confirm} disabled={!preview.valid} loading={activating}>
					Turn on
				</Button>
			</div>
		{/if}
	</Dialog>
{/if}

<style lang="scss">
	.activation {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__lead {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-large);

			:global(strong) {
				color: var(--color-heading);
			}
		}

		&__block {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			padding: var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}

		&__block-icon {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			margin-top: 2px;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__block-title {
			margin: 0 0 var(--space-smallest);
			font-weight: 600;
		}

		&__block-text {
			margin: 0;
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-large);
		}

		&__block-list {
			margin: 0;
			padding-left: var(--space-base);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-large);
		}

		&__facts {
			display: grid;
			grid-template-columns: repeat(2, 1fr);
			gap: var(--space-base);
			margin: 0;

			&--tight {
				gap: var(--space-small);
			}
		}

		&__fact {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			dd {
				margin: 0;
				color: var(--color-heading);
				font-weight: 600;
				font-variant-numeric: tabular-nums;
			}
		}

		&__limits {
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__limits-title {
			margin: 0 0 var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-transform: uppercase;
			letter-spacing: 0.02em;
		}

		&__error {
			margin: 0;
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}
	}

	.activation__actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-large);
	}
</style>
