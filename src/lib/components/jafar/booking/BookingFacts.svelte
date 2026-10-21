<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import videoIcon from '@tabler/icons/outline/video.svg?raw';
	import {
		VIDEO_PROVIDER_WORDS,
		dateWords,
		timeWords,
		zoneCity,
		type LocationKind
	} from '$lib/jafar/booking';

	// Jafar business management E1/E2: when a booked call is and how it happens, in the visitor's zone. E4a: a video
	// call shows its joining link, or says the link will follow by email. Look: design skill `layout.md` → Booking
	// page → Settled states (rows of a 40 tile, label over value).

	type Props = {
		startsAt: string;
		endsAt: string;
		zone: string;
		locale?: string;
		hostName: string;
		phone: string;
		locationKind: LocationKind;
		/** A video call's joining link; null while it is still to follow. */
		videoJoinUrl?: string | null;
		/** Strike the time through: it no longer stands (cancelled, declined, withdrawn). */
		struck?: boolean;
		/** A bordered box, for facts that sit among other content rather than in a settled state's facts band. */
		framed?: boolean;
	};

	let {
		startsAt,
		endsAt,
		zone,
		locale,
		hostName,
		phone,
		locationKind,
		videoJoinUrl = null,
		struck = false,
		framed = false
	}: Props = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<dl class={['booking-facts', framed && 'booking-facts--framed']}>
	<div class="booking-facts__row">
		<IconTile icon={calendarIcon} tone="time" />
		<div class="booking-facts__text">
			<dt>When</dt>
			<dd class:booking-facts__struck={struck}>
				{dateWords(startsAt, zone, locale)}<br />
				{timeWords(startsAt, zone, locale)} – {timeWords(endsAt, zone, locale)}
				({zoneCity(zone)} time)
			</dd>
		</div>
	</div>
	{#if !struck}
		<div class="booking-facts__row">
			<IconTile icon={locationKind === 'phone' ? phoneIcon : videoIcon} tone="conversation" />
			<div class="booking-facts__text">
				<dt>How</dt>
				{#if locationKind === 'phone'}
					<dd>{hostName} will phone you on {phone}.</dd>
				{:else}
					{@const provider = VIDEO_PROVIDER_WORDS[locationKind]}
					<dd>
						{provider} video call with {hostName}.
						{#if videoJoinUrl}
							<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- the call's joining link, on the video provider's site. -->
							<a class="booking-facts__join" href={videoJoinUrl} target="_blank" rel="noopener"
								><span aria-hidden="true">{@html externalLinkIcon}</span>Join the {provider} call</a
							>
						{:else}
							<span class="booking-facts__pending"
								>We'll email you the joining link before the call.</span
							>
						{/if}
					</dd>
				{/if}
			</div>
		</div>
	{/if}
</dl>

<style lang="scss">
	.booking-facts {
		display: flex;
		flex-direction: column;
		width: 100%;
		margin: 0;
		text-align: left;

		&--framed {
			padding: var(--space-smaller) var(--space-medium);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
		}
	}

	.booking-facts__row {
		display: flex;
		align-items: flex-start;
		gap: 14px;
		padding: var(--space-base) 0;

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}
	}

	.booking-facts__text {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		min-width: 0;

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		dd {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			line-height: 1.45;
			overflow-wrap: anywhere;
		}
	}

	.booking-facts__join {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		margin-top: var(--space-smaller);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
		text-decoration: none;

		span {
			display: inline-flex;
		}
		:global(svg) {
			width: 14px;
			height: 14px;
		}
		&:hover {
			text-decoration: underline;
		}
		&:focus-visible {
			border-radius: var(--radius-small);
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.booking-facts__pending {
		display: block;
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-label);
		font-weight: 400;
	}

	.booking-facts__struck {
		color: var(--color-text--secondary) !important;
		text-decoration: line-through;
	}
</style>
