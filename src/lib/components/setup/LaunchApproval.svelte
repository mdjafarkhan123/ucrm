<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import LaunchChecksSummary from './LaunchChecksSummary.svelte';
	import {
		decideSetupLaunch,
		fetchSetupLaunchApproval,
		setupLaunchApprovalKey,
		setupPreviewKey,
		setupSummaryKey,
		type SetupWriteFailure
	} from '$lib/setup/api';
	import {
		LAUNCH_APPROVAL_METHOD_LABEL,
		LAUNCH_NOT_YET_NOTE_MAX,
		launchApprovalWording
	} from '$lib/setup/launch-approval';
	import { getSupportAsk } from '$lib/support/ask';

	// Client onboarding E4 (plan §6): launch approval on the Setup page. Uplift asks the final approver named in
	// setup to approve the newest preview. Signed in with that email, they tick one box and approve, or choose Not
	// yet, which tells Uplift and opens Chat with Uplift. Everyone else on the team sees who is being asked. Once
	// approved this is the receipt. Industry reference: Jobber's online quote approval, DocuSign's signing step.
	let { userId }: { userId: string | null } = $props();

	const queryClient = useQueryClient();
	const askUplift = getSupportAsk();
	const query = createQuery(() => ({
		queryKey: setupLaunchApprovalKey(userId),
		queryFn: fetchSetupLaunchApproval
	}));

	const request = $derived(query.data?.request ?? null);
	let agreed = $state(false);
	let confirmNotYet = $state(false);
	let notYetNote = $state('');
	let error = $state('');

	const refresh = () =>
		Promise.all([
			queryClient.invalidateQueries({ queryKey: setupLaunchApprovalKey(userId) }),
			queryClient.invalidateQueries({ queryKey: setupSummaryKey(userId) }),
			queryClient.invalidateQueries({ queryKey: setupPreviewKey(userId) })
		]);

	const failure = (cause: Error) => (cause as SetupWriteFailure).fieldErrors?.form ?? cause.message;

	const approve = createMutation(() => ({
		mutationFn: () =>
			decideSetupLaunch({ version: request!.version, decision: 'approve', agreed: true }),
		onMutate: () => (error = ''),
		onError: (cause) => (error = failure(cause)),
		onSettled: refresh
	}));

	const notYet = createMutation(() => ({
		mutationFn: () =>
			decideSetupLaunch({
				version: request!.version,
				decision: 'not_yet',
				note: notYetNote.trim() || null
			}),
		onMutate: () => (error = ''),
		onSuccess: () => {
			confirmNotYet = false;
			notYetNote = '';
			askUplift(null);
		},
		onError: (cause) => {
			confirmNotYet = false;
			error = failure(cause);
		},
		onSettled: refresh
	}));

	const busy = $derived(approve.isPending || notYet.isPending);

	const day = (value: string) =>
		new Date(value).toLocaleDateString(undefined, {
			weekday: 'short',
			day: 'numeric',
			month: 'short'
		});
	const moment = (value: string) =>
		new Date(value).toLocaleString(undefined, {
			day: 'numeric',
			month: 'long',
			year: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});

	// The request email links to #approval, which exists only once the answer has arrived.
	let scrolled = false;
	$effect(() => {
		if (!request || scrolled) return;
		scrolled = true;
		if (window.location.hash !== '#approval') return;
		requestAnimationFrame(() =>
			document.getElementById('approval')?.scrollIntoView({ behavior: 'smooth', block: 'start' })
		);
	});
</script>

{#if query.isPending}
	<LoadingSkeleton variant="card" label="Loading your launch approval" />
{:else if request?.status === 'approved' && request.approved_at}
	<SectionBlock id="approval" title="Approved for launch" icon={circleCheckIcon}>
		<div class="launch-approval launch-approval--done">
			<p class="launch-approval__lead">
				<strong>{request.approved_by_name}</strong> approved preview version {request.version} on
				{moment(request.approved_at)}{request.approval_method
					? `, ${LAUNCH_APPROVAL_METHOD_LABEL[request.approval_method]}`
					: ''}.
			</p>
			<blockquote class="launch-approval__wording">{request.approval_wording}</blockquote>
			<p class="launch-approval__muted">
				Uplift is preparing your launch and will tell you when it is live. A receipt was emailed to
				{request.approver_name} and your owners and administrators.
			</p>
		</div>
	</SectionBlock>
{:else if request?.status === 'open'}
	<SectionBlock
		id="approval"
		title="Approve your launch"
		icon={rocketIcon}
		hint="Asked {day(request.requested_at)}"
	>
		<div class="launch-approval">
			{#if query.data?.is_approver}
				<p class="launch-approval__lead">
					Uplift has checked your system. Look over preview version {request.version} below, then approve
					it to go live. Nothing goes live until you do.
				</p>
				{#if request.not_yet_at}
					<Banner type="notice">
						You told Uplift it is not ready yet on {day(request.not_yet_at)}. Uplift will talk it
						through with you in Chat with Uplift. You can still approve here when you are happy.
					</Banner>
				{/if}
				<LaunchChecksSummary checks={request.launch_checks} askedAt={request.requested_at} />
				<div class="launch-approval__agree">
					<Checkbox
						id="launch-approval-agree"
						label={launchApprovalWording(request.version)}
						checked={agreed}
						disabled={busy}
						onchange={(checked) => (agreed = checked)}
					/>
				</div>
				{#if error}
					<p class="launch-approval__error" role="alert">{error}</p>
				{/if}
				<div class="launch-approval__actions">
					<Button
						disabled={!agreed || busy}
						loading={approve.isPending}
						onclick={() => approve.mutate()}>Approve launch</Button
					>
					<Button
						variant="secondary"
						disabled={busy}
						onclick={() => {
							error = '';
							confirmNotYet = true;
						}}>Not yet — talk to Uplift</Button
					>
				</div>
			{:else}
				<p class="launch-approval__lead">
					Uplift has asked <strong>{request.approver_name}</strong>, the person named in setup to
					approve your launch, to approve preview version {request.version}. Uplift emailed them a
					private link on {day(request.link_sent_at)}.
				</p>
				{#if request.not_yet_at}
					<Banner type="notice">
						{request.not_yet_by_name ?? request.approver_name} told Uplift it is not ready yet on
						{day(request.not_yet_at)}. Uplift will talk it through with them.
					</Banner>
				{/if}
				<LaunchChecksSummary checks={request.launch_checks} askedAt={request.requested_at} />
				<p class="launch-approval__muted">
					Should someone else approve? Change the final approver in Your business, send your changes
					to Uplift, and Uplift will ask again.
				</p>
			{/if}
		</div>
	</SectionBlock>

	<ConfirmDialog
		open={confirmNotYet}
		title="Tell Uplift it is not ready yet?"
		confirmLabel="Tell Uplift"
		loading={notYet.isPending}
		onConfirm={() => notYet.mutate()}
		onClose={() => (confirmNotYet = false)}
	>
		<p>
			Nothing is approved. Uplift will be told, and Chat with Uplift opens so you can talk it
			through.
		</p>
		<Textarea
			id="launch-not-yet-note"
			label="What is not ready? (optional)"
			rows={3}
			maxlength={LAUNCH_NOT_YET_NOTE_MAX}
			bind:value={notYetNote}
		/>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.launch-approval {
		display: grid;
		gap: var(--space-base);

		&__lead {
			margin: 0;
			color: var(--color-text);
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__agree {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__wording {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-left: 3px solid var(--color-success);
			background: var(--color-surface--background);
			color: var(--color-heading);
			font-style: italic;
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
