<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		smsModeQuery,
		smsSendersQuery,
		smsTwilioAccountQuery
	} from '$lib/jafar/organization-communications-queries';
	import { jafarOrganizationSmsModeKey } from '$lib/jafar/query-keys';
	import {
		shortSid,
		TWILIO_SUBACCOUNTS_URL,
		type BusinessDestinations
	} from '$lib/jafar/texting-setup';
	import { smsDestinationsQuery } from '$lib/jafar/organization-communications-queries';
	import { languageName } from '$lib/communications/sms-opt-out-words';
	import powerIcon from '@tabler/icons/outline/power.svg?raw';
	import keyIcon from '@tabler/icons/outline/key.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import externalIcon from '@tabler/icons/outline/external-link.svg?raw';

	// The two side cards at the top of a business's Communications › Texting view (`concept.pen` board `v6Jtu`):
	// who decides if it can text (Uplift can force it with a reason), and the Twilio account Uplift made for it.
	let { organizationId, organizationName }: { organizationId: string; organizationName: string } =
		$props();

	type SmsMode = 'off' | 'operational';
	type ModeResponse = {
		mode: {
			package_max_mode: SmsMode;
			chosen_mode: SmsMode;
			override_mode: SmsMode | null;
			override_reason: string | null;
		} | null;
		effective_mode: SmsMode;
	};
	type Sender = { lifecycle_state: string; sender_type: string | null };
	type AccountResponse = {
		account: {
			subaccount_sid: string;
			messaging_service_sid: string | null;
			lifecycle_state: string;
		} | null;
	};
	type Override = 'none' | SmsMode;

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const mode = createQuery(() => smsModeQuery<ModeResponse>(organizationId));
	const account = createQuery(() => smsTwilioAccountQuery<AccountResponse>(organizationId));
	const senders = createQuery(() => smsSendersQuery<{ senders: Sender[] }>(organizationId));
	// The same countries query as the card beside it; it carries the opt-out languages Uplift added (Part 5d).
	const countries = createQuery(() => smsDestinationsQuery<BusinessDestinations>(organizationId));
	const optOutWords = $derived(
		[
			'English',
			...(countries.data?.opt_out_languages ?? []).map((row) => languageName(row.language))
		].join(', ')
	);

	const on = $derived(mode.data?.effective_mode === 'operational');
	// No saved mode means texting was never set up, and it is off until it is.
	const facts = $derived.by(() => {
		const current = mode.data?.mode;
		const unset = 'Not set up yet';
		const override = current?.override_mode;
		return [
			{
				label: 'Package allows',
				value: !current
					? unset
					: current.package_max_mode === 'operational'
						? 'Texting included'
						: 'No texting'
			},
			{
				label: `${organizationName} chose`,
				value: !current ? unset : current.chosen_mode === 'operational' ? 'On' : 'Off'
			},
			{
				label: 'Uplift override',
				value: override
					? `Forced ${override === 'operational' ? 'on' : 'off'} · ${current?.override_reason}`
					: 'None'
			}
		];
	});

	const SENDER_KINDS: Record<string, string> = {
		long_code: 'local',
		toll_free: 'toll-free',
		short_code: 'short code',
		alphanumeric: 'sender name'
	};
	const numbers = $derived.by(() => {
		const live = (senders.data?.senders ?? []).filter((row) => row.lifecycle_state !== 'released');
		if (!live.length) return 'None yet';
		const counts = new Map<string, number>();
		for (const row of live) {
			const kind = SENDER_KINDS[row.sender_type ?? ''] ?? 'other';
			counts.set(kind, (counts.get(kind) ?? 0) + 1);
		}
		return `${live.length} · ${[...counts].map(([kind, count]) => `${count} ${kind}`).join(', ')}`;
	});

	// Changing the mode: the override and, when forcing, the reason the owner log keeps.
	let editing = $state(false);
	let override = $state<Override>('none');
	let reason = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	const overrideOptions = [
		{ value: 'none', label: 'None' },
		{ value: 'off', label: 'Force off' },
		{ value: 'operational', label: 'Force on' }
	];

	function startChange() {
		override = mode.data?.mode?.override_mode ?? 'none';
		reason = mode.data?.mode?.override_reason ?? '';
		fieldErrors = {};
		editing = true;
	}

	const save = createMutation<unknown, Error, Record<string, unknown>>(() => ({
		mutationFn: async (body) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/mode`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(body)
				}
			);
			const result = await response.json().catch(() => ({}));
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'The texting mode could not be changed.');
			}
			return result;
		},
		onError: (error) => {
			if (!Object.keys(fieldErrors).length) toast.error('Couldn’t save the mode', error.message);
		},
		onSuccess: async () => {
			editing = false;
			toast.success('Texting mode saved', `${organizationName} sees the change straight away.`);
			await queryClient.invalidateQueries({
				queryKey: jafarOrganizationSmsModeKey(organizationId)
			});
		}
	}));

	function submit(event: SubmitEvent) {
		event.preventDefault();
		fieldErrors = {};
		const current = mode.data?.mode;
		if (override === 'none') {
			if (!current?.override_mode) {
				editing = false;
				return;
			}
			save.mutate({ clear_override: true });
			return;
		}
		if (!reason.trim()) {
			fieldErrors = { override_reason: 'Say why, so the log explains it later.' };
			return;
		}
		save.mutate({ override_mode: override, override_reason: reason.trim() });
	}

	let copied = $state<string | null>(null);
	async function copy(value: string) {
		try {
			await navigator.clipboard.writeText(value);
			copied = value;
			toast.success('Copied', value);
		} catch {
			toast.error('Couldn’t copy', 'Select the ID and copy it by hand.');
		}
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. Twilio’s own pages are not app routes. -->
<!-- eslint-disable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
<div class="texting-side">
	<section class="texting-side__card" aria-labelledby="texting-mode-title">
		<CardHeader
			id="texting-mode-title"
			title="Texting mode"
			hint={editing ? 'Changing' : `Who decides if ${organizationName} can text`}
			icon={powerIcon}
			tone="success"
			level={3}
			compact
		>
			{#snippet actions()}
				{#if mode.data && !editing}
					<StatusBadge status={on ? 'success' : 'inactive'} size="small"
						>{on ? 'On' : 'Off'}</StatusBadge
					>
				{/if}
			{/snippet}
		</CardHeader>

		{#if mode.isPending}
			<div class="texting-side__body" aria-busy="true" aria-label="Loading the texting mode">
				{#each [0, 1, 2] as row (row)}<div class="texting-side__fact texting-side__fact--loading">
						<span></span><span></span>
					</div>{/each}
			</div>
		{:else if mode.isError}
			<div class="texting-side__state">
				<ErrorState
					title="Couldn’t load the texting mode"
					description="Check your connection and try again."
					retry={() => mode.refetch()}
				/>
			</div>
		{:else if editing}
			<form class="texting-side__form" onsubmit={submit}>
				<dl class="texting-side__body">
					{#each facts.slice(0, 2) as fact (fact.label)}
						<div class="texting-side__fact">
							<dt>{fact.label}</dt>
							<dd>{fact.value}</dd>
						</div>
					{/each}
				</dl>
				<div class="texting-side__fields">
					<Select
						id="texting-mode-override"
						label="Uplift override"
						options={overrideOptions}
						bind:value={override}
						disabled={save.isPending}
					/>
					{#if override !== 'none'}
						<Input
							id="texting-mode-reason"
							label="Reason, kept in the log"
							bind:value={reason}
							required
							disabled={save.isPending}
							invalid={Boolean(fieldErrors.override_reason)}
							errorMessage={fieldErrors.override_reason}
						/>
					{/if}
				</div>
				<div class="texting-side__foot texting-side__foot--end">
					<Button
						size="small"
						variant="secondary"
						disabled={save.isPending}
						onclick={() => (editing = false)}>Cancel</Button
					>
					<Button size="small" type="submit" loading={save.isPending}>
						<span aria-hidden="true">{@html checkIcon}</span>
						Save mode
					</Button>
				</div>
			</form>
		{:else}
			<dl class="texting-side__body">
				{#each facts as fact (fact.label)}
					<div class="texting-side__fact">
						<dt>{fact.label}</dt>
						<dd>{fact.value}</dd>
					</div>
				{/each}
			</dl>
			<div class="texting-side__foot">
				<p>Uplift can force it {on ? 'off' : 'on'} with a reason.</p>
				<Button size="small" variant="secondary" onclick={startChange}>
					<span aria-hidden="true">{@html pencilIcon}</span>
					Change
				</Button>
			</div>
		{/if}
	</section>

	<section class="texting-side__card" aria-labelledby="twilio-account-title">
		<CardHeader
			id="twilio-account-title"
			title="Twilio account"
			hint={account.data && !account.data.account
				? 'Not made yet'
				: `Made by Uplift for ${organizationName}`}
			icon={keyIcon}
			tone="informative"
			level={3}
			compact
		/>

		{#if account.isPending}
			<div class="texting-side__body" aria-busy="true" aria-label="Loading the Twilio account">
				{#each [0, 1, 2, 3] as row (row)}<div
						class="texting-side__fact texting-side__fact--loading"
					>
						<span></span><span></span>
					</div>{/each}
			</div>
		{:else if account.isError}
			<div class="texting-side__state">
				<ErrorState
					title="Couldn’t load the Twilio account"
					description="Check your connection and try again."
					retry={() => account.refetch()}
				/>
			</div>
		{:else if !account.data?.account}
			<p class="texting-side__empty">
				Uplift makes {organizationName}’s Twilio account when it gets its first number.
			</p>
		{:else}
			{@const row = account.data.account}
			<dl class="texting-side__body">
				<div class="texting-side__fact">
					<dt>Account</dt>
					<dd>{organizationName} · {shortSid(row.subaccount_sid)}</dd>
					<button
						type="button"
						class="texting-side__copy"
						aria-label="Copy the account ID"
						title={copied === row.subaccount_sid ? 'Copied' : 'Copy the account ID'}
						onclick={() => copy(row.subaccount_sid)}>{@html copyIcon}</button
					>
				</div>
				<div class="texting-side__fact">
					<dt>Messaging service</dt>
					<dd>
						{row.messaging_service_sid ? shortSid(row.messaging_service_sid) : 'Not made yet'}
					</dd>
					{#if row.messaging_service_sid}
						{@const sid = row.messaging_service_sid}
						<button
							type="button"
							class="texting-side__copy"
							aria-label="Copy the messaging service ID"
							title={copied === sid ? 'Copied' : 'Copy the messaging service ID'}
							onclick={() => copy(sid)}>{@html copyIcon}</button
						>
					{/if}
				</div>
				<div class="texting-side__fact">
					<dt>Opt-out words</dt>
					<dd>{optOutWords}</dd>
				</div>
				<div class="texting-side__fact">
					<dt>Numbers</dt>
					<dd>{senders.isPending ? '…' : numbers}</dd>
				</div>
			</dl>
			<div class="texting-side__foot">
				<a
					class="texting-side__link"
					href={TWILIO_SUBACCOUNTS_URL}
					target="_blank"
					rel="noreferrer"
				>
					Open this account in Twilio
					<span aria-hidden="true">{@html externalIcon}</span>
				</a>
			</div>
		{/if}
	</section>
</div>

<!-- eslint-enable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->

<style lang="scss">
	.texting-side {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		align-items: start;
		gap: var(--space-large);
		min-width: 0;

		&__card {
			display: flex;
			flex-direction: column;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
		}

		&__body {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: var(--space-smaller) var(--space-base);
		}

		&__fact {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) 0;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}

			dt {
				flex: none;
				width: 130px;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 500;
			}

			dd {
				flex: 1;
				min-width: 0;
				margin: 0;
				overflow: hidden;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 500;
				text-overflow: ellipsis;
				white-space: nowrap;
			}

			&--loading span {
				height: var(--space-slim);
				border-radius: var(--radius-small);
				background: var(--color-surface--background);

				&:first-child {
					width: 100px;
				}

				&:last-child {
					width: 140px;
				}
			}
		}

		&__copy {
			display: grid;
			flex: none;
			place-items: center;
			width: 24px;
			height: 24px;
			padding: 0;
			border: 0;
			border-radius: var(--radius-small);
			color: var(--color-icon--secondary);
			background: none;
			cursor: pointer;

			&:hover {
				color: var(--color-icon);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__form {
			display: flex;
			flex-direction: column;
		}

		&__fields {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			padding: 0 var(--space-base) var(--space-base);
		}

		&__foot {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin-top: auto;
			padding: var(--space-slim) var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);

			p {
				flex: 1;
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}

			&--end {
				justify-content: flex-end;
			}
		}

		&__link {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__empty {
			margin: 0;
			padding: var(--space-medium) var(--space-base);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}

		&__state {
			padding: var(--space-base);
		}
	}
</style>
