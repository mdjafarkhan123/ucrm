<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { communicationSendersKey } from '$lib/communications/senders';
	import {
		EmailSetupWriteError,
		MAILBOX_PROVIDERS,
		cancelEmailSetup,
		emailSetupKey,
		fetchEmailSetup,
		mailboxProviderLabel,
		requestEmailSetup,
		type MailboxProvider
	} from '$lib/communications/email-setup';
	import inboxIcon from '@tabler/icons/outline/mail-forward.svg?raw';

	const queryClient = useQueryClient();

	const setupQuery = createQuery(() => ({
		queryKey: emailSetupKey,
		queryFn: fetchEmailSetup,
		staleTime: 30_000
	}));
	const setup = $derived(setupQuery.data ?? null);
	const request = $derived(setup?.request ?? null);
	// Only owners and admins can ask; a teammate who can open this page just does not see the card.
	const forbidden = $derived(
		setupQuery.isError && (setupQuery.error as { status?: number }).status === 403
	);

	const providerOptions = MAILBOX_PROVIDERS.map((provider) => ({
		value: provider.value,
		label: provider.label
	}));

	let requestOpen = $state(false);
	let cancelOpen = $state(false);
	let rootDomain = $state('');
	let mailboxProvider = $state('');
	let note = $state('');
	let noDomain = $state(false);
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');

	function openRequest() {
		rootDomain = '';
		mailboxProvider = '';
		note = '';
		noDomain = false;
		fieldErrors = {};
		formError = '';
		requestOpen = true;
	}

	function closeRequest() {
		if (requestMutation.isPending) return;
		requestOpen = false;
	}

	async function refresh() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: emailSetupKey }),
			queryClient.invalidateQueries({ queryKey: communicationSendersKey })
		]);
	}

	const requestMutation = createMutation<unknown, Error, void>(() => ({
		mutationFn: () =>
			requestEmailSetup({
				root_domain: rootDomain,
				mailbox_provider: mailboxProvider as MailboxProvider,
				note
			}),
		onMutate: () => {
			fieldErrors = {};
			formError = '';
		},
		onError: (error) => {
			if (error instanceof EmailSetupWriteError) fieldErrors = error.fieldErrors;
			formError = error.message;
		},
		onSuccess: async () => {
			requestOpen = false;
			await refresh();
		}
	}));

	const cancelMutation = createMutation<unknown, Error, string>(() => ({
		mutationFn: (requestId) => cancelEmailSetup(requestId),
		onError: (error) => {
			formError = error.message;
		},
		// A refusal (Jafar has just started) also lands here after a refetch, so the card shows the true state.
		onSettled: async () => {
			cancelOpen = false;
			await refresh();
		}
	}));

	function submit(event: SubmitEvent) {
		event.preventDefault();
		const errors: Record<string, string> = {};
		if (!rootDomain.trim())
			errors.root_domain = 'Enter the website domain your business owns, such as yourbusiness.com.';
		if (!mailboxProvider) errors.mailbox_provider = 'Choose where your business email lives today.';
		fieldErrors = errors;
		if (Object.keys(errors).length) return;
		requestMutation.mutate();
	}

	function sentOn(value: string) {
		return new Date(value).toLocaleDateString('en-US', { dateStyle: 'medium' });
	}
</script>

{#if !forbidden && (!setupQuery.isSuccess || setup?.state !== 'ready')}
	<SectionBlock
		title="Set up your business email"
		hint="Customers see your business name and address, and their replies land in your inbox here."
		icon={inboxIcon}
		level={2}
	>
		{#snippet actions()}
			{#if setup?.state === 'none' || setup?.state === 'declined'}
				<Button onclick={openRequest}
					>{setup.state === 'declined' ? 'Request again' : 'Request email setup'}</Button
				>
			{/if}
		{/snippet}

		{#if setupQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading your email setup" />
		{:else if setupQuery.isError}
			<ErrorState
				description="Your email setup could not be loaded."
				retry={() => setupQuery.refetch()}
			/>
		{:else if setup?.state === 'waiting' && request}
			<div class="email-setup">
				<div class="email-setup__head">
					<Badge status="warning">Waiting for UCRM</Badge>
					<span class="email-setup__meta">Sent {sentOn(request.created_at)}</span>
				</div>
				<dl class="email-setup__facts">
					<div>
						<dt>Domain</dt>
						<dd>{request.root_domain}</dd>
					</div>
					<div>
						<dt>Email lives at</dt>
						<dd>{mailboxProviderLabel(request.mailbox_provider)}</dd>
					</div>
				</dl>
				<p class="email-setup__text">
					Your current mailbox keeps working. UCRM will contact you if we need access to your
					domain.
				</p>
				{#if formError}<p class="email-setup__error" role="alert">{formError}</p>{/if}
				<div>
					<Button
						variant="secondary"
						variation="subtle"
						onclick={() => {
							formError = '';
							cancelOpen = true;
						}}>Cancel request</Button
					>
				</div>
			</div>
		{:else if setup?.state === 'setting_up'}
			<div class="email-setup">
				<div class="email-setup__head">
					<Badge status="warning">Setting up</Badge>
					{#if request}<span class="email-setup__meta">{request.root_domain}</span>{/if}
				</div>
				<p class="email-setup__text">
					UCRM is setting up your business email now. You can add senders as soon as it is ready. To
					change anything, please contact us.
				</p>
			</div>
		{:else if setup?.state === 'declined' && request}
			<div class="email-setup">
				<div class="email-setup__head">
					<Badge status="critical">Request closed</Badge>
					<span class="email-setup__meta">{request.root_domain}</span>
				</div>
				<p class="email-setup__note">{request.closed_note}</p>
			</div>
		{:else}
			<p class="email-setup__text">
				Request setup and UCRM will do the technical work for you. You keep your current mailbox and
				never need to touch DNS yourself.
			</p>
		{/if}
	</SectionBlock>
{/if}

{#if requestOpen}
	<Dialog open title="Request email setup" onClose={closeRequest}>
		<form class="email-setup__form" onsubmit={submit}>
			{#if formError}<p class="email-setup__error" role="alert">{formError}</p>{/if}
			<Checkbox
				id="email-setup-no-domain"
				label="My business doesn't have its own website domain yet"
				checked={noDomain}
				onchange={(checked) => (noDomain = checked)}
			/>
			{#if noDomain}
				<p class="email-setup__notice" role="status">
					Business email is sent from a domain your business owns, such as yourbusiness.com. Once
					you have one, come back here and request setup.
				</p>
				<div class="email-setup__actions">
					<Button type="button" variant="secondary" variation="subtle" onclick={closeRequest}
						>Close</Button
					>
				</div>
			{:else}
				<Input
					id="email-setup-domain"
					label="Website domain"
					required
					autocapitalize="none"
					autocomplete="off"
					spellcheck={false}
					placeholder="yourbusiness.com"
					bind:value={rootDomain}
					invalid={Boolean(fieldErrors.root_domain)}
					errorMessage={fieldErrors.root_domain}
				/>
				<Select
					id="email-setup-provider"
					label="Where does your business email live today?"
					required
					placeholder="Choose one"
					options={providerOptions}
					bind:value={mailboxProvider}
				/>
				{#if fieldErrors.mailbox_provider}
					<p class="email-setup__error" role="alert">{fieldErrors.mailbox_provider}</p>
				{/if}
				<Textarea
					id="email-setup-note"
					label="Anything we should know? (optional)"
					rows={3}
					maxlength={1000}
					bind:value={note}
					invalid={Boolean(fieldErrors.note)}
					errorMessage={fieldErrors.note}
				/>
				<div class="email-setup__actions">
					<Button type="submit" loading={requestMutation.isPending}>Send request</Button>
					<Button
						type="button"
						variant="secondary"
						variation="subtle"
						disabled={requestMutation.isPending}
						onclick={closeRequest}>Cancel</Button
					>
				</div>
			{/if}
		</form>
	</Dialog>
{/if}

{#if cancelOpen && request}
	<ConfirmDialog
		open
		title="Cancel this request?"
		confirmLabel="Cancel request"
		cancelLabel="Keep request"
		loading={cancelMutation.isPending}
		onConfirm={() => cancelMutation.mutate(request.id)}
		onClose={() => (cancelOpen = false)}
	>
		<p>
			We haven't started yet, so nothing has changed on your domain. You can send a new request any
			time.
		</p>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.email-setup,
	.email-setup__form {
		display: grid;
		gap: var(--space-base);
	}
	.email-setup__head {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}
	.email-setup__meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.email-setup__facts {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr));
		gap: var(--space-base);
		margin: 0;

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		dd {
			margin: 0;
			font-weight: 600;
			overflow-wrap: anywhere;
		}
	}
	.email-setup__text,
	.email-setup__note {
		margin: 0;
		color: var(--color-text--secondary);
	}
	.email-setup__note {
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: var(--color-surface--background);
		white-space: pre-wrap;
	}
	.email-setup__notice {
		margin: 0;
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.email-setup__error {
		margin: 0;
		color: var(--color-critical--onSurface);
	}
	.email-setup__actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 640px) {
		.email-setup__actions {
			justify-content: flex-start;
		}
	}
</style>
