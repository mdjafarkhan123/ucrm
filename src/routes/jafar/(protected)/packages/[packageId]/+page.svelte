<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate, goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import PackageAllowancesBlock from '$lib/components/jafar/packages/PackageAllowancesBlock.svelte';
	import PackageCapabilitiesBlock from '$lib/components/jafar/packages/PackageCapabilitiesBlock.svelte';
	import PackageDraftConflictDialog from '$lib/components/jafar/packages/PackageDraftConflictDialog.svelte';
	import PackageHistory from '$lib/components/jafar/packages/PackageHistory.svelte';
	import PackageListRows from '$lib/components/jafar/packages/PackageListRows.svelte';
	import PackagePublishDialog from '$lib/components/jafar/packages/PackagePublishDialog.svelte';
	import PackageWebsiteReminder from '$lib/components/jafar/packages/PackageWebsiteReminder.svelte';
	import { jafarPackageKey, jafarPackagesKey } from '$lib/jafar/query-keys';
	import {
		allowanceApplies,
		changePackage,
		deletePackageDraft,
		describeDraft,
		draftDifferences,
		fetchPackageBuilder,
		formatUsd,
		formFromTerms,
		isStaleDraft,
		openPackageDraft,
		PackageApiError,
		publishPackageDraft,
		savePackageDraft,
		type CatalogAction,
		type DraftForm,
		type EditionTerms,
		type PackageBuilder,
		type PublishProblem
	} from '$lib/jafar/packages';

	// Package builder P6: Jafar edits one package's draft and saves all of it together. The save names the
	// revision this tab loaded; if another tab saved first, nothing is written and the two versions are
	// compared (ADR 0003 decision 3). P7: Jafar publishes the exact saved draft after reviewing it, and
	// changes who can choose the package, archives or restores it, and confirms the marketing site matches.
	const queryClient = useQueryClient();
	const toast = getToastManager();
	const packageId = $derived(page.params.packageId ?? '');

	const builderQuery = createQuery(() => ({
		queryKey: jafarPackageKey(packageId),
		queryFn: () => fetchPackageBuilder(packageId),
		staleTime: 30_000
	}));
	const builder = $derived(builderQuery.data);

	let form = $state<DraftForm | null>(null);
	let loaded = $state<{ editionId: string; revision: number; snapshot: string } | null>(null);
	let saving = $state(false);
	let opening = $state(false);
	let saveError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let conflict = $state<EditionTerms | null>(null);
	let deleteOpen = $state(false);
	let deleting = $state(false);
	let layout = $state<RecordFormLayout>();
	let publishOpen = $state(false);
	let publishing = $state(false);
	let publishProblems = $state<PublishProblem[]>([]);
	let archiveOpen = $state(false);
	let catalogPending = $state<CatalogAction['action'] | null>(null);

	/** The draft exactly as it would be saved: core features always in, one allowance row per allowance. */
	function normalize(draft: DraftForm, reference: PackageBuilder): DraftForm {
		const capabilities = reference.capabilities
			.filter(
				(capability) => capability.kind === 'core' || draft.capabilities.includes(capability.key)
			)
			.map((capability) => capability.key);
		return {
			...draft,
			capabilities,
			allowances: reference.allowances.map((allowance) => {
				const current = draft.allowances.find((value) => value.key === allowance.key);
				if (!allowanceApplies(allowance, capabilities)) {
					return { key: allowance.key, state: 'not_included', value: null };
				}
				if (current?.state === 'unlimited') {
					return { key: allowance.key, state: 'unlimited', value: null };
				}
				return { key: allowance.key, state: 'numeric', value: current?.value ?? null };
			})
		};
	}

	function load(reference: PackageBuilder, terms: EditionTerms) {
		const next = normalize(formFromTerms(terms, reference.package.slug), reference);
		form = next;
		loaded = {
			editionId: terms.edition_id,
			revision: terms.revision,
			snapshot: JSON.stringify(next)
		};
		fieldErrors = {};
		saveError = '';
	}

	// Load the draft when it first arrives or changes underneath an untouched form. A newer revision never
	// replaces edits in progress; saving them brings up the comparison instead.
	$effect(() => {
		const reference = builder;
		untrack(() => {
			if (!reference?.draft) {
				form = null;
				loaded = null;
				return;
			}
			if (
				!loaded ||
				loaded.editionId !== reference.draft.edition_id ||
				(loaded.revision !== reference.draft.revision && !dirty)
			) {
				load(reference, reference.draft);
			}
		});
	});

	const normalized = $derived(form && builder ? normalize(form, builder) : null);
	const dirty = $derived(
		normalized !== null && loaded !== null && JSON.stringify(normalized) !== loaded.snapshot
	);

	const yearlySaving = $derived.by(() => {
		if (form?.monthly_price_usd_cents == null || form.yearly_price_usd_cents == null) return null;
		const twelveMonths = form.monthly_price_usd_cents * 12;
		if (twelveMonths === 0) return null;
		return {
			amount: twelveMonths - form.yearly_price_usd_cents,
			percent: Math.round(((twelveMonths - form.yearly_price_usd_cents) / twelveMonths) * 100)
		};
	});

	const allowanceErrors = $derived.by(() => {
		const errors: Record<string, string> = {};
		for (const [path, message] of Object.entries(fieldErrors)) {
			const match = /^allowances\.(\d+)/.exec(path);
			const key = match && normalized?.allowances[Number(match[1])]?.key;
			if (key) errors[key] = message;
		}
		return errors;
	});

	const errorFields = $derived(
		Object.keys(fieldErrors).length === 0
			? []
			: [
					...(fieldErrors.name ? [{ anchor: 'package-name', label: 'Name' }] : []),
					...(fieldErrors.slug ? [{ anchor: 'package-slug', label: 'Web address' }] : []),
					...(Object.keys(allowanceErrors).length
						? [{ anchor: 'package-allowances', label: 'Allowances' }]
						: [])
				]
	);

	beforeNavigate((navigation) => {
		if (!dirty || saving) return;
		if (!confirm('Leave this page? Your changes to this draft have not been saved.')) {
			navigation.cancel();
		}
	});
	$effect(() => {
		function handler(event: BeforeUnloadEvent) {
			if (dirty) event.preventDefault();
		}
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	function missingAllowanceNumbers(draft: DraftForm) {
		const errors: Record<string, string> = {};
		draft.allowances.forEach((allowance, index) => {
			if (allowance.state === 'numeric' && allowance.value === null) {
				errors[`allowances.${index}.value`] = 'Enter a number.';
			}
		});
		return errors;
	}

	async function save(revision = loaded?.revision) {
		if (!normalized || !loaded || revision === undefined) return;
		saveError = '';
		fieldErrors = missingAllowanceNumbers(normalized);
		if (Object.keys(fieldErrors).length) {
			saveError = 'Some allowances have no number. Enter one, or switch them to Unlimited.';
			return;
		}
		saving = true;
		try {
			const { draft } = await savePackageDraft(packageId, {
				edition_id: loaded.editionId,
				revision,
				terms: normalized
			});
			conflict = null;
			queryClient.setQueryData<PackageBuilder>(jafarPackageKey(packageId), (current) =>
				current
					? {
							...current,
							draft: { ...draft, publish_problems: current.draft?.publish_problems ?? [] },
							package: { ...current.package, slug: normalized.slug }
						}
					: current
			);
			load({ ...builder!, package: { ...builder!.package, slug: normalized.slug } }, draft);
			// The publish checks for the new terms come with the refetched package; saving stays true until
			// they arrive, so Review and publish never offers the old answer.
			await refreshPackage();
			toast.success('Draft saved.');
		} catch (error) {
			if (isStaleDraft(error) && error.body.draft) {
				const saved = error.body.draft;
				if (
					draftDifferences(normalized, savedForm(saved), builder!.capabilities, builder!.allowances)
						.length === 0
				) {
					// The other tab saved the same terms; adopt its revision and nothing is lost.
					await save(saved.revision);
					return;
				}
				conflict = saved;
			} else if (error instanceof PackageApiError && error.body.field_errors) {
				fieldErrors = error.body.field_errors;
				saveError = error.message;
			} else {
				saveError = error instanceof Error ? error.message : 'The draft could not be saved.';
				if (error instanceof PackageApiError && error.status === 404) {
					await queryClient.invalidateQueries({ queryKey: jafarPackageKey(packageId) });
				}
			}
		} finally {
			saving = false;
		}
	}

	function savedForm(terms: EditionTerms) {
		return normalize(formFromTerms(terms, form?.slug ?? builder!.package.slug), builder!);
	}

	function useSaved() {
		if (!conflict || !builder) return;
		const saved = conflict;
		conflict = null;
		queryClient.setQueryData<PackageBuilder>(jafarPackageKey(packageId), (current) =>
			current
				? {
						...current,
						draft: { ...saved, publish_problems: current.draft?.publish_problems ?? [] }
					}
				: current
		);
		void queryClient.invalidateQueries({ queryKey: jafarPackageKey(packageId) });
		load(builder, saved);
		toast.success('Loaded the saved version.');
	}

	function cancel() {
		if (builder?.draft) load(builder, builder.draft);
	}

	async function startDraft() {
		opening = true;
		try {
			await openPackageDraft(packageId);
			await queryClient.invalidateQueries({ queryKey: jafarPackageKey(packageId) });
			await queryClient.invalidateQueries({ queryKey: jafarPackagesKey });
		} catch (error) {
			toast.error(error instanceof Error ? error.message : 'The draft could not be started.');
		} finally {
			opening = false;
		}
	}

	async function removeDraft() {
		if (!loaded) return;
		deleting = true;
		try {
			const result = await deletePackageDraft(packageId, {
				edition_id: loaded.editionId,
				revision: loaded.revision
			});
			deleteOpen = false;
			form = null;
			loaded = null;
			await queryClient.invalidateQueries({ queryKey: jafarPackagesKey });
			if (result.package_removed) {
				queryClient.removeQueries({ queryKey: jafarPackageKey(packageId) });
				toast.success('Package deleted.');
				await goto(resolve('/jafar/packages'));
			} else {
				await queryClient.invalidateQueries({ queryKey: jafarPackageKey(packageId) });
				toast.success('Draft discarded.');
			}
		} catch (error) {
			deleteOpen = false;
			toast.error(
				isStaleDraft(error)
					? 'This draft was saved in another tab. Review the latest version before deleting it.'
					: error instanceof Error
						? error.message
						: 'The draft could not be deleted.'
			);
			await queryClient.invalidateQueries({ queryKey: jafarPackageKey(packageId) });
		} finally {
			deleting = false;
		}
	}

	// The saved draft in words, and which lines differ from the published edition, for the publish review.
	const savedLines = $derived(
		builder?.draft
			? describeDraft(savedForm(builder.draft), builder.capabilities, builder.allowances)
			: []
	);
	const changedFields = $derived.by(() => {
		if (!builder?.published) return new Set<string>();
		const published = describeDraft(
			savedForm(builder.published),
			builder.capabilities,
			builder.allowances
		);
		return new Set(
			savedLines
				.filter((line, index) => line.value !== published[index]?.value)
				.map((line) => line.field)
		);
	});
	const listing = $derived<'public' | 'private' | 'archived'>(
		builder?.package.archived_at ? 'archived' : (builder?.package.visibility ?? 'private')
	);
	const savedProblems = $derived(builder?.draft?.publish_problems ?? []);
	const websiteChanges = $derived.by(() => {
		const since = builder?.package.website_update_pending_since;
		if (!builder || !since) return [];
		return builder.history
			.filter((event) => event.created_at >= since && event.event_type !== 'website_confirmed')
			.reverse();
	});

	function openPublish() {
		publishProblems = [];
		publishOpen = true;
	}

	async function refreshPackage() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: jafarPackageKey(packageId) }),
			queryClient.invalidateQueries({ queryKey: jafarPackagesKey })
		]);
	}

	async function publish() {
		if (!loaded || dirty) return;
		publishing = true;
		try {
			const result = await publishPackageDraft(packageId, {
				edition_id: loaded.editionId,
				revision: loaded.revision
			});
			publishOpen = false;
			toast.success(`Edition ${result.edition_number} published.`);
			await refreshPackage();
		} catch (error) {
			if (error instanceof PackageApiError && error.body.reason === 'not_ready') {
				publishProblems = error.body.problems ?? [];
				await refreshPackage();
			} else {
				publishOpen = false;
				toast.error(
					isStaleDraft(error)
						? 'This draft was saved again after you opened the review. Check the latest version, then publish.'
						: error instanceof Error
							? error.message
							: 'The draft could not be published.'
				);
				await refreshPackage();
			}
		} finally {
			publishing = false;
		}
	}

	async function runCatalogAction(command: CatalogAction, success: string) {
		catalogPending = command.action;
		try {
			await changePackage(packageId, command);
			archiveOpen = false;
			toast.success(success);
		} catch (error) {
			archiveOpen = false;
			toast.error(error instanceof Error ? error.message : 'The package could not be changed.');
		} finally {
			catalogPending = null;
			await refreshPackage();
		}
	}

	function formatDate(value: string) {
		return new Date(value).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
	}
</script>

<svelte:head
	><title>{form?.name || builder?.published?.name || 'Package'} · Packages · Control Room</title
	></svelte:head
>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="package-builder">
	{#if builderQuery.isPending}
		<LoadingSkeleton variant="card" rows={6} label="Loading package" />
	{:else if builderQuery.isError}
		<ErrorState
			title="The package could not be loaded"
			description={builderQuery.error.message}
			retry={() => builderQuery.refetch()}
		/>
	{:else if builder}
		<Breadcrumbs
			items={[
				{ label: 'Packages', href: resolve('/jafar/packages') },
				{ label: (builder.draft ?? builder.published)?.name ?? 'Package' }
			]}
		/>

		{#snippet rail()}
			<RailCard title="Status">
				<dl class="package-builder__status">
					<div>
						<dt>Draft</dt>
						<dd>
							{#if builder.draft}
								<Badge status={dirty ? 'warning' : 'inactive'} size="small"
									>{dirty ? 'Unsaved changes' : 'Saved'}</Badge
								>
								<span class="package-builder__muted"
									>Last saved {formatDate(builder.draft.updated_at)}{builder.draft.updated_by_email
										? ` by ${builder.draft.updated_by_email}`
										: ''}</span
								>
							{:else}
								<span class="package-builder__muted">No draft open</span>
							{/if}
						</dd>
					</div>
					<div>
						<dt>Published</dt>
						<dd>
							{#if builder.published}
								<Badge status="success" size="small"
									>Edition {builder.published.edition_number}</Badge
								>
								<span class="package-builder__muted"
									>{builder.package.organization_count}
									{builder.package.organization_count === 1 ? 'customer' : 'customers'} on this package</span
								>
							{:else}
								<span class="package-builder__muted"
									>Never published. Nobody can see or buy it.</span
								>
							{/if}
						</dd>
					</div>
					{#if builder.package.ever_published}
						<div>
							<dt>New customers</dt>
							<dd>
								{#if listing === 'archived'}
									<Badge size="small">Archived</Badge>
									<span class="package-builder__muted"
										>Hidden from new customers. Customers on it keep their edition.</span
									>
								{:else if listing === 'public'}
									<Badge status="informative" size="small">Public</Badge>
									<span class="package-builder__muted">Can choose it on sign-up.</span>
								{:else}
									<Badge status="inactive" size="small">Private</Badge>
									<span class="package-builder__muted">Only you can assign it.</span>
								{/if}
							</dd>
						</div>
					{/if}
				</dl>
				{#if builder.draft}
					<p class="package-builder__muted">
						{builder.published
							? `Saving changes the draft only. Customers keep edition ${builder.published.edition_number} until you move them.`
							: 'Saving keeps this as a private draft.'}
					</p>
				{/if}
			</RailCard>

			{#if builder.draft}
				<RailCard title="Publish">
					{#if dirty}
						<p class="package-builder__muted">
							Save your changes first. Publishing uses the saved draft, exactly as saved.
						</p>
					{:else if savedProblems.length}
						<p class="package-builder__muted">Fix these before publishing:</p>
						<ul class="package-builder__problems">
							{#each savedProblems as problem (problem.code + (problem.key ?? ''))}
								<li>{problem.message}</li>
							{/each}
						</ul>
					{:else}
						<p class="package-builder__muted">
							Review the saved terms, then publish them as edition {(builder.published
								?.edition_number ?? 0) + 1}.
						</p>
					{/if}
					<div>
						<Button
							size="small"
							disabled={dirty || saving || savedProblems.length > 0}
							onclick={openPublish}
							><span class="package-builder__button-icon" aria-hidden="true">{@html sendIcon}</span
							>Review and publish</Button
						>
					</div>
				</RailCard>
			{/if}

			{#if builder.package.ever_published}
				<RailCard title="Catalog">
					{#if listing === 'archived'}
						<p class="package-builder__muted">
							Restoring lets new customers choose it again{builder.package.visibility === 'private'
								? ' once it is public'
								: ''}.
						</p>
						<div>
							<Button
								size="small"
								variant="secondary"
								loading={catalogPending === 'restore'}
								disabled={catalogPending !== null}
								onclick={() => runCatalogAction({ action: 'restore' }, 'Package restored.')}
								>Restore package</Button
							>
						</div>
					{:else}
						<p class="package-builder__muted">
							{builder.package.visibility === 'public'
								? 'Making it private removes it from sign-up. You can still assign it to a customer.'
								: 'Making it public lists it on sign-up for new customers.'}
						</p>
						<div class="package-builder__rail-actions">
							<Button
								size="small"
								variant="secondary"
								loading={catalogPending === 'set_visibility'}
								disabled={catalogPending !== null}
								onclick={() =>
									runCatalogAction(
										{
											action: 'set_visibility',
											visibility: builder.package.visibility === 'public' ? 'private' : 'public'
										},
										builder.package.visibility === 'public'
											? 'Package made private.'
											: 'Package made public.'
									)}
								>{builder.package.visibility === 'public' ? 'Make private' : 'Make public'}</Button
							>
							<Button
								size="small"
								variant="secondary"
								disabled={catalogPending !== null}
								onclick={() => (archiveOpen = true)}
								><span class="package-builder__button-icon" aria-hidden="true"
									>{@html archiveIcon}</span
								>Archive</Button
							>
						</div>
					{/if}
				</RailCard>
			{/if}

			<RailCard title="History">
				<PackageHistory events={builder.history} />
			</RailCard>

			{#if builder.draft}
				<RailCard title={builder.published ? 'Discard draft' : 'Delete draft'}>
					<p class="package-builder__muted">
						{builder.published
							? 'Throw away this draft. The published edition and its customers are not affected.'
							: builder.package.email_template_count > 0
								? 'An email template is limited to this package. Change that template before deleting it.'
								: 'Nobody uses this package yet, so it can be deleted.'}
					</p>
					<div>
						<Button
							variant="secondary"
							variation="destructive"
							size="small"
							disabled={!builder.published && builder.package.email_template_count > 0}
							onclick={() => (deleteOpen = true)}
							>{builder.published ? 'Discard draft' : 'Delete draft'}</Button
						>
					</div>
				</RailCard>
			{/if}
		{/snippet}

		{#if builder.package.website_update_pending_since}
			<PackageWebsiteReminder
				name={builder.published?.name ?? builder.draft?.name ?? 'This package'}
				changes={websiteChanges}
				pending={catalogPending === 'confirm_website'}
				onConfirm={() =>
					runCatalogAction(
						{
							action: 'confirm_website',
							pending_since: builder.package.website_update_pending_since!
						},
						'Marked the marketing site as up to date.'
					)}
			/>
		{/if}

		{#if !builder.draft}
			<RecordFormLayout title={builder.published?.name ?? 'Package'} icon={packageIcon} {rail}>
				{#snippet main()}
					<div class="package-builder__published">
						<p>
							Edition {builder.published?.edition_number} is published, and its terms cannot change. To
							change this package, start a draft from it. Customers stay on edition {builder
								.published?.edition_number} until you move them.
						</p>
						<div>
							<Button loading={opening} onclick={startDraft}
								><span class="package-builder__button-icon" aria-hidden="true"
									>{@html pencilIcon}</span
								>Start a draft</Button
							>
						</div>
					</div>
				{/snippet}
			</RecordFormLayout>
		{:else if form}
			<RecordFormLayout
				title={form.name || 'Untitled package'}
				icon={packageIcon}
				bind:this={layout}
				error={saveError}
				{errorFields}
				{rail}
			>
				{#snippet main()}
					<SectionBlock title="Package" form>
						<Input
							id="package-name"
							label="Name"
							required
							bind:value={form!.name}
							invalid={Boolean(fieldErrors.name)}
							errorMessage={fieldErrors.name}
						/>
						<div class="package-builder__field">
							<Input
								id="package-slug"
								label="Web address"
								required
								bind:value={form!.slug}
								disabled={builder.package.ever_published}
								invalid={Boolean(fieldErrors.slug)}
								errorMessage={fieldErrors.slug}
							/>
							{#if !fieldErrors.slug}
								<p class="package-builder__hint">
									{builder.package.ever_published
										? 'Fixed once published, so links from your marketing site keep working.'
										: 'Used in links from your marketing site. Fixed once published.'}
								</p>
							{/if}
						</div>
						<Textarea
							id="package-promise"
							label="Promise"
							rows={2}
							maxlength={300}
							bind:value={form!.promise}
							invalid={Boolean(fieldErrors.promise)}
							errorMessage={fieldErrors.promise}
						/>
					</SectionBlock>

					<SectionBlock
						title="Prices"
						form
						hint="US dollars. Yearly is paid once, upfront, for the whole year."
					>
						<div class="package-builder__prices">
							<div class="package-builder__price">
								<Checkbox
									id="package-offer-monthly"
									label="Offer monthly billing"
									checked={form!.monthly_price_usd_cents !== null}
									onchange={(checked) => (form!.monthly_price_usd_cents = checked ? 0 : null)}
								/>
								{#if form!.monthly_price_usd_cents !== null}
									<MoneyInput
										id="package-monthly-price"
										label="Price per month"
										bind:value={
											() => form!.monthly_price_usd_cents ?? 0,
											(cents) => (form!.monthly_price_usd_cents = cents)
										}
										invalid={Boolean(fieldErrors.monthly_price_usd_cents)}
										errorMessage={fieldErrors.monthly_price_usd_cents}
									/>
								{/if}
							</div>
							<div class="package-builder__price">
								<Checkbox
									id="package-offer-yearly"
									label="Offer yearly billing"
									checked={form!.yearly_price_usd_cents !== null}
									onchange={(checked) => (form!.yearly_price_usd_cents = checked ? 0 : null)}
								/>
								{#if form!.yearly_price_usd_cents !== null}
									<MoneyInput
										id="package-yearly-price"
										label="Price per year"
										bind:value={
											() => form!.yearly_price_usd_cents ?? 0,
											(cents) => (form!.yearly_price_usd_cents = cents)
										}
										invalid={Boolean(fieldErrors.yearly_price_usd_cents)}
										errorMessage={fieldErrors.yearly_price_usd_cents}
									/>
								{/if}
							</div>
						</div>
						{#if yearlySaving}
							<p
								class="package-builder__hint"
								class:package-builder__hint--warning={yearlySaving.amount < 0}
							>
								{yearlySaving.amount > 0
									? `Yearly saves the customer ${formatUsd(yearlySaving.amount)} (${yearlySaving.percent}%) compared with 12 monthly payments.`
									: yearlySaving.amount < 0
										? `Yearly costs ${formatUsd(-yearlySaving.amount)} more than 12 monthly payments.`
										: 'Yearly costs the same as 12 monthly payments.'}
							</p>
						{/if}
						{#if form!.monthly_price_usd_cents === null && form!.yearly_price_usd_cents === null}
							<p class="package-builder__hint">
								Choose at least one billing option before the package can be published.
							</p>
						{/if}
					</SectionBlock>

					<SectionBlock
						title="Customer highlights"
						form
						hint="Short selling points for the package card, like “Never miss a lead”. Four to six read best. They describe the package; they do not turn anything on."
					>
						<PackageListRows
							bind:items={form!.highlights}
							itemName="highlight"
							addLabel="Add highlight"
							max={12}
							emptyText="No highlights yet."
							create={() => ''}
						>
							{#snippet row(index)}
								<Input
									id={`package-highlight-${index}`}
									size="small"
									aria-label={`Highlight ${index + 1}`}
									maxlength={80}
									bind:value={form!.highlights[index]}
									invalid={Boolean(fieldErrors[`highlights.${index}`])}
									errorMessage={fieldErrors[`highlights.${index}`]}
								/>
							{/snippet}
						</PackageListRows>
					</SectionBlock>

					<SectionBlock
						title="Included services"
						form
						hint="Work Uplift delivers as part of the package, like a premium website or Google Business Profile management. Do not promise rankings or 5-star reviews."
					>
						<PackageListRows
							bind:items={form!.included_services}
							itemName="service"
							addLabel="Add service"
							max={12}
							emptyText="No services included. The package is app access only."
							create={() => ({ name: '', description: '' })}
						>
							{#snippet row(index)}
								<Input
									id={`package-service-name-${index}`}
									size="small"
									label="Service"
									maxlength={80}
									bind:value={form!.included_services[index].name}
									invalid={Boolean(fieldErrors[`included_services.${index}.name`])}
									errorMessage={fieldErrors[`included_services.${index}.name`]}
								/>
								<Textarea
									id={`package-service-description-${index}`}
									label="What the customer gets"
									rows={2}
									maxlength={300}
									bind:value={form!.included_services[index].description}
									invalid={Boolean(fieldErrors[`included_services.${index}.description`])}
									errorMessage={fieldErrors[`included_services.${index}.description`]}
								/>
							{/snippet}
						</PackageListRows>
					</SectionBlock>

					<PackageCapabilitiesBlock
						capabilities={builder.capabilities}
						bind:selected={form!.capabilities}
					/>

					<PackageAllowancesBlock
						allowances={builder.allowances}
						capabilities={builder.capabilities}
						selected={normalized?.capabilities ?? form!.capabilities}
						bind:values={form!.allowances}
						errors={allowanceErrors}
					/>

					<SectionBlock
						title="Exclusions and prerequisites"
						form
						hint="What the package does not cover, or what the customer must provide. Shown in the package details."
					>
						<Textarea
							id="package-exclusions"
							label="Exclusions and prerequisites"
							rows={4}
							maxlength={2000}
							bind:value={form!.exclusions}
							invalid={Boolean(fieldErrors.exclusions)}
							errorMessage={fieldErrors.exclusions}
						/>
					</SectionBlock>
				{/snippet}

				{#snippet actions()}
					<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
					<Button
						onclick={() => void save().finally(() => layout?.revealError())}
						disabled={!dirty || saving}
						loading={saving}>Save draft</Button
					>
				{/snippet}
			</RecordFormLayout>
		{/if}
	{/if}
</main>

{#if form && builder}
	<PackageDraftConflictDialog
		open={conflict !== null}
		differences={conflict
			? draftDifferences(
					normalized ?? form,
					savedForm(conflict),
					builder.capabilities,
					builder.allowances
				)
			: []}
		savedBy={conflict?.updated_by_email ?? null}
		savedAt={conflict?.updated_at ?? null}
		pending={saving}
		onKeepMine={() => conflict && void save(conflict.revision)}
		onUseSaved={useSaved}
		onClose={() => (conflict = null)}
	/>
{/if}

{#if builder?.draft}
	<PackagePublishDialog
		open={publishOpen}
		editionNumber={(builder.published?.edition_number ?? 0) + 1}
		lines={savedLines}
		{changedFields}
		previousEditionNumber={builder.published?.edition_number ?? null}
		customerCount={builder.package.organization_count}
		{listing}
		problems={publishProblems}
		pending={publishing}
		onPublish={publish}
		onClose={() => (publishOpen = false)}
	/>
{/if}

<ConfirmDialog
	open={archiveOpen}
	title="Archive this package?"
	icon={archiveIcon}
	confirmLabel="Archive package"
	loading={catalogPending === 'archive'}
	onConfirm={() => runCatalogAction({ action: 'archive' }, 'Package archived.')}
	onClose={() => (archiveOpen = false)}
>
	<p>
		New customers can no longer choose it. {builder?.package.organization_count
			? `The ${builder.package.organization_count} ${builder.package.organization_count === 1 ? 'customer' : 'customers'} already on it keep their edition, price, and access.`
			: 'Nobody is on it today.'} You can restore it at any time.
	</p>
</ConfirmDialog>

<ConfirmDialog
	open={deleteOpen}
	title={builder?.published ? 'Discard draft?' : 'Delete draft?'}
	icon={trashIcon}
	tone="critical"
	destructive
	confirmLabel={builder?.published ? 'Discard draft' : 'Delete draft'}
	loading={deleting}
	onConfirm={removeDraft}
	onClose={() => (deleteOpen = false)}
>
	<p>
		{builder?.published
			? `The changes in this draft are thrown away. Edition ${builder.published.edition_number} and its customers are not affected.`
			: 'This package was never published, so nobody uses it. The draft and its web address are removed for good.'}
	</p>
</ConfirmDialog>

<style lang="scss">
	.package-builder {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__field {
			display: grid;
			gap: var(--space-small);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);

			&--warning {
				color: var(--color-warning--onSurface);
			}
		}

		&__prices {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
			gap: var(--space-base);
		}

		&__price {
			display: grid;
			align-content: start;
			gap: var(--space-slim);
		}

		&__published {
			display: grid;
			gap: var(--space-base);

			p {
				margin: 0;
				max-width: 64ch;
				color: var(--color-text--secondary);
				line-height: var(--typography--lineHeight-base);
			}
		}

		&__status {
			display: grid;
			gap: var(--space-base);
			margin: 0;

			div {
				display: grid;
				gap: var(--space-smaller);
			}

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}

			dd {
				display: grid;
				justify-items: start;
				gap: var(--space-smaller);
				margin: 0;
			}
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__problems {
			display: grid;
			gap: var(--space-smaller);
			margin: 0;
			padding-inline-start: var(--space-base);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__rail-actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__button-icon {
			display: inline-flex;
			width: 1.8rem;
			height: 1.8rem;

			:global(svg) {
				width: 100%;
				height: 100%;
			}
		}
	}
</style>
