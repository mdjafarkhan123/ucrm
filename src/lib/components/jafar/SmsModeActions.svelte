<script lang="ts">
	import { smsModeQuery } from '$lib/jafar/organization-communications-queries';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import { jafarOrganizationSmsModeKey } from '$lib/jafar/query-keys';

	type SmsMode = 'off' | 'operational';
	type OrgMode = {
		package_max_mode: SmsMode;
		chosen_mode: SmsMode;
		override_mode: SmsMode | null;
		override_reason: string | null;
		updated_at: string;
	};
	type ModeResponse = { mode: OrgMode | null; effective_mode: SmsMode; error?: string };
	type MutationBody = {
		package_max_mode?: SmsMode;
		chosen_mode?: SmsMode;
		override_mode?: SmsMode;
		override_reason?: string;
		clear_override?: boolean;
	};
	type MutationResponse = { error?: string; field_errors?: Record<string, string> };

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const modeKey = $derived(jafarOrganizationSmsModeKey(organizationId));

	const modeQuery = createQuery<ModeResponse>(() => smsModeQuery<ModeResponse>(organizationId));

	const modeOptions = [
		{ value: 'off', label: 'Off' },
		{ value: 'operational', label: 'Operational' }
	];
	const overrideOptions = [
		{ value: 'unchanged', label: 'Leave the override as is' },
		{ value: 'clear', label: 'Clear the override' },
		{ value: 'off', label: 'Force off' },
		{ value: 'operational', label: 'Force operational' }
	];

	let editing = $state(false);
	let packageMaxMode = $state<SmsMode>('operational');
	let chosenMode = $state<SmsMode>('operational');
	let overrideChoice = $state<'unchanged' | 'clear' | SmsMode>('unchanged');
	let overrideReason = $state('');
	let feedbackMessage = $state('');
	let feedbackError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	function startEditing() {
		const mode = modeQuery.data?.mode;
		feedbackMessage = '';
		feedbackError = '';
		fieldErrors = {};
		packageMaxMode = mode?.package_max_mode ?? 'operational';
		chosenMode = mode?.chosen_mode ?? 'operational';
		overrideChoice = 'unchanged';
		overrideReason = '';
		editing = true;
	}

	const modeMutation = createMutation<MutationResponse, Error, MutationBody>(() => ({
		mutationFn: async (body) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/mode`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(body)
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'The SMS mode could not be changed.');
			}
			return result;
		},
		onMutate: () => {
			feedbackError = '';
			fieldErrors = {};
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async () => {
			editing = false;
			feedbackMessage = 'SMS mode updated.';
			await queryClient.invalidateQueries({ queryKey: modeKey });
		}
	}));

	function submit(event: SubmitEvent) {
		event.preventDefault();
		const mode = modeQuery.data?.mode;
		const body: MutationBody = {};
		if (packageMaxMode !== (mode?.package_max_mode ?? 'operational'))
			body.package_max_mode = packageMaxMode;
		if (chosenMode !== (mode?.chosen_mode ?? 'operational')) body.chosen_mode = chosenMode;
		if (overrideChoice === 'clear') body.clear_override = true;
		else if (overrideChoice === 'off' || overrideChoice === 'operational') {
			body.override_mode = overrideChoice;
			body.override_reason = overrideReason.trim();
		}
		if (Object.keys(body).length === 0) {
			fieldErrors = { form: 'Choose at least one change to make.' };
			return;
		}
		modeMutation.mutate(body);
	}

	function formatTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}
</script>

<div class="sms-mode-actions">
	<div class="sms-mode-actions__heading">
		<div>
			<h3>SMS mode</h3>
			<p>
				The mode actually in effect is the lesser of the package ceiling and the contractor's
				choice, unless you set a reasoned override.
			</p>
		</div>
	</div>

	{#if feedbackMessage}<p class="sms-mode-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="sms-mode-actions__error" role="alert">{feedbackError}</p>{/if}

	{#if modeQuery.isPending}
		<LoadingSkeleton variant="table" rows={2} label="Loading SMS mode" />
	{:else if modeQuery.isError}
		<ErrorState
			title="SMS mode could not be loaded"
			description={modeQuery.error instanceof Error ? modeQuery.error.message : 'Try again.'}
			retry={() => modeQuery.refetch()}
		/>
	{:else}
		<div class="sms-mode-actions__summary">
			<Badge status={modeQuery.data?.effective_mode === 'operational' ? 'success' : 'inactive'}>
				{modeQuery.data?.effective_mode === 'operational' ? 'Operational' : 'Off'}
			</Badge>
			<dl>
				<div>
					<dt>Package ceiling</dt>
					<dd>{modeQuery.data?.mode?.package_max_mode ?? 'operational'}</dd>
				</div>
				<div>
					<dt>Contractor's choice</dt>
					<dd>{modeQuery.data?.mode?.chosen_mode ?? 'operational'}</dd>
				</div>
				{#if modeQuery.data?.mode?.override_mode}
					<div>
						<dt>Owner override</dt>
						<dd>
							Force {modeQuery.data.mode.override_mode} &middot; {modeQuery.data.mode
								.override_reason}
						</dd>
					</div>
					<div>
						<dt>Set</dt>
						<dd>{formatTime(modeQuery.data.mode.updated_at)}</dd>
					</div>
				{/if}
			</dl>
		</div>

		{#if editing}
			<form class="sms-mode-actions__form" onsubmit={submit}>
				<Select
					id="sms-mode-package"
					label="Package ceiling"
					options={modeOptions}
					bind:value={packageMaxMode}
				/>
				<Select
					id="sms-mode-chosen"
					label="Contractor's choice"
					options={modeOptions}
					bind:value={chosenMode}
				/>
				<Select
					id="sms-mode-override"
					label="Owner override"
					options={overrideOptions}
					bind:value={overrideChoice}
				/>
				{#if overrideChoice === 'off' || overrideChoice === 'operational'}
					<Input
						id="sms-mode-override-reason"
						label="Reason (kept in the owner audit log)"
						bind:value={overrideReason}
						required
						invalid={Boolean(fieldErrors.override_reason)}
						errorMessage={fieldErrors.override_reason}
					/>
				{/if}
				{#if fieldErrors.form}<p class="sms-mode-actions__field-error" role="alert">
						{fieldErrors.form}
					</p>{/if}
				<div class="sms-mode-actions__actions">
					<Button type="submit" loading={modeMutation.isPending}>Save mode</Button>
					<Button
						type="button"
						variant="secondary"
						variation="subtle"
						onclick={() => (editing = false)}>Cancel</Button
					>
				</div>
			</form>
		{:else}
			<div class="sms-mode-actions__actions">
				<Button size="small" variant="secondary" variation="subtle" onclick={startEditing}>
					Change mode
				</Button>
			</div>
		{/if}
	{/if}
</div>

<style lang="scss">
	.sms-mode-actions,
	.sms-mode-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.sms-mode-actions__heading h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.sms-mode-actions__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.sms-mode-actions__success {
		color: var(--color-success--onSurface);
	}
	.sms-mode-actions__error,
	.sms-mode-actions__field-error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.sms-mode-actions__summary {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.sms-mode-actions__summary dl {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;
	}
	.sms-mode-actions__summary dl > div {
		display: grid;
		gap: var(--space-smallest);
	}
	.sms-mode-actions__summary dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-mode-actions__summary dd {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}
	.sms-mode-actions__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.sms-mode-actions__summary dl {
			grid-template-columns: 1fr;
		}
	}
</style>
