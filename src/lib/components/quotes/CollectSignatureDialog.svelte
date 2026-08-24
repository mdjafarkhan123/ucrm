<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import SignaturePad from '$lib/components/quotes/SignaturePad.svelte';
	import { emptySignature } from '$lib/quotes/signature';
	import { untrack } from 'svelte';

	// The in-person close: the customer signs the tablet at their own door and the quote is approved.
	// Following Jobber, this is offered in every status the quote can still be answered in, and from a
	// draft the command publishes the version first so the signature has a document behind it.
	//
	// Jobber's pad also carries a "send your client a copy" checkbox. That is email, and email belongs to
	// Communications, so it is not here rather than here and doing nothing.

	let {
		open,
		clientName,
		saving = false,
		onClose,
		onCollect
	}: {
		open: boolean;
		/** Pre-fills the name, because the person signing is almost always the client. */
		clientName: string | null;
		saving?: boolean;
		onClose: () => void;
		onCollect: (input: {
			name: string;
			method: 'typed' | 'in_person';
			image: string | null;
			note: string;
		}) => Promise<void>;
	} = $props();

	// The page mounts this only while it is open, so the pad starts clean every time and the client's
	// name is filled in once, here, rather than being pushed in by an effect later.
	let signature = $state({ ...emptySignature(), name: untrack(() => clientName) ?? '' });
	let note = $state('');
	let problem = $state('');

	function close() {
		onClose();
	}

	async function submit() {
		if (saving) return;
		const name = signature.name.trim();
		if (!name) {
			problem = 'Type the name of the person signing.';
			return;
		}
		if (signature.method === 'drawn' && !signature.image) {
			problem = 'Ask them to sign, or switch to typing the name.';
			return;
		}

		problem = '';
		try {
			await onCollect({
				name,
				// The customer's own page records a drawing as `drawn`; the same drawing taken on our
				// device at their door is `in_person`, because that is what actually happened.
				method: signature.method === 'drawn' ? 'in_person' : 'typed',
				image: signature.image,
				note: note.trim()
			});
			close();
		} catch (error) {
			problem = error instanceof Error ? error.message : 'That signature could not be recorded.';
		}
	}
</script>

<Dialog {open} title="Collect signature" onClose={close}>
	<div class="collect-signature">
		<p class="collect-signature__lead">
			Signing here approves this quote and records who signed it. A quote still in draft is sent
			first, so the signature belongs to a real version.
		</p>

		<SignaturePad bind:value={signature} idPrefix="collect" disabled={saving} />

		<Textarea
			id="collect-signature-note"
			label="Note (optional)"
			bind:value={note}
			rows={2}
			maxlength={1000}
			disabled={saving}
		/>

		{#if problem}
			<p class="collect-signature__problem" role="alert">{problem}</p>
		{/if}

		<footer class="collect-signature__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={close}>
				Cancel
			</Button>
			<Button variant="primary" loading={saving} onclick={() => void submit()}>
				Approve with signature
			</Button>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	.collect-signature {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.collect-signature__lead {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-base);
	}

	.collect-signature__problem {
		margin: 0;
		color: var(--color-destructive);
		font-size: var(--typography--fontSize-base);
	}

	.collect-signature__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}
</style>
