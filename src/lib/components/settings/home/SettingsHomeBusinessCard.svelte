<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import type { BusinessFact } from '$lib/settings/home-rows';
	import leafIcon from '@tabler/icons/outline/leaf.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';

	// The business identity card at the top of the Settings home (Pencil: "Batch 63 · Settings home", Your
	// business card): the name customers see, how to reach the business, and six facts that shape every
	// quote, invoice and visit.
	let {
		name,
		profileComplete,
		place,
		phone,
		email,
		website,
		logoUrl,
		facts,
		editHref
	}: {
		name: string;
		profileComplete: boolean;
		place: string | null;
		phone: string | null;
		email: string | null;
		website: string | null;
		logoUrl: string | null;
		facts: BusinessFact[];
		editHref: string;
	} = $props();

	const contacts = $derived(
		[
			{ key: 'phone', icon: phoneIcon, tone: 'time', text: phone },
			{ key: 'email', icon: mailIcon, tone: 'conversation', text: email },
			{ key: 'website', icon: worldIcon, tone: 'inactive', text: website }
		].filter((contact) => contact.text)
	);
	const factRows = $derived(
		Array.from({ length: Math.ceil(facts.length / 2) }, (_, index) =>
			facts.slice(index * 2, index * 2 + 2)
		)
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="home-business" aria-labelledby="settings-business-name">
	<div class="home-business__identity">
		<span class="home-business__logo" aria-hidden="true">
			{#if logoUrl}<img src={logoUrl} alt="" />{:else}{@html leafIcon}{/if}
		</span>
		<div class="home-business__copy">
			<div class="home-business__name-row">
				<h2 id="settings-business-name" class="home-business__name">{name}</h2>
				<StatusBadge status={profileComplete ? 'success' : 'warning'}>
					{profileComplete ? 'Profile complete' : 'Profile incomplete'}
				</StatusBadge>
			</div>
			<p class="home-business__line">
				{place ? `${place} · ` : ''}customers see this on quotes, invoices and emails
			</p>
			{#if contacts.length}
				<ul class="home-business__contacts">
					{#each contacts as contact (contact.key)}
						<li>
							<span class="home-business__contact-icon home-business__contact-icon--{contact.tone}">
								{@html contact.icon}
							</span>
							{contact.text}
						</li>
					{/each}
				</ul>
			{/if}
		</div>
		<Button href={editHref} variant="secondary" size="small"
			><span aria-hidden="true">{@html pencilIcon}</span>Edit profile</Button
		>
	</div>
	<div class="home-business__facts">
		{#each factRows as row, index (index)}
			<div class="home-business__fact-row">
				{#each row as fact (fact.key)}
					<div class="home-business__fact">
						<IconTile icon={fact.icon} tone={fact.tone} size={32} />
						<div class="home-business__fact-copy">
							<span class="home-business__fact-label">{fact.label}</span>
							<span class="home-business__fact-value">{fact.value ?? 'Not set'}</span>
						</div>
					</div>
				{/each}
			</div>
		{/each}
	</div>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.home-business {
		display: flex;
		flex-direction: column;
		background: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		overflow: hidden;

		&__identity {
			display: flex;
			align-items: flex-start;
			gap: var(--space-base);
			padding: var(--space-large) var(--space-large) var(--space-medium);
		}
		&__logo {
			display: grid;
			flex: none;
			place-items: center;
			width: 64px;
			height: 64px;
			overflow: hidden;
			background: var(--color-interactive);
			color: var(--color-white);
			border-radius: var(--radius-large);

			:global(svg) {
				width: 30px;
				height: 30px;
			}
			img {
				width: 100%;
				height: 100%;
				object-fit: cover;
			}
		}
		&__copy {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);
			min-width: 0;
		}
		&__name-row {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-slim);
		}
		&__name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-display);
			font-weight: 700;
			letter-spacing: -0.6px;
		}
		&__line {
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
		}
		&__contacts {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;

			li {
				display: flex;
				align-items: center;
				gap: var(--space-small);
			}
		}
		&__contact-icon {
			display: grid;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
			&--time {
				color: var(--color-time);
			}
			&--conversation {
				color: var(--color-conversation);
			}
			&--inactive {
				color: var(--color-inactive);
			}
		}
		&__facts {
			display: flex;
			flex: 1;
			flex-direction: column;
			padding: 0 var(--space-large);
			background: var(--color-surface--background--subtle);
			border-top: var(--border-base) solid var(--color-border);
		}
		&__fact-row {
			display: flex;
			flex: 1;
			align-items: center;
			gap: var(--space-base);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}
		&__fact {
			display: flex;
			flex: 1;
			align-items: center;
			gap: var(--space-slim);
			min-width: 0;
			padding: var(--space-base) 0;
		}
		&__fact-copy {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			min-width: 0;
		}
		&__fact-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
		&__fact-value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			overflow-wrap: anywhere;
		}
	}
</style>
