<script lang="ts">
	import worldIcon from '@tabler/icons/outline/world-www.svg?raw';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import type { PackageSummary } from '$lib/jafar/packages';

	// Package builder P7: the marketing site is edited by hand, so after a change to what sign-up lists the
	// package keeps this reminder until Jafar confirms the site matches. The CRM cannot check the site itself.
	let {
		name,
		changes,
		pending = false,
		onConfirm
	}: {
		name: string;
		changes: PackageSummary['website_changes'];
		pending?: boolean;
		onConfirm: () => void;
	} = $props();

	function phrase(change: PackageSummary['website_changes'][number]) {
		switch (change.event_type) {
			case 'published':
				return `edition ${change.edition_number} published`;
			case 'visibility_changed':
				return change.detail.to === 'public' ? 'made public' : 'made private';
			case 'moved':
				return 'moved in the list';
			case 'archived':
				return 'archived';
			case 'restored':
				return 'restored';
			default:
				return null;
		}
	}

	const summary = $derived(
		[...new Set(changes.map(phrase).filter((text) => text !== null))].join(', ')
	);
</script>

<Banner type="warning" icon={worldIcon}>
	<p>
		<strong>{name}</strong> changed{summary ? `: ${summary}` : ''}. Update your marketing site to
		match, then confirm here.
	</p>
	{#snippet action()}
		<Button size="small" variant="secondary" loading={pending} onclick={onConfirm}
			>I've updated the site</Button
		>
	{/snippet}
</Banner>
