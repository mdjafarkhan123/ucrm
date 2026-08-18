<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';

	const queryClient = useQueryClient();

	type Client = {
		id: string;
		display_name: string;
		email: string | null;
		phone: string | null;
		lifecycle_status: string;
		lead_source: string | null;
	};
	type Property = {
		id: string;
		client_id: string;
		label: string;
		address_line1: string;
		city: string;
		state_region: string | null;
	};
	type WorkRequest = {
		id: string;
		client_id: string;
		property_id: string;
		title: string;
		description: string | null;
		service_type: string | null;
		status: string;
		created_at: string;
	};
	type Overview = {
		organization: { id: string; name: string; role: string };
		clients: Client[];
		properties: Property[];
		requests: WorkRequest[];
	};
	type MutationInput = { endpoint: string; payload: Record<string, string> };
	type ApiError = Error & { fieldErrors?: Record<string, string> };

	const emptyOverview: Overview = {
		organization: { id: '', name: 'Contractor CRM', role: '' },
		clients: [],
		properties: [],
		requests: []
	};
	const overview = createQuery<Overview>(() => ({
		queryKey: ['crm', 'overview'],
		queryFn: fetchOverview
	}));
	const mutation = createMutation<unknown, Error, MutationInput>(() => ({
		mutationFn: submitMutation,
		onSuccess: () => void queryClient.invalidateQueries({ queryKey: ['crm', 'overview'] })
	}));

	let formMode = $state<'customer' | 'property' | 'request' | null>(null);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let customerForm = $state({
		display_name: '',
		email: '',
		phone: '',
		lead_source: 'staff',
		first_name: '',
		last_name: '',
		company_name: '',
		initial_note: ''
	});
	let propertyForm = $state({
		client_id: '',
		label: 'Primary property',
		address_line1: '',
		address_line2: '',
		city: '',
		state_region: '',
		postal_code: '',
		country: 'US',
		access_notes: ''
	});
	let requestForm = $state({
		client_id: '',
		property_id: '',
		title: '',
		description: '',
		service_type: '',
		source: 'staff',
		preferred_time: ''
	});

	const data = $derived(overview.data ?? emptyOverview);
	const requestProperties = $derived(
		data.properties.filter((property) => property.client_id === requestForm.client_id)
	);

	async function fetchOverview(): Promise<Overview> {
		const response = await fetch('/api/crm/overview');
		if (!response.ok) throw new Error('We could not load your workspace.');
		return response.json();
	}

	async function submitMutation({ endpoint, payload }: MutationInput) {
		const response = await fetch(endpoint, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(payload)
		});
		const result = await response.json();
		if (!response.ok) {
			const error = new Error(result.error ?? 'We could not save that record.') as ApiError;
			error.fieldErrors = result.field_errors ?? {};
			throw error;
		}
		return result;
	}

	function openForm(mode: 'customer' | 'property' | 'request') {
		formMode = mode;
		formError = '';
		fieldErrors = {};
	}

	function closeForm() {
		formMode = null;
		formError = '';
		fieldErrors = {};
	}

	async function save(mode: 'customer' | 'property' | 'request', payload: Record<string, string>) {
		formError = '';
		fieldErrors = {};
		try {
			await mutation.mutateAsync({
				endpoint: `/api/${mode === 'customer' ? 'clients' : mode === 'property' ? 'properties' : 'requests'}`,
				payload
			});
			closeForm();
			if (mode === 'customer')
				customerForm = {
					display_name: '',
					email: '',
					phone: '',
					lead_source: 'staff',
					first_name: '',
					last_name: '',
					company_name: '',
					initial_note: ''
				};
			if (mode === 'property')
				propertyForm = {
					client_id: '',
					label: 'Primary property',
					address_line1: '',
					address_line2: '',
					city: '',
					state_region: '',
					postal_code: '',
					country: 'US',
					access_notes: ''
				};
			if (mode === 'request')
				requestForm = {
					client_id: '',
					property_id: '',
					title: '',
					description: '',
					service_type: '',
					source: 'staff',
					preferred_time: ''
				};
		} catch (error) {
			const apiError = error as ApiError;
			formError = apiError.message;
			fieldErrors = apiError.fieldErrors ?? {};
		}
	}

	function errorFor(field: string) {
		return fieldErrors[field];
	}
	function clientName(id: string) {
		return data.clients.find((client) => client.id === id)?.display_name ?? 'Unknown customer';
	}
	function propertyName(id: string) {
		return data.properties.find((property) => property.id === id)?.label ?? 'Unknown property';
	}
	function formatDate(value: string) {
		return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(
			new Date(value)
		);
	}
</script>

<svelte:head><title>Workspace · Contractor CRM</title></svelte:head>

<div class="workspace">
	<main class="content">
		<PageHeader title="Dashboard" description="Your workspace at a glance." />
		{#if !data.organization.id}
			<section class="notice">
				<strong>Your account is signed in, but it is not connected to an organization yet.</strong
				><span
					>Ask the platform owner to add you to a contractor organization before creating records.</span
				>
			</section>
		{/if}

		<section class="stats" aria-label="Workspace summary">
			<div class="stat-card">
				<span>Customers</span><strong>{data.clients.length}</strong><small
					>Leads and active customers</small
				>
			</div>
			<div class="stat-card">
				<span>Properties</span><strong>{data.properties.length}</strong><small
					>Service locations</small
				>
			</div>
			<div class="stat-card stat-card--request">
				<span>Open requests</span><strong
					>{data.requests.filter((request) => !['converted', 'archived'].includes(request.status))
						.length}</strong
				><small>Ready for the next action</small>
			</div>
		</section>

		{#if overview.isPending}
			<div class="loading-grid">
				<div class="skeleton skeleton--card"></div>
				<div class="skeleton skeleton--card"></div>
				<div class="skeleton skeleton--card"></div>
			</div>
		{:else if overview.isError}
			<section class="notice notice--error">
				<strong>Workspace data could not be loaded.</strong><span
					>Refresh the page and try again.</span
				>
			</section>
		{:else}
			<div class="workspace-grid">
				<section class="panel panel--customers" aria-labelledby="customers-heading">
					<div class="panel__header">
						<div>
							<span class="panel__eyebrow">Relationship record</span>
							<h2 id="customers-heading">Customers</h2>
						</div>
						<button class="button button--small" type="button" onclick={() => openForm('customer')}
							>Add customer</button
						>
					</div>
					{#if data.clients.length === 0}<div class="empty">
							<strong>No customers yet</strong><span
								>Create the first lead and start a complete work history.</span
							><button
								class="button button--secondary"
								type="button"
								onclick={() => openForm('customer')}>Create first customer</button
							>
						</div>{/if}
					<div class="record-list">
						{#each data.clients as client (client.id)}
							<article class="record">
								<div class="record__avatar">{client.display_name.slice(0, 1).toUpperCase()}</div>
								<div class="record__body">
									<div class="record__title">
										<strong>{client.display_name}</strong><span
											class="badge badge--{client.lifecycle_status}">{client.lifecycle_status}</span
										>
									</div>
									<span>{client.email || client.phone || 'No contact details yet'}</span><small
										>{data.properties.filter((property) => property.client_id === client.id).length} properties
										· {data.requests.filter((request) => request.client_id === client.id).length} requests</small
									>
								</div>
								<button
									class="text-button"
									type="button"
									onclick={() => {
										propertyForm.client_id = client.id;
										openForm('property');
									}}>Add property</button
								>
							</article>
						{/each}
					</div>
				</section>

				<section class="panel" aria-labelledby="requests-heading">
					<div class="panel__header">
						<div>
							<span class="panel__eyebrow">Incoming work</span>
							<h2 id="requests-heading">Requests</h2>
						</div>
						<button
							class="button button--small"
							type="button"
							onclick={() => openForm('request')}
							disabled={data.properties.length === 0}>New request</button
						>
					</div>
					{#if data.requests.length === 0}<div class="empty">
							<strong>No requests yet</strong><span
								>Add a property first, then record what the customer needs.</span
							>
						</div>{/if}
					<div class="record-list">
						{#each data.requests as request (request.id)}
							<article class="request-record">
								<div class="request-record__top">
									<span class="request-dot"></span>
									<div>
										<strong>{request.title}</strong><small
											>{clientName(request.client_id)} · {propertyName(request.property_id)}</small
										>
									</div>
									<span class="badge badge--request">{request.status.replace('_', ' ')}</span>
								</div>
								<p>{request.description || 'No description added.'}</p>
								<footer>
									<span>{request.service_type || 'General service'}</span><span
										>{formatDate(request.created_at)}</span
									>
								</footer>
							</article>
						{/each}
					</div>
				</section>
			</div>
		{/if}
	</main>
</div>

{#if formMode}
	<div
		class="modal-backdrop"
		role="presentation"
		onclick={(event) => {
			if (event.target === event.currentTarget) closeForm();
		}}
	>
		<div class="modal" role="dialog" aria-modal="true" aria-labelledby="form-title">
			<div class="modal__header">
				<div>
					<span class="panel__eyebrow"
						>{formMode === 'customer'
							? 'Relationship record'
							: formMode === 'property'
								? 'Service location'
								: 'Incoming work'}</span
					>
					<h2 id="form-title">
						{formMode === 'customer'
							? 'Add customer'
							: formMode === 'property'
								? 'Add property'
								: 'New request'}
					</h2>
				</div>
				<button class="close-button" type="button" aria-label="Close form" onclick={closeForm}
					>×</button
				>
			</div>
			{#if formError}<div class="form-alert" role="alert">{formError}</div>{/if}
			{#if formMode === 'customer'}
				<form
					onsubmit={(event) => {
						event.preventDefault();
						void save('customer', customerForm);
					}}
				>
					<label
						>Customer name<input
							bind:value={customerForm.display_name}
							aria-invalid={!!errorFor('display_name')}
						/>{#if errorFor('display_name')}<small class="field-error"
								>{errorFor('display_name')}</small
							>{/if}</label
					>
					<div class="form-grid">
						<label>Email<input type="email" bind:value={customerForm.email} /></label><label
							>Phone<input type="tel" bind:value={customerForm.phone} /></label
						>
					</div>
					<div class="form-grid">
						<label>First name<input bind:value={customerForm.first_name} /></label><label
							>Last name<input bind:value={customerForm.last_name} /></label
						>
					</div>
					<label>How did they find you?<input bind:value={customerForm.lead_source} /></label><label
						>Notes<textarea rows="3" bind:value={customerForm.initial_note}></textarea></label
					>
					<div class="modal__actions">
						<button class="button button--quiet" type="button" onclick={closeForm}>Cancel</button
						><button class="button" type="submit" disabled={mutation.isPending}
							>Save customer</button
						>
					</div>
				</form>
			{:else if formMode === 'property'}
				<form
					onsubmit={(event) => {
						event.preventDefault();
						void save('property', propertyForm);
					}}
				>
					<label
						>Customer<select bind:value={propertyForm.client_id}
							><option value="">Choose customer</option
							>{#each data.clients as client (client.id)}<option value={client.id}
									>{client.display_name}</option
								>{/each}</select
						>{#if errorFor('client_id')}<small class="field-error">{errorFor('client_id')}</small
							>{/if}</label
					>
					<label
						>Property label<input
							bind:value={propertyForm.label}
							placeholder="Main home, office, rental…"
						/></label
					><label>Address<input bind:value={propertyForm.address_line1} /></label><label
						>Address line 2<input bind:value={propertyForm.address_line2} /></label
					>
					<div class="form-grid">
						<label>City<input bind:value={propertyForm.city} /></label><label
							>State/region<input bind:value={propertyForm.state_region} /></label
						>
					</div>
					<div class="form-grid">
						<label>Postal code<input bind:value={propertyForm.postal_code} /></label><label
							>Country<input bind:value={propertyForm.country} maxlength="2" /></label
						>
					</div>
					<label
						>Access notes<textarea rows="3" bind:value={propertyForm.access_notes}
						></textarea></label
					>
					<div class="modal__actions">
						<button class="button button--quiet" type="button" onclick={closeForm}>Cancel</button
						><button class="button" type="submit" disabled={mutation.isPending}
							>Save property</button
						>
					</div>
				</form>
			{:else}
				<form
					onsubmit={(event) => {
						event.preventDefault();
						void save('request', requestForm);
					}}
				>
					<div class="form-grid">
						<label
							>Customer<select
								bind:value={requestForm.client_id}
								onchange={() => (requestForm.property_id = '')}
								><option value="">Choose customer</option
								>{#each data.clients as client (client.id)}<option value={client.id}
										>{client.display_name}</option
									>{/each}</select
							></label
						><label
							>Property<select
								bind:value={requestForm.property_id}
								disabled={!requestForm.client_id}
								><option value="">Choose property</option
								>{#each requestProperties as property (property.id)}<option value={property.id}
										>{property.label} · {property.city}</option
									>{/each}</select
							></label
						>
					</div>
					<label
						>What do they need?<input
							bind:value={requestForm.title}
							placeholder="Repair leaking kitchen faucet"
						/></label
					>
					<div class="form-grid">
						<label
							>Service type<input
								bind:value={requestForm.service_type}
								placeholder="Plumbing"
							/></label
						><label
							>Preferred timing<input
								bind:value={requestForm.preferred_time}
								placeholder="This week, mornings"
							/></label
						>
					</div>
					<label
						>Description<textarea rows="4" bind:value={requestForm.description}></textarea></label
					>
					<div class="modal__actions">
						<button class="button button--quiet" type="button" onclick={closeForm}>Cancel</button
						><button class="button" type="submit" disabled={mutation.isPending}>Save request</button
						>
					</div>
				</form>
			{/if}
		</div>
	</div>
{/if}

<style lang="scss">
	.workspace {
		min-height: 100vh;
		background: var(--color-surface--background);
	}
	.topbar__eyebrow,
	.page-intro__eyebrow,
	.panel__eyebrow {
		display: block;
		margin-bottom: 6px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		letter-spacing: 0.08em;
		text-transform: uppercase;
	}
	.content {
		margin: 0 auto;
		padding-top: var(--space-large);
	}
	.page-intro {
		display: flex;
		align-items: end;
		justify-content: space-between;
		gap: 24px;
		margin-bottom: 32px;
	}
	h1 {
		max-width: 650px;
		margin-bottom: 10px;
		color: var(--color-heading);
		font-size: clamp(30px, 5vw, 48px);
		line-height: 1.08;
		letter-spacing: -0.03em;
	}
	.page-intro p {
		color: var(--color-text--secondary);
		font-size: 16px;
	}
	.page-actions {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}
	.button {
		padding: 11px 16px;
		border: 0;
		border-radius: var(--radius-small);
		color: var(--color-text--reverse);
		background: var(--color-interactive);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
		transition:
			background var(--timing-quick) ease,
			opacity var(--timing-quick) ease;
	}
	.button:hover {
		background: var(--color-interactive--hover);
	}
	.button:disabled {
		opacity: 0.45;
		cursor: not-allowed;
	}
	.button--secondary {
		color: var(--color-heading);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
	}
	.button--secondary:hover,
	.button--quiet:hover {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}
	.button--quiet {
		color: var(--color-text);
		background: transparent;
	}
	.button--small {
		padding: 8px 12px;
		font-size: var(--typography--fontSize-small);
	}
	.stats {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 16px;
		margin-bottom: 24px;
	}
	.stat-card {
		padding: 20px;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.stat-card span,
	.stat-card small {
		display: block;
		color: var(--color-text--secondary);
	}
	.stat-card strong {
		display: block;
		margin: 10px 0 4px;
		color: var(--color-heading);
		font-size: 32px;
	}
	.stat-card--request {
		border-top: 3px solid var(--color-request);
	}
	.workspace-grid {
		display: grid;
		grid-template-columns: minmax(0, 1.05fr) minmax(0, 0.95fr);
		gap: 24px;
	}
	.panel {
		min-width: 0;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.panel__header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 16px;
		padding: 24px;
		border-bottom: 1px solid var(--color-border);
	}
	.panel h2 {
		color: var(--color-heading);
		font-size: 20px;
	}
	.record-list {
		display: grid;
	}
	.record {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 16px 24px;
		border-bottom: 1px solid var(--color-border);
	}
	.record:last-child,
	.request-record:last-child {
		border-bottom: 0;
	}
	.record__avatar {
		display: grid;
		flex: 0 0 40px;
		place-items: center;
		width: 40px;
		height: 40px;
		border-radius: 50%;
		color: var(--color-client--onSurface);
		background: var(--color-client--surface);
		font-weight: 700;
	}
	.record__body {
		min-width: 0;
		flex: 1;
	}
	.record__body > span,
	.record__body small,
	.request-record small {
		display: block;
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.record__body small {
		margin-top: 5px;
	}
	.record__title {
		display: flex;
		align-items: center;
		gap: 8px;
		color: var(--color-heading);
	}
	.badge {
		display: inline-flex;
		padding: 4px 7px;
		border-radius: 999px;
		color: var(--color-client--onSurface);
		background: var(--color-client--surface);
		font-size: 10px;
		font-weight: 700;
		text-transform: capitalize;
	}
	.badge--customer {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.badge--request {
		color: var(--color-request--onSurface);
		background: var(--color-request--surface);
	}
	.text-button {
		flex: 0 0 auto;
		border: 0;
		color: var(--color-interactive);
		background: transparent;
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}
	.text-button:hover {
		text-decoration: underline;
	}
	.request-record {
		padding: 18px 24px;
		border-bottom: 1px solid var(--color-border);
	}
	.request-record__top {
		display: flex;
		align-items: flex-start;
		gap: 10px;
	}
	.request-dot {
		flex: 0 0 8px;
		width: 8px;
		height: 8px;
		margin-top: 6px;
		border-radius: 50%;
		background: var(--color-request);
	}
	.request-record__top > div {
		min-width: 0;
		flex: 1;
	}
	.request-record__top strong {
		display: block;
		overflow: hidden;
		color: var(--color-heading);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.request-record p {
		margin: 12px 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-base);
		line-height: 1.45;
	}
	.request-record footer {
		display: flex;
		justify-content: space-between;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.empty {
		display: grid;
		justify-items: start;
		gap: 8px;
		padding: 32px 24px;
		color: var(--color-text--secondary);
	}
	.empty strong {
		color: var(--color-heading);
	}
	.empty .button {
		margin-top: 8px;
	}
	.notice {
		display: flex;
		flex-direction: column;
		gap: 4px;
		margin-bottom: 24px;
		padding: 16px 20px;
		border: 1px solid var(--color-warning);
		border-radius: var(--radius-base);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.notice--error {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.loading-grid {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 16px;
	}
	.skeleton--card {
		height: 140px;
	}
	.modal-backdrop {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		display: grid;
		place-items: center;
		padding: 20px;
		background: var(--color-overlay);
	}
	.modal {
		width: min(100%, 600px);
		max-height: min(90vh, 800px);
		overflow: auto;
		padding: 24px;
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
	}
	.modal__header {
		display: flex;
		justify-content: space-between;
		gap: 16px;
		margin-bottom: 24px;
	}
	.modal h2 {
		color: var(--color-heading);
		font-size: 24px;
	}
	.close-button {
		width: 32px;
		height: 32px;
		border: 0;
		border-radius: 50%;
		color: var(--color-text);
		background: transparent;
		font-size: 24px;
	}
	.close-button:hover {
		background: var(--color-surface--hover);
	}
	.modal form {
		display: grid;
		gap: 16px;
	}
	.modal label {
		display: grid;
		gap: 6px;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}
	.modal input,
	.modal select,
	.modal textarea {
		width: 100%;
		padding: 11px 12px;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-small);
		color: var(--color-text);
		background: var(--color-surface);
	}
	.modal textarea {
		resize: vertical;
	}
	.form-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 12px;
	}
	.modal__actions {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
		margin-top: 8px;
	}
	.form-alert {
		margin-bottom: 16px;
		padding: 10px 12px;
		border-radius: var(--radius-small);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
		font-size: var(--typography--fontSize-small);
	}
	.field-error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	@media (max-width: 800px) {
		.page-intro,
		.workspace-grid {
			display: block;
		}
		.page-actions {
			margin-top: 20px;
		}
		.panel + .panel {
			margin-top: 24px;
		}
	}
	@media (max-width: 560px) {
		.content {
			width: min(100% - 24px, 1400px);
		}
		.stats {
			grid-template-columns: 1fr;
		}
		.form-grid {
			grid-template-columns: 1fr;
		}
		.record {
			align-items: flex-start;
			flex-wrap: wrap;
		}
		.text-button {
			margin-left: 52px;
		}
	}
</style>
