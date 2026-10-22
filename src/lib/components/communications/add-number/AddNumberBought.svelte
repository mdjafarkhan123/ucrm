<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import NextSteps from './NextSteps.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import { formatMinor, formatPhone, type NumberOrder } from '$lib/communications/sms-number-shop';
	import { nextSteps, registersAfter } from './add-number';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import fileCheckIcon from '@tabler/icons/outline/file-check.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';

	// The bought view of Add number (`concept.pen` board `qaFQf`, "Bought"): the number is the business's, what it
	// cost, and that it can't text until its registration or Uplift's checks are done.
	let { order }: { order: NumberOrder } = $props();

	let registers = $derived(registersAfter(order.country_code));
	let tollFree = $derived(order.number_type === 'toll_free');
	let countryName = $derived(countryDisplayName(order.country_code));
</script>

<div class="add-number-bought">
	<div class="add-number-bought__hero">
		<IconTile icon={circleCheckIcon} tone="success" />
		<h3>{formatPhone(order.phone_number)} is yours</h3>
		<p>
			We charged {formatMinor(order.charge_minor, order.currency_code)} from your texting balance. It
			now shows under Phone numbers.
		</p>
	</div>

	{#if registers}
		<Banner type="warning" icon={fileCheckIcon}>
			{#if tollFree}
				It can’t text yet. Toll-free numbers need a toll-free check first: about 10 minutes to fill
				in, then the phone companies take a few days to approve.
			{:else}
				It can’t text yet. {order.country_code === 'US' ? 'US' : 'Canadian'} numbers need your business
				registered first: about 10 minutes to fill in, then the phone companies take a few days to approve.
			{/if}
		</Banner>
	{:else}
		<Banner type="notice" icon={infoIcon}>
			It can’t text yet. Uplift is checking what texting from {countryName} needs, and will tell you when
			it’s ready.
		</Banner>
	{/if}

	<NextSteps
		steps={nextSteps({
			countryCode: order.country_code,
			numberType: order.number_type,
			paperworkFirst: false,
			bought: true
		})}
	/>
</div>

<style lang="scss">
	.add-number-bought {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__hero {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-small);
			padding-top: var(--space-base);
			text-align: center;

			h3 {
				margin: var(--space-small) 0 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
				font-weight: 700;
			}

			p {
				max-width: 440px;
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
				line-height: var(--typography--lineHeight-larger);
			}
		}
	}
</style>
