<script lang="ts">
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import { dateWords, timeWords, zoneCity } from '$lib/jafar/booking';

	// Jafar business management E1/E2: when a booked call is and how it happens, in the visitor's zone.

	type Props = {
		startsAt: string;
		endsAt: string;
		zone: string;
		locale?: string;
		hostName: string;
		phone: string;
		/** Strike the time through: it no longer stands (cancelled, declined, withdrawn). */
		struck?: boolean;
	};

	let { startsAt, endsAt, zone, locale, hostName, phone, struck = false }: Props = $props();
</script>

<dl class="booking-facts">
	<div>
		<dt><span aria-hidden="true">{@html calendarIcon}</span><span>When</span></dt>
		<dd class:booking-facts__struck={struck}>
			{dateWords(startsAt, zone, locale)}<br />
			{timeWords(startsAt, zone, locale)} – {timeWords(endsAt, zone, locale)}
			({zoneCity(zone)} time)
		</dd>
	</div>
	{#if !struck}
		<div>
			<dt><span aria-hidden="true">{@html phoneIcon}</span><span>How</span></dt>
			<dd>{hostName} will phone you on {phone}.</dd>
		</div>
	{/if}
</dl>

<style lang="scss">
	.booking-facts {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		width: 100%;
		margin: 0;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		text-align: left;

		div {
			display: grid;
			grid-template-columns: 6rem 1fr;
			gap: var(--space-base);

			@media (max-width: 400px) {
				grid-template-columns: 1fr;
				gap: var(--space-smaller);
			}
		}

		dt {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-text--secondary);
			font-weight: 600;

			span:first-child {
				display: inline-flex;
			}

			:global(svg) {
				width: 1.125rem;
				height: 1.125rem;
			}
		}

		dd {
			margin: 0;
			font-weight: 600;
			line-height: var(--typography--lineHeight-base);
			overflow-wrap: anywhere;
		}
	}

	.booking-facts__struck {
		color: var(--color-text--secondary);
		text-decoration: line-through;
	}
</style>
