<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import type { SetupOwnerChoice } from '$lib/jafar/deals';

	// Who is responsible for something in the Jafar Panel -- a Lead's owner (D3a), a client's setup (B5): Jafar
	// unless someone else is chosen. Shows the person, and for anyone allowed a Change menu of Jafar and the
	// teammates who qualify. The teammates load when Change is hovered or opened, not with the page.
	let {
		current,
		choicesUrl,
		choicesKey,
		canChange,
		saving = false,
		changeLabel,
		noTeammatesLabel,
		onChoose
	}: {
		/** Null is Jafar. */
		current: SetupOwnerChoice | null;
		/** GET returns `{ choices }`: the teammates who may be chosen. */
		choicesUrl: string;
		choicesKey: readonly unknown[];
		canChange: boolean;
		saving?: boolean;
		/** The menu button's accessible name, e.g. "Change who owns this Lead". */
		changeLabel: string;
		/** Shown in the menu when no teammate qualifies. */
		noTeammatesLabel: string;
		onChoose: (memberId: string | null, name: string) => void;
	} = $props();

	let wantChoices = $state(false);
	let menuOpen = $state(false);

	const choices = createQuery(() => ({
		queryKey: choicesKey,
		queryFn: async (): Promise<SetupOwnerChoice[]> => {
			const response = await fetch(choicesUrl);
			const result = await response.json();
			if (!response.ok) throw new Error(result.error ?? 'Your team could not be loaded.');
			return result.choices as SetupOwnerChoice[];
		},
		staleTime: 60_000,
		enabled: canChange && (wantChoices || menuOpen)
	}));

	function choose(memberId: string | null, name: string) {
		if (saving || (current?.id ?? null) === memberId) return;
		onChoose(memberId, name);
	}

	const items = $derived.by(() => {
		const now = current?.id ?? null;
		const jafar = {
			key: 'jafar',
			label: now === null ? 'Jafar (now)' : 'Jafar',
			disabled: now === null,
			onSelect: () => choose(null, 'Jafar')
		};
		const note = (key: string, label: string) => ({
			key,
			label,
			disabled: true,
			onSelect: () => {}
		});
		if (choices.isPending) return [jafar, note('loading', 'Loading teammates…')];
		if (choices.isError) return [jafar, note('error', 'Teammates could not be loaded')];
		const teammates = (choices.data ?? []).map((choice) => ({
			key: choice.id,
			label: choice.id === now ? `${choice.name} (now)` : choice.name,
			disabled: choice.id === now,
			onSelect: () => choose(choice.id, choice.name)
		}));
		return teammates.length ? [jafar, ...teammates] : [jafar, note('none', noTeammatesLabel)];
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="owner-picker">
	<Avatar
		id={current?.id ?? 'jafar'}
		name={current?.name ?? 'Jafar'}
		src={current?.avatar_url}
		size="small"
	/>
	<span class="owner-picker__name">{current?.name ?? 'Jafar'}</span>
	{#if canChange}
		<span
			class="owner-picker__change"
			role="presentation"
			onpointerenter={() => (wantChoices = true)}
			onfocusin={() => (wantChoices = true)}
		>
			<DropdownMenu
				{items}
				triggerLabel={changeLabel}
				triggerClass="owner-picker__trigger"
				disabled={saving}
				bind:open={menuOpen}
			>
				{#snippet trigger()}
					Change<span class="owner-picker__chevron" aria-hidden="true">{@html chevronDownIcon}</span>
				{/snippet}
			</DropdownMenu>
		</span>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.owner-picker {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);

		&__name {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__change {
			margin-left: auto;

			:global(.owner-picker__trigger) {
				display: inline-flex;
				align-items: center;
				padding: var(--space-smaller) var(--space-small);
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-base);
				background: var(--color-surface);
				color: var(--color-heading);
				font: inherit;
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
				cursor: pointer;
				transition: background-color var(--timing-quick);

				&:hover:not(:disabled) {
					background: var(--color-surface--hover);
				}

				&:focus-visible {
					outline: none;
					box-shadow: var(--shadow-focus);
				}

				&:disabled {
					cursor: progress;
					opacity: 0.6;
				}
			}
		}

		&__chevron {
			display: inline-flex;
			margin-left: var(--space-smaller);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
	}
</style>
