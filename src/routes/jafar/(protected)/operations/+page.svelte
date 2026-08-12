<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';

	const queryClient = useQueryClient();

	type OperationStatus = 'pending' | 'retrying' | 'succeeded' | 'acknowledged' | 'manually_resolved';
	type Operation = {
		id: string;
		correlation_id: string;
		operation_type: string;
		target_kind: string;
		target_id: string | null;
		status: OperationStatus;
		attempt_count: number;
		last_error: string | null;
		acknowledged_at: string | null;
		acknowledged_by_owner_email: string | null;
		resolved_at: string | null;
		resolved_by_owner_email: string | null;
		resolution_note: string | null;
		created_at: string;
		updated_at: string;
	};
	type OperationListResponse = { operations: Operation[]; error?: string };
	type ActionResponse = { ok?: boolean; error?: string };

	const statuses: { value: string; label: string }[] = [
		{ value: '', label: 'Open (not succeeded)' },
		{ value: 'pending', label: 'Pending' },
		{ value: 'retrying', label: 'Retrying' },
		{ value: 'acknowledged', label: 'Acknowledged' },
		{ value: 'manually_resolved', label: 'Manually resolved' },
		{ value: 'succeeded', label: 'Succeeded' }
	];

	const operationTypeLabels: Record<string, string> = {
		setup_email_delivery: 'Setup email delivery',
		outbox_email_delivery: 'Queued email delivery',
		onboarding_application_provisioning: 'Organization provisioning'
	};

	const retryableTypes = new Set(['setup_email_delivery', 'outbox_email_delivery']);
	const retryableStatuses = new Set<OperationStatus>(['pending', 'retrying', 'acknowledged']);
	const acknowledgeableStatuses = new Set<OperationStatus>(['pending', 'retrying']);
	const closedStatuses = new Set<OperationStatus>(['succeeded', 'manually_resolved']);

	let statusFilter = $state('');
	let selectedOperationId = $state<string | null>(null);
	let resolvingOperation = $state(false);
	let resolutionNote = $state('');
	let actionError = $state('');
	let actionMessage = $state('');

	function clearFeedback() {
		actionError = '';
		actionMessage = '';
	}

	function selectOperation(id: string) {
		selectedOperationId = id;
		resolvingOperation = false;
		resolutionNote = '';
		clearFeedback();
	}

	function clearSelection() {
		selectedOperationId = null;
		resolvingOperation = false;
		resolutionNote = '';
		clearFeedback();
	}

	function handleRowKeydown(event: KeyboardEvent, id: string) {
		if (event.key !== 'Enter' && event.key !== ' ') return;
		event.preventDefault();
		selectOperation(id);
	}

	const operations = createQuery<OperationListResponse>(() => ({
		queryKey: ['jafar', 'operations', statusFilter],
		queryFn: async () => {
			const params = new URLSearchParams();
			if (statusFilter) params.set('status', statusFilter);
			const query = params.toString();
			const response = await fetch(`/api/jafar/operations${query ? `?${query}` : ''}`);
			const result = (await response.json()) as OperationListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Operations could not be loaded.');
			return result;
		}
	}));

	const operationList = $derived(operations.data?.operations ?? []);
	const selectedOperation = $derived(
		operationList.find((operation) => operation.id === selectedOperationId) ?? null
	);
	const retryingCount = $derived(
		operationList.filter((operation) => operation.status === 'retrying').length
	);
	const acknowledgedCount = $derived(
		operationList.filter((operation) => operation.status === 'acknowledged').length
	);

	const retryOperation = createMutation<ActionResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!selectedOperationId) throw new Error('Choose an operation first.');
			const response = await fetch(`/api/jafar/operations/${selectedOperationId}/retry`, {
				method: 'POST'
			});
			const result = (await response.json()) as ActionResponse;
			if (!response.ok) throw new Error(result.error ?? 'The operation could not be retried.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			actionMessage = 'Retried. The operation clears automatically once it succeeds.';
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'operations'] });
		}
	}));

	const acknowledgeOperation = createMutation<ActionResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!selectedOperationId) throw new Error('Choose an operation first.');
			const response = await fetch(`/api/jafar/operations/${selectedOperationId}/acknowledge`, {
				method: 'POST'
			});
			const result = (await response.json()) as ActionResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The operation could not be acknowledged.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			actionMessage = 'Marked as seen.';
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'operations'] });
		}
	}));

	const resolveOperation = createMutation<ActionResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!selectedOperationId) throw new Error('Choose an operation first.');
			const response = await fetch(`/api/jafar/operations/${selectedOperationId}/resolve`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ note: resolutionNote })
			});
			const result = (await response.json()) as ActionResponse;
			if (!response.ok) throw new Error(result.error ?? 'The operation could not be resolved.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			resolvingOperation = false;
			resolutionNote = '';
			actionMessage = 'Operation resolved.';
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'operations'] });
		}
	}));

	function operationLabel(operation: Operation) {
		return operationTypeLabels[operation.operation_type] ?? operation.operation_type;
	}

	function statusLabel(status: OperationStatus) {
		return statuses.find((option) => option.value === status)?.label ?? status;
	}

	function statusTone(status: OperationStatus) {
		return status === 'succeeded'
			? 'success'
			: status === 'manually_resolved'
				? 'inactive'
				: status === 'acknowledged'
					? 'informative'
					: status === 'retrying'
						? 'warning'
						: 'critical';
	}

	function formatDate(value: string | null) {
		return value
			? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
					new Date(value)
				)
			: '—';
	}
</script>

<svelte:head>
	<title>Operations · Control Room</title>
</svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="operations">
	<header class="operations__header">
		<div>
			<p class="operations__eyebrow">Recovery queue</p>
			<h1>Operations</h1>
			<p class="operations__description">
				Background work that did not complete on its own, like a setup email that could not
				send. Retry it, mark it seen, or close it with a note.
			</p>
		</div>
	</header>

	<section class="operations__summary" aria-label="Operations summary">
		<KpiCard
			label="Shown"
			value={String(operationList.length)}
			note="Current results"
			icon={alertIcon}
			variant="compact"
		/>
		<KpiCard
			label="Retrying"
			value={String(retryingCount)}
			note="Failed at least once"
			icon={refreshIcon}
			tone="warning"
			variant="compact"
		/>
		<KpiCard
			label="Acknowledged"
			value={String(acknowledgedCount)}
			note="Seen, not yet closed"
			icon={checkIcon}
			tone="informative"
			variant="compact"
		/>
	</section>

	<section class="operations__filters" aria-label="Operation filters">
		<div class="operations__filter-field">
			<label for="operation-status">Status</label>
			<Select
				id="operation-status"
				bind:value={statusFilter}
				options={statuses}
				ariaLabel="Filter operations by status"
				onchange={clearSelection}
			/>
		</div>
	</section>

	<section class="operations__table-panel" aria-labelledby="operation-list-title">
		<h2 id="operation-list-title" class="operations__sr-only">Operation list</h2>
		{#if operations.isPending}
			<div class="operations__state">
				<LoadingSkeleton variant="table" rows={5} label="Loading operations" />
			</div>
		{:else if operations.isError}
			<div class="operations__state">
				<ErrorState
					title="Operations could not be loaded"
					description={operations.error.message}
					retry={() => operations.refetch()}
				/>
			</div>
		{:else if operationList.length === 0}
			<div class="operations__state">
				<EmptyState title="Nothing needs attention" description="No operations match this filter." />
			</div>
		{:else}
			<div class="operations__table-wrap">
				<table>
					<thead>
						<tr>
							<th scope="col">Operation</th>
							<th scope="col">Target</th>
							<th scope="col">Status</th>
							<th scope="col">Attempts</th>
							<th scope="col">Updated</th>
							<th scope="col"><span class="operations__sr-only">Open detail</span></th>
						</tr>
					</thead>
					<tbody>
						{#each operationList as operation (operation.id)}
							<tr
								class={[
									'operations__table-row',
									selectedOperationId === operation.id && 'operations__table-row--selected'
								]}
								tabindex="0"
								aria-label={`Review ${operationLabel(operation)}`}
								aria-selected={selectedOperationId === operation.id}
								onclick={() => selectOperation(operation.id)}
								onkeydown={(event) => handleRowKeydown(event, operation.id)}
							>
								<th scope="row">
									<strong>{operationLabel(operation)}</strong>
									{#if operation.last_error}
										<small class="operations__error-preview">{operation.last_error}</small>
									{/if}
								</th>
								<td>
									<small>{operation.target_kind} · {operation.target_id ?? '—'}</small>
								</td>
								<td><Badge status={statusTone(operation.status)}>{statusLabel(operation.status)}</Badge></td>
								<td>{operation.attempt_count}</td>
								<td>{formatDate(operation.updated_at)}</td>
								<td>
									<span class="operations__row-action" aria-hidden="true">{@html arrowRightIcon}</span>
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
		<footer class="operations__table-footer">
			<span>Rows clear on their own once the underlying action succeeds.</span>
		</footer>
	</section>

	<Dialog
		open={Boolean(selectedOperation)}
		title={selectedOperation ? operationLabel(selectedOperation) : ''}
		onClose={clearSelection}
	>
		{#if selectedOperation}
			<Badge status={statusTone(selectedOperation.status)}
				>{statusLabel(selectedOperation.status)}</Badge
			>
			<dl class="operations__review-details">
				<div>
					<dt>Target</dt>
					<dd>{selectedOperation.target_kind} · {selectedOperation.target_id ?? '—'}</dd>
				</div>
				<div>
					<dt>Attempts</dt>
					<dd>{selectedOperation.attempt_count}</dd>
				</div>
				<div>
					<dt>Correlation ID</dt>
					<dd>{selectedOperation.correlation_id}</dd>
				</div>
				<div>
					<dt>Last updated</dt>
					<dd>{formatDate(selectedOperation.updated_at)}</dd>
				</div>
			</dl>
			{#if selectedOperation.last_error}
				<p class="operations__last-error">
					<strong>Last error:</strong>
					{selectedOperation.last_error}
				</p>
			{/if}
			{#if selectedOperation.acknowledged_at}
				<p class="operations__note-line">
					Seen by {selectedOperation.acknowledged_by_owner_email} on {formatDate(
						selectedOperation.acknowledged_at
					)}.
				</p>
			{/if}
			{#if selectedOperation.resolved_at}
				<p class="operations__note-line">
					Resolved by {selectedOperation.resolved_by_owner_email} on {formatDate(
						selectedOperation.resolved_at
					)}: {selectedOperation.resolution_note}
				</p>
			{/if}

			{#if actionMessage}<p class="operations__feedback operations__feedback--success" role="status">
					{actionMessage}
				</p>{/if}
			{#if actionError}<p class="operations__feedback operations__feedback--error" role="alert">
					{actionError}
				</p>{/if}

			{#if !closedStatuses.has(selectedOperation.status)}
				<div class="operations__owner-actions">
					{#if retryableTypes.has(selectedOperation.operation_type) && retryableStatuses.has(selectedOperation.status)}
						<Button
							type="button"
							variant="tertiary"
							loading={retryOperation.isPending}
							onclick={() => retryOperation.mutate()}>Retry now</Button
						>
					{/if}
					{#if acknowledgeableStatuses.has(selectedOperation.status)}
						<Button
							type="button"
							variant="tertiary"
							loading={acknowledgeOperation.isPending}
							onclick={() => acknowledgeOperation.mutate()}>Mark as seen</Button
						>
					{/if}
					<Button
						type="button"
						variant="tertiary"
						disabled={resolvingOperation}
						onclick={() => {
							clearFeedback();
							resolutionNote = '';
							resolvingOperation = true;
						}}>Resolve manually</Button
					>
				</div>
			{/if}

			{#if resolvingOperation}
				<form
					class="operations__resolve-form"
					onsubmit={(event) => {
						event.preventDefault();
						resolveOperation.mutate();
					}}
				>
					<label
						><span>What did you do to fix this?</span><textarea
							bind:value={resolutionNote}
							required
							maxlength="500"
						></textarea></label
					>
					<div class="operations__form-actions">
						<Button
							type="button"
							variant="secondary"
							variation="subtle"
							disabled={resolveOperation.isPending}
							onclick={() => (resolvingOperation = false)}>Cancel</Button
						>
						<Button type="submit" loading={resolveOperation.isPending}>Resolve</Button>
					</div>
				</form>
			{/if}
		{/if}
	</Dialog>
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.operations {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}

	.operations h1,
	.operations h2,
	.operations p {
		margin: 0;
	}

	.operations h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}

	.operations h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}

	.operations__header {
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.operations__eyebrow {
		margin-bottom: var(--space-small) !important;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}

	.operations__description {
		max-width: 65ch;
		margin-top: var(--space-small) !important;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	.operations__summary {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.operations__filters {
		display: flex;
		align-items: flex-end;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}

	.operations__filter-field {
		display: grid;
		width: min(260px, 100%);
		gap: var(--space-small);

		label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}
	}

	.operations__table-panel {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}

	.operations__table-wrap {
		overflow-x: auto;
	}

	.operations table {
		width: 100%;
		min-width: 780px;
		border-collapse: collapse;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
	}

	.operations th,
	.operations td {
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		vertical-align: middle;
	}

	.operations thead {
		background: var(--color-surface--background--subtle);
	}

	.operations thead th {
		color: var(--color-text--secondary);
		font-weight: 700;
		white-space: nowrap;
	}

	.operations tbody th {
		color: var(--color-heading);
		font-weight: 700;
	}

	.operations tbody th strong {
		display: block;
	}

	.operations tbody small {
		display: block;
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
		line-height: var(--typography--lineHeight-tighter);
	}

	.operations__error-preview {
		max-width: 42ch;
		overflow: hidden;
		white-space: nowrap;
		text-overflow: ellipsis;
	}

	.operations tbody tr {
		transition: background-color var(--timing-quick);

		&:hover,
		&.operations__table-row--selected {
			background: var(--color-surface--hover);
		}

		&:last-child th,
		&:last-child td {
			border-bottom: 0;
		}
	}

	.operations__row-action {
		display: grid;
		width: 32px;
		height: 32px;
		place-items: center;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;

		& :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}

	.operations__table-footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.operations__state {
		padding: var(--space-large);
	}

	.operations__review-details {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
		margin: var(--space-base) 0 0;

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		dd {
			margin: var(--space-smaller) 0 0;
			color: var(--color-heading);
			overflow-wrap: anywhere;
		}
	}

	.operations__last-error,
	.operations__note-line {
		margin-top: var(--space-base);
		line-height: var(--typography--lineHeight-large);
		overflow-wrap: anywhere;
	}

	.operations__feedback {
		margin-top: var(--space-base);
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
	}

	.operations__feedback--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}

	.operations__feedback--error {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}

	.operations__owner-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
		margin-top: var(--space-base);
	}

	.operations__resolve-form {
		display: grid;
		gap: var(--space-base);
		margin-top: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-informative);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		label {
			display: grid;
			gap: var(--space-small);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		textarea {
			min-height: 88px;
			box-sizing: border-box;
			padding: var(--space-small);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-text);
			background: var(--color-surface);
			font: inherit;
			resize: vertical;
		}

		textarea:focus-visible {
			outline: none;
			border-color: var(--color-interactive);
			box-shadow: var(--shadow-focus);
		}
	}

	.operations__form-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}

	.operations__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (max-width: 900px) {
		.operations__summary {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}

		.operations__review-details {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 767px) {
		.operations__filters,
		.operations__table-footer {
			align-items: stretch;
			flex-direction: column;
		}

		.operations__filter-field {
			width: 100%;
		}
	}

	@media (max-width: 639px) {
		.operations h1 {
			font-size: 28px;
		}

		.operations__summary,
		.operations__review-details {
			grid-template-columns: 1fr;
		}
	}
</style>
