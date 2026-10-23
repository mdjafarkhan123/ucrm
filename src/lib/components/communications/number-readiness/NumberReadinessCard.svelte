<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import PaperworkFlag from '$lib/components/communications/paperwork/PaperworkFlag.svelte';
	import type {
		NumberCard,
		ReadinessAction,
		ReadinessStatus,
		StepState
	} from '$lib/communications/number-readiness';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import loaderIcon from '@tabler/icons/outline/loader.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import phoneCallIcon from '@tabler/icons/outline/phone-call.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import fileXIcon from '@tabler/icons/outline/file-x.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import pauseIcon from '@tabler/icons/outline/player-pause.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import filePencilIcon from '@tabler/icons/outline/file-pencil.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import walletIcon from '@tabler/icons/outline/wallet.svg?raw';
	import calendarXIcon from '@tabler/icons/outline/calendar-x.svg?raw';
	import phoneOffIcon from '@tabler/icons/outline/phone-off.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	// One texting number on Phone & SMS (`concept.pen` board `NbWfA`, Approved B): who it is, its four steps as a
	// little journey, what it can do, and a band at the foot saying where it stands with the one button to press.
	// Rename and Make default stay from the live page, in the ⋯ menu; renaming happens in the card. Part 7 adds the
	// renewal strip between the steps and the band (board `QiDBX`, Approved B).
	let {
		card,
		renaming,
		renameSaving,
		defaultSaving,
		actionLoading = false,
		onStartRename,
		onCancelRename,
		onSaveRename,
		onMakeDefault,
		onAction,
		renameDraft = $bindable('')
	}: {
		card: NumberCard;
		renaming: boolean;
		renameSaving: boolean;
		defaultSaving: boolean;
		actionLoading?: boolean;
		onStartRename: () => void;
		onCancelRename: () => void;
		onSaveRename: () => void;
		onMakeDefault: () => void;
		onAction: (action: ReadinessAction) => void;
		renameDraft?: string;
	} = $props();

	const STEP_ICONS: Partial<Record<StepState, string>> = {
		done: checkIcon,
		waiting: hourglassIcon,
		connecting: loaderIcon,
		your_turn: pencilIcon,
		failed: xIcon,
		paused: pauseIcon,
		ended: xIcon
	};

	const BAND: Record<ReadinessStatus, { tone: string; icon: string }> = {
		business_details_needed: { tone: 'informative', icon: buildingIcon },
		under_review: { tone: 'warning', icon: hourglassIcon },
		action_needed: { tone: 'critical', icon: fileXIcon },
		ready_to_text: { tone: 'success', icon: circleCheckIcon },
		getting_ready: { tone: 'warning', icon: loaderIcon },
		texting_paused: { tone: 'critical', icon: pauseIcon },
		sending_paused: { tone: 'critical', icon: pauseIcon },
		released: { tone: 'inactive', icon: phoneOffIcon }
	};

	const STRIP_ICONS = {
		paid: refreshIcon,
		short: walletIcon,
		unpaid: calendarXIcon,
		released: phoneOffIcon
	};

	const ACTION_ICONS: Record<ReadinessAction['kind'], string> = {
		add_business_details: pencilIcon,
		fix_business_details: filePencilIcon,
		see_business_details: eyeIcon,
		toll_free_check: filePencilIcon,
		update_paperwork: filePencilIcon,
		see_paperwork: eyeIcon,
		add_number: plusIcon
	};

	const band = $derived(card.status ? BAND[card.status] : null);
	const urgent = $derived(
		card.status === 'action_needed' ||
			card.status === 'texting_paused' ||
			card.status === 'sending_paused' ||
			card.renewal?.tone === 'unpaid'
	);
	const abilities = $derived(
		[
			card.capabilities.sms ? { label: 'Texts', icon: messageIcon } : null,
			card.capabilities.mms ? { label: 'Picture messages', icon: photoIcon } : null,
			card.capabilities.voice ? { label: 'Calls', icon: phoneCallIcon } : null
		].filter((ability) => ability !== null)
	);
	const menuItems = $derived([
		{ label: 'Rename', icon: pencilIcon, onSelect: onStartRename },
		...(card.is_default
			? []
			: [
					{
						label: 'Make default',
						icon: starIcon,
						onSelect: onMakeDefault,
						disabled: !card.can_be_default,
						hint: card.can_be_default ? undefined : 'Once this number can text'
					}
				])
	]);
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<article class="number-readiness" class:number-readiness--urgent={urgent}>
	<div class="number-readiness__top">
		<header class="number-readiness__head">
			<PaperworkFlag code={card.country_code} size={40} />
			{#if renaming}
				<form
					class="number-readiness__rename"
					onsubmit={(event) => {
						event.preventDefault();
						onSaveRename();
					}}
				>
					<div class="number-readiness__rename-row">
						<Input
							id={`number-name-${card.key}`}
							aria-label="Number name"
							maxlength={60}
							placeholder={card.name}
							bind:value={renameDraft}
							class="number-readiness__rename-field"
						/>
						<Button
							type="button"
							size="small"
							variant="quiet"
							disabled={renameSaving}
							onclick={onCancelRename}>Cancel</Button
						>
						<Button type="submit" size="small" loading={renameSaving}>
							<span aria-hidden="true">{@html checkIcon}</span>
							Save name
						</Button>
					</div>
					<p class="number-readiness__detail">{card.detail}</p>
				</form>
			{:else}
				<div class="number-readiness__identity">
					<div class="number-readiness__name-row">
						<h3 class="number-readiness__name">{card.name}</h3>
						{#if card.is_default}
							<span class="number-readiness__default">
								<span aria-hidden="true">{@html starIcon}</span>
								Default
							</span>
						{/if}
					</div>
					<p class="number-readiness__detail">{card.detail}</p>
				</div>
				{#if card.sender_id && !card.released}
					<DropdownMenu
						items={menuItems}
						wide
						triggerLabel={`More for ${card.name}`}
						disabled={defaultSaving}
					/>
				{/if}
			{/if}
		</header>

		<ol
			class="number-readiness__journey"
			class:number-readiness__journey--ended={card.released}
			aria-label="Steps for this number"
		>
			{#each card.steps as step, index (step.key)}
				<li
					class="number-readiness__step number-readiness__step--{step.state}"
					class:number-readiness__step--done-before={index > 0 &&
						card.steps[index - 1].state === 'done' &&
						step.state === 'done'}
				>
					<span class="number-readiness__circle" aria-hidden="true">
						{#if STEP_ICONS[step.state]}{@html STEP_ICONS[step.state]}{:else}{index + 1}{/if}
					</span>
					<span class="number-readiness__step-name">{step.label}</span>
					<span class="number-readiness__step-hint">{step.hint}</span>
				</li>
			{/each}
		</ol>

		{#if abilities.length && !card.released}
			<ul class="number-readiness__abilities" aria-label="What this number can do">
				{#each abilities as ability (ability.label)}
					<li class="number-readiness__ability">
						<span aria-hidden="true">{@html ability.icon}</span>
						{ability.label}
					</li>
				{/each}
			</ul>
		{/if}
	</div>

	{#if card.renewal}
		{@const strip = card.renewal}
		<section
			class="number-readiness__renewal number-readiness__renewal--{strip.tone}"
			aria-label="Monthly renewal"
		>
			<div class="number-readiness__renewal-head">
				<span class="number-readiness__renewal-tile" aria-hidden="true"
					>{@html STRIP_ICONS[strip.tone]}</span
				>
				<div class="number-readiness__renewal-text">
					<span class="number-readiness__renewal-eyebrow">{strip.eyebrow}</span>
					<strong>{strip.headline}</strong>
					{#if strip.note}<span class="number-readiness__renewal-note">{strip.note}</span>{/if}
				</div>
				{#if strip.add_money}
					<Button size="small" variant="secondary" href="/settings/communications/balance">
						<span aria-hidden="true">{@html walletIcon}</span>
						Add money
					</Button>
				{/if}
			</div>
			{#if strip.meter}
				{@const meter = strip.meter}
				<div class="number-readiness__meter">
					<div class="number-readiness__meter-words">
						<span class="number-readiness__meter-left">{meter.left}</span>
						<span>{meter.right}</span>
					</div>
					{#if meter.kind === 'days'}
						<span
							class="number-readiness__days"
							role="meter"
							aria-label="Days left to renew"
							aria-valuemin={0}
							aria-valuemax={meter.total}
							aria-valuenow={meter.days_left}
						>
							{#each Array.from({ length: meter.total }, (_, index) => index) as day (day)}
								<span
									class="number-readiness__day"
									class:number-readiness__day--used={day < meter.total - meter.days_left}
								></span>
							{/each}
						</span>
					{:else}
						<span
							class="number-readiness__bar"
							role="meter"
							aria-label="How much of the price your balance covers"
							aria-valuemin={0}
							aria-valuemax={100}
							aria-valuenow={Math.round(meter.fraction * 100)}
						>
							<span
								class="number-readiness__bar-fill"
								style:width="{Math.min(100, Math.max(0, meter.fraction * 100))}%"
							></span>
						</span>
					{/if}
				</div>
			{/if}
		</section>
	{/if}

	{#if band && card.status}
		<footer class="number-readiness__band number-readiness__band--{band.tone}" role="status">
			<span class="number-readiness__band-tile" aria-hidden="true">{@html band.icon}</span>
			<div class="number-readiness__band-text">
				<strong>{card.title}</strong>
				<span>{card.line}</span>
			</div>
			{#if card.action}
				{@const action = card.action}
				<Button
					size="small"
					variant="secondary"
					loading={actionLoading}
					onclick={() => onAction(action)}
				>
					<span aria-hidden="true">{@html ACTION_ICONS[action.kind]}</span>
					{action.label}
				</Button>
			{/if}
		</footer>
	{/if}
</article>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.number-readiness {
		display: flex;
		flex-direction: column;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&--urgent {
			border: 1.5px solid var(--color-critical);
		}

		&__top {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 18px;
			padding: var(--space-medium);
		}

		&__head {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}

		&__identity {
			display: grid;
			flex: 1 1 auto;
			gap: var(--space-smallest);
			min-width: 0;
		}

		&__name-row {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;
		}

		&__name {
			overflow: hidden;
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
			line-height: var(--typography--lineHeight-base);
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__default {
			display: inline-flex;
			flex: none;
			align-items: center;
			gap: var(--space-smaller);
			padding: 3px 9px;
			border-radius: var(--radius-circle);
			color: var(--color-heading);
			background: var(--color-inactive--surface);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}

		&__detail {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}

		&__rename {
			display: grid;
			flex: 1 1 auto;
			gap: var(--space-smaller);
			min-width: 0;
		}

		&__rename-row {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			:global(.number-readiness__rename-field) {
				flex: 1 1 auto;
			}

			:global(.button) {
				flex: none;
				white-space: nowrap;
			}

			:global(.number-readiness__rename-field .input__control) {
				border: 1.5px solid var(--color-interactive);
			}

			:global(.number-readiness__rename-field input) {
				height: 36px;
			}
		}

		&__journey--ended {
			opacity: 0.45;
		}

		&__journey {
			display: grid;
			grid-template-columns: repeat(4, minmax(0, 1fr));
			margin: 0;
			padding: 14px var(--space-slim);
			border-radius: var(--radius-tile-large);
			background: var(--color-surface--background--subtle);
			list-style: none;
		}

		&__step {
			position: relative;
			display: grid;
			justify-items: center;
			gap: var(--space-smaller);
			text-align: center;

			// The 2px line joining this step's circle to the one before it.
			& + &::before {
				position: absolute;
				top: 13px;
				right: calc(50% + 22px);
				left: calc(-50% + 22px);
				height: 2px;
				border-radius: var(--radius-circle);
				background: var(--color-border);
				content: '';
			}

			&--done-before::before {
				background: var(--color-success--surface-edge) !important;
			}
		}

		&__circle {
			display: grid;
			place-items: center;
			width: 28px;
			height: 28px;
			margin-bottom: var(--space-smaller);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			color: var(--color-text--secondary);
			background: var(--color-surface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		@each $state,
			$tone
				in (
					done: success,
					waiting: warning,
					connecting: warning,
					your_turn: informative,
					failed: critical,
					paused: critical,
					ended: inactive
				)
		{
			&__step--#{$state} &__circle {
				border-color: var(--color-#{$tone}--surface-edge);
				color: var(--color-#{$tone});
				background: var(--color-#{$tone}--surface);
			}
		}

		&__step--waiting &__circle,
		&__step--connecting &__circle {
			color: var(--color-warning--onSurface);
		}

		&__step--connecting &__circle :global(svg) {
			animation: number-readiness-spin 1s linear infinite;
		}

		&__step-name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
		}

		&__step-hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}

		&__step--failed &__step-hint,
		&__step--paused &__step-hint {
			color: var(--color-critical--onSurface);
		}

		&__abilities {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__ability {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			height: 28px;
			padding: 0 10px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			color: var(--color-heading);
			background: var(--color-surface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;

			:global(svg) {
				width: 14px;
				height: 14px;
				color: var(--color-conversation);
			}
		}

		&__band {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 14px var(--space-medium);

			:global(.button) {
				flex: none;
				margin-left: auto;
			}
		}

		@each $tone in (informative, warning, critical, success, inactive) {
			&__band--#{$tone} {
				color: var(--color-#{$tone}--onSurface);
				background: var(--color-#{$tone}--surface);

				.number-readiness__band-tile {
					border-color: var(--color-#{$tone}--surface-edge);
					color: var(--color-#{$tone});
				}
			}
		}

		&__band--warning &__band-tile {
			color: var(--color-warning--onSurface);
		}

		// The renewal strip (design `layout.md` § Number readiness, Renewal strip).
		&__renewal {
			display: grid;
			gap: var(--space-slim);
			padding: 14px var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);

			:global(.button) {
				flex: none;
				margin-left: auto;
			}
		}

		&__renewal-head {
			display: flex;
			align-items: center;
			gap: var(--space-base);
		}

		&__renewal-tile {
			display: grid;
			flex: none;
			place-items: center;
			width: 32px;
			height: 32px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-conversation);
			background: var(--color-surface);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__renewal-text {
			display: grid;
			gap: var(--space-smallest);
			min-width: 0;
			color: var(--color-heading);

			strong {
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
		}

		&__renewal-eyebrow {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__renewal-note {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}

		&__meter {
			display: grid;
			gap: var(--space-small);
		}

		&__meter-words {
			display: flex;
			justify-content: space-between;
			gap: var(--space-slim);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}

		&__meter-left {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__bar {
			display: block;
			overflow: hidden;
			height: 8px;
			border-radius: var(--radius-circle);
			background: var(--color-border);
		}

		&__bar-fill {
			display: block;
			height: 100%;
			border-radius: var(--radius-circle);
			background: var(--color-success);
		}

		&__days {
			display: grid;
			grid-template-columns: repeat(14, minmax(0, 1fr));
			gap: var(--space-smaller);
		}

		&__day {
			height: 8px;
			border-radius: var(--radius-circle);
			background: var(--color-critical--surface-edge);

			&--used {
				background: var(--color-critical);
			}
		}

		&__renewal--short {
			border-top-color: var(--color-warning--surface-edge);
			background: var(--color-warning--surface);

			.number-readiness__renewal-tile {
				border-color: var(--color-warning--surface-edge);
				color: var(--color-warning--onSurface);
			}

			.number-readiness__renewal-eyebrow,
			.number-readiness__meter-words {
				color: var(--color-warning--onSurface);
			}

			.number-readiness__bar {
				background: var(--color-warning--surface-edge);
			}

			.number-readiness__bar-fill {
				background: var(--color-warning);
			}
		}

		&__renewal--unpaid {
			border-top-color: var(--color-critical--surface-edge);
			background: var(--color-critical--surface);

			.number-readiness__renewal-tile {
				border-color: var(--color-critical--surface-edge);
				color: var(--color-critical);
			}

			.number-readiness__renewal-eyebrow,
			.number-readiness__meter-words {
				color: var(--color-critical--onSurface);
			}
		}

		&__renewal--released .number-readiness__renewal-tile {
			color: var(--color-inactive);
		}

		&__band-tile {
			display: grid;
			flex: none;
			place-items: center;
			width: 32px;
			height: 32px;
			border: var(--border-base) solid;
			border-radius: var(--radius-base);
			background: var(--color-surface);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__band-text {
			display: grid;
			gap: var(--space-smallest);
			min-width: 0;

			strong {
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			span {
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}
		}
	}

	@keyframes number-readiness-spin {
		to {
			transform: rotate(360deg);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.number-readiness__step--connecting .number-readiness__circle :global(svg) {
			animation: none;
		}
	}
</style>
