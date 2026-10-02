<script lang="ts">
	import { tick } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import {
		fetchMentionableTeammates,
		mentionableTeammatesKey,
		type MentionableTeammate
	} from '$lib/pipeline/api';
	import {
		insertMention,
		matchTeammates,
		mentionQueryAt,
		type PickedMention
	} from '$lib/pipeline/mentions';

	// A Note's text box that can @mention a teammate, the way HubSpot and Pipedrive notes do. Typing "@"
	// after a space opens a short list of teammates who can see the Pipeline; arrow keys move, Enter or Tab
	// picks, Escape closes. Picking writes "@Name" into the text and remembers who it was in `picked`. The
	// caller sends only the people still named in the text (`mentionsStillIn`), so deleting the words drops
	// the mention.
	let {
		id,
		label,
		value = $bindable(''),
		picked = $bindable([]),
		maxlength = 4000,
		rows = 3
	}: {
		id: string;
		label?: string;
		value?: string;
		picked?: PickedMention[];
		maxlength?: number;
		rows?: number;
	} = $props();

	// Only fetched once someone actually types "@", so a note written without a mention costs nothing.
	let wanted = $state(false);
	const teamQuery = createQuery(() => ({
		queryKey: mentionableTeammatesKey,
		queryFn: fetchMentionableTeammates,
		staleTime: 300_000,
		enabled: wanted
	}));

	let active = $state<{ start: number; query: string } | null>(null);
	let highlighted = $state(0);

	const matches = $derived(active ? matchTeammates(teamQuery.data ?? [], active.query) : []);
	const open = $derived(active !== null && (matches.length > 0 || teamQuery.isPending));
	const listId = $derived(`${id}-mentions`);

	function textarea() {
		return document.getElementById(id) as HTMLTextAreaElement | null;
	}

	function refresh() {
		const element = textarea();
		if (!element) return;
		const next = mentionQueryAt(element.value, element.selectionStart ?? element.value.length);
		if (next) wanted = true;
		if (next?.start !== active?.start || next?.query !== active?.query) highlighted = 0;
		active = next;
	}

	async function pick(member: MentionableTeammate) {
		if (!active || !member.full_name) return;
		const result = insertMention(value, active, member.full_name);
		value = result.text;
		picked = [...picked, { id: member.id, name: member.full_name }];
		active = null;
		await tick();
		const element = textarea();
		element?.focus();
		element?.setSelectionRange(result.caret, result.caret);
	}

	function onkeydown(event: KeyboardEvent) {
		if (!open || matches.length === 0) {
			if (event.key === 'Escape' && active) active = null;
			return;
		}
		if (event.key === 'ArrowDown') {
			event.preventDefault();
			highlighted = (highlighted + 1) % matches.length;
		} else if (event.key === 'ArrowUp') {
			event.preventDefault();
			highlighted = (highlighted - 1 + matches.length) % matches.length;
		} else if (event.key === 'Enter' || event.key === 'Tab') {
			event.preventDefault();
			void pick(matches[highlighted]);
		} else if (event.key === 'Escape') {
			// Closes the list only, not whatever dialog or drawer the box sits in.
			event.preventDefault();
			event.stopPropagation();
			active = null;
		}
	}
</script>

<div class="mention-textarea">
	<Textarea
		{id}
		{label}
		bind:value
		{maxlength}
		{rows}
		role="combobox"
		aria-autocomplete="list"
		aria-expanded={open}
		aria-controls={open ? listId : undefined}
		aria-activedescendant={open && matches[highlighted]
			? `${listId}-${matches[highlighted].id}`
			: undefined}
		oninput={refresh}
		onclick={refresh}
		onkeyup={(event: KeyboardEvent) => {
			if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') refresh();
		}}
		{onkeydown}
		onblur={() => (active = null)}
	/>

	{#if open}
		<ul class="mention-textarea__list" id={listId} role="listbox" aria-label="Mention a teammate">
			{#if teamQuery.isPending}
				<li class="mention-textarea__empty">Loading your team…</li>
			{:else}
				{#each matches as member, index (member.id)}
					<li
						id={`${listId}-${member.id}`}
						class="mention-textarea__option"
						class:mention-textarea__option--active={index === highlighted}
						role="option"
						aria-selected={index === highlighted}
						onmousedown={(event) => {
							// Keeps focus in the text box, so blur does not close the list before the pick lands.
							event.preventDefault();
							void pick(member);
						}}
						onmouseenter={() => (highlighted = index)}
					>
						<Avatar id={member.id} name={member.full_name} src={member.avatar_url} size="small" />
						<span>{member.full_name}</span>
					</li>
				{/each}
			{/if}
		</ul>
	{/if}
</div>

<style lang="scss">
	.mention-textarea {
		position: relative;

		&__list {
			position: absolute;
			z-index: 20;
			top: calc(100% - var(--space-base));
			left: 0;
			width: min(280px, 100%);
			max-height: 240px;
			margin: 0;
			padding: var(--space-smaller);
			overflow-y: auto;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			box-shadow: var(--shadow-base);
			list-style: none;
		}

		&__option {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-smaller) var(--space-small);
			border-radius: var(--radius-small);
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			cursor: pointer;

			&--active {
				background: var(--color-surface--hover);
			}
		}

		&__empty {
			padding: var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
