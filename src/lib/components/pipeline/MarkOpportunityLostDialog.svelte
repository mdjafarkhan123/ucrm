<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import requestIcon from '@tabler/icons/outline/inbox.svg?raw';
	import quoteIcon from '@tabler/icons/outline/file-text.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import lostIcon from '@tabler/icons/outline/circle-x.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import {
		markOpportunityLost,
		setLostReason,
		OutcomeWriteError,
		fetchLostReasons,
		lostReasonsKey,
		type LostReason,
		type OutcomeCommandResult
	} from '$lib/pipeline/api';

	// The card's `Mark as lost` action, and the same reason-and-note form reused to classify a record that
	// is already Lost. Owns its own write, the same way `TaskDialog` does — there is no page draft to stage
	// into, so Save writes straight away and the caller only has to react to the result.
	let {
		open,
		opportunityId,
		subject = 'request',
		existing,
		subtitle,
		onSaved,
		onClose
	}: {
		open: boolean;
		opportunityId: string;
		// What the card stands for, so the notice says what really happens to it.
		subject?: 'request' | 'quote';
		// The header's quiet line naming the record, e.g. "Request · Kitchen remodel · Dana Ortiz".
		subtitle?: string;
		// Set when the record is already Lost: the dialog then only saves its reason and note. A customer's
		// decline arrives with their own words and no reason, so those words are shown above the form.
		existing?: { reason: LostReason | null; note: string | null; customerMessage: string | null };
		// A fresh Lost carries the command's result; saving a reason on an existing one carries nothing.
		onSaved: (result?: OutcomeCommandResult) => void;
		onClose: () => void;
	} = $props();

	// Read once: the dialog is mounted per open, and the form is the user's from then on.
	// svelte-ignore state_referenced_locally
	const classifying = existing !== undefined;

	// The organization's own list. The card menu warms it on hover, so it is usually here already. A
	// retired reason is offered only to the record that already carries it, so editing that record's note
	// does not silently drop its reason.
	const reasonsQuery = createQuery(() => ({
		queryKey: lostReasonsKey,
		queryFn: fetchLostReasons,
		staleTime: 5 * 60_000
	}));
	const reasonOptions = $derived([
		{ value: '', label: reasonsQuery.isPending ? 'Loading reasons…' : 'No reason selected' },
		...(reasonsQuery.data ?? [])
			.filter((option) => option.retired_at === null || option.key === existing?.reason)
			.map((option) => ({
				value: option.key,
				label: option.retired_at === null ? option.label : `${option.label} (retired)`
			}))
	]);

	// svelte-ignore state_referenced_locally
	let reason = $state<string>(existing?.reason ?? '');
	// svelte-ignore state_referenced_locally
	let note = $state(existing?.note ?? '');
	let saving = $state(false);
	const toast = getToastManager();
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	// Minted once per open, not per submit — a retried submit after a dropped response carries the same
	// key, so the server recognises it as a repeat instead of a second Lost event.
	let idempotencyKey = crypto.randomUUID();

	const noteRequired = $derived(reason === 'other');

	async function save() {
		if (saving) return;
		saving = true;
		formError = '';
		fieldErrors = {};
		try {
			const input = {
				reason: (reason || null) as LostReason | null,
				note: note.trim() || null
			};
			if (classifying) {
				await setLostReason(opportunityId, input);
				toast.success('Lost reason saved');
				onSaved();
			} else {
				const result = await markOpportunityLost(opportunityId, { idempotencyKey, ...input });
				toast.success('Marked as lost');
				onSaved(result);
			}
		} catch (thrown) {
			if (thrown instanceof OutcomeWriteError) {
				fieldErrors = thrown.fieldErrors;
				formError =
					fieldErrors.form ?? (Object.keys(fieldErrors).length === 0 ? thrown.message : '');
			} else {
				formError =
					thrown instanceof Error
						? thrown.message
						: classifying
							? 'That reason could not be saved.'
							: 'That opportunity could not be marked lost.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title={classifying ? 'Lost reason' : 'Mark as lost'}
	{subtitle}
	icon={subject === 'quote' ? quoteIcon : requestIcon}
	iconTone={subject}
	onClose={saving ? () => {} : onClose}
>
	<div class="lost-dialog">
		{#if formError}<Banner type="error">{formError}</Banner>{/if}

		{#if classifying}
			{#if existing?.customerMessage}
				<div class="lost-dialog__quoted">
					<span class="lost-dialog__quoted-label">What the customer said</span>
					<p class="lost-dialog__message">{existing.customerMessage}</p>
				</div>
			{/if}
			<p class="lost-dialog__private">
				<span aria-hidden="true">{@html lockIcon}</span>
				Only your team sees this reason. It is used to report why work was lost.
			</p>
		{:else if subject === 'quote'}
			<Banner type="warning">
				This quote will leave the board and be archived, and its tasks will be removed. The amount
				the customer last saw is kept as the lost value.
			</Banner>
		{:else}
			<Banner type="warning">
				This request will leave the board, be archived, and its open tasks will be marked complete.
			</Banner>
		{/if}

		<Select
			id="lost-dialog-reason"
			label="Reason (optional)"
			bind:value={reason}
			options={reasonOptions}
			disabled={reasonsQuery.isPending || saving}
		/>

		<div class="lost-dialog__note">
			<Textarea
				id="lost-dialog-note"
				label={noteRequired ? 'Note (required for “Other”)' : 'Note (optional)'}
				rows={4}
				maxlength={1000}
				showCount={false}
				bind:value={note}
				disabled={saving}
				invalid={Boolean(fieldErrors.note)}
				errorMessage={fieldErrors.note}
			/>
			<p class="lost-dialog__count">{note.length.toLocaleString('en-US')} / 1,000</p>
		</div>
	</div>

	{#snippet footer()}
		<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}
			>Cancel</Button
		>
		<Button
			variant="primary"
			variation={classifying ? 'work' : 'destructive'}
			disabled={noteRequired && note.trim().length === 0}
			loading={saving}
			onclick={() => void save()}
		>
			{@html classifying ? checkIcon : lostIcon}
			{classifying ? 'Save reason' : 'Mark as lost'}
		</Button>
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.lost-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__quoted {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			padding: var(--space-small) var(--space-slim);
			border-left: 3px solid var(--color-border);
			background: var(--color-surface--background);
			border-radius: var(--radius-small);
		}
		&__quoted-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__message {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-large);
			white-space: pre-wrap;
			overflow-wrap: anywhere;
		}
		&__note {
			position: relative;
			padding-bottom: var(--space-base);
		}
		// Takes the place of the box's own "N left" count, at the same spot under it.
		&__count {
			position: absolute;
			right: 0;
			bottom: 0;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
		&__private {
			display: flex;
			align-items: center;
			gap: var(--space-smaller);
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;

			:global(svg) {
				width: 14px;
				height: 14px;
				flex: 0 0 auto;
			}
		}
	}
</style>
