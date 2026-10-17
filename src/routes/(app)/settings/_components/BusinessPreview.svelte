<script lang="ts">
	import buildingIcon from '@tabler/icons/outline/building-store.svg?raw';
	let {
		profile
	}: {
		profile: {
			name: string;
			trade: string;
			tradeOther: string;
			description: string;
			phone: string;
			website: string;
			address_line1: string;
			city: string;
			region: string;
			postal_code: string;
			address_is_public: boolean;
		};
	} = $props();
	const destinations = [
		['Quotes', 'Identity, logo, phone and address.', '/(app)/settings/quotes'],
		['Invoices', 'The same details, from quote to payment.', '/(app)/settings/invoices'],
		['Client portal', 'A familiar business customers recognize.', '/(app)/settings/branding'],
		['Booking forms', 'Your service area and business hours.', '/(app)/settings/business-hours']
	] as const;
</script>

<aside class="business-preview">
	<section class="business-preview__card">
		<h2>What customers see</h2>
		<p>A live preview of your business details.</p>
		<div class="business-preview__document">
			<div class="business-preview__brand">
				<!-- eslint-disable-next-line svelte/no-at-html-tags --><span aria-hidden="true"
					>{@html buildingIcon}</span
				><strong>{profile.name || 'Your business'}</strong><b>QUOTE</b>
			</div>
			{#if profile.trade}<p>
					{profile.trade === 'Other' ? profile.tradeOther : profile.trade}
				</p>{/if}
			{#if profile.description}<p>{profile.description}</p>{/if}
			<hr />
			{#if profile.phone}<p>{profile.phone}</p>{/if}
			{#if profile.website}<p>{profile.website}</p>{/if}
			<p>
				{#if profile.address_is_public}{profile.address_line1}{/if}
				{[profile.city, profile.region, ...(profile.address_is_public ? [profile.postal_code] : [])]
					.filter(Boolean)
					.join(', ')}
			</p>
		</div>
	</section>
	<section class="business-preview__card">
		<h2>Where this is used</h2>
		{#each destinations as item (item[0])}
			<div class="business-preview__usage"><strong>{item[0]}</strong><span>{item[1]}</span></div>
		{/each}
	</section>
</aside>

<style lang="scss">
	.business-preview {
		display: grid;
		gap: var(--space-large);
		&__card {
			padding: 24px;
			border: 1px solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}
		h2 {
			font-size: 16px;
			font-weight: 700;
			color: var(--color-heading);
		}
		p,
		&__usage span {
			font-size: 12px;
			color: var(--color-text--secondary);
			line-height: 1.6;
		}
		&__document {
			margin-top: 20px;
			padding: 16px;
			border: 1px solid var(--color-border);
			border-radius: var(--radius-base);
		}
		&__brand {
			display: flex;
			align-items: center;
			gap: 8px;
			margin-bottom: 12px;
			strong {
				flex: 1;
				font-size: 14px;
				color: var(--color-interactive);
			}
			b {
				font-size: 11px;
				color: var(--color-quote);
			}
			span {
				padding: 8px;
				background: var(--color-interactive);
				color: var(--color-text--reverse);
				border-radius: var(--radius-base);
			}
		}
		&__brand :global(svg) {
			display: block;
			width: 20px;
			height: 20px;
		}
		hr {
			border: 0;
			border-top: 1px solid var(--color-border);
			margin: 16px 0;
		}
		&__usage {
			display: grid;
			gap: 4px;
			padding: 14px 0;
			border-bottom: 1px solid var(--color-border);
			text-decoration: none;
			color: var(--color-heading);
			&:last-child {
				border: 0;
				padding-bottom: 0;
			}
			&:focus-visible {
				outline: 2px solid var(--color-interactive);
				outline-offset: 4px;
			}
		}
	}
</style>
