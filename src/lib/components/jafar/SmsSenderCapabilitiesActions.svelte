<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	type LifecycleState = 'pending_setup' | 'ready' | 'restricted' | 'suspended' | 'released';
	type Sender = {
		id: string;
		phone_number: string;
		display_name: string | null;
		lifecycle_state: LifecycleState;
		allows_manual: boolean;
		allows_automated: boolean;
		country_code: string | null;
		sender_type: string | null;
		capable_sms: boolean;
		capable_mms: boolean;
		capable_voice: boolean;
		registration_id: string | null;
	};
	type SenderListResponse = { senders?: Sender[]; error?: string };
	type Registration = { id: string; country_code: string; sender_type: string; use_case: string };
	type RegistrationListResponse = { registrations?: Registration[]; error?: string };
	type MutationResponse = { error?: string; field_errors?: Record<string, string> };

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const sendersKey = $derived(['jafar', 'organizations', organizationId, 'sms', 'senders']);
	// Shares its cache with SmsRegistrationActions's identical query key.
	const registrationsKey = $derived([
		'jafar',
		'organizations',
		organizationId,
		'sms',
		'registrations'
	]);

	const sendersQuery = createQuery<SenderListResponse>(() => ({
		queryKey: sendersKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/sender-identities`
			);
			const result = (await response.json()) as SenderListResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'SMS sender identities could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	const registrationsQuery = createQuery<RegistrationListResponse>(() => ({
		queryKey: registrationsKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/registrations`
			);
			const result = (await response.json()) as RegistrationListResponse;
			if (!response.ok) throw new Error(result.error ?? 'SMS registrations could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	const senderTypeOptions = [
		{ value: 'long_code', label: 'Long code' },
		{ value: 'toll_free', label: 'Toll-free' },
		{ value: 'short_code', label: 'Short code' },
		{ value: 'alphanumeric', label: 'Alphanumeric' }
	];
	const lifecycleTone: Record<LifecycleState, 'success' | 'warning' | 'critical' | 'inactive'> = {
		pending_setup: 'warning',
		ready: 'success',
		restricted: 'warning',
		suspended: 'critical',
		released: 'inactive'
	};
	const registrationOptions = $derived([
		{ value: '', label: 'No linked registration' },
		...(registrationsQuery.data?.registrations ?? []).map((registration) => ({
			value: registration.id,
			label: `${registration.country_code} · ${registration.sender_type} · ${registration.use_case}`
		}))
	]);

	let editingId = $state<string | null>(null);
	let countryCode = $state('');
	let senderType = $state('long_code');
	let capableSms = $state(false);
	let capableMms = $state(false);
	let capableVoice = $state(false);
	let registrationId = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	const toast = getToastManager();
	let feedbackError = $state('');

	function startEditing(sender: Sender) {
		editingId = sender.id;
		countryCode = sender.country_code ?? '';
		senderType = sender.sender_type ?? 'long_code';
		capableSms = sender.capable_sms;
		capableMms = sender.capable_mms;
		capableVoice = sender.capable_voice;
		registrationId = sender.registration_id ?? '';
		fieldErrors = {};
		feedbackError = '';
	}

	const capabilitiesMutation = createMutation<
		MutationResponse,
		Error,
		{ senderId: string; body: Record<string, unknown> }
	>(() => ({
		mutationFn: async ({ senderId, body }) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/sender-identities/${senderId}/capabilities`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(body)
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'The capabilities could not be set.');
			}
			return result;
		},
		onMutate: () => {
			feedbackError = '';
			fieldErrors = {};
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async () => {
			editingId = null;
			await queryClient.invalidateQueries({ queryKey: sendersKey });
			toast.success('Sender capabilities saved.');
		}
	}));

	function submit(event: SubmitEvent) {
		event.preventDefault();
		if (!editingId) return;
		if (!/^[A-Za-z]{2}$/.test(countryCode.trim())) {
			fieldErrors = { country_code: 'Enter a 2-letter country code.' };
			return;
		}
		capabilitiesMutation.mutate({
			senderId: editingId,
			body: {
				country_code: countryCode.trim().toUpperCase(),
				sender_type: senderType,
				capable_sms: capableSms,
				capable_mms: capableMms,
				capable_voice: capableVoice,
				...(registrationId ? { registration_id: registrationId } : {})
			}
		});
	}
</script>

<div class="sms-sender-actions">
	<div class="sms-sender-actions__heading">
		<div>
			<h3>SMS sender capabilities</h3>
			<p>
				What each assigned business number can actually do, as reported by the provider, and the
				registration it belongs to.
			</p>
		</div>
	</div>

	{#if feedbackError}<p class="sms-sender-actions__error" role="alert">{feedbackError}</p>{/if}

	{#if sendersQuery.isPending}
		<LoadingSkeleton variant="table" rows={2} label="Loading SMS sender identities" />
	{:else if sendersQuery.isError}
		<ErrorState
			title="SMS sender identities could not be loaded"
			description={sendersQuery.error instanceof Error ? sendersQuery.error.message : 'Try again.'}
			retry={() => sendersQuery.refetch()}
		/>
	{:else if (sendersQuery.data?.senders ?? []).length === 0}
		<EmptyState
			title="No business number assigned"
			description="Numbers appear here once assigned to this organization."
		/>
	{:else}
		<ul class="sms-sender-actions__list">
			{#each sendersQuery.data?.senders ?? [] as sender (sender.id)}
				<li class="sms-sender-actions__row">
					<div class="sms-sender-actions__row-heading">
						<div>
							<h4>{sender.display_name ?? sender.phone_number}</h4>
							<p>{sender.phone_number}</p>
						</div>
						<Badge status={lifecycleTone[sender.lifecycle_state]}>{sender.lifecycle_state}</Badge>
					</div>
					<dl>
						<div>
							<dt>Capabilities</dt>
							<dd>
								{[
									sender.capable_sms && 'SMS',
									sender.capable_mms && 'MMS',
									sender.capable_voice && 'Voice'
								]
									.filter(Boolean)
									.join(', ') || 'None recorded'}
							</dd>
						</div>
						<div>
							<dt>Provider details</dt>
							<dd>{sender.country_code ?? 'Not set'} &middot; {sender.sender_type ?? 'Not set'}</dd>
						</div>
					</dl>

					{#if editingId === sender.id}
						<form class="sms-sender-actions__form" onsubmit={submit}>
							<Input
								id={`sms-sender-country-${sender.id}`}
								label="Country code (e.g. US)"
								bind:value={countryCode}
								maxlength={2}
								invalid={Boolean(fieldErrors.country_code)}
								errorMessage={fieldErrors.country_code}
							/>
							<Select
								id={`sms-sender-type-${sender.id}`}
								label="Sender type"
								options={senderTypeOptions}
								bind:value={senderType}
							/>
							<div class="sms-sender-actions__checkboxes">
								<Checkbox
									id={`sms-sender-sms-${sender.id}`}
									label="SMS"
									bind:checked={capableSms}
								/>
								<Checkbox
									id={`sms-sender-mms-${sender.id}`}
									label="MMS"
									bind:checked={capableMms}
								/>
								<Checkbox
									id={`sms-sender-voice-${sender.id}`}
									label="Voice"
									bind:checked={capableVoice}
								/>
							</div>
							<Select
								id={`sms-sender-registration-${sender.id}`}
								label="Linked registration"
								options={registrationOptions}
								bind:value={registrationId}
							/>
							<div class="sms-sender-actions__actions">
								<Button type="submit" loading={capabilitiesMutation.isPending}
									>Save capabilities</Button
								>
								<Button
									type="button"
									variant="secondary"
									variation="subtle"
									onclick={() => (editingId = null)}>Cancel</Button
								>
							</div>
						</form>
					{:else}
						<div class="sms-sender-actions__actions">
							<Button
								size="small"
								variant="secondary"
								variation="subtle"
								onclick={() => startEditing(sender)}
							>
								Edit capabilities
							</Button>
						</div>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style lang="scss">
	.sms-sender-actions {
		display: grid;
		gap: var(--space-base);
	}
	.sms-sender-actions__heading h3 {
		font-size: var(--typography--fontSize-large);
	}
	.sms-sender-actions__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.sms-sender-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.sms-sender-actions__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.sms-sender-actions__row {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.sms-sender-actions__row-heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-sender-actions__row-heading h4 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.sms-sender-actions__row-heading p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-sender-actions__row dl {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;
	}
	.sms-sender-actions__row dl > div {
		display: grid;
		gap: var(--space-smallest);
	}
	.sms-sender-actions__row dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-sender-actions__row dd {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}
	.sms-sender-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.sms-sender-actions__checkboxes {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-base);
	}
	.sms-sender-actions__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.sms-sender-actions__row-heading {
			flex-direction: column;
		}
		.sms-sender-actions__row dl {
			grid-template-columns: 1fr;
		}
	}
</style>
