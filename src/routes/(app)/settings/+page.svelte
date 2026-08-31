<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import SettingsDestinationCard from '$lib/components/settings/SettingsDestinationCard.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { fetchSettingsHome, settingsHomeKey } from '$lib/settings/api';
	import { AUTOMATION_JOURNEY_READY } from '$lib/automation/journey';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building-store.svg?raw';
	import paletteIcon from '@tabler/icons/outline/palette.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import layoutKanbanIcon from '@tabler/icons/outline/layout-kanban.svg?raw';
	import receiptTaxIcon from '@tabler/icons/outline/receipt-tax.svg?raw';
	import listIcon from '@tabler/icons/outline/list-details.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import shieldLockIcon from '@tabler/icons/outline/shield-lock.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import mailOffIcon from '@tabler/icons/outline/mail-off.svg?raw';
	import messageCircleIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import templateIcon from '@tabler/icons/outline/template.svg?raw';
	import robotIcon from '@tabler/icons/outline/robot.svg?raw';

	const query = createQuery(() => ({
		queryKey: settingsHomeKey,
		queryFn: fetchSettingsHome
	}));

	// Automation has a working access decision and shell (Part 6B) but the contractor journey is a limited
	// pilot, so its card stays hidden from ordinary packages until the shared journey flag flips. The
	// permission gate below already handles who may see it once it is on.
</script>

<svelte:head><title>Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<div class="settings-page">
		<PageHeader
			eyebrow="Control room"
			title="Settings"
			description="Everything that shapes how your business looks and runs, in one place."
		/>

		{#if query.isPending}
			<LoadingSkeleton variant="card" rows={3} />
		{:else if query.isError}
			<ErrorState description="Settings could not be loaded." retry={() => query.refetch()} />
		{:else}
			{@const home = query.data}
			{@const isTemplatesManager =
				home.permissions.snippets_manage &&
				(home.member.role === 'owner' || home.member.role === 'admin')}
			{@const showAutomation = home.permissions.automations_view && AUTOMATION_JOURNEY_READY}
			<div class="settings-page__member">
				<Avatar
					id={home.member.email ?? 'me'}
					name={home.member.name ?? home.member.email ?? 'You'}
					size="large"
				/>
				<div class="settings-page__member-copy">
					<span class="settings-page__member-name">{home.member.name ?? 'Your account'}</span>
					<span class="settings-page__member-role">{home.member.role}</span>
				</div>
				<a class="settings-page__member-link" href={resolve('/settings/security')}
					>Password and security</a
				>
			</div>

			<nav class="settings-page__jump" aria-label="Settings categories">
				<a href="#business">Business</a>
				{#if home.permissions.communications_manage}<a href="#communications">Communications</a
					>{/if}
				{#if showAutomation}<a href="#automations">Automations</a>{/if}
				{#if home.permissions.team_manage}<a href="#team-access">Team & access</a>{/if}
			</nav>

			<div class="settings-page__groups">
				<SectionBlock
					title="Business"
					hint="The identity, look, and hours customers and staff both rely on."
					id="business"
					icon={buildingIcon}
					level={2}
				>
					<div class="settings-page__grid">
						<SettingsDestinationCard
							href={resolve('/settings/business-profile')}
							icon={buildingIcon}
							title="Business profile"
							description="Your name, contact details, address, timezone, and currency."
							status={home.readiness.business_profile.complete
								? undefined
								: { label: 'Incomplete', tone: 'warning' }}
						/>
						<SettingsDestinationCard
							href={resolve('/settings/branding')}
							icon={paletteIcon}
							title="Branding"
							description="The logo and brand color customers see on quotes and invoices."
						/>
						<SettingsDestinationCard
							href={resolve('/settings/business-hours')}
							icon={clockIcon}
							title="Business hours"
							description="When your business is normally open, for scheduling and booking."
							status={home.readiness.business_hours_set
								? undefined
								: { label: 'Not set', tone: 'inactive' }}
						/>
						<SettingsDestinationCard
							href={resolve('/settings/pipeline')}
							icon={layoutKanbanIcon}
							title="Pipeline"
							description="How the Pipeline board groups the Assessment stages."
						/>
						{#if home.permissions.taxes_manage}
							<SettingsDestinationCard
								href={resolve('/(app)/settings/taxes')}
								icon={receiptTaxIcon}
								title="Taxes"
								description="The tax rates you charge and which one applies by default."
							/>
						{/if}
						{#if home.permissions.price_book_manage}
							<SettingsDestinationCard
								href={resolve('/(app)/settings/price-book')}
								icon={listIcon}
								title="Price Book"
								description="The products and services you sell, ready to add to any quote."
							/>
						{/if}
						{#if home.permissions.quotes_manage}
							<SettingsDestinationCard
								href={resolve('/(app)/settings/quotes')}
								icon={fileTextIcon}
								title="Quote Settings"
								description="Default terms, your representative block, target margin, and signature policy."
							/>
						{/if}
					</div>
				</SectionBlock>

				{#if home.permissions.communications_manage || home.permissions.snippets_manage}
					<SectionBlock
						title="Communications"
						hint="The verified email identities your team can use with customers."
						id="communications"
						icon={mailIcon}
						level={2}
					>
						<div class="settings-page__grid">
							{#if home.permissions.communications_manage}
								<SettingsDestinationCard
									href={resolve('/settings/communications/email')}
									icon={mailIcon}
									title="Email identity"
									description="Choose the email addresses staff and automations can use."
								/>
								<SettingsDestinationCard
									href={resolve('/settings/communications/blocked-addresses')}
									icon={mailOffIcon}
									title="Blocked addresses"
									description="Customer email addresses that bounced or reported spam, and how to unblock them."
								/>
								<SettingsDestinationCard
									href={resolve('/settings/communications/website-chat')}
									icon={messageCircleIcon}
									title="Website Chat"
									description="The chat widgets your website can show customers."
								/>
							{/if}
							{#if home.permissions.snippets_manage}
								<SettingsDestinationCard
									href={resolve('/settings/communications/snippets')}
									icon={fileTextIcon}
									title="Snippets"
									description="Reusable text your team can drop into any conversation reply."
								/>
							{/if}
							{#if isTemplatesManager}
								<SettingsDestinationCard
									href={resolve('/settings/communications/templates')}
									icon={templateIcon}
									title="Templates"
									description="Reusable emails your team can send from any conversation."
								/>
							{/if}
						</div>
					</SectionBlock>
				{/if}

				{#if showAutomation}
					<SectionBlock
						title="Automations, notifications & connections"
						hint="Work that happens on its own, so your team doesn’t have to remember it."
						id="automations"
						icon={robotIcon}
						level={2}
					>
						<div class="settings-page__grid">
							<SettingsDestinationCard
								href={resolve('/settings/automation')}
								icon={robotIcon}
								title="Automation"
								description="Automatic follow-ups that reach out to customers for you, on your rules."
							/>
						</div>
					</SectionBlock>
				{/if}

				{#if home.permissions.team_manage}
					<SectionBlock
						title="Team & access"
						hint="The people who work in your business and what they can do."
						id="team-access"
						icon={usersIcon}
						level={2}
					>
						<div class="settings-page__grid">
							<SettingsDestinationCard
								href={resolve('/(app)/settings/team')}
								icon={usersIcon}
								title="Team"
								description="Invite people and manage their business contact details."
							/>
							<SettingsDestinationCard
								href={resolve('/(app)/settings/team')}
								icon={shieldLockIcon}
								title="Roles & permissions"
								description="Choose a team member to control what they can see and do."
							/>
						</div>
					</SectionBlock>
				{/if}
			</div>
		{/if}
	</div>
</PageContainer>

<style lang="scss">
	.settings-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__member {
			display: flex;
			align-items: center;
			gap: var(--space-base);
			padding-bottom: var(--space-large);
			border-bottom: var(--border-base) solid var(--color-border);
		}
		&__member-copy {
			display: flex;
			min-width: 0;
			flex: 1;
			flex-direction: column;
			gap: var(--space-smallest);
		}
		&__member-name {
			color: var(--color-heading);
			font-weight: 700;
		}
		&__member-role {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-transform: capitalize;
		}
		&__member-link {
			flex: 0 0 auto;
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-decoration: none;
		}
		&__member-link:hover {
			text-decoration: underline;
		}

		&__jump {
			position: sticky;
			top: var(--space-base);
			z-index: var(--elevation-base);
			display: flex;
			gap: var(--space-small);
			padding: var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			overflow-x: auto;
		}
		&__jump a {
			flex: 0 0 auto;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-large);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-decoration: none;
			white-space: nowrap;
		}
		&__jump a:hover {
			color: var(--color-heading);
			background: var(--color-surface--hover);
		}

		&__groups {
			--section-block-notch: var(--color-surface);
			display: flex;
			flex-direction: column;
			gap: var(--space-larger);
		}

		&__grid {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: var(--space-large);
		}
	}

	@media (max-width: 1439px) {
		.settings-page__grid {
			grid-template-columns: repeat(3, minmax(0, 1fr));
		}
	}
	@media (max-width: 1079px) {
		.settings-page__grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@media (max-width: 639px) {
		.settings-page {
			gap: var(--space-base);
		}
		.settings-page__grid {
			grid-template-columns: 1fr;
		}
	}
</style>
