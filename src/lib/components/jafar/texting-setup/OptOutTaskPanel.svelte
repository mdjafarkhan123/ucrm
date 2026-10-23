<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import PaperworkFlag from '$lib/components/communications/paperwork/PaperworkFlag.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import { OPT_OUT_LANGUAGES } from '$lib/communications/sms-opt-out-words';
	import {
		shortSid,
		whenAsked,
		TWILIO_MESSAGING_SERVICES_URL,
		type OptOutTask
	} from '$lib/jafar/texting-setup';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import replyIcon from '@tabler/icons/outline/corner-down-right.svg?raw';
	import externalIcon from '@tabler/icons/outline/external-link.svg?raw';

	// An opt-out words task (Stage 10 Part 5d, board `v6Jtu` "Add Spanish opt-out words"): the language's stop
	// and start words with Twilio's replies, to add in the business's Advanced Opt-Out, then "Mark as done".
	let {
		task,
		marking,
		onTick,
		onMark
	}: {
		task: OptOutTask;
		marking: boolean;
		/** The box was ticked: this is the task being worked on now. */
		onTick: () => void;
		onMark: () => void;
	} = $props();

	// The page draws a fresh panel for each task, so a new task starts unticked.
	let ticked = $state(false);
	let copied = $state<string | null>(null);

	const language = $derived(OPT_OUT_LANGUAGES[task.language]);
	const countries = $derived(task.countries.map(countryDisplayName).join(' and '));
	const service = $derived(
		task.messaging_service_sid ? ` (${shortSid(task.messaging_service_sid)})` : ''
	);
	const groups = $derived([
		{ title: 'Stop words', words: language.stop, reply: language.stopReply },
		{ title: 'Start again words', words: language.start, reply: language.startReply }
	]);

	async function copy(text: string) {
		try {
			await navigator.clipboard.writeText(text);
			copied = text;
		} catch {
			copied = null;
		}
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<section class="opt-out-panel" aria-labelledby="opt-out-panel-title">
	<header class="opt-out-panel__head">
		<PaperworkFlag code={task.countries[0]} size={40} />
		<div class="opt-out-panel__title">
			<div class="opt-out-panel__title-line">
				<h2 id="opt-out-panel-title">Add {language.name} opt-out words</h2>
				<StatusBadge status="warning">To do</StatusBadge>
			</div>
			<p>
				Needed before {task.organization_name} texts {countries} · {whenAsked(task.requested_at)}
			</p>
		</div>
	</header>

	<div class="opt-out-panel__body">
		<p class="opt-out-panel__line">
			Twilio only stops texts for the words it is told. Add these in Advanced Opt-Out on {task.organization_name}’s
			messaging service{service}.
		</p>

		{#each groups as group (group.title)}
			<div class="opt-out-panel__group">
				<h3>{group.title}</h3>
				<ul class="opt-out-panel__words">
					{#each group.words as word (word)}
						<li>{word}</li>
					{/each}
				</ul>
				<div class="opt-out-panel__reply">
					<span class="opt-out-panel__reply-icon" aria-hidden="true">{@html replyIcon}</span>
					<span class="opt-out-panel__reply-text">Reply: “{group.reply}”</span>
					<button
						type="button"
						class="opt-out-panel__copy"
						aria-label={`Copy the reply to ${group.title.toLowerCase()}`}
						title={copied === group.reply ? 'Copied' : 'Copy the reply'}
						onclick={() => copy(group.reply)}
						>{@html copied === group.reply ? checkIcon : copyIcon}</button
					>
				</div>
			</div>
		{/each}

		<div class="opt-out-panel__twilio">
			<Checkbox
				id="opt-out-ticked"
				label="I added these words in Twilio and saved"
				bind:checked={ticked}
				onchange={(checked) => checked && onTick()}
				disabled={marking}
			/>
			<Button
				variant="secondary"
				size="small"
				href={TWILIO_MESSAGING_SERVICES_URL}
				target="_blank"
				disabled={marking}
			>
				<span aria-hidden="true">{@html externalIcon}</span>
				Open in Twilio
			</Button>
		</div>
	</div>

	<footer class="opt-out-panel__foot">
		<span class="opt-out-panel__hint">{ticked ? '' : 'Tick the box first'}</span>
		<Button onclick={onMark} disabled={!ticked} loading={marking}>
			{#if !marking}<span aria-hidden="true">{@html checkIcon}</span>{/if}
			{marking ? 'Marking…' : 'Mark as done'}
		</Button>
	</footer>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.opt-out-panel {
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
				font-size: var(--typography--fontSize-small);
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

		&__body {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-base);
			padding: var(--space-base) var(--space-large);
		}

		&__line {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__group {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
		}

		&__words {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: inline-flex;
				align-items: center;
				height: 28px;
				padding: 0 var(--space-small);
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-circle);
				background: var(--color-surface--background--subtle);
				color: var(--color-heading);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 600;
			}
		}

		&__reply {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__reply-icon {
			display: inline-flex;
			flex: none;
			width: 14px;
			height: 14px;
			color: var(--color-text--secondary);
		}

		&__reply-text {
			flex: 1;
			min-width: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
		}

		&__copy {
			display: inline-flex;
			flex: none;
			align-items: center;
			justify-content: center;
			width: 24px;
			height: 24px;
			padding: var(--space-smaller);
			border: 0;
			border-radius: var(--radius-small);
			background: none;
			color: var(--color-text--secondary);
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
				color: var(--color-heading);
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: 1px;
			}
		}

		&__twilio {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			padding: var(--space-base) var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}

		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}
	}
</style>
