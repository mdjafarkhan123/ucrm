<script lang="ts">
	import type { Snippet } from 'svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import type { SetupCheckItem } from '$lib/setup/check';

	// One setup task's answers read back, question beside answer (GOV.UK "Summary list"). The client sees it on
	// Check and send (B13) and Jafar on a client's Setup tab (C2); `audience` picks who the words speak to.
	let {
		items,
		audience,
		changedLabel = 'Changed',
		flagged,
		extra
	}: {
		items: SetupCheckItem[];
		audience: 'client' | 'uplift';
		changedLabel?: string;
		/** Questions Uplift sent back to change (C3), highlighted. */
		flagged?: ReadonlySet<string>;
		/** More under an answer: Jafar's page shows the files a photo or file answer holds. */
		extra?: Snippet<[SetupCheckItem]>;
	} = $props();

	const WORDS = {
		client: {
			need_help: 'You asked for Uplift’s help',
			not_yet: 'You don’t have this yet',
			missing: 'Still needs an answer'
		},
		uplift: {
			need_help: 'Asked for Uplift’s help',
			not_yet: 'Doesn’t have this yet',
			missing: 'Not answered'
		}
	};

	function itemText(item: SetupCheckItem): string {
		const words = WORDS[audience];
		if (item.state === 'need_help') return words.need_help;
		if (item.state === 'not_yet') return words.not_yet;
		return item.required ? words.missing : 'Not answered';
	}
</script>

<dl class="setup-answers">
	{#each items as item (item.key)}
		{@const isFlagged = flagged?.has(item.key) ?? false}
		<div
			class="setup-answers__row"
			class:setup-answers__row--changed={item.changed && !isFlagged}
			class:setup-answers__row--flagged={isFlagged}
		>
			<dt>
				{item.label}
				{#if isFlagged}<Badge status="warning" size="small">Sent back</Badge>{/if}
				{#if item.changed}<Badge status="informative" size="small">{changedLabel}</Badge>{/if}
			</dt>
			<dd>
				{#if item.state === 'answered'}
					{#if item.same_as}
						<span class="setup-answers__muted">Same as “{item.same_as}”</span>
					{/if}
					{#each item.lines as line, index (index)}
						<span>{line}</span>
					{/each}
				{:else}
					<span
						class="setup-answers__muted"
						class:setup-answers__missing={item.state === 'skipped' && item.required}
						>{itemText(item)}</span
					>
					{#if item.note}<span>“{item.note}”</span>{/if}
				{/if}
				{@render extra?.(item)}
			</dd>
		</div>
	{/each}
</dl>

<style lang="scss">
	.setup-answers {
		display: flex;
		flex-direction: column;
		margin: 0;

		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__missing {
			color: var(--color-critical);
			font-weight: 700;
		}

		&__row {
			display: grid;
			grid-template-columns: minmax(0, 2fr) minmax(0, 3fr);
			gap: var(--space-base);
			padding: var(--space-slim) var(--space-small);
			border-top: var(--border-base) solid var(--color-border);

			dt {
				display: flex;
				flex-wrap: wrap;
				align-items: center;
				gap: var(--space-small);
				color: var(--color-heading);
				font-weight: 700;
			}

			dd {
				display: flex;
				flex-direction: column;
				gap: var(--space-smallest);
				margin: 0;
				color: var(--color-text);
				overflow-wrap: anywhere;
				white-space: pre-line;
			}

			&--changed {
				border-radius: var(--radius-base);
				background: var(--color-surface--background);
			}

			&--flagged {
				border-radius: var(--radius-base);
				background: var(--color-warning--surface);
			}
		}
	}

	@media (max-width: 767px) {
		.setup-answers__row {
			grid-template-columns: 1fr;
			gap: var(--space-smallest);
			padding-inline: 0;
		}

		// A tinted row keeps its text off the tint's edge.
		.setup-answers__row--changed,
		.setup-answers__row--flagged {
			padding-inline: var(--space-small);
		}
	}
</style>
