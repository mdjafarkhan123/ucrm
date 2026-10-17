<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import leafIcon from '@tabler/icons/outline/leaf.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import printIcon from '@tabler/icons/outline/printer.svg?raw';

	// The right-rail card on a recorded payment: a small drawing of the receipt the customer gets, with the
	// two ways staff look at the real one. The lines come from the payment itself — the drawing never makes up
	// a figure — and the real document is still the receipt page the buttons open.
	type ReceiptLine = {
		/** Tabler icon (`?raw`) drawn before the line. */
		icon: string;
		text: string;
	};

	let {
		businessName,
		logoUrl = null,
		recipient,
		tagline,
		lines,
		onView,
		onPrint
	}: {
		businessName: string;
		logoUrl?: string | null;
		/** Who the email goes to, for the heading line: "What Priya gets by email". */
		recipient: string;
		tagline: string;
		lines: ReceiptLine[];
		onView: () => void;
		onPrint: () => void;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="receipt-card" aria-label="Receipt">
	<header class="receipt-card__header">
		<h2 class="receipt-card__title">Receipt</h2>
		<p class="receipt-card__sub">What {recipient} gets by email</p>
	</header>

	<div class="receipt-card__document" aria-hidden="true">
		<div class="receipt-card__doc-top">
			<span class="receipt-card__logo">
				{#if logoUrl}
					<img class="receipt-card__logo-image" src={logoUrl} alt="" />
				{:else}
					{@html leafIcon}
				{/if}
			</span>
			<span class="receipt-card__business">{businessName}</span>
			<span class="receipt-card__chip">Receipt</span>
		</div>
		<p class="receipt-card__tagline">{tagline}</p>
		<ul class="receipt-card__lines">
			{#each lines as line (line.text)}
				<li class="receipt-card__line">
					<span class="receipt-card__line-icon">{@html line.icon}</span>
					<span class="receipt-card__line-text">{line.text}</span>
				</li>
			{/each}
		</ul>
		<div class="receipt-card__skeleton">
			<span></span><span></span><span></span>
		</div>
	</div>

	<div class="receipt-card__actions">
		<Button variant="secondary" size="small" onclick={onView}>
			<span class="receipt-card__button-icon" aria-hidden="true">{@html externalLinkIcon}</span>
			View receipt
		</Button>
		<Button variant="secondary" size="small" onclick={onPrint}>
			<span class="receipt-card__button-icon" aria-hidden="true">{@html printIcon}</span>
			Print or save PDF
		</Button>
	</div>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.receipt-card {
		display: flex;
		flex-direction: column;
		gap: 16px;
		padding: 20px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: linear-gradient(
			180deg,
			var(--color-surface--background--subtle) 0%,
			var(--color-surface) 55%
		);

		&__header {
			display: flex;
			flex-direction: column;
			gap: 2px;
		}

		&__title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
			letter-spacing: -0.2px;
			line-height: var(--typography--lineHeight-tight);
		}

		&__sub {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		// A small sheet of paper: it stays white in both themes' surface colour, never a form.
		&__document {
			display: flex;
			flex-direction: column;
			gap: 14px;
			padding: 18px;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}

		&__doc-top {
			display: flex;
			align-items: center;
			gap: 8px;
		}

		&__logo {
			display: grid;
			flex: 0 0 42px;
			place-items: center;
			width: 42px;
			height: 42px;
			overflow: hidden;
			border-radius: var(--radius-base);
			color: var(--color-text--reverse);
			background: var(--color-interactive);

			:global(svg) {
				display: block;
				width: 20px;
				height: 20px;
			}
		}

		&__logo-image {
			width: 100%;
			height: 100%;
			object-fit: cover;
		}

		&__business {
			flex: 1;
			min-width: 0;
			overflow: hidden;
			color: var(--color-heading);
			font-size: 15px;
			font-weight: 800;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__chip {
			flex: 0 0 auto;
			padding: 3px 8px;
			border-radius: 8px;
			color: var(--color-interactive);
			background: var(--color-success--surface);
			font-size: 11px;
			font-weight: 700;
			letter-spacing: 0.4px;
			text-transform: uppercase;
		}

		&__tagline {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: 12px;
			font-weight: 500;
			line-height: 1.45;
		}

		&__lines {
			display: flex;
			flex-direction: column;
			gap: 8px;
			margin: 0;
			padding: 12px 0 0;
			border-top: var(--border-base) solid var(--color-border);
			list-style: none;
		}

		&__line {
			display: flex;
			align-items: flex-start;
			gap: 8px;
			color: var(--color-text);
			font-size: 12px;
			font-weight: 500;
			line-height: 1.35;
		}

		&__line-icon :global(svg) {
			display: block;
			width: 13px;
			height: 13px;
			margin-top: 1px;
			color: var(--color-text--secondary);
		}

		&__line-text {
			min-width: 0;
			overflow-wrap: anywhere;
		}

		&__skeleton {
			display: flex;
			flex-direction: column;
			gap: 6px;
			padding-top: 4px;

			span {
				display: block;
				height: 7px;
				border-radius: 4px;
				background: var(--color-border);

				&:nth-child(2) {
					width: 180px;
					max-width: 80%;
				}
				&:nth-child(3) {
					width: 220px;
					max-width: 95%;
				}
			}
		}

		&__actions {
			display: grid;
			grid-template-columns: minmax(0, 0.85fr) minmax(0, 1.15fr);
			gap: 8px;

			:global(.button) {
				width: 100%;
				padding-inline: 8px;
				white-space: nowrap;
			}
		}

		&__button-icon {
			display: inline-flex;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
