<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import SettingsDestinationCard from '$lib/components/settings/SettingsDestinationCard.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ProfilePhotoDialog from '$lib/components/profile/ProfilePhotoDialog.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { fetchSettingsHome, settingsHomeKey } from '$lib/settings/api';
	import { smsRegistrationBadge } from '$lib/communications/sms-registration';
	import { AUTOMATION_JOURNEY_READY } from '$lib/automation/journey';
	import buildingIcon from '@tabler/icons/outline/building-store.svg?raw';
	import paletteIcon from '@tabler/icons/outline/palette.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import usersGroupIcon from '@tabler/icons/outline/users-group.svg?raw';
	import layoutKanbanIcon from '@tabler/icons/outline/layout-kanban.svg?raw';
	import receiptTaxIcon from '@tabler/icons/outline/receipt-tax.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import listIcon from '@tabler/icons/outline/list-details.svg?raw';
	import checklistIcon from '@tabler/icons/outline/checklist.svg?raw';
	import formsIcon from '@tabler/icons/outline/forms.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import shieldLockIcon from '@tabler/icons/outline/shield-lock.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import mailOffIcon from '@tabler/icons/outline/mail-off.svg?raw';
	import messageCircleIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import deviceMobileMessageIcon from '@tabler/icons/outline/device-mobile-message.svg?raw';
	import walletIcon from '@tabler/icons/outline/wallet.svg?raw';
	import templateIcon from '@tabler/icons/outline/template.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell-ringing.svg?raw';
	import robotIcon from '@tabler/icons/outline/robot.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';

	const query = createQuery(() => ({
		queryKey: settingsHomeKey,
		queryFn: fetchSettingsHome
	}));

	// The photo comes from the shell's own load, which the dialog refreshes after a change.
	const userId = $derived(page.data.user?.id as string);
	const avatarUrl = $derived((page.data.account?.avatarUrl as string | null | undefined) ?? null);
	let photoOpen = $state(false);

	// Automation has a working access decision and shell (Part 6B) but the contractor journey is a limited
	// pilot, so its card stays hidden from ordinary packages until the shared journey flag flips. The
	// permission gate below already handles who may see it once it is on.
</script>

<!-- eslint-disable svelte/no-at-html-tags -->

<svelte:head><title>Settings · Contractor CRM</title></svelte:head>

<ProfilePhotoDialog
	open={photoOpen}
	avatarId={userId}
	name={page.data.account?.name ?? page.data.account?.email ?? null}
	{avatarUrl}
	endpoint="/api/profile/photo"
	onClose={() => (photoOpen = false)}
/>

<PageContainer variant="open">
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
			<div class="settings-page__body">
				<div class="settings-page__main">
					<section class="settings-page__hero">
						<div class="settings-page__hero-heading">
							<span aria-hidden="true">{@html buildingIcon}</span>
							<div>
								<p>Your business</p>
								<h2>{home.organization.name}</h2>
							</div>
							<Button
								href={resolve('/(app)/settings/business-profile')}
								variant="secondary"
								size="small">Edit profile</Button
							>
						</div>
						<div class="settings-page__hero-facts">
							<div>
								<span>Business profile</span><strong
									>{home.readiness.business_profile.complete ? 'Ready' : 'Incomplete'}</strong
								>
							</div>
							<div>
								<span>Business hours</span><strong
									>{home.readiness.business_hours_set ? 'Configured' : 'Not set'}</strong
								>
							</div>
							<div><span>Your access</span><strong>{home.member.role}</strong></div>
						</div>
					</section>

					<nav class="settings-page__jump" aria-label="Settings categories">
						<a href="#business">Business</a><a href="#sales-work">Sales & work</a>
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
								{#if home.permissions.pipeline_view}
									<SettingsDestinationCard
										href={resolve('/settings/pipeline')}
										icon={layoutKanbanIcon}
										title="Pipeline"
										description="How the Pipeline board groups the Assessment stages."
									/>
								{/if}
								{#if home.readiness.handover_delivered}
									<SettingsDestinationCard
										href={resolve('/(app)/setup/handover')}
										icon={packageIcon}
										title="Handover pack"
										description="Who owns which account, your team’s guides, and your launch approval from Uplift."
									/>
								{/if}
								<SettingsDestinationCard
									href={resolve('/settings/contact-matching')}
									icon={usersGroupIcon}
									title="Contact matching"
									description="Which client a website chat or form joins when its phone and email belong to two clients."
								/>
							</div></SectionBlock
						>
						<SectionBlock
							id="sales-work"
							title="Sales & work"
							hint="The defaults behind every quote, job and invoice."
							icon={fileTextIcon}
							level={2}
							><div class="settings-page__grid">
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
								{#if home.permissions.checklists_manage}
									<SettingsDestinationCard
										href={resolve('/(app)/settings/checklists')}
										icon={checklistIcon}
										title="Checklists"
										description="The lists your crew ticks off on site, ready to attach to any job."
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
								{#if home.permissions.invoices_manage}
									<SettingsDestinationCard
										href={resolve('/(app)/settings/invoices')}
										icon={receiptIcon}
										title="Invoice Settings"
										description="Payment terms and which one applies by default."
									/>
								{/if}
								{#if home.permissions.payments_manage}
									<SettingsDestinationCard
										href={resolve('/(app)/settings/payments')}
										icon={creditCardIcon}
										title="Payments"
										description="Connect Stripe so customers can pay invoices and deposits online."
									/>
								{/if}
								{#if home.permissions.forms_manage}
									<SettingsDestinationCard
										href={resolve('/(app)/settings/forms')}
										icon={formsIcon}
										title="Request Forms"
										description="The online forms customers fill in to request work from you."
									/>
								{/if}
								{#if home.permissions.reviews_manage}
									<SettingsDestinationCard
										href={resolve('/(app)/reviews/settings')}
										icon={starIcon}
										title="Google reviews"
										description="Your Google review link, review page, private feedback form, and request messages."
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
										{#if home.readiness.sms_registration}
											<SettingsDestinationCard
												href={resolve('/settings/communications/sms')}
												icon={deviceMobileMessageIcon}
												title="Phone & SMS"
												description="Registration, sending numbers and texting readiness."
												status={smsRegistrationBadge(
													home.readiness.sms_registration.readiness_state
												)}
											/>
										{/if}
										<SettingsDestinationCard
											href={resolve('/settings/communications/balance')}
											icon={walletIcon}
											title="Communication Balance"
											description="Balance and top-ups for texts and extra email sending, plus this month's charges."
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
										<SettingsDestinationCard
											href={resolve('/(app)/settings/inquiry-alerts')}
											icon={bellIcon}
											title="Inquiry alerts"
											description="Who gets alerted when a website form or chat brings in a new customer."
											status={home.readiness.inquiry_alerts_owner_only
												? { label: 'Owner only', tone: 'warning' }
												: undefined}
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
				</div>
				<aside class="settings-page__rail">
					<div class="settings-page__member">
						<Avatar
							id={userId}
							name={home.member.name ?? home.member.email ?? 'You'}
							src={avatarUrl}
							size="large"
						/>
						<div class="settings-page__member-copy">
							<span class="settings-page__member-name">{home.member.name ?? 'Your account'}</span>
							<span class="settings-page__member-role">{home.member.role}</span>
						</div>
						<Button size="small" variant="tertiary" onclick={() => (photoOpen = true)}>
							{avatarUrl ? 'Change photo' : 'Add photo'}
						</Button>
						<a class="settings-page__member-link" href={resolve('/settings/security')}
							>Password and security</a
						>
					</div>
					<section class="settings-page__rail-card">
						<h2>Needs attention</h2>
						<p>Keep your business ready for customers.</p>
						{#if !home.readiness.business_profile.complete}<a
								href={resolve('/(app)/settings/business-profile')}>Complete business profile</a
							>{/if}{#if !home.readiness.business_hours_set}<a
								href={resolve('/(app)/settings/business-hours')}>Set business hours</a
							>{/if}{#if home.readiness.inquiry_alerts_owner_only && home.permissions.communications_manage}<a
								href={resolve('/(app)/settings/inquiry-alerts')}>Choose who gets inquiry alerts</a
							>{/if}{#if home.readiness.business_profile.complete && home.readiness.business_hours_set && !home.readiness.inquiry_alerts_owner_only}<p
							>
								Your business basics are ready.
							</p>{/if}
					</section>
				</aside>
			</div>
		{/if}
	</div>
</PageContainer>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.settings-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__body {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 336px;
			gap: 20px;
			align-items: start;
		}
		&__main {
			min-width: 0;
			display: grid;
			gap: 24px;
		}
		&__rail {
			display: grid;
			gap: 20px;
		}
		&__hero {
			padding: 24px;
			background: var(--color-base-blue--900);
			color: var(--color-base-white);
			border-radius: var(--radius-base);
		}
		&__hero-heading {
			display: flex;
			gap: 16px;
			align-items: center;
			> span {
				display: grid;
				place-items: center;
				padding: 14px;
				background: var(--color-interactive);
				border-radius: var(--radius-base);
			}
			:global(svg) {
				width: 28px;
				height: 28px;
			}
			> div {
				flex: 1;
			}
			p {
				font-size: 12px;
				opacity: 0.7;
			}
			h2 {
				font-size: 28px;
				font-weight: 800;
			}
		}
		&__hero-facts {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: 10px;
			margin-top: 20px;
			> div {
				display: grid;
				gap: 5px;
				border: 1px solid color-mix(in srgb, var(--color-base-white) 15%, transparent);
				background: color-mix(in srgb, var(--color-base-white) 5%, transparent);
				border-radius: var(--radius-base);
				padding: 12px;
			}
			span {
				opacity: 0.7;
				font-size: 11px;
			}
			strong {
				font-size: 13px;
				text-transform: capitalize;
			}
		}
		&__rail-card {
			background: var(--color-surface);
			padding: 24px;
			border: 1px solid var(--color-border);
			border-radius: var(--radius-base);
			h2 {
				font-size: 15px;
				color: var(--color-heading);
			}
			p {
				color: var(--color-text--secondary);
				font-size: 12px;
				margin: 8px 0;
			}
			a {
				display: block;
				padding: 12px 0;
				font-size: 13px;
				color: var(--color-interactive);
				border-top: 1px solid var(--color-border);
			}
		}
		&__member {
			display: flex;
			align-items: center;
			gap: var(--space-base);
			flex-wrap: wrap;
			padding: 24px;
			background: var(--color-surface);
			border-radius: var(--radius-base);
			border: var(--border-base) solid var(--color-border);
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
			padding: 0;
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
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: 0;
		}
	}

	@media (max-width: 1439px) {
		.settings-page__grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
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

	.settings-page :global(.section-block) {
		padding: 0;
		margin: 0;
		background: var(--color-surface);
		border: 0;
		gap: 0;
	}
	.settings-page :global(.section-block .section-block__title) {
		position: static;
		max-width: none;
		padding: 16px;
		transform: none;
		font-size: 16px;
		background: var(--color-job--surface);
		border-radius: var(--radius-base) var(--radius-base) 0 0;
	}
	.settings-page :global(.section-block__hint) {
		margin: 0;
		padding: 0 16px 16px;
		background: var(--color-job--surface);
	}
	.settings-page :global(#sales-work .section-block__title),
	.settings-page :global(#sales-work .section-block__hint),
	.settings-page :global(#communications .section-block__title),
	.settings-page :global(#communications .section-block__hint) {
		background: var(--color-invoice--surface);
	}
	.settings-page :global(#team-access .section-block__title),
	.settings-page :global(#team-access .section-block__hint) {
		background: var(--color-quote--surface);
	}
	@media (max-width: 1100px) {
		.settings-page__body {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
