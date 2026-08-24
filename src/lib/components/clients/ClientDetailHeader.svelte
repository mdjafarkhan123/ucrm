<script lang="ts">
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import ManualEmailDialog from '$lib/components/clients/ManualEmailDialog.svelte';
	import type { ClientDetail } from '$lib/clients/api';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import coinIcon from '@tabler/icons/outline/coin.svg?raw';
	import fileIcon from '@tabler/icons/outline/file-text.svg?raw';
	import toolIcon from '@tabler/icons/outline/tool.svg?raw';

	// The identity card at the top of a client's page: who they are, how to reach them, and how much work
	// they represent. Money and job counts have no source yet, so they read as not-yet rather than zero.
	let { client, onEdit }: { client: ClientDetail; onEdit: () => void } = $props();

	const isCustomer = $derived(client.lifecycle_status === 'customer');

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
	const clientSince = $derived(
		client.created_at ? dateFormat.format(new Date(client.created_at)) : '—'
	);

	// Each figure waits on the part of the product that produces it, so it says what it is waiting for
	// instead of showing a zero that is not true.
	// Spelled out for screen readers as well as the hover title, because a disabled button never takes
	// focus and its reason would otherwise reach mouse users only.
	const callReason = 'Calling arrives with the communications work';
	const messageReason = 'Messaging arrives with the communications work';
	let manualEmailOpen = $state(false);

	const stats = [
		{ icon: coinIcon, label: 'Lifetime', waiting: 'Once you start invoicing' },
		{ icon: fileIcon, label: 'Open quotes', waiting: 'Once you start quoting' },
		{ icon: toolIcon, label: 'Active jobs', waiting: 'Once you start booking jobs' }
	];
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="client-header" aria-label="Client summary">
	<div class="client-header__top">
		<Avatar id={client.id} name={client.display_name} size="medium" />
		<Badge status={isCustomer ? 'success' : 'informative'}>{isCustomer ? 'Customer' : 'Lead'}</Badge
		>
		<div class="client-header__buttons">
			<span class="client-header__waiting" title={callReason}>
				<Button variant="secondary" size="small" disabled>Call</Button>
				<span class="client-header__reason">{callReason}</span>
			</span>
			<Button variant="secondary" size="small" onclick={() => (manualEmailOpen = true)}
				>Message</Button
			>
			<Button variant="secondary" size="small" onclick={onEdit}>Edit</Button>
		</div>
	</div>

	<div class="client-header__identity">
		<h1>{client.display_name}</h1>
		<PencilButton size="base" onclick={onEdit} label="Edit {client.display_name}" />
	</div>

	<div class="client-header__body">
		<dl class="client-header__facts">
			<div class="client-header__fact">
				<dt><span aria-hidden="true">{@html phoneIcon}</span>Main phone</dt>
				<dd>
					{#if client.phone}
						<a href={`tel:${client.phone}`}>{client.phone}</a>
					{:else}
						<span class="client-header__blank">Not added yet</span>
					{/if}
				</dd>
			</div>
			<div class="client-header__fact">
				<dt><span aria-hidden="true">{@html messageIcon}</span>Main email</dt>
				<dd>
					{#if client.email}
						<a href={`mailto:${client.email}`}>{client.email}</a>
					{:else}
						<span class="client-header__blank">Not added yet</span>
					{/if}
				</dd>
			</div>
			<div class="client-header__fact">
				<dt>Client since</dt>
				<dd>{clientSince}</dd>
			</div>
		</dl>

		<ul class="client-header__stats">
			{#each stats as stat (stat.label)}
				<li class="client-header__stat">
					<span class="client-header__stat-icon" aria-hidden="true">{@html stat.icon}</span>
					<span class="client-header__stat-text">
						<span class="client-header__stat-label">{stat.label}</span>
						<span class="client-header__stat-value">{stat.waiting}</span>
					</span>
				</li>
			{/each}
		</ul>
	</div>
</section>

{#if manualEmailOpen}
	<ManualEmailDialog open={manualEmailOpen} {client} onClose={() => (manualEmailOpen = false)} />
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-header__waiting {
		display: inline-flex;
		align-items: center;
	}

	.client-header__reason {
		position: absolute;
		width: 1px;
		height: 1px;
		margin: -1px;
		padding: 0;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
		border: 0;
	}

	.client-header {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);

		&__top {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__buttons {
			display: flex;
			gap: var(--space-small);
			margin-left: auto;
		}

		&__identity {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);

			h1 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
				font-weight: 700;
				line-height: var(--typography--lineHeight-tight);
			}
		}

		&__body {
			display: grid;
			grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
			gap: var(--space-large);
			align-items: start;
		}

		&__facts {
			display: flex;
			flex-direction: column;
		}

		&__fact {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-small) 0;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}

			dt {
				display: flex;
				align-items: center;
				gap: var(--space-small);
				color: var(--color-text--secondary);

				:global(svg) {
					display: block;
					width: 16px;
					height: 16px;
					color: var(--color-icon--secondary);
				}
			}

			dd {
				overflow: hidden;
				color: var(--color-heading);
				font-weight: 600;
				text-overflow: ellipsis;
				white-space: nowrap;

				a {
					color: inherit;
					text-decoration: none;

					&:hover {
						text-decoration: underline;
					}
				}
			}
		}

		&__blank {
			color: var(--color-text--secondary);
			font-weight: 400;
		}

		&__stats {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__stat {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__stat-icon {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: var(--space-larger);
			height: var(--space-larger);
			border-radius: var(--radius-base);
			color: var(--color-icon);
			background: var(--color-surface);

			:global(svg) {
				display: block;
				width: 20px;
				height: 20px;
			}
		}

		&__stat-text {
			display: flex;
			min-width: 0;
			flex-direction: column;
		}

		&__stat-label {
			color: var(--color-heading);
			font-weight: 700;
		}

		&__stat-value {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	@media (max-width: 767px) {
		.client-header {
			padding: var(--space-base);

			&__body {
				grid-template-columns: 1fr;
				gap: var(--space-base);
			}
			&__buttons {
				width: 100%;
				margin-left: 0;
			}
			&__top {
				flex-wrap: wrap;
			}
		}
	}
</style>
