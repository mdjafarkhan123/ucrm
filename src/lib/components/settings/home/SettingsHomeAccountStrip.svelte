<script lang="ts">
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import cameraIcon from '@tabler/icons/outline/camera.svg?raw';
	import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';

	// Your account (Pencil: Batch 63, You strip): the signed-in person's own settings, kept apart from the
	// business's. The photo opens its pop-up; security and alerts are their own pages.
	let {
		userId,
		name,
		role,
		avatarUrl,
		securityHref,
		alertsHref,
		onPhoto
	}: {
		userId: string;
		name: string;
		role: string;
		avatarUrl: string | null;
		securityHref: string;
		alertsHref: string;
		onPhoto: () => void;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="home-account" aria-labelledby="settings-account-title">
	<div class="home-account__who">
		<Avatar id={userId} {name} src={avatarUrl} size="large" />
		<div class="home-account__copy">
			<h2 id="settings-account-title" class="home-account__title">Your account</h2>
			<p class="home-account__sub">{name} · <span class="home-account__role">{role}</span></p>
		</div>
	</div>
	<button type="button" class="home-account__cell" onclick={onPhoto}>
		<IconTile icon={cameraIcon} tone="inactive" size={32} />
		<span class="home-account__name">Profile photo</span>
		<span class="home-account__value">{avatarUrl ? 'Change' : 'Add'}</span>
		<span class="home-account__chevron" aria-hidden="true">{@html chevronRightIcon}</span>
	</button>
	<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- the page passes hrefs built with resolve() -->
	<a class="home-account__cell" href={securityHref}>
		<IconTile icon={shieldCheckIcon} tone="success" size={32} />
		<span class="home-account__name">Password & security</span>
		<span class="home-account__chevron" aria-hidden="true">{@html chevronRightIcon}</span>
	</a>
	<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- the page passes hrefs built with resolve() -->
	<a class="home-account__cell" href={alertsHref}>
		<IconTile icon={bellIcon} tone="informative" size={32} />
		<span class="home-account__name">My alerts</span>
		<span class="home-account__chevron" aria-hidden="true">{@html chevronRightIcon}</span>
	</a>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.home-account {
		display: flex;
		align-items: center;
		gap: var(--space-large);
		padding: 14px var(--space-base);
		background: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);

		&__who {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}
		&__copy {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
		}
		&__title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}
		&__sub {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}
		&__role {
			text-transform: capitalize;
		}
		&__cell {
			display: flex;
			flex: 1;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-small) var(--space-base);
			color: inherit;
			font: inherit;
			text-align: left;
			text-decoration: none;
			background: none;
			border: 0;
			border-left: var(--border-base) solid var(--color-border);
			border-radius: 0;
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
		&__name {
			flex: 1;
			white-space: nowrap;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		&__value {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
		}
		&__chevron {
			display: grid;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
