<script lang="ts">
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import type { SupportPeople } from '$lib/support/api';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	// Who is in a support conversation, and — for the person who started it, an owner or admin, or Uplift —
	// adding and removing teammates (D3, Zendesk's CC list). Each change posts a grey line in the
	// conversation, written by the database, so nobody is added or removed silently.
	let {
		people,
		loading = false,
		failed = false,
		onRetry,
		onChange,
		viewerUserId = null
	}: {
		people: SupportPeople | undefined;
		loading?: boolean;
		failed?: boolean;
		onRetry?: () => void;
		/** Resolves once saved; rejects with the reason to show. */
		onChange: (userId: string, adding: boolean) => Promise<void>;
		/** Marks the viewer as "you" in the list. */
		viewerUserId?: string | null;
	} = $props();

	const uid = $props.id();
	let choice = $state('');
	let busy = $state<string | null>(null);
	let error = $state('');

	const options = $derived(
		(people?.addable ?? []).map((person) => ({ value: person.user_id, label: person.name }))
	);

	async function change(userId: string, adding: boolean) {
		busy = userId;
		error = '';
		try {
			await onChange(userId, adding);
			if (adding) choice = '';
		} catch (failure) {
			error = failure instanceof Error ? failure.message : 'That change could not be saved.';
		} finally {
			busy = null;
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="support-people" aria-labelledby={`${uid}-title`}>
	<h3 id={`${uid}-title`} class="support-people__title">People in this conversation</h3>
	<p class="support-people__hint">
		Everyone here can read the conversation and write in it. Owners and admins can also see it.
	</p>

	{#if loading}
		<LoadingSkeleton variant="text" rows={3} label="Loading people" />
	{:else if failed || !people}
		<ErrorState
			description="The people in this conversation could not be loaded."
			retry={onRetry}
		/>
	{:else}
		<ul class="support-people__list">
			{#each people.people as person (person.user_id)}
				<li class="support-people__person">
					<Avatar id={person.user_id} name={person.name} size="small" />
					<span class="support-people__name">
						{person.name}{person.user_id === viewerUserId ? ' (you)' : ''}
						<small>
							{person.started ? 'Started this conversation' : 'Added'}{person.active
								? ''
								: ' · No longer on the team'}
						</small>
					</span>
					{#if people.can_manage && !person.started}
						<button
							class="support-people__remove"
							type="button"
							disabled={busy !== null}
							aria-label={`Remove ${person.name}`}
							title={`Remove ${person.name}`}
							onclick={() => void change(person.user_id, false)}
						>
							<span aria-hidden="true">{@html closeIcon}</span>
						</button>
					{/if}
				</li>
			{/each}
		</ul>

		{#if people.can_manage}
			{#if options.length > 0}
				<div class="support-people__add">
					<Select
						id={`${uid}-add`}
						ariaLabel="Teammate to add"
						placeholder="Choose a teammate"
						{options}
						bind:value={choice}
						disabled={busy !== null}
					/>
					<Button
						size="small"
						disabled={!choice || busy !== null}
						loading={busy === choice && choice !== ''}
						onclick={() => void change(choice, true)}>Add</Button
					>
				</div>
			{:else}
				<p class="support-people__hint">Everyone on the team is already here.</p>
			{/if}
		{/if}

		{#if error}
			<p class="support-people__error" role="alert">{error}</p>
		{/if}
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.support-people {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-base);
		overflow-y: auto;

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__person {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-height: 44px;
		}

		&__name {
			display: flex;
			flex: 1;
			flex-direction: column;
			min-width: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);

			small {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__remove {
			display: grid;
			flex: none;
			place-items: center;
			width: 32px;
			height: 32px;
			padding: 0;
			border: 0;
			border-radius: var(--radius-base);
			color: var(--color-icon);
			background: transparent;
			cursor: pointer;

			span {
				display: inline-flex;
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}

			&:hover:not(:disabled) {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				cursor: default;
				opacity: 0.5;
			}
		}

		&__add {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			:global(> :first-child) {
				flex: 1;
				min-width: 0;
			}
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
