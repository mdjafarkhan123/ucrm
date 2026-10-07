<script lang="ts">
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import { countryName, type ContactMethodKind, type LeadDuplicate } from '$lib/jafar/leads';
	import { applicationHref } from '$lib/jafar/lead-history';
	import { jafarLeadsKey } from '$lib/jafar/query-keys';

	// Jafar business management: while a Lead's business or contact details are typed, anything already on file
	// that looks like the same business -- a Lead, an Application, or a client. Shown for review; saving is never
	// blocked by it and nothing is merged. Used by the add form and by editing on the Lead page, where the Lead
	// itself is left out.
	let {
		businessName,
		countryCode,
		website,
		contacts,
		excludeId,
		hint = 'Nothing is merged. Save anyway if this is a different business.'
	}: {
		businessName: string;
		countryCode: string;
		website: string;
		contacts: ReadonlyArray<{ kind: ContactMethodKind; value: string }>;
		/** The Lead being edited, which would otherwise match itself. */
		excludeId?: string;
		hint?: string;
	} = $props();

	type Probe = {
		business_name: string;
		country_code: string;
		website: string;
		emails: string[];
		phones: string[];
		exclude_id?: string;
	};
	let probe = $state<Probe>({
		business_name: '',
		country_code: '',
		website: '',
		emails: [],
		phones: []
	});

	// Waits for a pause in typing before asking, so a half-typed website does not fire a lookup per keystroke.
	$effect(() => {
		const name = businessName.trim();
		const next: Probe = {
			business_name: name.length >= 3 ? name : '',
			country_code: countryCode,
			website: website.trim(),
			emails: contacts
				.filter((row) => row.kind === 'email' && row.value.includes('@'))
				.map((row) => row.value.trim()),
			phones: contacts
				.filter(
					(row) =>
						(row.kind === 'phone' || row.kind === 'whatsapp') &&
						row.value.replace(/\D/g, '').length >= 7
				)
				.map((row) => row.value.trim()),
			...(excludeId ? { exclude_id: excludeId } : {})
		};
		const handle = setTimeout(() => (probe = next), 500);
		return () => clearTimeout(handle);
	});

	const probeHasInput = $derived(
		Boolean(probe.business_name || probe.website || probe.emails.length || probe.phones.length)
	);

	const duplicates = createQuery(() => ({
		queryKey: [...jafarLeadsKey, 'duplicates', probe] as const,
		queryFn: async () => {
			const response = await fetch('/api/jafar/leads/duplicates', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(probe)
			});
			const result = (await response.json()) as { duplicates?: LeadDuplicate[]; error?: string };
			if (!response.ok) throw new Error(result.error ?? 'The duplicate check is unavailable.');
			return result.duplicates ?? [];
		},
		enabled: probeHasInput,
		staleTime: 30_000,
		gcTime: 60_000
	}));

	const duplicateList = $derived(probeHasInput ? (duplicates.data ?? []) : []);

	const MATCH_WORDS = { website: 'website', email: 'email', phone: 'phone', name: 'name' } as const;
	function matchSentence(match: LeadDuplicate) {
		const words = match.matched_on.map((field) => MATCH_WORDS[field]);
		return words.length > 1
			? `Same ${words.slice(0, -1).join(', ')} and ${words.at(-1)}`
			: `Same ${words[0]}`;
	}
	function kindLabel(match: LeadDuplicate) {
		if (match.kind === 'application') return 'Application';
		if (match.kind === 'organization') return 'Client';
		return 'Lead';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if duplicateList.length > 0}
	<div class="lead-duplicates" role="status">
		<p class="lead-duplicates__title">
			<span aria-hidden="true">{@html alertTriangleIcon}</span>
			{duplicateList.length === 1
				? 'This may already be on file'
				: `This may already be on file ${duplicateList.length} times`}
		</p>
		<ul>
			{#each duplicateList as match (match.kind + match.id)}
				<li>
					<span class="lead-duplicates__kind">{kindLabel(match)}</span>
					{#if match.kind === 'organization'}
						<a
							href={resolve('/jafar/(protected)/organizations/[organizationId]', {
								organizationId: match.id
							})}>{match.name}</a
						>
					{:else if match.kind === 'lead'}
						<a href={resolve('/jafar/(protected)/leads/[id]', { id: match.id })}>{match.name}</a>
					{:else}
						<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- applicationHref resolves the path. -->
						<a href={applicationHref(match.id)}>{match.name}</a>
					{/if}
					{#if match.country_code}<span>· {countryName(match.country_code)}</span>{/if}
					<span class="lead-duplicates__why">{matchSentence(match)}</span>
				</li>
			{/each}
		</ul>
		<p class="lead-duplicates__hint">{hint}</p>
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.lead-duplicates {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-warning);
		border-radius: var(--radius-base);
		background: var(--color-warning--surface);
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);

		ul {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		li {
			display: flex;
			flex-wrap: wrap;
			align-items: baseline;
			gap: var(--space-smaller) var(--space-small);
		}

		a {
			color: var(--color-interactive);
			font-weight: 700;
		}

		&__title {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;

			:global(svg) {
				display: block;
				width: 18px;
				height: 18px;
			}
		}

		&__kind {
			padding: 0 var(--space-small);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: var(--color-text--secondary);
			font-weight: 600;
		}

		// Full-strength text: secondary grey is too faint on the warning tint.
		&__why,
		&__hint {
			color: var(--color-text);
		}
	}
</style>
