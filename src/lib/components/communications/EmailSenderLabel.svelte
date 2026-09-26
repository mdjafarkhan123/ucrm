<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import {
		fetchResolvedEmailSender,
		resolvedEmailSenderKey,
		type ResolvedEmailSenderKind
	} from '$lib/communications/senders';

	// The "From" value of an email preview: the real address the send will use, read the same way the
	// send itself chooses it. It mounts only inside an opened dialog or composer, so it loads on reveal.
	let { kind }: { kind: ResolvedEmailSenderKind } = $props();

	const senderQuery = createQuery(() => ({
		queryKey: resolvedEmailSenderKey(kind),
		queryFn: () => fetchResolvedEmailSender(kind),
		staleTime: 60_000
	}));
	const sender = $derived(senderQuery.data);
</script>

{#if senderQuery.isPending}
	<span class="email-sender-label email-sender-label--muted">Loading sender…</span>
{:else if senderQuery.isError}
	<span class="email-sender-label email-sender-label--muted">Sender could not be loaded</span>
{:else if sender}
	<span class="email-sender-label">
		{sender.display_name}
		<span class="email-sender-label__address">&lt;{sender.email_address}&gt;</span>
	</span>
{:else}
	<span class="email-sender-label email-sender-label--warning">
		{kind === 'manual'
			? 'No email address is assigned to you yet'
			: 'No default business email address is set up yet'}
	</span>
{/if}

<style lang="scss">
	.email-sender-label {
		overflow-wrap: anywhere;

		&__address {
			color: var(--color-text--secondary);
		}

		&--muted {
			color: var(--color-text--secondary);
		}

		&--warning {
			color: var(--color-warning);
		}
	}
</style>
