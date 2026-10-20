<script lang="ts">
	import { splitMentions } from '$lib/pipeline/mentions';

	// A Note's text, with each "@Name" of a teammate it mentions picked out. The text itself stays plain, so
	// this only ever adds emphasis -- it never turns words into anything clickable.
	let {
		body,
		mentionNames = []
	}: {
		body: string;
		/** Names of the teammates the Note mentions. */
		mentionNames?: string[];
	} = $props();

	const parts = $derived(splitMentions(body, mentionNames));
</script>

<p class="note-body">
	{#each parts as part, index (index)}{#if part.mention}<span class="note-body__mention"
				>{part.text}</span
			>{:else}{part.text}{/if}{/each}
</p>

<style lang="scss">
	.note-body {
		margin: 6px 0 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-large);
		white-space: pre-wrap;
		overflow-wrap: anywhere;

		&__mention {
			padding: 1px var(--space-smaller);
			border-radius: var(--radius-small);
			color: var(--color-conversation--onSurface);
			background: var(--color-conversation--surface);
			font-weight: 600;
		}
	}
</style>
