<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';

	const queryClient = useQueryClient();

	type VersionStatus = 'draft' | 'published' | 'retired';
	type LimitState = 'unlimited' | 'not_included' | 'numeric';
	const employeeSeatOptions = [
		{ value: 'not_included', label: 'Not included' },
		{ value: 'numeric', label: 'Limited number' },
		{ value: 'unlimited', label: 'Unlimited' }
	];
	type PackageVersion = {
		id: string;
		package_id: string;
		version_number: number;
		status: VersionStatus;
		display_name: string;
		public_description: string;
		value_explanation: string | null;
		price_usd_cents: number;
		currency: string;
		billing_period: string;
		published_at: string | null;
		retired_at: string | null;
		created_at: string;
		features: string[];
		limits: { limit_key: string; limit_state: LimitState; limit_value: number | null }[];
	};
	type PackageDefinition = {
		package_id: string;
		package_key: 'starter' | 'growth' | 'elite';
		display_name: string;
		sort_order: number;
		status: 'published' | 'retired';
		versions: PackageVersion[];
	};
	type PackagesResponse = {
		packages: PackageDefinition[];
		feature_catalog: { feature_key: string; description: string | null }[];
		error?: string;
	};
	type MutationResponse = { version_id?: string; package_id?: string; error?: string };

	let selectedPackageKey = $state<PackageDefinition['package_key'] | null>(null);
	let editingVersionId = $state<string | null>(null);
	let displayName = $state('');
	let description = $state('');
	let valueExplanation = $state('');
	let priceDollars = $state('');
	let featureKeys = $state<string[]>([]);
	let employeeSeatState = $state<LimitState>('not_included');
	let employeeSeatCount = $state('');
	let operationalEmailState = $state<LimitState>('not_included');
	let operationalEmailCount = $state('');
	let essentialEmailState = $state<LimitState>('not_included');
	let essentialEmailCount = $state('');
	let actionError = $state('');
	let actionMessage = $state('');
	let publishConfirmed = $state(false);
	let retiringPackageKey = $state<PackageDefinition['package_key'] | null>(null);

	const packages = createQuery<PackagesResponse>(() => ({
		queryKey: ['jafar', 'packages'],
		queryFn: async () => {
			const response = await fetch('/api/jafar/packages');
			const result = (await response.json()) as PackagesResponse;
			if (!response.ok) throw new Error(result.error ?? 'Packages could not be loaded.');
			return result;
		}
	}));

	const packageList = $derived(packages.data?.packages ?? []);
	const selectedPackage = $derived(
		packageList.find((item) => item.package_key === selectedPackageKey) ?? null
	);
	const selectedDraft = $derived(
		selectedPackage?.versions.find((version) => version.id === editingVersionId) ?? null
	);

	const saveDraft = createMutation<MutationResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!selectedPackage) throw new Error('Choose a package first.');
			const response = await fetch('/api/jafar/packages/versions', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					package_key: selectedPackage.package_key,
					version_id: editingVersionId ?? undefined,
					display_name: displayName,
					public_description: description,
					value_explanation: valueExplanation || null,
					price_usd_cents: Math.round(Number(priceDollars) * 100),
					feature_keys: featureKeys,
					limit: {
						key: 'employee_seats',
						state: employeeSeatState,
						value: employeeSeatState === 'numeric' ? Number(employeeSeatCount) : null
					},
					email_allowances: {
						operational: {
							state: operationalEmailState,
							value: operationalEmailState === 'numeric' ? Number(operationalEmailCount) : null
						},
						essential: {
							state: essentialEmailState,
							value: essentialEmailState === 'numeric' ? Number(essentialEmailCount) : null
						}
					}
				})
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'The draft could not be saved.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: (result) => {
			editingVersionId = result.version_id ?? editingVersionId;
			actionMessage = 'Draft saved. Review it, then publish when ready.';
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'packages'] });
		}
	}));

	const publishDraft = createMutation<MutationResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!selectedPackage || !editingVersionId)
				throw new Error('Save a draft before publishing it.');
			const response = await fetch('/api/jafar/packages/publish', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					package_key: selectedPackage.package_key,
					version_id: editingVersionId
				})
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'The draft could not be published.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			publishConfirmed = false;
			editingVersionId = null;
			actionMessage =
				'Package version published. The prior published version is retained for history.';
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'packages'] });
		}
	}));

	const retirePackage = createMutation<MutationResponse, Error, PackageDefinition['package_key']>(
		() => ({
			mutationFn: async (packageKey) => {
				const response = await fetch('/api/jafar/packages/retire', {
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ package_key: packageKey })
				});
				const result = (await response.json()) as MutationResponse;
				if (!response.ok) throw new Error(result.error ?? 'The package could not be retired.');
				return result;
			},
			onMutate: () => clearFeedback(),
			onError: (error) => (actionError = error.message),
			onSuccess: () => {
				retiringPackageKey = null;
				actionMessage = 'Package retired. Organizations already on it keep their current access.';
				void queryClient.invalidateQueries({ queryKey: ['jafar', 'packages'] });
			}
		})
	);

	function clearFeedback() {
		actionError = '';
		actionMessage = '';
	}

	function openEditor(packageItem: PackageDefinition) {
		clearFeedback();
		selectedPackageKey = packageItem.package_key;
		const draft = packageItem.versions.find((version) => version.status === 'draft') ?? null;
		const source =
			draft ?? packageItem.versions.find((version) => version.status === 'published') ?? null;
		editingVersionId = draft?.id ?? null;
		displayName = source?.display_name ?? packageItem.display_name;
		description = source?.public_description ?? '';
		valueExplanation = source?.value_explanation ?? '';
		priceDollars = source ? String(source.price_usd_cents / 100) : '';
		featureKeys = source?.features ?? [];
		const seats = source?.limits.find((limit) => limit.limit_key === 'employee_seats');
		employeeSeatState = seats?.limit_state ?? 'not_included';
		employeeSeatCount = seats?.limit_value !== null ? String(seats.limit_value) : '';
		const operationalEmail = source?.limits.find(
			(limit) => limit.limit_key === 'operational_email_recipients'
		);
		operationalEmailState = operationalEmail?.limit_state ?? 'not_included';
		operationalEmailCount =
			operationalEmail?.limit_value !== null ? String(operationalEmail.limit_value) : '';
		const essentialEmail = source?.limits.find(
			(limit) => limit.limit_key === 'essential_email_recipients'
		);
		essentialEmailState = essentialEmail?.limit_state ?? 'not_included';
		essentialEmailCount =
			essentialEmail?.limit_value !== null ? String(essentialEmail.limit_value) : '';
		publishConfirmed = false;
	}

	function toggleFeature(featureKey: string, checked: boolean) {
		featureKeys = checked
			? [...featureKeys, featureKey]
			: featureKeys.filter((current) => current !== featureKey);
	}

	function formatMoney(cents: number, currency: string) {
		return new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(cents / 100);
	}

	function formatDate(value: string | null) {
		return value
			? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value))
			: '—';
	}

	function statusTone(status: VersionStatus | PackageDefinition['status']) {
		return status === 'published' ? 'success' : status === 'draft' ? 'informative' : 'inactive';
	}

	function seatLabel(version: PackageVersion | undefined) {
		const seats = version?.limits.find((limit) => limit.limit_key === 'employee_seats');
		if (!seats || seats.limit_state === 'not_included') return 'No team seats included';
		return seats.limit_state === 'unlimited'
			? 'Unlimited team seats'
			: `Up to ${seats.limit_value} team seats`;
	}
</script>

<svelte:head><title>Packages · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="packages">
	<header class="packages__header">
		<div>
			<p class="packages__eyebrow">Commercial rules</p>
			<h1>Packages</h1>
			<p class="packages__description">
				One source of truth for public pricing, access, features, and team limits.
			</p>
		</div>
	</header>

	<section class="packages__notice" aria-label="Package versioning">
		<span aria-hidden="true">{@html historyIcon}</span>
		<p>
			<strong>Version history protects existing accounts.</strong> Publishing a draft replaces the public
			definition without changing organizations already assigned to an earlier version.
		</p>
	</section>

	{#if actionMessage}<p class="packages__feedback packages__feedback--success" role="status">
			{actionMessage}
		</p>{/if}
	{#if actionError}<p class="packages__feedback packages__feedback--error" role="alert">
			{actionError}
		</p>{/if}

	{#if packages.isPending}
		<LoadingSkeleton variant="table" rows={5} label="Loading packages" />
	{:else if packages.isError}
		<ErrorState
			title="Packages could not be loaded"
			description={packages.error.message}
			retry={() => packages.refetch()}
		/>
	{:else}
		<section class="packages__grid" aria-label="Package definitions">
			{#each packageList as packageItem (packageItem.package_id)}
				{@const current = packageItem.versions.find((version) => version.status === 'published')}
				{@const draft = packageItem.versions.find((version) => version.status === 'draft')}
				<article
					class:packages__card--featured={packageItem.package_key === 'growth'}
					class="packages__card"
				>
					<header class="packages__card-header">
						<div>
							<p class="packages__eyebrow">
								{packageItem.display_name} · {current
									? `v${current.version_number}`
									: 'No published version'}
							</p>
							<h2>{packageItem.display_name}</h2>
						</div>
						<Badge status={statusTone(draft?.status ?? packageItem.status)}
							>{draft
								? 'Draft ready'
								: packageItem.status === 'retired'
									? 'Retired'
									: 'Published'}</Badge
						>
					</header>
					<div class="packages__price">
						<strong>{current ? formatMoney(current.price_usd_cents, current.currency) : '—'}</strong
						><span>USD / month</span>
					</div>
					<p class="packages__card-description">
						{current?.public_description ?? 'No public package definition is available.'}
					</p>
					<ul>
						{#each (current?.features ?? []).slice(0, 5) as featureKey (featureKey)}
							<li>
								<span aria-hidden="true">{@html checkIcon}</span
								>{packages.data?.feature_catalog.find(
									(feature) => feature.feature_key === featureKey
								)?.description ?? featureKey}
							</li>
						{/each}
					</ul>
					<p class="packages__limits"><strong>Limits</strong>{seatLabel(current)}</p>
					<footer>
						{#if packageItem.status !== 'retired'}<Button
								variant="tertiary"
								onclick={() => openEditor(packageItem)}
								>{draft ? 'Edit draft' : 'Create draft'}</Button
							>{/if}
						{#if packageItem.status === 'published'}<Button
								variant="tertiary"
								onclick={() => (retiringPackageKey = packageItem.package_key)}
								>Retire package</Button
							>{/if}
					</footer>
					{#if retiringPackageKey === packageItem.package_key}
						<div class="packages__retire-confirm" role="alertdialog" aria-live="assertive">
							<span aria-hidden="true">{@html alertIcon}</span>
							<p>
								Retiring stops new organizations from choosing <strong
									>{packageItem.display_name}</strong
								>. Organizations already assigned to it keep their current access.
							</p>
							<div class="packages__retire-confirm-actions">
								<Button
									variant="tertiary"
									onclick={() => (retiringPackageKey = null)}
									disabled={retirePackage.isPending}>Cancel</Button
								>
								<Button
									variation="destructive"
									loading={retirePackage.isPending}
									onclick={() => retirePackage.mutate(packageItem.package_key)}
									>Confirm retire</Button
								>
							</div>
						</div>
					{/if}
				</article>
			{/each}
		</section>

		{#if selectedPackage}
			<section class="packages__editor" aria-labelledby="package-editor-title">
				<header>
					<div>
						<p class="packages__eyebrow">{editingVersionId ? 'Editing draft' : 'New draft'}</p>
						<h2 id="package-editor-title">{selectedPackage.display_name} definition</h2>
						<p>
							A published version is never edited in place. This draft becomes the next version when
							you publish it.
						</p>
					</div>
					<Button
						variant="tertiary"
						onclick={() => {
							selectedPackageKey = null;
							editingVersionId = null;
						}}>Close</Button
					>
				</header>
				<form
					onsubmit={(event) => {
						event.preventDefault();
						saveDraft.mutate();
					}}
				>
					<div class="packages__form-grid">
						<label
							><span>Name</span><input
								bind:value={displayName}
								required
								minlength="2"
								maxlength="80"
							/></label
						>
						<label
							><span>Monthly price (USD)</span><input
								bind:value={priceDollars}
								type="number"
								min="0"
								step="0.01"
								required
							/></label
						>
						<label class="packages__form-wide"
							><span>Public description</span><textarea
								bind:value={description}
								required
								maxlength="500"></textarea></label
						>
						<label class="packages__form-wide"
							><span>Value explanation (optional)</span><textarea
								bind:value={valueExplanation}
								maxlength="500"></textarea></label
						>
					</div>
					<fieldset>
						<legend>Included capabilities</legend>
						<div class="packages__features">
							{#each packages.data?.feature_catalog ?? [] as feature (feature.feature_key)}<label
									><input
										type="checkbox"
										checked={featureKeys.includes(feature.feature_key)}
										onchange={(event) =>
											toggleFeature(feature.feature_key, event.currentTarget.checked)}
									/><span>{feature.description ?? feature.feature_key}</span></label
								>{/each}
						</div>
					</fieldset>
					<fieldset>
						<legend>Team seats</legend>
						<div class="packages__seat-controls">
							<div class="packages__seat-field">
								<label for="employee-seat-state">Availability</label>
								<Select
									id="employee-seat-state"
									value={employeeSeatState}
									options={employeeSeatOptions}
									onchange={(nextValue) => (employeeSeatState = nextValue as LimitState)}
								/>
							</div>
							{#if employeeSeatState === 'numeric'}<label
									><span>Maximum seats</span><input
										bind:value={employeeSeatCount}
										type="number"
										min="1"
										required
									/></label
								>{/if}
						</div>
					</fieldset>
					<fieldset>
						<legend>Email allowances</legend>
						<p class="packages__field-hint">
							Allowances reset at the organization’s subscription-period boundary. Essential mail
							uses its own protected reserve; ordinary mail cannot consume it.
						</p>
						<div class="packages__allowance-controls">
							<div class="packages__allowance-group">
								<h3>Normal recipients</h3>
								<div class="packages__seat-controls">
									<div class="packages__seat-field">
										<label for="operational-email-state">Allowance type</label>
										<Select
											id="operational-email-state"
											value={operationalEmailState}
											options={employeeSeatOptions}
											onchange={(nextValue) => (operationalEmailState = nextValue as LimitState)}
										/>
									</div>
									{#if operationalEmailState === 'numeric'}
										<label
											><span>Recipients per period</span><input
												bind:value={operationalEmailCount}
												type="number"
												min="1"
												required
											/></label
										>
									{/if}
								</div>
							</div>
							<div class="packages__allowance-group">
								<h3>Protected essential reserve</h3>
								<div class="packages__seat-controls">
									<div class="packages__seat-field">
										<label for="essential-email-state">Reserve type</label>
										<Select
											id="essential-email-state"
											value={essentialEmailState}
											options={employeeSeatOptions}
											onchange={(nextValue) => (essentialEmailState = nextValue as LimitState)}
										/>
									</div>
									{#if essentialEmailState === 'numeric'}
										<label
											><span>Recipients per period</span><input
												bind:value={essentialEmailCount}
												type="number"
												min="1"
												required
											/></label
										>
									{/if}
								</div>
							</div>
						</div>
					</fieldset>
					<div class="packages__actions">
						<Button type="submit" loading={saveDraft.isPending}>Save draft</Button
						>{#if selectedDraft || editingVersionId}<label class="packages__confirm"
								><input type="checkbox" bind:checked={publishConfirmed} />
								<span>I understand publishing makes this definition permanent.</span></label
							><Button
								type="button"
								variation="learning"
								disabled={!publishConfirmed}
								loading={publishDraft.isPending}
								onclick={() => publishDraft.mutate()}>Publish version</Button
							>{/if}
					</div>
				</form>
			</section>
		{/if}

		<section class="packages__history" aria-labelledby="package-history-title">
			<header>
				<div>
					<p class="packages__eyebrow">Immutable record</p>
					<h2 id="package-history-title">Version history</h2>
				</div>
			</header>
			<div class="packages__table-wrap">
				<table>
					<thead
						><tr
							><th scope="col">Version</th><th scope="col">Status</th><th scope="col">Price</th><th
								scope="col">Published</th
							></tr
						></thead
					><tbody
						>{#each packageList.flatMap( (packageItem) => packageItem.versions.map( (version) => ({ packageItem, version }) ) ) as row (row.version.id)}<tr
								><th scope="row">{row.packageItem.display_name} v{row.version.version_number}</th
								><td><Badge status={statusTone(row.version.status)}>{row.version.status}</Badge></td
								><td>{formatMoney(row.version.price_usd_cents, row.version.currency)}</td><td
									>{formatDate(row.version.published_at ?? row.version.created_at)}</td
								></tr
							>{/each}</tbody
					>
				</table>
			</div>
		</section>
	{/if}
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.packages {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}
	.packages__header {
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.packages__eyebrow {
		margin: 0 0 var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h1,
	h2,
	p {
		margin: 0;
	}
	h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}
	h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}
	.packages__description,
	.packages__editor header p {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
	}
	.packages__notice {
		display: flex;
		gap: var(--space-base);
		align-items: flex-start;
		padding: var(--space-base) var(--space-large);
		border: var(--border-base) solid var(--color-informative);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.packages__notice span {
		display: grid;
		width: 32px;
		height: 32px;
		flex: 0 0 32px;
		place-items: center;
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.packages__notice :global(svg) {
		width: 18px;
		height: 18px;
	}
	.packages__feedback {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
	}
	.packages__feedback--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.packages__feedback--error {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.packages__grid {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.packages__card,
	.packages__editor,
	.packages__history {
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}
	.packages__card {
		display: flex;
		min-height: 370px;
		flex-direction: column;
		padding: var(--space-large);
	}
	.packages__card--featured {
		border-color: var(--color-brand);
		box-shadow:
			0 0 0 var(--border-base) var(--color-brand),
			var(--shadow-low);
	}
	.packages__card-header,
	.packages__editor header,
	.packages__history header {
		display: flex;
		justify-content: space-between;
		gap: var(--space-base);
		align-items: flex-start;
	}
	.packages__price {
		display: flex;
		gap: var(--space-small);
		align-items: baseline;
		margin: var(--space-large) 0 var(--space-small);
	}
	.packages__price strong {
		color: var(--color-heading);
		font-size: 36px;
		line-height: 1;
	}
	.packages__price span,
	.packages__card-description,
	.packages__limits {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.packages__card-description {
		min-height: 42px;
		line-height: var(--typography--lineHeight-large);
	}
	.packages__card ul {
		display: grid;
		gap: var(--space-small);
		margin: var(--space-large) 0;
		padding: var(--space-large) 0;
		border-top: var(--border-base) solid var(--color-border);
		border-bottom: var(--border-base) solid var(--color-border);
		list-style: none;
	}
	.packages__card li {
		display: flex;
		gap: var(--space-small);
		align-items: center;
	}
	.packages__card li span {
		color: var(--color-success);
	}
	.packages__card li :global(svg) {
		width: 18px;
		height: 18px;
	}
	.packages__limits {
		display: grid;
		gap: var(--space-smaller);
		margin-bottom: var(--space-large);
	}
	.packages__limits strong {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.packages__card footer {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
		margin-top: auto;
	}
	.packages__retire-confirm {
		display: grid;
		gap: var(--space-small);
		margin-top: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-critical);
		border-radius: var(--radius-base);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
		font-size: var(--typography--fontSize-small);
	}
	.packages__retire-confirm span {
		color: var(--color-critical);
	}
	.packages__retire-confirm :global(svg) {
		width: 20px;
		height: 20px;
	}
	.packages__retire-confirm-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.packages__editor {
		padding: var(--space-large);
	}
	.packages__editor form {
		display: grid;
		gap: var(--space-large);
		margin-top: var(--space-large);
	}
	.packages__form-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.packages__form-wide {
		grid-column: 1 / -1;
	}
	label,
	.packages__seat-field,
	fieldset {
		display: grid;
		gap: var(--space-small);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}
	input,
	textarea {
		width: 100%;
		min-height: 40px;
		box-sizing: border-box;
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: var(--color-surface);
		font: inherit;
	}
	textarea {
		min-height: 84px;
		resize: vertical;
	}
	input:focus-visible,
	textarea:focus-visible {
		outline: none;
		border-color: var(--color-interactive);
		box-shadow: var(--shadow-focus);
	}
	fieldset {
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	legend {
		padding: 0 var(--space-smaller);
		color: var(--color-heading);
		font-weight: 700;
	}
	.packages__features {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-small);
	}
	.packages__features label,
	.packages__confirm {
		display: flex;
		gap: var(--space-small);
		align-items: flex-start;
		font-weight: 400;
	}
	.packages__features input,
	.packages__confirm input {
		width: 20px;
		min-width: 20px;
		height: 20px;
		padding: 0;
	}
	.packages__seat-controls,
	.packages__allowance-controls,
	.packages__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-base);
		align-items: flex-end;
	}
	.packages__seat-controls > label,
	.packages__seat-controls > .packages__seat-field {
		min-width: 220px;
	}
	.packages__field-hint {
		max-width: 65ch;
		margin: 0;
		color: var(--color-text--secondary);
		font-weight: 400;
		line-height: var(--typography--lineHeight-base);
	}
	.packages__allowance-controls {
		align-items: stretch;
	}
	.packages__allowance-group {
		display: grid;
		flex: 1 1 320px;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}
	.packages__allowance-group h3 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}
	.packages__actions {
		justify-content: flex-end;
	}
	.packages__confirm {
		max-width: 360px;
		margin-right: auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.packages__history {
		overflow: hidden;
	}
	.packages__history header {
		padding: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.packages__table-wrap {
		overflow-x: auto;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
	}
	th,
	td {
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		white-space: nowrap;
	}
	thead {
		background: var(--color-surface--background--subtle);
	}
	thead th {
		color: var(--color-text--secondary);
	}
	tbody tr:last-child th,
	tbody tr:last-child td {
		border-bottom: 0;
	}
	@media (max-width: 1023px) {
		.packages__grid {
			grid-template-columns: 1fr;
		}
		.packages__card {
			min-height: auto;
		}
	}
	@media (max-width: 767px) {
		.packages__form-grid,
		.packages__features {
			grid-template-columns: 1fr;
		}
		.packages__editor header,
		.packages__actions {
			align-items: stretch;
			flex-direction: column;
		}
		.packages__confirm {
			margin-right: 0;
		}
	}
</style>
