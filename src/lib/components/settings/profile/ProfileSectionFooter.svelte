<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import compareIcon from '@tabler/icons/outline/git-compare.svg?raw';

	// The bar under an open section: a quiet hint, Cancel, and a Save named for the section.
	let {
		hint,
		saving,
		saveLabel,
		saveDisabled,
		showSeeTheirs = false,
		seeTheirsLoading = false,
		onCancel,
		onSave,
		onSeeTheirs
	}: {
		hint: string;
		saving: boolean;
		saveLabel: string;
		saveDisabled: boolean;
		showSeeTheirs?: boolean;
		seeTheirsLoading?: boolean;
		onCancel: () => void;
		onSave: () => void;
		onSeeTheirs: () => void;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<footer class="profile-footer">
	<p class="profile-footer__hint">{hint}</p>
	{#if showSeeTheirs}
		<Button variant="secondary" onclick={onSeeTheirs} loading={seeTheirsLoading}>
			<span aria-hidden="true">{@html compareIcon}</span>See their version
		</Button>
	{:else}
		<Button variant="secondary" onclick={onCancel} disabled={saving}>Cancel</Button>
	{/if}
	<Button onclick={onSave} loading={saving} disabled={saveDisabled}>
		<span aria-hidden="true">{@html checkIcon}</span>{saveLabel}
	</Button>
</footer>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.profile-footer {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-medium);
		background: var(--color-surface--background--subtle);
		border-top: var(--border-base) solid var(--color-border);

		&__hint {
			flex: 1;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}
	}
</style>
