<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import {
		recordMarketingConsent,
		ClientWriteError,
		type MarketingConsentState
	} from '$lib/clients/api';

	let {
		open,
		clientId,
		consent,
		onSaved,
		onClose
	}: {
		open: boolean;
		clientId: string;
		consent: MarketingConsentState;
		onSaved: (next: MarketingConsentState) => void;
		onClose: () => void;
	} = $props();

	// The likely reason to open this is to record the opposite of what stands now: someone opted in usually
	// gets here to be taken off, and everyone else to be added. The dialog is mounted fresh each time it
	// opens, so seeding from the state consent held at open (untracked) is deliberate, not a missed update.
	let decision = $state<'opt_in' | 'opt_out'>(
		untrack(() => (consent.state === 'opted_in' ? 'opt_out' : 'opt_in'))
	);
	let note = $state('');
	let saving = $state(false);
	let error = $state('');

	async function save() {
		if (saving) return;
		saving = true;
		error = '';
		try {
			const next = await recordMarketingConsent(clientId, {
				contact_method_id: consent.contact_method_id,
				decision,
				note: note.trim() || undefined
			});
			onSaved(next);
		} catch (caught) {
			error =
				caught instanceof ClientWriteError || caught instanceof Error
					? caught.message
					: 'That consent change could not be recorded.';
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Record marketing consent" size="default" {onClose}>
	<p class="marketing-consent__lead">
		Log what {consent.email} told you about marketing emails. This is kept as a dated record of their
		real preference — only record what they actually agreed to.
	</p>

	<fieldset class="marketing-consent__choice">
		<legend class="marketing-consent__legend">Their preference</legend>

		<label
			class="marketing-consent__option"
			class:marketing-consent__option--active={decision === 'opt_in'}
		>
			<input type="radio" name="marketing-decision" value="opt_in" bind:group={decision} />
			<span class="marketing-consent__option-body">
				<span class="marketing-consent__option-title">They agreed to marketing emails</span>
				<span class="marketing-consent__option-hint">
					They gave clear permission, by phone, in person, or in writing.
				</span>
			</span>
		</label>

		<label
			class="marketing-consent__option"
			class:marketing-consent__option--active={decision === 'opt_out'}
		>
			<input type="radio" name="marketing-decision" value="opt_out" bind:group={decision} />
			<span class="marketing-consent__option-body">
				<span class="marketing-consent__option-title"
					>They asked not to receive marketing emails</span
				>
				<span class="marketing-consent__option-hint">
					They opted out or asked to be taken off marketing.
				</span>
			</span>
		</label>
	</fieldset>

	<Textarea
		id="marketing-consent-note"
		label="How they told you (optional)"
		bind:value={note}
		rows={3}
		maxlength={500}
		placeholder="e.g. Confirmed over the phone during the quote call."
	/>

	{#if error}
		<p class="marketing-consent__error" role="alert">{error}</p>
	{/if}

	<footer class="marketing-consent__footer">
		<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
		<Button variant="primary" onclick={save} loading={saving}>Record</Button>
	</footer>
</Dialog>

<style lang="scss">
	.marketing-consent {
		&__lead {
			margin-bottom: var(--space-base);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__choice {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0 0 var(--space-base);
			padding: 0;
			border: none;
		}

		&__legend {
			margin-bottom: var(--space-slim);
			padding: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__option {
			display: flex;
			gap: var(--space-small);
			align-items: flex-start;
			padding: var(--space-base);
			border: 1px solid var(--color-border);
			border-radius: var(--radius-base);
			cursor: pointer;
			transition:
				border-color 0.15s ease,
				background 0.15s ease;

			&:hover {
				border-color: var(--color-border--interactive);
			}

			&--active {
				border-color: var(--color-brand);
				background: var(--color-surface--active);
			}

			input {
				margin-top: 2px;
				accent-color: var(--color-brand);
			}
		}

		&__option-body {
			display: flex;
			flex-direction: column;
			gap: 2px;
		}

		&__option-title {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__option-hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: var(--space-base) 0 0;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: var(--typography--fontSize-small);
		}

		&__footer {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-large);
		}
	}
</style>
