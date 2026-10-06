<script lang="ts">
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import {
		HANDOVER_GUIDES_MAX,
		HANDOVER_GUIDE_TITLE_MAX,
		HANDOVER_SUMMARY_MAX,
		LINK_MAX,
		type HandoverGuide,
		type SetupHandover
	} from '$lib/setup/training';
	import { formatDateTime } from './format';

	// Client onboarding E6 (plan §6): Jafar's access and ownership summary and the guide links on the client's
	// handover pack, saved whole. Delivery needs the summary and at least one guide. The parent remounts this when
	// a save lands, so the draft always starts from what is stored.
	let {
		handover,
		saving,
		onSave
	}: {
		handover: SetupHandover | null;
		saving: boolean;
		onSave: (input: { access_summary: string | null; guides: HandoverGuide[] }) => void;
	} = $props();

	// The draft deliberately starts from the stored handover once; a save remounts the editor.
	// svelte-ignore state_referenced_locally
	let summary = $state(handover?.access_summary ?? '');
	// svelte-ignore state_referenced_locally
	let guides = $state<HandoverGuide[]>(handover?.guides.map((guide) => ({ ...guide })) ?? []);
	let problem = $state('');

	const changed = $derived(
		summary.trim() !== (handover?.access_summary ?? '') ||
			JSON.stringify(
				guides.map((guide) => ({ title: guide.title.trim(), url: guide.url.trim() }))
			) !== JSON.stringify(handover?.guides ?? [])
	);

	function save() {
		problem = '';
		const cleaned = guides.map((guide) => ({ title: guide.title.trim(), url: guide.url.trim() }));
		if (cleaned.some((guide) => !guide.title || !guide.url)) {
			problem = 'Give every guide a title and a link, or remove the empty one.';
			return;
		}
		if (cleaned.some((guide) => !/^https:\/\/\S+$/.test(guide.url))) {
			problem = 'Guide links must be full addresses starting with https://.';
			return;
		}
		onSave({ access_summary: summary.trim() || null, guides: cleaned });
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="handover-editor">
	<Textarea
		id="handover-access-summary"
		label="Access and ownership summary"
		placeholder="Who owns each account and login: the domain at Namecheap is in the owner’s name; Google Business Profile — owner is primary owner, Uplift is a manager…"
		rows={6}
		maxlength={HANDOVER_SUMMARY_MAX}
		bind:value={summary}
	/>

	<div class="handover-editor__guides">
		<p class="handover-editor__label">Guides for their team</p>
		{#if guides.length === 0}
			<p class="handover-editor__muted">No guides yet. Delivery needs at least one.</p>
		{/if}
		{#each guides as guide, index (index)}
			<div class="handover-editor__guide">
				<Input
					id={`handover-guide-title-${index}`}
					label="Title"
					maxlength={HANDOVER_GUIDE_TITLE_MAX}
					bind:value={guide.title}
				/>
				<Input
					id={`handover-guide-url-${index}`}
					label="Link"
					type="url"
					placeholder="https://"
					maxlength={LINK_MAX}
					bind:value={guide.url}
				/>
				<button
					type="button"
					class="handover-editor__icon-button"
					aria-label={`Remove guide ${index + 1}${guide.title.trim() ? `, ${guide.title.trim()}` : ''}`}
					onclick={() => guides.splice(index, 1)}
					><span aria-hidden="true">{@html trashIcon}</span></button
				>
			</div>
		{/each}
		{#if guides.length < HANDOVER_GUIDES_MAX}
			<button
				type="button"
				class="handover-editor__add"
				onclick={() => guides.push({ title: '', url: '' })}
				><span aria-hidden="true">{@html plusIcon}</span>Add a guide</button
			>
		{/if}
	</div>

	{#if problem}<Banner type="error">{problem}</Banner>{/if}

	<div class="handover-editor__footer">
		<Button variant="secondary" disabled={!changed || saving} loading={saving} onclick={save}
			>Save handover</Button
		>
		{#if handover?.updated_at}
			<span class="handover-editor__muted">Last saved {formatDateTime(handover.updated_at)}</span>
		{/if}
	</div>
</div>

<style lang="scss">
	.handover-editor {
		display: grid;
		gap: var(--space-base);

		&__guides {
			display: grid;
			gap: var(--space-small);
		}

		&__label {
			margin: 0;
			font-weight: 600;
		}

		&__guide {
			display: grid;
			grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr) auto;
			gap: var(--space-small);
			align-items: start;

			@media (max-width: 640px) {
				grid-template-columns: minmax(0, 1fr) auto;

				:global(> :nth-child(2)) {
					grid-column: 1;
					grid-row: 2;
				}
			}
		}

		&__icon-button,
		&__add {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			min-height: 4.4rem;
			padding: 0 var(--space-small);
			border: 0;
			border-radius: var(--radius-base);
			background: none;
			color: var(--color-text--secondary);
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			:global(svg) {
				width: 1.6rem;
				height: 1.6rem;
			}

			&:hover {
				background: var(--color-surface--hover);
				color: var(--color-heading);
			}
		}

		&__icon-button {
			justify-content: center;
			min-width: 4.4rem;
		}

		&__add {
			justify-self: start;
			color: var(--color-interactive);
		}

		&__footer {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
