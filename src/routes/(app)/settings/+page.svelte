<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import SettingsHomeAreaCard from '$lib/components/settings/home/SettingsHomeAreaCard.svelte';
	import SettingsHomeBusinessCard from '$lib/components/settings/home/SettingsHomeBusinessCard.svelte';
	import SettingsHomeReadyCard from '$lib/components/settings/home/SettingsHomeReadyCard.svelte';
	import SettingsHomeBalanceCard from '$lib/components/settings/home/SettingsHomeBalanceCard.svelte';
	import SettingsHomeAccountStrip from '$lib/components/settings/home/SettingsHomeAccountStrip.svelte';
	import ProfilePhotoDialog from '$lib/components/profile/ProfilePhotoDialog.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import {
		fetchSettingsHome,
		fetchSettingsHomeSummary,
		settingsHomeKey,
		settingsHomeSummaryKey
	} from '$lib/settings/api';
	import { fetchSmsUsage, smsUsageKey } from '$lib/communications/sms-usage';
	import { smsRegistrationBadge } from '$lib/communications/sms-registration';
	import { settingsReady } from '$lib/settings/home-ready';
	import { rowMatches, type BusinessFact, type SettingsHomeRow } from '$lib/settings/home-rows';
	import { AUTOMATION_JOURNEY_READY } from '$lib/automation/journey';
	import settingsPageIcon from '@tabler/icons/outline/settings.svg?raw';
	import storeIcon from '@tabler/icons/outline/building-store.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import paletteIcon from '@tabler/icons/outline/palette.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock-hour-4.svg?raw';
	import percentIcon from '@tabler/icons/outline/percentage.svg?raw';
	import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';
	import messagesIcon from '@tabler/icons/outline/messages.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import mobileIcon from '@tabler/icons/outline/device-mobile.svg?raw';
	import messageCircleIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import clipboardListIcon from '@tabler/icons/outline/clipboard-list.svg?raw';
	import bellRingingIcon from '@tabler/icons/outline/bell-ringing.svg?raw';
	import templateIcon from '@tabler/icons/outline/template.svg?raw';
	import quoteIcon from '@tabler/icons/outline/quote.svg?raw';
	import gitMergeIcon from '@tabler/icons/outline/git-merge.svg?raw';
	import mailOffIcon from '@tabler/icons/outline/mail-off.svg?raw';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import bookIcon from '@tabler/icons/outline/book.svg?raw';
	import checklistIcon from '@tabler/icons/outline/checklist.svg?raw';
	import layoutKanbanIcon from '@tabler/icons/outline/layout-kanban.svg?raw';
	import trendingUpIcon from '@tabler/icons/outline/trending-up.svg?raw';
	import robotIcon from '@tabler/icons/outline/robot.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import currencyIcon from '@tabler/icons/outline/currency-dollar.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import homeIcon from '@tabler/icons/outline/home.svg?raw';
	import helmetIcon from '@tabler/icons/outline/helmet.svg?raw';

	const query = createQuery(() => ({ queryKey: settingsHomeKey, queryFn: fetchSettingsHome }));
	// The captions and figures fill in after the rows are already there, so the page never waits on them.
	const summaryQuery = createQuery(() => ({
		queryKey: settingsHomeSummaryKey,
		queryFn: fetchSettingsHomeSummary
	}));
	const usageQuery = createQuery(() => ({
		queryKey: smsUsageKey,
		queryFn: fetchSmsUsage,
		enabled: query.data?.permissions.communications_manage === true
	}));

	// The photo comes from the shell's own load, which the dialog refreshes after a change.
	const userId = $derived(page.data.user?.id as string);
	const avatarUrl = $derived((page.data.account?.avatarUrl as string | null | undefined) ?? null);
	let photoOpen = $state(false);
	let search = $state('');

	const home = $derived(query.data);
	const summary = $derived(summaryQuery.data);
	const values = $derived(summary?.values);
	const signals = $derived(summary?.signals);

	const ready = $derived(home ? settingsReady(home, summary) : null);
	const readyHrefs: Record<string, string> = {
		profile: resolve('/(app)/settings/business-profile'),
		hours: resolve('/(app)/settings/business-hours'),
		logo: resolve('/(app)/settings/branding'),
		tax: resolve('/(app)/settings/taxes'),
		payments: resolve('/(app)/settings/payments'),
		texting: resolve('/(app)/settings/communications/sms'),
		email: resolve('/(app)/settings/communications/email'),
		products: resolve('/(app)/settings/price-book'),
		team: resolve('/(app)/settings/team'),
		forms: resolve('/(app)/settings/forms'),
		alerts: resolve('/(app)/settings/inquiry-alerts'),
		reviews: resolve('/(app)/reviews/settings')
	};

	function timeZoneText(timeZone: string | undefined) {
		if (!timeZone) return null;
		try {
			const offset =
				new Intl.DateTimeFormat('en-US', { timeZone, timeZoneName: 'shortOffset' })
					.formatToParts(new Date())
					.find((part) => part.type === 'timeZoneName')?.value ?? '';
			const city = timeZone.split('/').pop()?.replaceAll('_', ' ') ?? timeZone;
			return `${city} (${offset.replace('GMT', 'UTC').replace('-', '−') || 'UTC'})`;
		} catch {
			return timeZone;
		}
	}
	function currencyText(code: string | null | undefined) {
		if (!code) return null;
		try {
			const name = new Intl.DisplayNames(['en'], { type: 'currency' }).of(code);
			return name ? `${code} · ${name}` : code;
		} catch {
			return code;
		}
	}

	const facts = $derived.by((): BusinessFact[] => {
		const business = summary?.business;
		const city = business?.place?.split(',')[0] ?? null;
		return [
			{
				key: 'timezone',
				label: 'Time zone',
				value: timeZoneText(business?.timezone),
				icon: worldIcon,
				tone: 'time'
			},
			{
				key: 'currency',
				label: 'Currency',
				value: currencyText(business?.currency_code),
				icon: currencyIcon,
				tone: 'invoice'
			},
			{
				key: 'open',
				label: 'Open today',
				value: business?.open_today ?? null,
				icon: clockIcon,
				tone: 'time'
			},
			{
				key: 'service',
				label: 'Service area',
				value: business?.service_radius_miles
					? `${business.service_radius_miles} mi${city ? ` around ${city}` : ''}`
					: null,
				icon: mapPinIcon,
				tone: 'client'
			},
			{
				key: 'address',
				label: 'Business address',
				value: business?.address ?? null,
				icon: homeIcon,
				tone: 'client'
			},
			{
				key: 'trade',
				label: 'Trade',
				value: business?.trade ?? null,
				icon: helmetIcon,
				tone: 'job'
			}
		];
	});

	function needsYou(rows: SettingsHomeRow[]) {
		return rows.filter((row) => row.pill?.tone === 'warning' || row.pill?.tone === 'critical')
			.length;
	}
	function areaHint(rows: SettingsHomeRow[], fallback: string) {
		const needs = needsYou(rows);
		return needs
			? `${rows.length} settings · ${needs} need${needs === 1 ? 's' : ''} you`
			: fallback;
	}

	const areas = $derived.by(() => {
		if (!home) return null;
		const p = home.permissions;
		const isTemplatesManager = p.snippets_manage && ['owner', 'admin'].includes(home.member.role);
		const showAutomation = p.automations_view && AUTOMATION_JOURNEY_READY;

		const business: SettingsHomeRow[] = [
			{
				key: 'profile',
				title: 'Business profile',
				icon: buildingIcon,
				tone: 'inactive',
				href: resolve('/(app)/settings/business-profile'),
				pill: home.readiness.business_profile.complete
					? { label: 'Complete', tone: 'success' }
					: { label: 'Incomplete', tone: 'warning' }
			},
			{
				key: 'branding',
				title: 'Branding',
				icon: paletteIcon,
				tone: 'inactive',
				href: resolve('/(app)/settings/branding'),
				value: values?.branding
			},
			{
				key: 'hours',
				title: 'Business hours',
				icon: clockIcon,
				tone: 'time',
				href: resolve('/(app)/settings/business-hours'),
				...(home.readiness.business_hours_set
					? { value: values?.hours }
					: { pill: { label: 'Not set', tone: 'warning' as const } })
			}
		];
		if (p.taxes_manage)
			business.push({
				key: 'taxes',
				title: 'Taxes',
				icon: percentIcon,
				tone: 'invoice',
				href: resolve('/(app)/settings/taxes'),
				value: values?.taxes
			});
		if (p.payments_manage)
			business.push({
				key: 'payments',
				title: 'Payments',
				icon: creditCardIcon,
				tone: 'invoice',
				href: resolve('/(app)/settings/payments'),
				...(signals?.payments_connected === false
					? { pill: { label: 'Not connected', tone: 'warning' as const } }
					: signals?.payments_connected
						? { pill: { label: 'Connected', tone: 'success' as const } }
						: {})
			});
		if (home.readiness.handover_delivered)
			business.push({
				key: 'handover',
				title: 'Handover pack',
				icon: packageIcon,
				tone: 'inactive',
				href: resolve('/(app)/setup/handover'),
				value: 'Delivered'
			});

		const talking: SettingsHomeRow[] = [];
		if (p.communications_manage) {
			talking.push({
				key: 'email',
				title: 'Email address',
				icon: mailIcon,
				tone: 'conversation',
				href: resolve('/(app)/settings/communications/email'),
				...(signals?.email_verified === true
					? { pill: { label: 'Verified', tone: 'success' as const } }
					: signals?.email_verified === false
						? { pill: { label: 'Not set up', tone: 'warning' as const } }
						: {})
			});
			if (home.readiness.sms_registration)
				talking.push({
					key: 'sms',
					title: 'Phone & texting',
					icon: mobileIcon,
					tone: 'conversation',
					href: resolve('/(app)/settings/communications/sms'),
					pill: smsRegistrationBadge(home.readiness.sms_registration.readiness_state)
				});
			talking.push({
				key: 'chat',
				title: 'Website chat',
				icon: messageCircleIcon,
				tone: 'conversation',
				href: resolve('/(app)/settings/communications/website-chat'),
				value: values?.website_chat
			});
		}
		if (p.forms_manage)
			talking.push({
				key: 'forms',
				title: 'Request forms',
				icon: clipboardListIcon,
				tone: 'request',
				href: resolve('/(app)/settings/forms'),
				value: values?.request_forms
			});
		if (p.communications_manage)
			talking.push({
				key: 'alerts',
				title: 'New-customer alerts',
				icon: bellRingingIcon,
				tone: 'request',
				href: resolve('/(app)/settings/inquiry-alerts'),
				...(home.readiness.inquiry_alerts_owner_only
					? { pill: { label: 'Only you', tone: 'warning' as const } }
					: { value: 'Your team' })
			});
		if (isTemplatesManager)
			talking.push({
				key: 'templates',
				title: 'Email templates',
				icon: templateIcon,
				tone: 'conversation',
				href: resolve('/(app)/settings/communications/templates'),
				value: values?.email_templates
			});
		if (p.snippets_manage)
			talking.push({
				key: 'snippets',
				title: 'Snippets',
				icon: quoteIcon,
				tone: 'conversation',
				href: resolve('/(app)/settings/communications/snippets'),
				value: values?.snippets
			});
		talking.push({
			key: 'matching',
			title: 'Contact matching',
			icon: gitMergeIcon,
			tone: 'client',
			href: resolve('/(app)/settings/contact-matching'),
			value: values?.contact_matching
		});
		if (p.communications_manage)
			talking.push({
				key: 'blocked',
				title: 'Blocked addresses',
				icon: mailOffIcon,
				tone: 'conversation',
				href: resolve('/(app)/settings/communications/blocked-addresses'),
				value: values?.blocked_addresses
			});

		const work: SettingsHomeRow[] = [];
		if (p.quotes_manage)
			work.push({
				key: 'quotes',
				title: 'Quotes',
				icon: fileTextIcon,
				tone: 'quote',
				href: resolve('/(app)/settings/quotes'),
				value: values?.quotes
			});
		if (p.invoices_manage)
			work.push({
				key: 'invoices',
				title: 'Invoices',
				icon: receiptIcon,
				tone: 'invoice',
				href: resolve('/(app)/settings/invoices'),
				value: values?.invoices
			});
		if (p.price_book_manage)
			work.push({
				key: 'products',
				title: 'Products & services',
				icon: bookIcon,
				tone: 'quote',
				href: resolve('/(app)/settings/price-book'),
				value: values?.products
			});
		if (p.checklists_manage)
			work.push({
				key: 'checklists',
				title: 'Checklists',
				icon: checklistIcon,
				tone: 'job',
				href: resolve('/(app)/settings/checklists'),
				value: values?.checklists
			});
		if (p.pipeline_view)
			work.push({
				key: 'pipeline',
				title: 'Pipeline',
				icon: layoutKanbanIcon,
				tone: 'growth',
				href: resolve('/(app)/settings/pipeline'),
				value: values?.pipeline
			});

		const growth: SettingsHomeRow[] = [];
		if (showAutomation)
			growth.push({
				key: 'automation',
				title: 'Automations',
				icon: robotIcon,
				tone: 'growth',
				href: resolve('/(app)/settings/automation'),
				value: values?.automations
			});
		if (p.reviews_manage)
			growth.push({
				key: 'reviews',
				title: 'Google reviews',
				icon: starIcon,
				tone: 'review',
				href: resolve('/(app)/reviews/settings'),
				...(signals?.review_link === false
					? { pill: { label: 'No link yet', tone: 'warning' as const } }
					: signals?.review_link
						? { value: 'Link added' }
						: {})
			});

		const team: SettingsHomeRow[] = [];
		if (p.team_manage)
			team.push(
				{
					key: 'members',
					title: 'Team members',
					icon: usersIcon,
					tone: 'inactive',
					href: resolve('/(app)/settings/team'),
					value: values?.team
				},
				{
					key: 'roles',
					title: 'Roles & permissions',
					icon: shieldCheckIcon,
					tone: 'inactive',
					href: resolve('/(app)/settings/team'),
					value: values?.roles
				},
				{
					key: 'activity',
					title: 'Team activity',
					icon: historyIcon,
					tone: 'inactive',
					href: resolve('/(app)/settings/team/activity'),
					value: values?.activity
				}
			);

		return {
			business: {
				id: 'settings-area-business',
				title: 'Your business',
				hint: areaHint(business, 'The identity, look and money basics'),
				icon: storeIcon,
				tone: 'inactive',
				rows: business
			},
			growth: {
				id: 'settings-area-growth',
				title: 'Growth',
				hint: 'Follow-ups and reviews',
				icon: trendingUpIcon,
				tone: 'growth',
				rows: growth
			},
			talking: {
				id: 'settings-area-talking',
				title: 'Talking to customers',
				hint: areaHint(talking, 'Email, texts, chat and forms'),
				icon: messagesIcon,
				tone: 'conversation',
				rows: talking
			},
			work: {
				id: 'settings-area-work',
				title: 'Work',
				hint: 'Behind quotes, jobs and invoices',
				icon: hammerIcon,
				tone: 'job',
				rows: work
			},
			team: {
				id: 'settings-area-team',
				title: 'Team',
				hint: 'Who works here, what they can do',
				icon: usersIcon,
				tone: 'inactive',
				rows: team
			}
		};
	});

	// The search narrows every area to the settings whose name or current value matches what was typed.
	const visible = $derived.by(() => {
		if (!areas) return null;
		const narrow = <T extends { rows: SettingsHomeRow[] }>(area: T) => ({
			...area,
			rows: area.rows.filter((row) => rowMatches(row, search))
		});
		const result = {
			business: narrow(areas.business),
			growth: narrow(areas.growth),
			talking: narrow(areas.talking),
			work: narrow(areas.work),
			team: narrow(areas.team)
		};
		const columns = [
			[result.business, result.growth],
			[result.talking],
			[result.work, result.team]
		].map((column) => column.filter((area) => area.rows.length > 0));
		return { columns, matches: columns.flat().length };
	});
</script>

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
			icon={settingsPageIcon}
			tone="inactive"
			title="Settings"
			description={home
				? `How ${home.organization.name} looks to customers and how the CRM works for your team.`
				: 'How your business looks to customers and how the CRM works for your team.'}
		>
			{#snippet actions()}
				<div class="settings-page__search">
					<SearchInput
						id="settings-search"
						bind:value={search}
						placeholder="Search settings: tax, logo, payment terms…"
						ariaLabel="Search settings"
					/>
				</div>
			{/snippet}
		</PageHeader>

		{#if query.isPending}
			<LoadingSkeleton variant="card" rows={3} />
		{:else if query.isError || !home || !visible || !ready}
			<ErrorState description="Settings could not be loaded." retry={() => query.refetch()} />
		{:else}
			{#if !search.trim()}
				<div class="settings-page__top">
					<SettingsHomeBusinessCard
						name={home.organization.name}
						profileComplete={home.readiness.business_profile.complete}
						place={summary?.business.place ?? null}
						phone={summary?.business.phone ?? null}
						email={summary?.business.email ?? null}
						website={summary?.business.website ?? null}
						logoUrl={summary?.business.logo_url ?? null}
						{facts}
						editHref={resolve('/(app)/settings/business-profile')}
					/>
					{#if (home.permissions.business_edit && ready.total > 0) || home.permissions.communications_manage}
						<div class="settings-page__side">
							{#if home.permissions.business_edit && ready.total > 0}
								<SettingsHomeReadyCard {ready} hrefs={readyHrefs} />
							{/if}
							{#if home.permissions.communications_manage}
								<SettingsHomeBalanceCard
									usage={usageQuery.data}
									href={resolve('/(app)/settings/communications/balance')}
								/>
							{/if}
						</div>
					{/if}
				</div>
			{/if}

			{#if visible.matches === 0}
				<EmptyState
					title="No settings match “{search.trim()}”"
					description="Try a shorter word, like tax, logo or email."
					icon={settingsPageIcon}
					tone="inactive"
				/>
			{:else}
				<div class="settings-page__areas">
					{#each visible.columns as column, index (index)}
						<div class="settings-page__column">
							{#each column as area (area.id)}
								<SettingsHomeAreaCard
									id={area.id}
									title={area.title}
									hint={area.hint}
									icon={area.icon}
									tone={area.tone}
									rows={area.rows}
								/>
							{/each}
						</div>
					{/each}
				</div>
			{/if}

			{#if !search.trim()}
				<SettingsHomeAccountStrip
					{userId}
					name={home.member.name ?? home.member.email ?? 'You'}
					role={home.member.role}
					{avatarUrl}
					securityHref={resolve('/(app)/settings/security')}
					alertsHref={resolve('/(app)/settings/alerts')}
					onPhoto={() => (photoOpen = true)}
				/>
			{/if}
		{/if}
	</div>
</PageContainer>

<style lang="scss">
	.settings-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__search {
			width: 360px;
		}
		&__top {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 360px;
			gap: var(--space-large);
			align-items: stretch;
		}
		&__side {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}
		&__areas {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: var(--space-large);
			align-items: start;
		}
		&__column {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			min-width: 0;
		}
	}

	@media (max-width: 1279px) {
		.settings-page__areas {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@media (max-width: 1079px) {
		.settings-page__top {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	@media (max-width: 719px) {
		.settings-page__areas {
			grid-template-columns: minmax(0, 1fr);
		}
		.settings-page__search {
			width: 100%;
		}
	}
</style>
