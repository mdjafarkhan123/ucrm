<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		disablePipelineStage,
		fetchPipelineStageCardCount,
		pipelineStageCardCountKey,
		type SettingsWriteError
	} from '$lib/settings/api';
	import type { CustomStage } from '$lib/pipeline/stages';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// What the Select holds for "each card goes back to the built-in stage its real work has it in".
	const BUILT_IN = 'built_in';

	// Taking a saved custom stage off the board. A stage holding cards is never removed without the person
	// saying where those cards go; the stage's name stays in every card's history either way.
	let {
		stage,
		destinations,
		revision,
		onClose,
		onRemoved
	}: {
		// The stage being removed, or null while the dialog is shut.
		stage: CustomStage | null;
		// The other saved custom stages of the same section — the only stages a card can be moved into by hand.
		destinations: CustomStage[];
		revision: number;
		onClose: () => void;
		onRemoved: (result: {
			stage: CustomStage;
			revision: number;
			movedCount: number;
			destinationName: string | null;
		}) => void;
	} = $props();

	const queryClient = useQueryClient();

	// The page warms this when the remove button is hovered or focused, so it is usually already here.
	const countQuery = createQuery(() => ({
		queryKey: pipelineStageCardCountKey(stage?.id ?? ''),
		queryFn: () => fetchPipelineStageCardCount(stage?.id ?? ''),
		enabled: stage !== null,
		// Cards move all day; a count from an earlier look at this dialog is not one to act on.
		staleTime: 0
	}));

	let destination = $state('');
	let removing = $state(false);
	let errorMessage = $state('');

	// A fresh question each time the dialog opens on a stage.
	function reset() {
		destination = '';
		errorMessage = '';
	}

	function close() {
		reset();
		onClose();
	}

	const cardCount = $derived(countQuery.data?.card_count ?? 0);
	const cards = $derived(cardCount === 1 ? '1 card' : `${cardCount} cards`);
	const options = $derived([
		{ value: BUILT_IN, label: 'Back to their built-in stage' },
		...destinations.map((other) => ({ value: other.id, label: other.name }))
	]);

	async function remove() {
		if (!stage || removing) return;
		const target = stage;
		errorMessage = '';
		removing = true;
		const result = await disablePipelineStage(target.id, {
			expected_revision: revision,
			destination: cardCount > 0 ? destination : null
		}).catch((error: SettingsWriteError) => {
			errorMessage = error.message;
			return null;
		});
		removing = false;
		if (!result) return;

		if ('needsDestination' in result) {
			// A card was moved in after this dialog counted. Show the real number and ask.
			queryClient.setQueryData(pipelineStageCardCountKey(target.id), {
				card_count: result.card_count
			});
			errorMessage = 'A card was just moved into this stage. Choose where its cards go.';
			return;
		}
		if ('conflict' in result) {
			errorMessage = `${result.editor_name ?? 'Someone else'} just changed the pipeline settings. Refresh the page, then try again.`;
			return;
		}

		queryClient.removeQueries({ queryKey: pipelineStageCardCountKey(target.id) });
		const movedTo = destinations.find((other) => other.id === destination)?.name ?? null;
		reset();
		onRemoved({
			stage: target,
			revision: result.pipeline_revision,
			movedCount: result.moved_count,
			destinationName: result.moved_count === 0 ? null : movedTo
		});
	}
</script>

<ConfirmDialog
	open={stage !== null}
	title={stage ? `Remove “${stage.name}”?` : 'Remove stage?'}
	icon={trashIcon}
	tone="critical"
	destructive
	confirmLabel="Remove stage"
	loading={removing}
	confirmDisabled={countQuery.isPending ||
		countQuery.isError ||
		(cardCount > 0 && destination === '')}
	onConfirm={remove}
	onClose={close}
>
	{#if stage}
		<div class="stage-remove">
			{#if countQuery.isPending}
				<LoadingSkeleton variant="text" label="Checking this stage for cards" />
				<LoadingSkeleton variant="text" label="Checking this stage for cards" />
			{:else if countQuery.isError}
				<p role="alert" class="stage-remove__error">
					This stage could not be checked for cards.
					<button type="button" class="stage-remove__retry" onclick={() => countQuery.refetch()}>
						Try again
					</button>
				</p>
			{:else}
				{#if cardCount > 0}
					<p>
						<strong>{cards}</strong>
						{cardCount === 1 ? 'is' : 'are'} in this stage. Choose where {cardCount === 1
							? 'it goes'
							: 'they go'}, and {cardCount === 1 ? 'it moves' : 'they all move'} when the stage is removed.
					</p>
					<Select
						id="pipeline-stage-destination"
						label={`Move ${cards} to`}
						placeholder="Choose a stage"
						required
						disabled={removing}
						{options}
						bind:value={destination}
					/>
					{#if destination === BUILT_IN}
						<p>
							Each card goes back to the built-in column that matches where its
							{stage.section === 'quote' ? 'quote' : 'request'} really stands.
						</p>
					{/if}
				{:else}
					<p>No cards are in this stage, so nothing needs to move.</p>
				{/if}
				<p>
					The column comes off the board for everyone. Cards that passed through it keep “{stage.name}”
					in their history.
				</p>
			{/if}

			{#if errorMessage}
				<p role="alert" class="stage-remove__error">{errorMessage}</p>
			{/if}
		</div>
	{/if}
</ConfirmDialog>

<style lang="scss">
	.stage-remove {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		p {
			margin: 0;
		}

		strong {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__error {
			color: var(--color-critical);
		}

		&__retry {
			padding: 0;
			border: 0;
			color: var(--color-interactive);
			background: none;
			font: inherit;
			font-weight: 600;
			cursor: pointer;

			&:hover,
			&:focus-visible {
				text-decoration: underline;
			}
			&:focus-visible {
				outline: none;
				border-radius: var(--radius-small);
				box-shadow: var(--shadow-focus);
			}
		}
	}
</style>
