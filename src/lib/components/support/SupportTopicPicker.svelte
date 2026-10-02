<script lang="ts">
	import { SUPPORT_TOPICS, type SupportTopic } from '$lib/support/api';

	// "What's this about?" above a new chat's first message (D4a). Optional: Other is chosen until the person
	// picks something else. Native radios, drawn as chips, so arrow keys move between them.
	let {
		value = $bindable('other'),
		disabled = false
	}: {
		value?: SupportTopic;
		disabled?: boolean;
	} = $props();

	const name = $props.id();
</script>

<fieldset class="support-topic-picker" {disabled}>
	<legend class="support-topic-picker__legend">What's this about? <span>Optional</span></legend>
	<div class="support-topic-picker__chips">
		{#each SUPPORT_TOPICS as topic (topic.value)}
			<label class="support-topic-picker__chip">
				<input type="radio" {name} value={topic.value} bind:group={value} />
				<span>{topic.label}</span>
			</label>
		{/each}
	</div>
</fieldset>

<style lang="scss">
	.support-topic-picker {
		margin: 0;
		padding: 0;
		border: 0;
		min-width: 0;
	}

	.support-topic-picker__legend {
		margin-bottom: var(--space-small);
		padding: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;

		span {
			color: var(--color-text--secondary);
			font-weight: 400;
		}
	}

	.support-topic-picker__chips {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.support-topic-picker__chip {
		position: relative;
		display: inline-flex;
		cursor: pointer;

		input {
			position: absolute;
			opacity: 0;
			pointer-events: none;
		}

		span {
			display: inline-flex;
			align-items: center;
			min-height: 32px;
			padding: 0 var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			color: var(--color-text);
			background: var(--color-surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			transition:
				background var(--timing-quick) ease,
				border-color var(--timing-quick) ease;
		}

		&:hover span {
			background: var(--color-surface--hover);
		}

		input:checked + span {
			border-color: var(--color-interactive);
			color: var(--color-heading);
			background: var(--color-surface--active);
			font-weight: 600;
		}

		input:focus-visible + span {
			box-shadow: var(--shadow-focus);
		}
	}

	.support-topic-picker:disabled .support-topic-picker__chip {
		cursor: default;
		opacity: 0.6;
	}
</style>
