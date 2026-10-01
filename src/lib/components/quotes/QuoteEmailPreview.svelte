<script lang="ts">
	import EmailSenderLabel from '$lib/components/communications/EmailSenderLabel.svelte';

	// What the customer's quote email will say and who it goes to. Shared by the Quote page's Send email
	// dialog and the Pipeline's send window, so both always preview the one email the server builds.
	let {
		recipient,
		organizationName
	}: {
		recipient: string | null;
		organizationName: string;
	} = $props();
</script>

<div class="quote-email-preview">
	<dl class="quote-email-preview__details">
		<div>
			<dt>To</dt>
			<dd>{recipient ?? 'No active customer email address'}</dd>
		</div>
		<div>
			<dt>From</dt>
			<dd><EmailSenderLabel kind="business" /></dd>
		</div>
		<div>
			<dt>Subject</dt>
			<dd>Your quote from {organizationName}</dd>
		</div>
	</dl>

	<div class="quote-email-preview__message">
		<p>Your quote is ready to review.</p>
		<span class="quote-email-preview__link" aria-label="View your quote button preview"
			>View your quote</span
		>
		<p class="quote-email-preview__fallback">
			A secure fallback link is included in the delivered email.
		</p>
	</div>
</div>

<style lang="scss">
	.quote-email-preview {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__details {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;

			div {
				display: grid;
				grid-template-columns: 72px minmax(0, 1fr);
				gap: var(--space-small);
			}

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			dd {
				min-width: 0;
				margin: 0;
				color: var(--color-heading);
				font-weight: 600;
				overflow-wrap: anywhere;
			}
		}

		&__message {
			display: flex;
			flex-direction: column;
			align-items: flex-start;
			gap: var(--space-base);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text);

			p {
				margin: 0;
			}
		}

		&__link {
			display: inline-flex;
			align-items: center;
			min-height: 40px;
			padding: 0 var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-surface);
			background: var(--color-interactive);
			font-weight: 600;
		}

		&__fallback {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
