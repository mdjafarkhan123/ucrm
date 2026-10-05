<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import {
		PROVIDER_WAIT_TITLE,
		providerWaitAside,
		providerWaitLabel,
		providerWaitTone,
		type ProviderWait
	} from '$lib/setup/provider-waits';

	// Client onboarding E2 (plan §5): the steps Google, the phone carriers, an old phone company or a domain
	// company take, kept apart from the project tracker so their time never reads as Uplift's. Only the waits
	// Uplift has started are shown. "You need to do something" emails link here (#outside-waits).
	let { waits }: { waits: ProviderWait[] } = $props();

	const day = (value: string) =>
		new Date(value).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
</script>

<SectionBlock
	id="outside-waits"
	class="outside-waits-block"
	title="Waiting on others"
	hint="Steps that Google, the phone companies or your domain company take. They run alongside your build."
>
	<ul class="outside-waits">
		{#each waits as wait (wait.key)}
			{@const aside = providerWaitAside(wait.key, wait.status)}
			<li
				class="outside-waits__item"
				class:outside-waits__item--action={wait.status === 'action_needed'}
			>
				<div class="outside-waits__head">
					<strong class="outside-waits__title">{PROVIDER_WAIT_TITLE[wait.key]}</strong>
					<StatusBadge status={providerWaitTone(wait.status)}
						>{providerWaitLabel(wait.key, wait.status)}</StatusBadge
					>
				</div>
				<span class="outside-waits__date">Updated {day(wait.updated_at)}</span>
				{#if wait.note}<p class="outside-waits__note">{wait.note}</p>{/if}
				{#if aside}<p class="outside-waits__aside">{aside}</p>{/if}
			</li>
		{/each}
	</ul>
</SectionBlock>

<style lang="scss">
	// The email's link jumps here; keep the title on the border line clear of the top edge.
	:global(.outside-waits-block) {
		scroll-margin-top: var(--space-largest);
	}

	.outside-waits {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;

		&__item {
			display: grid;
			gap: var(--space-smaller);
			padding: var(--space-slim) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			&--action {
				border-color: var(--color-warning);
				background: var(--color-warning--surface);
			}
		}

		&__head {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__title {
			color: var(--color-heading);
		}

		&__date,
		&__aside {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__note {
			margin: 0;
			color: var(--color-text);
			line-height: var(--typography--lineHeight-base);
			white-space: pre-line;
		}

		&__aside {
			margin: 0;
		}
	}
</style>
