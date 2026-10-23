<script lang="ts">
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import PaperworkFlag from '$lib/components/communications/paperwork/PaperworkFlag.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import {
		countryOptOutLanguages,
		englishOnlyLanguage,
		languageName
	} from '$lib/communications/sms-opt-out-words';
	import {
		historyTime,
		margin,
		shortSid,
		textPrice,
		whenAsked,
		TWILIO_GEO_PERMISSIONS_URL,
		type DestinationEvent,
		type TextingTask
	} from '$lib/jafar/texting-setup';
	import buildingIcon from '@tabler/icons/outline/building-store.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import keyIcon from '@tabler/icons/outline/key.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import externalIcon from '@tabler/icons/outline/external-link.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-2.svg?raw';
	import circleOffIcon from '@tabler/icons/outline/circle-off.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// One task's panel (board `v6Jtu`): the price, the opt-out words, the Twilio tick with the account it belongs to, then "Mark as
	// turned on" once the box says it was done. Can't turn on closes the request instead.
	let {
		task,
		marking,
		closing,
		onTick,
		onMark,
		onPrice,
		onOptOut,
		onCantTurnOn
	}: {
		task: TextingTask;
		marking: boolean;
		/** The Can't turn on pop-up is saving; the panel holds still meanwhile. */
		closing: boolean;
		/** The box was ticked: this is the task being worked on now. */
		onTick: () => void;
		onMark: () => void;
		/** Opens the Change price pop-up for the task's country. */
		onPrice: () => void;
		/** Opens the opt-out words task for a language this country still needs. */
		onOptOut: (language: string) => void;
		onCantTurnOn: () => void;
	} = $props();

	// The page draws a fresh panel for each task, so a new task starts unticked.
	let ticked = $state(false);
	let copied = $state(false);

	const country = $derived(countryDisplayName(task.country));
	const busy = $derived(marking || closing);
	const segment = $derived(task.price.segment);
	const businessHref = $derived(
		`${resolve('/jafar/(protected)/organizations/[organizationId]', { organizationId: task.organization_id })}?tab=communications&channel=texting`
	);
	const line = $derived(
		[
			task.organization_name,
			`asked ${whenAsked(task.requested_at)}${task.requested_by ? ` by ${task.requested_by}` : ''}`,
			task.is_home ? 'its home country' : ''
		]
			.filter(Boolean)
			.join(' · ')
	);
	const priceLine = $derived.by(() => {
		if (!segment) return '';
		const parts = [`${textPrice(segment.rate)} a segment`];
		if (segment.cost !== null) {
			parts.push(
				`Twilio charges us ${textPrice(segment.cost)}`,
				`${margin(segment.rate, segment.cost)} margin`
			);
		}
		const pictures = task.price.mms
			? `${textPrice(task.price.mms.rate)} a picture text.`
			: 'No picture texts there.';
		return `${parts.join(' · ')}. ${pictures}`;
	});

	// Part 5d: the customer's own language's stop words go into Twilio before the country is turned on.
	const missing = $derived(task.opt_out_missing);
	const missingNames = $derived(missing.map(languageName).join(' and '));
	const optOutLine = $derived.by(() => {
		const english = `English STOP, UNSUBSCRIBE and CANCEL already work in ${country}.`;
		const added = countryOptOutLanguages(task.country).map(languageName);
		if (added.length) return `${added.join(' and ')} words are in Twilio. ${english}`;
		const only = englishOnlyLanguage(task.country);
		if (only) return `Twilio takes no ${languageName(only)} words. ${english}`;
		return english;
	});

	async function copyAccount() {
		if (!task.account_sid) return;
		try {
			await navigator.clipboard.writeText(task.account_sid);
			copied = true;
		} catch {
			copied = false;
		}
	}

	const historyIcon: Record<DestinationEvent['kind'], { icon: string; tone: string }> = {
		requested: { icon: messageIcon, tone: 'conversation' },
		switched_on: { icon: checkIcon, tone: 'success' },
		closed: { icon: banIcon, tone: 'critical' },
		turned_off: { icon: circleOffIcon, tone: 'inactive' }
	};

	function historyText(event: DestinationEvent): string {
		const who = event.who ?? (event.kind === 'requested' ? task.organization_name : 'Uplift');
		if (event.kind === 'requested') return `${who} asked to text ${country}`;
		if (event.kind === 'switched_on') return `${who} turned ${country} on`;
		if (event.kind === 'closed') return `${who} couldn’t turn ${country} on: ${event.note ?? ''}`;
		return `${who} turned ${country} off: ${event.note ?? ''}`;
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<section class="task-panel" aria-labelledby="task-panel-title">
	<header class="task-panel__head">
		<PaperworkFlag code={task.country} size={40} />
		<div class="task-panel__title">
			<div class="task-panel__title-line">
				<h2 id="task-panel-title">Turn on {country}</h2>
				<StatusBadge status="warning">Setting up</StatusBadge>
			</div>
			<p>{line}</p>
		</div>
		<Button variant="secondary" size="small" href={businessHref} disabled={busy}>
			<span aria-hidden="true">{@html buildingIcon}</span>
			Open {task.organization_name}
		</Button>
	</header>

	<ol class="task-panel__steps">
		<li class="task-panel__step">
			{#if segment}
				<span class="task-panel__mark task-panel__mark--done" aria-hidden="true"
					>{@html checkIcon}</span
				>
				<div class="task-panel__step-copy">
					<h3 class="task-panel__step-title task-panel__step-title--done">Price for {country}</h3>
					<p>{priceLine}</p>
					<button type="button" class="task-panel__link" onclick={onPrice}>
						<span aria-hidden="true">{@html pencilIcon}</span>
						Change price
					</button>
				</div>
				<span class="task-panel__done">Done</span>
			{:else}
				<span class="task-panel__mark task-panel__mark--turn" aria-hidden="true"
					>{@html pencilIcon}</span
				>
				<div class="task-panel__step-copy">
					<h3 class="task-panel__step-title">Price for {country}</h3>
					<p>
						No price yet. {task.organization_name} sees Ready only once {country} has a price, so set
						one too.
					</p>
					<button type="button" class="task-panel__link" onclick={onPrice}>
						<span aria-hidden="true">{@html pencilIcon}</span>
						Set a price
					</button>
				</div>
			{/if}
		</li>

		<li class="task-panel__step">
			{#if missing.length}
				<span class="task-panel__mark task-panel__mark--turn" aria-hidden="true"
					>{@html pencilIcon}</span
				>
				<div class="task-panel__step-copy">
					<h3 class="task-panel__step-title">Opt-out words</h3>
					<p>
						Customers in {country} must be able to reply STOP in {missingNames}. Add those words in
						Twilio first.
					</p>
					{#each missing as language (language)}
						<button type="button" class="task-panel__link" onclick={() => onOptOut(language)}>
							<span aria-hidden="true">{@html arrowRightIcon}</span>
							Add {languageName(language)} opt-out words
						</button>
					{/each}
				</div>
			{:else}
				<span class="task-panel__mark task-panel__mark--done" aria-hidden="true"
					>{@html checkIcon}</span
				>
				<div class="task-panel__step-copy">
					<h3 class="task-panel__step-title task-panel__step-title--done">Opt-out words</h3>
					<p>{optOutLine}</p>
				</div>
				<span class="task-panel__done">Done</span>
			{/if}
		</li>

		<li class="task-panel__step">
			<span class="task-panel__mark task-panel__mark--turn" aria-hidden="true"
				>{@html pencilIcon}</span
			>
			<div class="task-panel__step-copy">
				<h3 class="task-panel__step-title">Tick {country} in Twilio</h3>
				<p>
					Open Geo permissions for {task.organization_name}’s Twilio account, tick {country} and press
					Save. Leave high-risk numbers off.
				</p>
				{#if task.account_sid}
					<div class="task-panel__account">
						<IconTile icon={keyIcon} tone="informative" size={32} />
						<span class="task-panel__account-copy">
							<strong>{task.organization_name} · {shortSid(task.account_sid)}</strong>
							<span>Messaging › Settings › Geo permissions</span>
						</span>
						<Button variant="secondary" size="small" onclick={copyAccount} disabled={busy}>
							<span aria-hidden="true">{@html copied ? checkIcon : copyIcon}</span>
							{copied ? 'Copied' : 'Copy ID'}
						</Button>
						<Button
							variant="secondary"
							size="small"
							href={TWILIO_GEO_PERMISSIONS_URL}
							target="_blank"
							disabled={busy}
						>
							<span aria-hidden="true">{@html externalIcon}</span>
							Open in Twilio
						</Button>
					</div>
				{:else}
					<p class="task-panel__missing">
						{task.organization_name} has no Twilio account yet. It gets one with its first number.
					</p>
				{/if}
			</div>
		</li>

		<li class="task-panel__step">
			<span class="task-panel__mark" aria-hidden="true">4</span>
			<div class="task-panel__step-copy">
				<h3 class="task-panel__step-title">Mark as turned on</h3>
				<p>{task.organization_name} sees Ready straight after, and we note who did it.</p>
				<div class="task-panel__tick">
					<Checkbox
						id="task-ticked"
						label={`I ticked ${country} in Twilio and saved`}
						bind:checked={ticked}
						onchange={(checked) => checked && onTick()}
						disabled={busy}
					/>
				</div>
			</div>
		</li>
	</ol>

	{#if task.history.length}
		<div class="task-panel__history">
			<h3>History</h3>
			<ul>
				{#each task.history as event (`${event.kind}-${event.at}`)}
					<li>
						<IconTile
							icon={historyIcon[event.kind].icon}
							tone={historyIcon[event.kind].tone}
							size={24}
						/>
						<span class="task-panel__history-text">{historyText(event)}</span>
						<time datetime={event.at}>{historyTime(event.at)}</time>
					</li>
				{/each}
			</ul>
		</div>
	{/if}

	<footer class="task-panel__foot">
		<Button variant="secondary" variation="destructive" onclick={onCantTurnOn} disabled={busy}>
			<span aria-hidden="true">{@html banIcon}</span>
			Can’t turn on
		</Button>
		<div class="task-panel__foot-end">
			{#if missing.length}<span class="task-panel__hint">Add the opt-out words first</span>
			{:else if !ticked}<span class="task-panel__hint">Tick the box first</span>{/if}
			<Button
				onclick={onMark}
				disabled={!ticked || closing || missing.length > 0}
				loading={marking}
			>
				{#if !marking}<span aria-hidden="true">{@html checkIcon}</span>{/if}
				{marking ? 'Marking…' : 'Mark as turned on'}
			</Button>
		</div>
	</footer>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.task-panel {
		display: flex;
		flex-direction: column;
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__head {
			display: flex;
			align-items: flex-start;
			gap: var(--space-slim);
			padding: var(--space-medium) var(--space-large);
			border-bottom: var(--border-base) solid var(--color-border);
		}

		&__title {
			flex: 1;
			min-width: 0;

			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
			}
		}

		&__title-line {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);

			h2 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
				font-weight: 700;
			}
		}

		&__steps {
			flex: 1;
			margin: 0;
			padding: 0 var(--space-large);
			list-style: none;
		}

		&__step {
			display: grid;
			grid-template-columns: 28px minmax(0, 1fr) auto;
			column-gap: var(--space-slim);
			padding: var(--space-base) 0;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__mark {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 28px;
			height: 28px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;

			:global(svg) {
				width: 14px;
				height: 14px;
			}

			&--done {
				border-color: var(--color-success--surface-edge);
				background: var(--color-success--surface);
				color: var(--color-success);
			}

			&--turn {
				border-color: var(--color-informative);
				background: var(--color-informative);
				// White in both modes: the drawn pencil sits on the blue, which stays bright in dark mode too.
				color: var(--color-white);
			}
		}

		&__step-copy {
			display: flex;
			flex-direction: column;
			align-items: flex-start;
			gap: var(--space-smaller);
			min-width: 0;

			p {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__step-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;

			&--done {
				color: var(--color-text--secondary);
			}
		}

		&__done {
			color: var(--color-success--onSurface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
		}

		&__link {
			display: inline-flex;
			align-self: flex-start;
			align-items: center;
			padding: 0;
			border: 0;
			background: none;
			cursor: pointer;
			gap: var(--space-smaller);
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-decoration: none;

			span {
				display: inline-flex;
				width: 14px;
				height: 14px;
			}

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: 2px;
				border-radius: var(--radius-small);
			}
		}

		&__account {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			align-self: stretch;
			margin-top: var(--space-small);
			padding: var(--space-slim) 14px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface--background--subtle);
		}

		&__account-copy {
			display: flex;
			flex: 1;
			flex-direction: column;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}
		}

		&__missing {
			margin-top: var(--space-small);
		}

		&__tick {
			margin-top: var(--space-small);
		}

		&__history {
			padding: var(--space-base) var(--space-large);
			border-top: var(--border-base) solid var(--color-border);

			h3 {
				margin: 0 0 var(--space-small);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-overline);
				font-weight: 600;
				letter-spacing: 0.04em;
				text-transform: uppercase;
			}

			ul {
				display: flex;
				flex-direction: column;
				gap: var(--space-small);
				margin: 0;
				padding: 0;
				list-style: none;
			}

			li {
				display: flex;
				align-items: center;
				gap: var(--space-small);
			}

			time {
				flex: none;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		&__history-text {
			flex: 1;
			min-width: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-slim);
			padding: var(--space-base) var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}

		&__foot-end {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}

		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}
	}
</style>
