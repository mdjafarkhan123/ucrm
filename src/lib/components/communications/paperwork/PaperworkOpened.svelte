<script lang="ts">
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { PaperworkDetail } from '$lib/communications/number-paperwork';
	import PaperworkFacts from './PaperworkFacts.svelte';
	import {
		countryName,
		kindWord,
		longDate,
		paperworkFacts,
		setTitle,
		shortDate
	} from './paperwork-ui';
	import fileXIcon from '@tabler/icons/outline/file-x.svg?raw';
	import filePenIcon from '@tabler/icons/outline/file-pencil.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import loaderIcon from '@tabler/icons/outline/loader-2.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import arrowIcon from '@tabler/icons/outline/arrow-down-right.svg?raw';

	// An opened set the business can't edit right now (`concept.pen` board `A0URqF`, "Opened set"): a status
	// card in the status colour with what to do, then what was sent. A set the phone company sent back lists
	// each thing to fix and opens the form on its step.
	let {
		detail,
		businessName,
		onFix
	}: {
		detail: PaperworkDetail;
		businessName: string;
		onFix: (step: 'details' | 'documents') => void;
	} = $props();

	const facts = $derived(paperworkFacts(detail, businessName));
	const country = $derived(countryName(detail.country_code));
	const band = $derived.by(() => {
		switch (detail.status) {
			case 'needs_fix':
				return {
					tone: 'critical',
					icon: fileXIcon,
					title: 'The phone company sent it back',
					line:
						detail.fixes.length > 1
							? `Fix the ${detail.fixes.length} things below and send it again. Everything else is kept.`
							: 'Fix the one thing below and send it again. Everything else is kept.'
				};
			case 'approved':
				return {
					tone: 'success',
					icon: circleCheckIcon,
					title: 'Approved',
					line: `Approved ${shortDate(detail.decided_at)}. Use it for any ${country} ${kindWord(detail.number_type)} number you buy.`
				};
			case 'sending':
				return {
					tone: 'informative',
					icon: loaderIcon,
					title: 'Sending to the phone company',
					line: 'This takes a minute. This page updates by itself.'
				};
			default:
				return {
					tone: 'warning',
					icon: hourglassIcon,
					title: 'Under review',
					line: `Sent ${shortDate(detail.submitted_at)}. The phone company usually answers within 5 business days. The answer shows here.`
				};
		}
	});
	const summary = $derived(
		detail.status === 'approved'
			? [
					['Country and kind', setTitle(detail)],
					['Numbers using it', detail.numbers.join(', ') || 'None yet'],
					['Approved on', `${longDate(detail.decided_at)} · kept on file`]
				]
			: [
					['Country and kind', setTitle(detail)],
					['Sent on', longDate(detail.submitted_at) || 'Just now'],
					['Changes', 'Locked while it’s checked']
				]
	);

	function jump(step: 'details' | 'documents', event: Event) {
		event.preventDefault();
		const row = document.getElementById(`paperwork-fact-${step}`);
		row?.scrollIntoView({ behavior: 'smooth', block: 'center' });
		row?.focus({ preventScroll: true });
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<section
	class={['paperwork-opened__status', `paperwork-opened__status--${band.tone}`]}
	aria-labelledby="paperwork-status"
>
	<div class="paperwork-opened__band">
		<IconTile
			icon={band.icon}
			tone={band.tone}
			white
			class={detail.status === 'sending' ? 'paperwork-opened__spin' : ''}
		/>
		<span class="paperwork-opened__band-copy">
			<strong id="paperwork-status">{band.title}</strong>
			<span>{band.line}</span>
		</span>
		{#if detail.status === 'needs_fix'}
			<Button onclick={() => onFix(detail.fixes[0]?.step ?? 'details')}>
				<span aria-hidden="true">{@html filePenIcon}</span>
				Fix and send again
			</Button>
		{:else if detail.status === 'approved'}
			<Button variant="secondary" href={resolve('/(app)/settings/communications/sms')}>
				<span aria-hidden="true">{@html plusIcon}</span>
				Add a number
			</Button>
		{/if}
	</div>

	{#if detail.status === 'needs_fix'}
		<ol class="paperwork-opened__fixes">
			{#each detail.fixes as fix, index (fix.target)}
				<li>
					<a href={`#paperwork-fact-${fix.step}`} onclick={(event) => jump(fix.step, event)}>
						<span class="paperwork-opened__number">{index + 1}</span>
						<span class="paperwork-opened__fix">
							<strong>{fix.label}</strong>
							<span>Their words: “{fix.reason}”</span>
						</span>
						<span class="paperwork-opened__arrow" aria-hidden="true">{@html arrowIcon}</span>
					</a>
				</li>
			{/each}
		</ol>
	{:else}
		<dl class="paperwork-opened__summary">
			{#each summary as [label, value] (label)}
				<div>
					<dt>{label}</dt>
					<dd>{value}</dd>
				</div>
			{/each}
		</dl>
	{/if}
</section>

{#if detail.status === 'needs_fix'}
	<section class="paperwork-opened__sent" aria-labelledby="paperwork-sent">
		<CardHeader
			id="paperwork-sent"
			title="What you sent"
			hint={`Sent ${shortDate(detail.submitted_at)}`}
			icon={fileTextIcon}
			tone="informative"
		/>
		<PaperworkFacts facts={facts.filter((fact) => fact.step !== 'start')} onChange={onFix} onlyFixes />
	</section>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.paperwork-opened {
		&__status,
		&__sent {
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
		}

		&__status--critical {
			border: 1.5px solid var(--color-critical);
		}

		&__band {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-base) var(--space-medium);
			background: var(--band-surface);

			.paperwork-opened__status--critical & {
				--band-surface: var(--color-critical--surface);
				--band-ink: var(--color-critical--onSurface);
			}
			.paperwork-opened__status--warning & {
				--band-surface: var(--color-warning--surface);
				--band-ink: var(--color-warning--onSurface);
			}
			.paperwork-opened__status--success & {
				--band-surface: var(--color-success--surface);
				--band-ink: var(--color-success--onSurface);
			}
			.paperwork-opened__status--informative & {
				--band-surface: var(--color-informative--surface);
				--band-ink: var(--color-informative--onSurface);
			}
		}

		&__band-copy {
			display: grid;
			flex: 1;
			gap: 2px;
			min-width: 0;
			color: var(--band-ink);

			strong {
				font-size: var(--typography--fontSize-large);
				font-weight: 600;
			}

			span {
				font-size: var(--typography--fontSize-smaller);
				line-height: var(--typography--lineHeight-large);
			}
		}

		:global(.paperwork-opened__spin svg) {
			animation: paperwork-opened-spin 1s linear infinite;
		}

		&__fixes {
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				border-top: var(--border-base) solid var(--color-border);
			}

			a {
				display: flex;
				align-items: center;
				gap: 10px;
				padding: 10px var(--space-medium);
				color: inherit;
				text-decoration: none;

				&:hover {
					background: var(--color-surface--hover);
				}

				&:hover .paperwork-opened__arrow {
					color: var(--color-heading);
				}

				&:focus-visible {
					outline: 2px solid var(--color-focus);
					outline-offset: -2px;
				}
			}
		}

		&__number {
			display: grid;
			flex: none;
			place-items: center;
			width: 20px;
			height: 20px;
			border-radius: var(--radius-circle);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 700;
		}

		&__fix {
			display: grid;
			flex: 1;
			gap: 2px;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		&__arrow {
			color: var(--color-icon--secondary);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__summary {
			margin: 0;

			div {
				display: grid;
				grid-template-columns: 150px minmax(0, 1fr);
				gap: var(--space-base);
				padding: var(--space-slim) var(--space-medium);
				border-top: var(--border-base) solid var(--color-border);
			}

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
			}

			dd {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 500;
			}
		}
	}

	@keyframes paperwork-opened-spin {
		to {
			transform: rotate(360deg);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		:global(.paperwork-opened__spin svg) {
			animation: none;
		}
	}
</style>
