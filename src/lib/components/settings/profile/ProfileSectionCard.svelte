<script lang="ts">
	import type { Snippet } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import ProfileSectionFooter from './ProfileSectionFooter.svelte';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import ProfileConflictNotice from './ProfileConflictNotice.svelte';

	// One section of the Business profile page (Pencil: "Batch 64 · Business profile", Profile at a glance).
	// Closed it reads as a card of facts with its own Edit; open it shows its fields and its own Save. The
	// page lets one section be open at a time.
	let {
		title,
		hint,
		icon,
		tone,
		open,
		canEdit,
		saving = false,
		saveLabel,
		saveDisabled = false,
		footerHint,
		conflict = null,
		onEdit,
		onCancel,
		onSave,
		onSeeTheirs,
		facts,
		form,
		note,
		side,
		class: className = ''
	}: {
		title: string;
		hint: string;
		icon: string;
		tone: string;
		open: boolean;
		canEdit: boolean;
		saving?: boolean;
		saveLabel: string;
		saveDisabled?: boolean;
		footerHint: string;
		/** Somebody else saved this part of the profile first: who, and what they changed (once looked at). */
		conflict?: { who: string; when: string; theirs: string[] | null; checking: boolean } | null;
		onEdit: () => void;
		onCancel: () => void;
		onSave: () => void;
		onSeeTheirs: () => void;
		/** The closed card's rows. */
		facts: Snippet;
		/** The open card's fields. */
		form: Snippet;
		/** A reason under the closed rows, in a quiet band. */
		note?: Snippet;
		/** A panel beside the rows or fields, such as the map. */
		side?: Snippet;
		class?: string;
	} = $props();

	const headingId = $props.id();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section
	class={[
		'profile-section',
		open && 'profile-section--open',
		conflict && 'profile-section--conflict',
		className
	]}
	aria-labelledby={headingId}
>
	<CardHeader {title} {hint} {icon} {tone} level={2} id={headingId}>
		{#snippet actions()}
			{#if !open && canEdit}
				<Button variant="secondary" size="small" onclick={onEdit} label={`Edit ${title}`}>
					<span aria-hidden="true">{@html pencilIcon}</span>Edit
				</Button>
			{/if}
		{/snippet}
	</CardHeader>

	<div class={['profile-section__split', side && 'profile-section__split--side']}>
		{#if side}<div class="profile-section__side">{@render side()}</div>{/if}
		{#if open}
			<div class="profile-section__body">
				{#if conflict}<ProfileConflictNotice {...conflict} />{/if}
				{@render form()}
			</div>
		{:else}
			<div class="profile-section__facts">{@render facts()}</div>
		{/if}
	</div>

	{#if open}
		<ProfileSectionFooter
			hint={conflict ? 'Your changes are kept' : footerHint}
			{saving}
			{saveLabel}
			{saveDisabled}
			{onCancel}
			{onSave}
			{onSeeTheirs}
			seeTheirsLoading={conflict?.checking ?? false}
			showSeeTheirs={Boolean(conflict && !conflict.theirs)}
		/>
	{:else if note}
		<div class="profile-section__note">{@render note()}</div>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.profile-section {
		display: flex;
		flex-direction: column;
		min-width: 0;
		overflow: hidden;
		background: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);

		&--open {
			border: 1.5px solid var(--color-interactive);
			box-shadow: var(--shadow-high);
		}
		&--conflict {
			border-color: var(--color-critical);
		}
		&__split {
			display: flex;
			flex: 1;
			min-width: 0;
			border-top: var(--border-base) solid var(--color-border);
		}
		&__side {
			display: flex;
			flex: none;
			width: 520px;
			border-right: var(--border-base) solid var(--color-border);

			:global(.service-map) {
				flex: 1;
			}
		}
		&__facts {
			display: flex;
			flex: 1;
			min-width: 0;
			flex-direction: column;
		}
		&__body {
			display: flex;
			flex: 1;
			min-width: 0;
			flex-direction: column;
			gap: var(--space-base);
			padding: var(--space-medium);
		}
		&__note {
			padding: var(--space-slim) var(--space-medium);
			background: var(--color-surface--background--subtle);
			border-top: var(--border-base) solid var(--color-border);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}
	}
	@media (max-width: 1079px) {
		.profile-section__split--side {
			flex-direction: column;
		}
		.profile-section__side {
			width: auto;
			border-right: 0;
			border-bottom: var(--border-base) solid var(--color-border);
		}
	}
</style>
