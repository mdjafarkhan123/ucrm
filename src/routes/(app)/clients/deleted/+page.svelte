<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import FilterChip from '$lib/components/ui/FilterChip.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import RadioTile from '$lib/components/ui/RadioTile.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchRecentlyDeletedClients,
		recentlyDeletedClientsKey,
		restoreClientDeletions,
		type ClientDeletionCounts,
		type ClientRestoreMatch,
		type RecentlyDeletedClient
	} from '$lib/clients/api';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import alarmIcon from '@tabler/icons/outline/alarm.svg?raw';
	import restoreIcon from '@tabler/icons/outline/rotate.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import shieldIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import invoiceIcon from '@tabler/icons/outline/receipt.svg?raw';
	import stopTextIcon from '@tabler/icons/outline/message-circle-off.svg?raw';
	import openIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import keepIcon from '@tabler/icons/outline/user-check.svg?raw';
	import mergeIcon from '@tabler/icons/outline/git-merge.svg?raw';
	import eyeOffIcon from '@tabler/icons/outline/eye-off.svg?raw';
	import requestIcon from '@tabler/icons/outline/inbox.svg?raw';
	import quoteIcon from '@tabler/icons/outline/file-text.svg?raw';
	import jobIcon from '@tabler/icons/outline/hammer.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import fileIcon from '@tabler/icons/outline/file.svg?raw';
	import propertyIcon from '@tabler/icons/outline/home.svg?raw';

	// Data privacy Part 6 (`layout.md` → Recently deleted page, Approved B): HubSpot's restore page and Google
	// Drive's trash. Every client still inside their 30 days, the soonest to go first, each with what comes back.
	// Restore needs no "are you sure?"; a newer client with the same phone or email gets the Merge choice.

	const toast = getToastManager();
	const queryClient = useQueryClient();

	const deletedQuery = createQuery(() => ({
		queryKey: recentlyDeletedClientsKey,
		queryFn: fetchRecentlyDeletedClients,
		staleTime: 15_000
	}));

	let search = $state('');
	let deletedBy = $state('');
	let picked = $state<Set<string>>(new Set());
	let restoringIds = $state<Set<string>>(new Set());
	let matchPrompt = $state<{ row: RecentlyDeletedClient; matches: ClientRestoreMatch[] } | null>(
		null
	);
	let matchChoice = $state<'merge' | 'separate'>('merge');

	const DAY = 24 * 60 * 60 * 1000;
	const rows = $derived(deletedQuery.data ?? []);
	const filtered = $derived(
		rows.filter(
			(row) =>
				(!deletedBy || (row.deleted_by ?? '') === deletedBy) &&
				(!search.trim() || row.display_name.toLowerCase().includes(search.trim().toLowerCase()))
		)
	);
	const daysLeft = (row: RecentlyDeletedClient) =>
		Math.max(0, Math.ceil((new Date(row.purge_after).getTime() - Date.now()) / DAY));
	const urgent = $derived(filtered.filter((row) => daysLeft(row) <= 3));
	const later = $derived(filtered.filter((row) => daysLeft(row) > 3));
	const keptInvoices = $derived(rows.reduce((sum, row) => sum + (row.kept?.invoices ?? 0), 0));

	const deleterOptions = $derived([
		{ value: '', label: 'Anyone' },
		...[
			...new Map(rows.filter((row) => row.deleted_by).map((row) => [row.deleted_by!, row])).values()
		].map((row) => ({ value: row.deleted_by!, label: row.deleted_by_name ?? 'A team member' }))
	]);

	const dateFormat = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' });
	const weekdayFormat = new Intl.DateTimeFormat(undefined, {
		weekday: 'short',
		month: 'short',
		day: 'numeric'
	});

	// What comes back, as count pills in each record's colour.
	const PILLS: {
		key: keyof ClientDeletionCounts;
		one: string;
		many: string;
		icon: string;
		tone: string;
	}[] = [
		{ key: 'properties', one: 'property', many: 'properties', icon: propertyIcon, tone: 'client' },
		{ key: 'requests', one: 'request', many: 'requests', icon: requestIcon, tone: 'request' },
		{ key: 'quotes', one: 'quote', many: 'quotes', icon: quoteIcon, tone: 'quote' },
		{ key: 'jobs', one: 'job', many: 'jobs', icon: jobIcon, tone: 'job' },
		{ key: 'messages', one: 'message', many: 'messages', icon: messageIcon, tone: 'conversation' },
		{ key: 'files', one: 'file', many: 'files', icon: fileIcon, tone: 'informative' }
	];
	const pillsFor = (row: RecentlyDeletedClient) =>
		PILLS.filter((pill) => (row.counts?.[pill.key] ?? 0) > 0).map((pill) => {
			const count = row.counts[pill.key];
			return { ...pill, text: `${count} ${count === 1 ? pill.one : pill.many}` };
		});

	function togglePick(id: string, on: boolean) {
		const next = new Set(picked);
		if (on) next.add(id);
		else next.delete(id);
		picked = next;
	}

	const restoreMutation = createMutation(() => ({
		mutationFn: ({ ids, mode }: { ids: string[]; mode: 'check' | 'separate' | 'merge' }) =>
			restoreClientDeletions(ids, mode),
		onMutate: ({ ids }) => {
			restoringIds = new Set(ids);
		},
		onSuccess: (result) => {
			restoringIds = new Set();
			// Their work, conversations and schedule come back everywhere.
			void queryClient.invalidateQueries();
			const restored = result.restored;
			if (restored.length === 1) {
				const back = restored[0];
				const id = back.merged_into ?? back.client_id;
				toast.show({
					variant: 'success',
					title: `${back.display_name} is back`,
					message: back.merged_into ? 'Merged into the newer client.' : undefined,
					action: {
						label: 'Open client',
						onSelect: () => goto(resolve('/(app)/clients/[id=uuid]', { id }))
					}
				});
			} else if (restored.length > 1) {
				toast.success(`${restored.length} clients are back`);
			}
			picked = new Set([...picked].filter((id) => !restored.some((row) => row.deletion_id === id)));
			matchPrompt = null;

			if (result.matches.length) {
				const firstId = result.matches[0].deletion_id;
				const row = rows.find((candidate) => candidate.deletion_id === firstId);
				if (row) {
					matchChoice =
						new Set(result.matches.map((m) => m.other_client_id)).size === 1 ? 'merge' : 'separate';
					matchPrompt = { row, matches: result.matches.filter((m) => m.deletion_id === firstId) };
				}
			}
		},
		onError: (error: Error, variables) => {
			restoringIds = new Set();
			toast.show({
				variant: 'error',
				title: 'They were not restored',
				message: error.message,
				action: { label: 'Try again', onSelect: () => restoreMutation.mutate(variables) }
			});
		}
	}));

	const restore = (ids: string[]) => restoreMutation.mutate({ ids, mode: 'check' });
	const canMergeMatch = $derived(
		matchPrompt ? new Set(matchPrompt.matches.map((m) => m.other_client_id)).size === 1 : false
	);
</script>

<svelte:head><title>Recently deleted · Contractor CRM</title></svelte:head>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="page-scroller">
	<PageContainer variant="open">
		<Breadcrumbs
			items={[
				{ label: 'Clients', href: resolve('/(app)/clients') },
				{ label: 'Recently deleted', icon: trashIcon }
			]}
		/>
		<PageHeader
			icon={trashIcon}
			tone="client"
			title="Recently deleted"
			description="Clients you deleted in the last 30 days. Restore brings back everything they had."
		/>

		<div class="recently-deleted__toolbar">
			<div class="recently-deleted__search">
				<SearchInput
					id="recently-deleted-search"
					bind:value={search}
					placeholder="Search deleted clients"
					size="compact"
				/>
			</div>
			<FilterChip
				id="recently-deleted-by"
				variant="toolbar"
				icon={userIcon}
				label="Deleted by"
				value={deletedBy}
				options={deleterOptions}
				restValue=""
				onchange={(value) => (deletedBy = value)}
			/>
			{#if rows.length}
				<p class="recently-deleted__total">
					{rows.length} deleted {rows.length === 1 ? 'client' : 'clients'} · {keptInvoices}
					{keptInvoices === 1 ? 'invoice' : 'invoices'} kept
				</p>
			{/if}
		</div>

		<div class="recently-deleted">
			<div class="recently-deleted__main">
				{#if deletedQuery.isPending}
					<Card>
						<ul class="recently-deleted__rows" aria-busy="true">
							{#each { length: 4 } as _, index (index)}
								<li class="recently-deleted__row">
									<span class="recently-deleted__bone recently-deleted__bone--ring"></span>
									<span class="recently-deleted__bone-lines">
										<span class="recently-deleted__bone recently-deleted__bone--name"></span>
										<span class="recently-deleted__bone recently-deleted__bone--pills"></span>
									</span>
									<span class="recently-deleted__bone recently-deleted__bone--button"></span>
								</li>
							{/each}
						</ul>
					</Card>
				{:else if deletedQuery.isError}
					<ErrorState
						title="Recently deleted couldn't load"
						description={deletedQuery.error.message}
						retry={() => deletedQuery.refetch()}
					/>
				{:else if rows.length === 0}
					<EmptyState
						icon={trashIcon}
						tone="client"
						title="Nothing deleted in the last 30 days"
						description="Clients you delete wait here for 30 days, so you can bring them back."
					>
						{#snippet action()}
							<Button variant="secondary" href={resolve('/(app)/clients')}>Back to Clients</Button>
						{/snippet}
					</EmptyState>
				{:else if filtered.length === 0}
					<EmptyState
						icon={searchIcon}
						tone="client"
						title="No deleted client matches"
						description="Try another name, or clear the search."
					>
						{#snippet action()}
							<Button
								variant="quiet"
								onclick={() => {
									search = '';
									deletedBy = '';
								}}>Clear search</Button
							>
						{/snippet}
					</EmptyState>
				{:else}
					{#each [{ key: 'urgent', title: 'Deleted for good this week', icon: alarmIcon, tone: 'critical', list: urgent }, { key: 'later', title: 'Can still be restored', icon: restoreIcon, tone: 'client', list: later }] as section (section.key)}
						{#if section.list.length}
							<Card heading={section.title} icon={section.icon} tone={section.tone}>
								{#snippet actions()}
									<Badge status={section.key === 'urgent' ? 'critical' : 'inactive'} size="small"
										>{section.list.length}</Badge
									>
								{/snippet}
								<ul
									class={[
										'recently-deleted__rows',
										picked.size > 0 && 'recently-deleted__rows--picking'
									]}
								>
									{#each section.list as row (row.deletion_id)}
										{@const days = daysLeft(row)}
										{@const pills = pillsFor(row)}
										{@const busy = restoringIds.has(row.deletion_id)}
										<li
											class={[
												'recently-deleted__row',
												picked.has(row.deletion_id) && 'recently-deleted__row--picked'
											]}
										>
											<span class="recently-deleted__lead">
												<span class="recently-deleted__pick">
													<Checkbox
														id="pick-{row.deletion_id}"
														label="Pick {row.display_name}"
														hideLabel
														checked={picked.has(row.deletion_id)}
														onchange={(on) => togglePick(row.deletion_id, on)}
													/>
												</span>
												<svg
													class={[
														'recently-deleted__ring',
														section.key === 'urgent' && 'recently-deleted__ring--urgent'
													]}
													viewBox="0 0 48 48"
													aria-hidden="true"
												>
													<circle class="recently-deleted__ring-track" cx="24" cy="24" r="21" />
													<circle
														class="recently-deleted__ring-arc"
														cx="24"
														cy="24"
														r="21"
														pathLength="30"
														stroke-dasharray="{days} 30"
													/>
												</svg>
												<span class="recently-deleted__days" aria-label="{days} days left">
													<strong>{days}</strong>
													<span>days</span>
												</span>
											</span>
											<span class="recently-deleted__who">
												<span class="recently-deleted__name-line">
													<span class="recently-deleted__name">{row.display_name}</span>
													<span class="recently-deleted__by">
														Deleted {dateFormat.format(new Date(row.deleted_at))}
														{#if row.deleted_by_name}by {row.deleted_by_name}{/if}
													</span>
												</span>
												{#if pills.length}
													<span class="recently-deleted__pills">
														{#each pills as pill (pill.key)}
															<span
																class="recently-deleted__pill recently-deleted__pill--{pill.tone}"
															>
																<span aria-hidden="true">{@html pill.icon}</span>
																{pill.text}
															</span>
														{/each}
													</span>
												{:else}
													<span class="recently-deleted__only">Only the client record</span>
												{/if}
											</span>
											<span class="recently-deleted__when">
												<span class="recently-deleted__goes">Goes for good</span>
												<span class="recently-deleted__date">
													{(section.key === 'urgent' ? weekdayFormat : dateFormat).format(
														new Date(row.purge_after)
													)}
												</span>
											</span>
											<Button
												variant="secondary"
												size="small"
												loading={busy}
												disabled={restoreMutation.isPending && !busy}
												onclick={() => restore([row.deletion_id])}
											>
												{@html restoreIcon}
												Restore
											</Button>
											<DropdownMenu
												triggerLabel="More actions for {row.display_name}"
												items={[
													{
														label: 'Restore',
														icon: restoreIcon,
														onSelect: () => restore([row.deletion_id])
													}
												]}
											/>
										</li>
									{/each}
								</ul>
							</Card>
						{/if}
					{/each}
				{/if}
			</div>

			<aside class="recently-deleted__side">
				<Card heading="How the 30 days work" icon={hourglassIcon} tone="client">
					<ol class="recently-deleted__steps">
						<li class="recently-deleted__step">
							<span class="recently-deleted__dot" aria-hidden="true">{@html eyeOffIcon}</span>
							<span>
								<span class="recently-deleted__step-title">The day you delete</span>
								<span class="recently-deleted__step-line"
									>They leave lists, search, the schedule and the inbox.</span
								>
							</span>
						</li>
						<li class="recently-deleted__step">
							<span class="recently-deleted__dot" aria-hidden="true">{@html restoreIcon}</span>
							<span>
								<span class="recently-deleted__step-title">Up to 30 days</span>
								<span class="recently-deleted__step-line"
									>Restore brings everything back as it was.</span
								>
							</span>
						</li>
						<li class="recently-deleted__step recently-deleted__step--last">
							<span class="recently-deleted__dot" aria-hidden="true">{@html trashIcon}</span>
							<span>
								<span class="recently-deleted__step-title">Day 30</span>
								<span class="recently-deleted__step-line">Deleted for good, on its own.</span>
							</span>
						</li>
					</ol>
				</Card>
				<Card heading="Always kept" icon={shieldIcon} tone="invoice">
					<ul class="recently-deleted__kept">
						<li>
							<IconTile icon={invoiceIcon} tone="invoice" size={32} />
							<span>
								<span class="recently-deleted__step-title">Invoices and payments</span>
								<span class="recently-deleted__step-line"
									>Tax law needs them as they were issued.</span
								>
							</span>
						</li>
						<li>
							<IconTile icon={stopTextIcon} tone="conversation" size={32} />
							<span>
								<span class="recently-deleted__step-title">"Stop texting" choices</span>
								<span class="recently-deleted__step-line"
									>So nobody texts or emails them by mistake.</span
								>
							</span>
						</li>
					</ul>
					<div class="recently-deleted__kept-link">
						<Button variant="secondary" size="small" href={resolve('/(app)/invoices')}>
							{@html openIcon}
							See kept invoices
						</Button>
					</div>
				</Card>
			</aside>
		</div>
	</PageContainer>
</div>

{#if picked.size > 0}
	<div class="recently-deleted__bar" role="region" aria-label="Picked clients">
		<span class="recently-deleted__bar-count">{picked.size}</span>
		<span class="recently-deleted__bar-label">
			{picked.size === 1 ? '1 client picked' : `${picked.size} clients picked`}
		</span>
		<Button variant="quiet" size="small" onclick={() => (picked = new Set())}>Clear</Button>
		<Button
			variant="primary"
			size="small"
			loading={restoreMutation.isPending && restoringIds.size > 1}
			disabled={restoreMutation.isPending}
			onclick={() => restore([...picked])}
		>
			{@html restoreIcon}
			Restore {picked.size}
		</Button>
	</div>
{/if}

{#if matchPrompt}
	{@const first = matchPrompt.matches[0]}
	<Dialog
		open
		title="Another {first.other_display_name} is in Clients"
		subtitle="Same {first.kind === 'phone' ? 'phone number' : 'email'}: {first.value}"
		icon={usersIcon}
		iconTone="client"
		closeDisabled={restoreMutation.isPending}
		onClose={() => (matchPrompt = null)}
	>
		<div class="restore-match">
			<p class="restore-match__intro">
				While {matchPrompt.row.display_name} was deleted, a newer client got the same contact details.
				Pick how to bring them back.
			</p>
			<div class="restore-match__cards">
				<section class="restore-match__card">
					<header class="restore-match__band">
						<span aria-hidden="true">{@html restoreIcon}</span>
						Coming back
					</header>
					<p class="restore-match__name">{matchPrompt.row.display_name}</p>
				</section>
				<section class="restore-match__card restore-match__card--there">
					<header class="restore-match__band">
						<span aria-hidden="true">{@html keepIcon}</span>
						Already in Clients
					</header>
					<p class="restore-match__name">{first.other_display_name}</p>
				</section>
			</div>
			<div class="restore-match__choices" role="radiogroup" aria-label="How to restore">
				{#if canMergeMatch}
					<RadioTile
						name="restore-match"
						value="merge"
						checked={matchChoice === 'merge'}
						icon={mergeIcon}
						tone="client"
						title="Restore and merge them"
						description="One client with both histories, kept as {first.other_display_name}."
						onselect={() => (matchChoice = 'merge')}
					/>
				{/if}
				<RadioTile
					name="restore-match"
					value="separate"
					checked={matchChoice === 'separate'}
					icon={userIcon}
					tone="client"
					title="Restore as a separate client"
					description="{first.other_display_name} keeps the shared {first.kind === 'phone'
						? 'phone number'
						: 'email'}."
					onselect={() => (matchChoice = 'separate')}
				/>
			</div>
		</div>
		{#snippet footer()}
			<span></span>
			<div class="restore-match__actions">
				<Button
					variant="secondary"
					disabled={restoreMutation.isPending}
					onclick={() => (matchPrompt = null)}>Cancel</Button
				>
				<Button
					variant="primary"
					loading={restoreMutation.isPending}
					onclick={() =>
						matchPrompt &&
						restoreMutation.mutate({ ids: [matchPrompt.row.deletion_id], mode: matchChoice })}
				>
					{@html matchChoice === 'merge' ? mergeIcon : restoreIcon}
					{matchChoice === 'merge' ? 'Restore and merge' : 'Restore'}
				</Button>
			</div>
		{/snippet}
	</Dialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.recently-deleted {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 360px;
		align-items: start;
		gap: var(--space-large);

		&__toolbar {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin-block: var(--space-base) var(--space-medium);
		}

		&__search {
			width: 300px;
			max-width: 100%;
		}

		&__total {
			margin: 0 0 0 auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
			font-weight: 500;
		}

		&__main,
		&__side {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			min-width: 0;
		}

		&__rows {
			margin: 0 calc(-1 * var(--space-medium));
			padding: 0;
			list-style: none;
		}

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-base);
			padding: var(--space-base) var(--space-medium);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}

			&--picked {
				background: var(--color-informative--surface);
			}
		}

		&__lead {
			position: relative;
			display: grid;
			flex: 0 0 auto;
			width: 48px;
			height: 48px;
			place-items: center;
		}

		// The tick box takes the ring's place on hover, and on every row once one is picked.
		&__pick {
			position: absolute;
			z-index: 1;
			display: none;
		}

		&__row:hover &__pick,
		&__row:focus-within &__pick,
		&__rows--picking &__pick {
			display: block;
		}

		&__row:hover &__ring,
		&__row:hover &__days,
		&__row:focus-within &__ring,
		&__row:focus-within &__days,
		&__rows--picking &__ring,
		&__rows--picking &__days {
			visibility: hidden;
		}

		&__ring {
			position: absolute;
			inset: 0;
			width: 48px;
			height: 48px;
			transform: rotate(-90deg);
		}

		&__ring-track,
		&__ring-arc {
			fill: none;
			stroke-width: 4;
		}

		&__ring-track {
			stroke: var(--color-border);
		}

		&__ring-arc {
			stroke: var(--color-client);
			stroke-linecap: round;
		}

		&__ring--urgent &__ring-arc {
			stroke: var(--color-critical);
		}

		&__days {
			display: grid;
			justify-items: center;
			line-height: 1;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 700;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__who {
			display: grid;
			flex: 1;
			gap: var(--space-small);
			min-width: 0;
		}

		&__name-line {
			display: flex;
			flex-wrap: wrap;
			align-items: baseline;
			gap: var(--space-small);
		}

		&__name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__by,
		&__only {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__by {
			font-size: var(--typography--fontSize-label);
		}

		&__pills {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-smaller);
		}

		&__pill {
			--pill-color: var(--color-client);
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			padding: 3px 9px 3px 7px;
			border: var(--border-base) solid var(--color-client--surface-edge);
			border-radius: var(--radius-circle);
			color: var(--color-client--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			span {
				display: inline-flex;
				color: var(--pill-color);
			}

			:global(svg) {
				width: 12px;
				height: 12px;
			}

			@each $tone in (request, quote, job, conversation, informative) {
				&--#{$tone} {
					--pill-color: var(--color-#{$tone});
					border-color: var(--color-#{$tone}--surface-edge);
					color: var(--color-#{$tone}--onSurface);
				}
			}
		}

		&__when {
			display: grid;
			justify-items: end;
			gap: 2px;
		}

		&__goes {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-transform: uppercase;
		}

		&__date {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__bone {
			display: block;
			border-radius: var(--radius-small);
			background: var(--color-border);

			&--ring {
				width: 48px;
				height: 48px;
				border-radius: var(--radius-circle);
			}

			&--name {
				width: 180px;
				height: 12px;
			}

			&--pills {
				width: 260px;
				height: 10px;
			}

			&--button {
				width: 80px;
				height: 32px;
				margin-left: auto;
				border-radius: var(--radius-base);
			}
		}

		&__bone-lines {
			display: grid;
			gap: var(--space-small);
		}

		&__steps,
		&__kept {
			display: grid;
			gap: 14px;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__step {
			position: relative;
			display: flex;
			gap: 12px;

			&:not(:last-child)::after {
				position: absolute;
				top: 28px;
				bottom: -14px;
				left: 13px;
				width: 2px;
				background: var(--color-border);
				content: '';
			}

			&--last .recently-deleted__dot {
				border-color: var(--color-critical--surface-edge);
				color: var(--color-critical);
			}
		}

		&__step > span:last-child,
		&__kept li > span {
			display: grid;
			gap: 2px;
		}

		&__kept li {
			display: flex;
			align-items: center;
			gap: 12px;
		}

		&__dot {
			display: grid;
			flex: 0 0 auto;
			width: 28px;
			height: 28px;
			place-items: center;
			border: var(--border-base) solid var(--color-client--surface-edge);
			border-radius: var(--radius-circle);
			color: var(--color-client);
			background: var(--color-surface);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__step-title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__step-line {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__kept-link {
			margin-top: 14px;
			padding-top: 14px;
			border-top: var(--border-base) solid var(--color-border);
		}

		&__bar {
			position: fixed;
			bottom: var(--space-large);
			left: 50%;
			z-index: 20;
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 10px 10px 10px var(--space-base);
			transform: translateX(-50%);
			border-radius: 12px;
			background: var(--color-surface);
			box-shadow: var(--shadow-high);
		}

		&__bar-count {
			display: grid;
			width: 24px;
			height: 24px;
			place-items: center;
			border-radius: var(--radius-circle);
			color: var(--color-text--reverse);
			background: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__bar-label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}
	}

	.restore-match {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__intro {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
		}

		&__cards {
			display: grid;
			grid-template-columns: 1fr 1fr;
			gap: var(--space-slim);
		}

		&__card {
			overflow: hidden;
			border: var(--border-base) solid var(--color-client--surface-edge);
			border-radius: 12px;

			&--there {
				border-color: var(--color-informative--surface-edge);
			}
		}

		&__band {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-slim);
			color: var(--color-client--onSurface);
			background: var(--color-client--surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			span {
				display: inline-flex;
			}

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__card--there &__band {
			color: var(--color-informative--onSurface);
			background: var(--color-informative--surface);
		}

		&__name {
			margin: 0;
			padding: var(--space-slim);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__choices {
			display: grid;
			gap: var(--space-small);
		}

		&__actions {
			display: flex;
			gap: var(--space-small);
		}
	}
</style>
