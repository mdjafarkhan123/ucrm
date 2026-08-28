<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ClientPicker from '$lib/components/work/ClientPicker.svelte';

	// One "pick a client, then act" dialog, shared by every Conversations action that needs a client it does
	// not have yet: linking a guarded conversation, and starting a new one. Purely presentational -- the page
	// owns the mutation and cache invalidation, the same way it does for resend, assign, and follow.
	let {
		open,
		title,
		lead,
		notice = '',
		confirmLabel,
		pending = false,
		errorMessage = '',
		suggestions = [],
		onCancel,
		onConfirm
	}: {
		open: boolean;
		title: string;
		/** Plain text; the caller has already resolved any names or addresses into it. */
		lead: string;
		notice?: string;
		confirmLabel: string;
		pending?: boolean;
		errorMessage?: string;
		/** The candidates a conflicting-identity Website Chat session already matched -- offered as a
		 *  quick pick above the search field. UCRM never picks between them; a person still confirms. */
		suggestions?: { clientId: string; clientName: string; matchedOn: string }[];
		onCancel: () => void;
		onConfirm: (clientId: string) => void;
	} = $props();

	// The parent renders this only while an action is in flight, so closing destroys the component and the
	// picked client resets on its own -- no reset effect needed.
	let clientId = $state('');
</script>

<Dialog {open} {title} size="small" onClose={onCancel}>
	<div class="choose-client">
		<p class="choose-client__lead">{lead}</p>
		{#if suggestions.length > 0}
			<div class="choose-client__suggestions">
				<p class="choose-client__suggestions-label">Possible matches</p>
				{#each suggestions as candidate (candidate.clientId)}
					<button
						type="button"
						class="choose-client__suggestion"
						class:choose-client__suggestion--active={clientId === candidate.clientId}
						onclick={() => (clientId = candidate.clientId)}
					>
						<strong>{candidate.clientName}</strong>
						<small>Matched on {candidate.matchedOn}</small>
					</button>
				{/each}
			</div>
		{/if}
		<!-- ClientPicker renders its own "Client" label. -->
		<ClientPicker
			id="choose-client-client"
			required
			placeholder="Search by name or company"
			onSelect={(client) => (clientId = client?.id ?? '')}
		/>
		{#if notice}<p class="choose-client__notice">{notice}</p>{/if}
		{#if errorMessage}<p class="choose-client__error" role="alert">{errorMessage}</p>{/if}
		<footer class="choose-client__footer">
			<Button variant="secondary" onclick={onCancel} disabled={pending}>Cancel</Button>
			<Button
				variant="primary"
				loading={pending}
				disabled={!clientId}
				onclick={() => onConfirm(clientId)}>{confirmLabel}</Button
			>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	/* Dialog content is portaled out of this component's subtree, so its styles have to be global. */
	:global(.choose-client) {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}
	:global(.choose-client__lead) {
		color: var(--color-text);
	}
	:global(.choose-client__suggestions) {
		display: grid;
		gap: var(--space-smaller);
	}
	:global(.choose-client__suggestions-label) {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}
	:global(.choose-client__suggestion) {
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: var(--color-surface);
		text-align: left;
		cursor: pointer;
	}
	:global(.choose-client__suggestion:hover) {
		background: var(--color-surface--hover);
	}
	:global(.choose-client__suggestion small) {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	:global(.choose-client__suggestion--active) {
		border-color: var(--color-interactive);
		background: var(--color-surface--active);
	}
	:global(.choose-client__notice) {
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: var(--color-surface--active);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}
	:global(.choose-client__error) {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	:global(.choose-client__footer) {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
