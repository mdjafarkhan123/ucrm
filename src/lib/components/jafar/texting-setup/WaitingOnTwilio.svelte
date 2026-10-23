<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import { relativeTime } from '$lib/collaboration/format';
	import { formatPhone } from '$lib/communications/sms-number-shop';
	import {
		fetchWaitingOnTwilio,
		textingSetupKey,
		waitingOnTwilioKey,
		whenAsked,
		type WaitingItem
	} from '$lib/jafar/texting-setup';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import fileIcon from '@tabler/icons/outline/file-text.svg?raw';
	import rotateIcon from '@tabler/icons/outline/rotate-clockwise.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';

	// Texting setup's Waiting on Twilio tab (`concept.pen` board `v6Jtu`): what Uplift sent to Twilio for every
	// business and is waiting to hear back on. Nothing to press but Check now, which asks Twilio straight away.
	const queryClient = useQueryClient();
	const toast = getToastManager();
	const waiting = createQuery(() => ({
		queryKey: waitingOnTwilioKey,
		queryFn: fetchWaitingOnTwilio
	}));

	let checking = $state(false);
	let checkedAt = $state<string | null>(null);
	const lastAsked = $derived.by(() => {
		const latest = [checkedAt, waiting.data?.last_checked_at]
			.filter((at): at is string => Boolean(at))
			.sort()
			.at(-1);
		return latest ? `Last asked ${relativeTime(latest).toLowerCase()}` : 'Not asked yet';
	});

	const KINDS = {
		registration: { icon: buildingIcon, tone: 'informative' },
		paperwork: { icon: fileIcon, tone: 'conversation' },
		tollfree: { icon: phoneIcon, tone: 'conversation' }
	} as const;

	const NUMBER_TYPES: Record<string, string> = {
		local: 'local',
		mobile: 'mobile',
		toll_free: 'toll-free',
		national: 'national'
	};

	function title(item: WaitingItem) {
		if (item.kind === 'registration') return 'US texting registration';
		if (item.kind === 'tollfree') return 'Toll-free check';
		const [country, type] = (item.detail ?? '').split(':');
		return `${countryDisplayName(country)} ${NUMBER_TYPES[type] ?? ''} number paperwork`.replace(
			'  ',
			' '
		);
	}

	function meta(item: WaitingItem) {
		if (item.turned_down) {
			const when = item.decided_at ? whenAsked(item.decided_at) : 'lately';
			return `${item.organization_name} · turned down ${when} · they were told what to fix`;
		}
		const sent = item.sent_at ? `sent ${whenAsked(item.sent_at)}` : 'sent';
		if (item.kind === 'registration')
			return `${item.organization_name} · ${sent} · Twilio usually answers in 1 to 3 weeks`;
		if (item.kind === 'tollfree')
			return [item.organization_name, item.detail && formatPhone(item.detail), sent]
				.filter(Boolean)
				.join(' · ');
		return `${item.organization_name} · ${sent} · usually answered in 1 to 5 business days`;
	}

	function pill(item: WaitingItem) {
		if (item.turned_down) return 'Turned down';
		return item.kind === 'tollfree' ? 'In review' : 'Under review';
	}

	async function checkNow() {
		checking = true;
		try {
			const response = await fetch('/api/jafar/texting-setup/waiting/check', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: '{}'
			});
			const body = await response.json().catch(() => ({}));
			if (!response.ok) {
				toast.error('Couldn’t ask Twilio', body.error ?? 'Try again in a moment.');
				return;
			}
			checkedAt = body.checked_at;
			await queryClient.invalidateQueries({ queryKey: textingSetupKey });
		} catch {
			toast.error('Couldn’t ask Twilio', 'Check your connection and try again.');
		} finally {
			checking = false;
		}
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<section class="waiting" aria-labelledby="waiting-title">
	<header class="waiting__head">
		<span class="waiting__words">
			<h2 id="waiting-title">Waiting on Twilio</h2>
			<span>{checking ? 'Asking Twilio…' : waiting.isPending ? 'Loading…' : lastAsked}</span>
		</span>
		<Button size="small" variant="secondary" loading={checking} onclick={checkNow}>
			<span aria-hidden="true">{@html rotateIcon}</span>
			{checking ? 'Checking…' : 'Check now'}
		</Button>
	</header>

	{#if waiting.isPending}
		<div aria-busy="true" aria-label="Loading what waits on Twilio">
			{#each [180, 140, 200] as width (width)}
				<div class="waiting__row waiting__row--loading">
					<span class="waiting__dot"></span>
					<span class="waiting__lines">
						<span style:width={`${width}px`}></span>
						<span style:width={`${width + 80}px`}></span>
					</span>
				</div>
			{/each}
		</div>
	{:else if waiting.isError}
		<div class="waiting__state">
			<ErrorState
				title="Couldn’t load what waits on Twilio"
				description="Check your connection and try again. Nothing was changed."
				retry={() => waiting.refetch()}
			/>
		</div>
	{:else if !waiting.data?.items.length}
		<div class="waiting__state">
			<EmptyState
				title="Nothing waits on Twilio"
				description="When Uplift sends a registration, paperwork or a toll-free check, it shows here until Twilio answers."
				icon={circleCheckIcon}
				tone="success"
			/>
		</div>
	{:else}
		<ul class="waiting__list">
			{#each waiting.data.items as item (`${item.kind}:${item.id}`)}
				<li class={['waiting__row', item.turned_down && 'waiting__row--turned-down']}>
					<IconTile icon={KINDS[item.kind].icon} tone={KINDS[item.kind].tone} size={32} />
					<span class="waiting__words">
						<strong>{title(item)}</strong>
						<span>{meta(item)}</span>
					</span>
					<StatusBadge
						status={item.turned_down ? 'critical' : 'warning'}
						size="small"
						outlined={item.turned_down}>{pill(item)}</StatusBadge
					>
				</li>
			{/each}
		</ul>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.waiting {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__head {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: 14px var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);

			h2 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 600;
			}
		}

		&__words {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;

			> span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
		}

		&__list {
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 14px var(--space-base);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}

			.waiting__words > span {
				font-weight: 500;
			}

			&--turned-down {
				background: var(--color-critical--surface);

				.waiting__words > span {
					color: var(--color-critical--onSurface);
				}
			}
		}

		&__dot {
			flex: none;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__lines {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);

			span {
				max-width: 100%;
				height: var(--space-slim);
				border-radius: var(--radius-small);
				background: var(--color-surface--background);
			}
		}

		&__state {
			padding: var(--space-larger);
		}
	}
</style>
