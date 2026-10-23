<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import PaperworkFlag from '$lib/components/communications/paperwork/PaperworkFlag.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import { smsDestinationsQuery } from '$lib/jafar/organization-communications-queries';
	import {
		destinationStatus,
		organizationDestinationsKey,
		textingSetupKey,
		textPrice,
		whenAsked,
		TWILIO_GEO_PERMISSIONS_URL,
		type BusinessDestination,
		type BusinessDestinations
	} from '$lib/jafar/texting-setup';
	import globeIcon from '@tabler/icons/outline/world.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import circleOffIcon from '@tabler/icons/outline/circle-off.svg?raw';
	import tagIcon from '@tabler/icons/outline/tag.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import externalIcon from '@tabler/icons/outline/external-link.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';

	// A business's countries on its Communications tab (board `v6Jtu`, A's table): the Twilio permission, the
	// price and the status of each. The work itself happens in Texting setup; a waiting row links there.
	let { organizationId, organizationName }: { organizationId: string; organizationName: string } =
		$props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const countries = createQuery(() => smsDestinationsQuery<BusinessDestinations>(organizationId));

	const rows = $derived(countries.data?.destinations ?? []);
	const waiting = $derived(
		rows.filter((row) => destinationStatus(row).label === 'Setting up').length
	);
	const hint = $derived(
		countries.isPending
			? 'Loading…'
			: countries.isError
				? 'Couldn’t load'
				: [
						`${rows.length} ${rows.length === 1 ? 'country' : 'countries'}`,
						waiting ? `${waiting} wait on Uplift, in Texting setup` : ''
					]
						.filter(Boolean)
						.join(' · ')
	);

	function asked(row: BusinessDestination) {
		return row.is_home ? 'Home country' : `Asked ${whenAsked(row.requested_at)}`;
	}

	function permission(row: BusinessDestination) {
		const lastBy = (kind: string) => row.history.find((event) => event.kind === kind)?.who;
		if (row.status === 'ready') {
			const who = lastBy('switched_on');
			return {
				icon: checkIcon,
				tone: 'on',
				state: 'On',
				detail: `Checked ${whenAsked(row.ready_at ?? row.requested_at)}${who ? ` by ${who}` : ''}`
			};
		}
		if (row.status === 'off') {
			return {
				icon: circleOffIcon,
				tone: 'off',
				state: 'Off',
				detail: `Turned off ${whenAsked(row.off_at ?? row.requested_at)}${row.off_reason ? ` · ${row.off_reason}` : ''}`
			};
		}
		return {
			icon: hourglassIcon,
			tone: 'waiting',
			state: 'Not turned on yet',
			detail: 'Tick it in Twilio'
		};
	}

	function taskHref(row: BusinessDestination) {
		return `${resolve('/jafar/(protected)/texting-setup')}?task=${row.id}`;
	}

	let turningOff = $state<BusinessDestination | null>(null);
	let reason = $state('');
	let reasonError = $state('');
	let saving = $state(false);

	function askTurnOff(row: BusinessDestination) {
		turningOff = row;
		reason = '';
		reasonError = '';
	}

	async function turnOff() {
		const row = turningOff;
		if (!row) return;
		if (reason.trim().length < 3) {
			reasonError = 'Enter a reason of at least 3 characters.';
			return;
		}
		saving = true;
		reasonError = '';
		try {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/destinations/${row.id}/turn-off`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ reason: reason.trim() })
				}
			);
			const body = await response.json().catch(() => ({}));
			if (!response.ok) {
				reasonError =
					body.field_errors?.reason ?? body.error ?? 'The country could not be turned off.';
				return;
			}
			turningOff = null;
			toast.success(`${countryDisplayName(row.country)} is off for ${organizationName}`);
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: organizationDestinationsKey(organizationId) }),
				queryClient.invalidateQueries({ queryKey: textingSetupKey })
			]);
		} catch {
			reasonError = 'Check your connection. Nothing was changed.';
		} finally {
			saving = false;
		}
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<section class="texting-countries" aria-labelledby="texting-countries-title">
	<CardHeader
		id="texting-countries-title"
		title={`Countries ${organizationName} can text`}
		{hint}
		icon={globeIcon}
		tone="conversation"
	/>

	{#if countries.isPending}
		<div class="texting-countries__skeleton" aria-busy="true" aria-label="Loading countries">
			{#each [120, 100, 140] as width (width)}
				<div class="texting-countries__skeleton-row">
					<span class="texting-countries__skeleton-dot"></span>
					<span class="texting-countries__skeleton-lines">
						<span style:width={`${width}px`}></span>
						<span style:width={`${width - 50}px`}></span>
					</span>
					<span class="texting-countries__skeleton-pill"></span>
				</div>
			{/each}
		</div>
	{:else if countries.isError}
		<ErrorState
			title={`Couldn’t load ${organizationName}’s countries`}
			description="Check your connection and try again. Nothing was changed."
			retry={() => countries.refetch()}
		/>
	{:else if rows.length === 0}
		<p class="texting-countries__line">
			No countries yet. {organizationName} gets its home country with its first number.
		</p>
	{:else}
		<div class="texting-countries__head" aria-hidden="true">
			<span>Country</span>
			<span>Twilio permission</span>
			<span>Price</span>
			<span>Status</span>
			<span></span>
		</div>
		<ul class="texting-countries__rows">
			{#each rows as row (row.id)}
				{@const status = destinationStatus(row)}
				{@const allowed = permission(row)}
				{@const country = countryDisplayName(row.country)}
				<li class="texting-countries__row">
					<span class="texting-countries__country">
						<PaperworkFlag code={row.country} />
						<span class="texting-countries__stack">
							<strong>{country}</strong>
							<span>{asked(row)}</span>
						</span>
					</span>
					<span class="texting-countries__permission">
						<span
							class="texting-countries__permission-icon texting-countries__permission-icon--{allowed.tone}"
							aria-hidden="true">{@html allowed.icon}</span
						>
						<span class="texting-countries__stack">
							<strong>{allowed.state}</strong>
							<span>{allowed.detail}</span>
						</span>
					</span>
					<span class="texting-countries__stack">
						{#if row.price.segment}
							<strong>{textPrice(row.price.segment.rate)} a segment</strong>
							<span>
								{row.price.mms
									? `${textPrice(row.price.mms.rate)} a picture text`
									: 'No picture texts'}
							</span>
						{:else}
							<span class="texting-countries__no-price">
								<span aria-hidden="true">{@html tagIcon}</span>
								No price yet
							</span>
						{/if}
					</span>
					<span><StatusBadge status={status.tone}>{status.label}</StatusBadge></span>
					<span class="texting-countries__action">
						{#if row.status === 'setting_up'}
							<Button variant="secondary" size="small" href={taskHref(row)}>
								<span aria-hidden="true">{@html arrowRightIcon}</span>
								Open task
							</Button>
						{:else}
							<DropdownMenu
								triggerLabel={`More for ${country}`}
								items={[
									{
										label: 'See it in Twilio',
										icon: externalIcon,
										onSelect: () => window.open(TWILIO_GEO_PERMISSIONS_URL, '_blank', 'noopener')
									}
								]}
								footer={row.status === 'ready'
									? [
											{
												label: `Turn off for ${organizationName}`,
												icon: circleOffIcon,
												destructive: true,
												onSelect: () => askTurnOff(row)
											}
										]
									: []}
							/>
						{/if}
					</span>
				</li>
			{/each}
		</ul>
		{#if rows.length === 1}
			<p class="texting-countries__line">{organizationName} hasn’t asked for other countries.</p>
		{/if}
		<p class="texting-countries__foot">
			<span aria-hidden="true">{@html infoIcon}</span>
			{organizationName} sees Ready once its Twilio permission is on and the country has a price. Uplift
			does that work in Texting setup; prices are the same for every business.
		</p>
	{/if}
</section>

{#if turningOff}
	{@const country = countryDisplayName(turningOff.country)}
	<ConfirmDialog
		open
		title={`Turn off ${country} for ${organizationName}?`}
		icon={circleOffIcon}
		tone="critical"
		confirmLabel="Turn off"
		destructive
		loading={saving}
		onConfirm={turnOff}
		onClose={() => {
			if (!saving) turningOff = null;
		}}
	>
		<p class="texting-countries__confirm">
			{organizationName} can’t text {country} numbers from now on, and texts waiting to go there won’t
			send. The business can ask for it again later.
		</p>
		<Input
			id="turn-off-reason"
			label="Reason, kept in the log"
			required
			bind:value={reason}
			invalid={!!reasonError}
			errorMessage={reasonError}
			disabled={saving}
		/>
	</ConfirmDialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.texting-countries {
		display: flex;
		flex-direction: column;
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__head,
		&__row {
			display: grid;
			grid-template-columns: minmax(0, 1.4fr) minmax(0, 1.2fr) minmax(0, 0.9fr) 130px 120px;
			align-items: center;
			column-gap: var(--space-slim);
		}

		&__head {
			padding: 10px var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			border-bottom: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__rows {
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			padding: 14px var(--space-medium);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__country,
		&__permission {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			min-width: 0;
		}

		&__permission {
			align-items: flex-start;
			gap: var(--space-small);
		}

		&__stack {
			display: flex;
			flex-direction: column;
			gap: 2px;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}

			> span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}
		}

		&__country &__stack strong {
			font-size: var(--typography--fontSize-base);
		}

		&__permission-icon {
			display: inline-flex;
			flex: none;
			width: 16px;
			height: 16px;
			margin-top: 1px;

			&--on {
				color: var(--color-success);
			}

			&--waiting {
				color: var(--color-warning--onSurface);
			}

			&--off {
				color: var(--color-text--secondary);
			}
		}

		&__no-price {
			display: inline-flex;
			align-items: center;
			align-self: flex-start;
			gap: var(--space-smaller);
			height: 24px;
			padding: 0 var(--space-small);
			border-radius: var(--radius-circle);
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;

			span {
				display: inline-flex;
				width: 12px;
				height: 12px;
			}
		}

		&__action {
			display: flex;
			justify-content: flex-end;
		}

		&__line {
			margin: 0;
			padding: 14px var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}

		&__foot {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-slim) var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);

			span {
				display: inline-flex;
				flex: none;
				width: 14px;
				height: 14px;
				color: var(--color-informative);
			}
		}

		&__confirm {
			margin: 0 0 var(--space-base);
		}

		&__skeleton {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__skeleton-row {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}

		&__skeleton-dot {
			flex: none;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
		}

		&__skeleton-lines {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);

			span {
				height: 10px;
				border-radius: var(--radius-small);
				background: var(--color-surface--background);
			}
		}

		&__skeleton-pill {
			width: 56px;
			height: 22px;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
		}
	}
</style>
