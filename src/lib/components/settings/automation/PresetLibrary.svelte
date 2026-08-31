<script lang="ts">
	import { resolve } from '$app/paths';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { AUTOMATION_PRESETS } from '$lib/automation/presets';
	import { triggerLabel } from '$lib/automation/catalog';
	import robotIcon from '@tabler/icons/outline/robot.svg?raw';
	import sparklesIcon from '@tabler/icons/outline/sparkles.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import pencilPlusIcon from '@tabler/icons/outline/pencil-plus.svg?raw';

	// The preset library shown at /settings/automation/new when no build mode is chosen. Each card is a
	// starting point that opens the builder with a local draft (?preset=<key>); a first Build-from-scratch
	// card opens the empty builder (?mode=scratch). Choosing a preset writes nothing — the first Save draft in
	// the builder is the first write (docs/automation-behavior-contract.md § Preset library). Presets whose
	// dependencies aren't ready are simply absent, never shown as dead cards; the code-owned library is the
	// single enabled one in v1.
	const newHref = resolve('/(app)/settings/automation/new');
</script>

<div class="preset-library">
	<SectionBlock
		title="Start from a ready-made automation"
		icon={sparklesIcon}
		hint="Presets are editable starting points. Pick one and change anything before you save."
	>
		<div class="preset-library__grid">
			<article class="preset-card preset-card--scratch">
				<span class="preset-card__icon" aria-hidden="true">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html pencilPlusIcon}
				</span>
				<h3 class="preset-card__title">Build from scratch</h3>
				<p class="preset-card__summary">
					Start with an empty automation and choose every step yourself.
				</p>
				<div class="preset-card__foot">
					<Button variant="secondary" href={`${newHref}?mode=scratch`}>Build from scratch</Button>
				</div>
			</article>

			{#each AUTOMATION_PRESETS as preset (preset.key)}
				<article class="preset-card">
					<span class="preset-card__icon" aria-hidden="true">
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						{@html robotIcon}
					</span>
					<h3 class="preset-card__title">{preset.name}</h3>
					<p class="preset-card__summary">{preset.summary}</p>

					<dl class="preset-card__meta">
						<div>
							<dt>Starts when</dt>
							<dd>{triggerLabel(preset.triggerKey)}</dd>
						</div>
					</dl>

					<div class="preset-card__channels">
						{#each preset.channels as channel (channel)}
							<Badge status="informative" dot={false}>
								<span class="preset-card__channel-icon" aria-hidden="true">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									{@html mailIcon}
								</span>
								{channel === 'email' ? 'Email' : 'Text'}
							</Badge>
						{/each}
					</div>

					<div class="preset-card__foot">
						<Button variant="primary" href={`${newHref}?preset=${preset.key}`}>Use preset</Button>
					</div>
				</article>
			{/each}
		</div>
	</SectionBlock>
</div>

<style lang="scss">
	.preset-library {
		&__grid {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
			gap: var(--space-base);
		}
	}

	.preset-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);

		&--scratch {
			border-style: dashed;
			background: var(--color-surface--background);
			box-shadow: none;
		}

		&__icon {
			display: grid;
			place-items: center;
			width: 40px;
			height: 40px;
			border-radius: var(--radius-base);
			color: var(--color-informative--onSurface);
			background: var(--color-informative--surface);
		}
		&__icon :global(svg) {
			width: 22px;
			height: 22px;
		}

		&__title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
			line-height: var(--typography--lineHeight-tight);
		}

		&__summary {
			flex: 1 1 auto;
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-large);
		}

		&__meta {
			margin: 0;

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
				text-transform: uppercase;
				letter-spacing: 0.02em;
			}
			dd {
				margin: var(--space-smallest) 0 0;
				color: var(--color-text);
			}
		}

		&__channels {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-smaller);
		}

		&__channel-icon {
			display: inline-grid;
			place-items: center;
			margin-right: var(--space-smallest);
		}
		&__channel-icon :global(svg) {
			width: 14px;
			height: 14px;
		}

		&__foot {
			margin-top: var(--space-small);
		}
	}
</style>
