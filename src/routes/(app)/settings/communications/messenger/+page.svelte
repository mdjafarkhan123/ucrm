<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import MessengerHubBanner from '$lib/components/communications/messenger/MessengerHubBanner.svelte';
	import MessengerPagesCard from '$lib/components/communications/messenger/MessengerPagesCard.svelte';
	import MessengerLiveTest from '$lib/components/communications/messenger/MessengerLiveTest.svelte';
	import MessengerGoodToKnow from '$lib/components/communications/messenger/MessengerGoodToKnow.svelte';
	import MessengerWelcome from '$lib/components/communications/messenger/MessengerWelcome.svelte';
	import MessengerChoosePagesDialog from '$lib/components/communications/messenger/MessengerChoosePagesDialog.svelte';
	import {
		MESSENGER_SETTINGS_API,
		connectMessengerPages,
		disconnectMessengerPage,
		fetchMessengerOverview,
		makeMessengerPageDefault,
		messengerOverviewKey,
		type MessengerConnectResult,
		type MessengerConnection,
		type MessengerLoginOutcome
	} from '$lib/communications/messenger-settings';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import messageCircleIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import loginIcon from '@tabler/icons/outline/login-2.svg?raw';
	import plugXIcon from '@tabler/icons/outline/plug-x.svg?raw';

	// Settings → Messenger (concept.pen board `tEAXY`, Approved B, Jafar 2026-10-23). GoHighLevel's flow: log in to
	// Facebook in its own small window, tick the Pages, connect, then prove it with a live test message.
	const queryClient = useQueryClient();
	const toast = getToastManager();
	const overviewQuery = createQuery(() => ({
		queryKey: messengerOverviewKey,
		queryFn: fetchMessengerOverview,
		staleTime: 30_000
	}));
	const overview = $derived(overviewQuery.data);
	const connections = $derived(overview?.connections ?? []);

	// Facebook's window ----------------------------------------------------------------------------------------

	type LoginProblem = 'no_pages' | 'cancelled' | 'failed' | 'blocked';
	const LOGIN_PROBLEMS: Record<
		LoginProblem,
		{ text: string; retry: 'Try again' | 'Log in again' }
	> = {
		no_pages: {
			text: "Facebook didn't share any Pages with us. Try again and leave your Pages ticked in Facebook's window.",
			retry: 'Try again'
		},
		cancelled: {
			text: "You closed Facebook's window before finishing. Nothing was connected.",
			retry: 'Log in again'
		},
		failed: {
			text: "Facebook couldn't finish logging you in. Nothing was connected.",
			retry: 'Try again'
		},
		blocked: {
			text: "Your browser blocked Facebook's window. Allow pop-ups for this site, then try again.",
			retry: 'Try again'
		}
	};

	let loggingIn = $state(false);
	let loginProblem = $state<LoginProblem | null>(null);
	let reconnectPageId = $state<string | null>(null);
	let sessionId = $state<string | null>(null);
	let popup: Window | null = null;
	let closedWatch: ReturnType<typeof setInterval> | undefined;

	function stopWatching() {
		clearInterval(closedWatch);
		closedWatch = undefined;
	}

	function startLogin(pageId: string | null = null) {
		if (loggingIn && popup && !popup.closed) {
			popup.focus();
			return;
		}
		loginProblem = null;
		reconnectPageId = pageId;
		sessionId = null;
		const width = 600;
		const height = 720;
		const left = Math.max(0, window.screenX + (window.outerWidth - width) / 2);
		const top = Math.max(0, window.screenY + (window.outerHeight - height) / 2);
		popup = window.open(
			`${MESSENGER_SETTINGS_API}/login`,
			'ucrm-messenger-login',
			`popup=yes,width=${width},height=${height},left=${left},top=${top}`
		);
		if (!popup) {
			loginProblem = 'blocked';
			return;
		}
		loggingIn = true;
		stopWatching();
		closedWatch = setInterval(() => {
			if (!popup?.closed) return;
			stopWatching();
			// The window's own message can trail its closing by a moment.
			setTimeout(() => {
				if (!loggingIn) return;
				loggingIn = false;
				loginProblem = 'cancelled';
			}, 1_500);
		}, 500);
	}

	function handleOutcome(outcome: MessengerLoginOutcome) {
		stopWatching();
		loggingIn = false;
		popup = null;
		if (outcome.result === 'ok') {
			loginProblem = null;
			connectFailures = [];
			sessionId = outcome.session_id;
		} else {
			loginProblem = outcome.result;
		}
	}

	function isOutcome(data: unknown): data is MessengerLoginOutcome {
		return (
			!!data &&
			typeof data === 'object' &&
			(data as { type?: unknown }).type === 'ucrm-messenger-login'
		);
	}

	onMount(() => {
		const onMessage = (event: MessageEvent) => {
			if (event.origin === window.location.origin && isOutcome(event.data))
				handleOutcome(event.data);
		};
		window.addEventListener('message', onMessage);
		let channel: BroadcastChannel | null = null;
		try {
			channel = new BroadcastChannel('ucrm-messenger-login');
			channel.onmessage = (event) => {
				if (isOutcome(event.data)) handleOutcome(event.data);
			};
		} catch {
			channel = null;
		}
		return () => {
			window.removeEventListener('message', onMessage);
			channel?.close();
			stopWatching();
		};
	});

	// Choose Pages ---------------------------------------------------------------------------------------------

	let connecting = $state(false);
	let connectFailures = $state<MessengerConnectResult['failed']>([]);

	async function connect(pageIds: string[]) {
		if (!sessionId || connecting) return;
		connecting = true;
		try {
			const result = await connectMessengerPages(sessionId, pageIds);
			await queryClient.invalidateQueries({ queryKey: messengerOverviewKey });
			if (result.connected.length) {
				toast.success(
					result.connected.length === 1
						? `${result.connected[0].page_name} is connected.`
						: `${result.connected.length} Pages are connected.`
				);
				startTest(result.connected[0].id);
			}
			if (result.failed.length) connectFailures = result.failed;
			else closeChooser();
		} catch (error) {
			toast.error(error instanceof Error ? error.message : 'The Pages could not be connected.');
		} finally {
			connecting = false;
		}
	}

	function closeChooser() {
		sessionId = null;
		reconnectPageId = null;
		connectFailures = [];
	}

	// Default and disconnect -------------------------------------------------------------------------------------

	let defaultSavingId = $state<string | null>(null);
	let disconnectTarget = $state<MessengerConnection | null>(null);
	let disconnecting = $state(false);

	async function makeDefault(connection: MessengerConnection) {
		defaultSavingId = connection.id;
		try {
			await makeMessengerPageDefault(connection.id);
			await queryClient.invalidateQueries({ queryKey: messengerOverviewKey });
			toast.success(`${connection.page_name} is now the default Page.`);
		} catch (error) {
			toast.error(
				error instanceof Error ? error.message : 'The default Page could not be changed.'
			);
		} finally {
			defaultSavingId = null;
		}
	}

	async function confirmDisconnect() {
		if (!disconnectTarget || disconnecting) return;
		disconnecting = true;
		const target = disconnectTarget;
		try {
			await disconnectMessengerPage(target.id);
			await queryClient.invalidateQueries({ queryKey: messengerOverviewKey });
			toast.success(`${target.page_name} is disconnected. Its conversations are kept.`);
			disconnectTarget = null;
		} catch (error) {
			toast.error(error instanceof Error ? error.message : 'The Page could not be disconnected.');
		} finally {
			disconnecting = false;
		}
	}

	// Live test --------------------------------------------------------------------------------------------------

	let testConnectionId = $state('');
	let testSince = $state(new Date(Date.now() - 5_000).toISOString());
	const testable = $derived(connections.filter((connection) => connection.status !== 'reconnect'));

	function startTest(connectionId: string) {
		testConnectionId = connectionId;
		testSince = new Date(Date.now() - 5_000).toISOString();
	}

	// Until someone picks: the first Page still waiting for a test, otherwise the default one.
	const activeTestId = $derived(
		testable.some((connection) => connection.id === testConnectionId)
			? testConnectionId
			: (
					testable.find((connection) => connection.status === 'waiting') ??
					testable.find((connection) => connection.is_default) ??
					testable[0]
				)?.id
	);

	const needsYou = $derived(
		connections.filter((connection) => connection.status === 'reconnect').length
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -- trusted build-time Tabler icons -->
<svelte:head><title>Messenger · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
	<div class="messenger-settings record-detail--cards">
		<div class="messenger-settings__heading">
			<Breadcrumbs
				items={[
					{ label: 'Settings', href: resolve('/(app)/settings') },
					{ label: 'Messenger', icon: messageCircleIcon }
				]}
			/>
			<PageHeader
				icon={phoneIcon}
				tone="conversation"
				title="Messenger"
				description="Your Facebook Pages, whether their messages reach Conversations, and what to do next."
			/>
		</div>

		{#if loginProblem}
			<Banner type="warning">
				{LOGIN_PROBLEMS[loginProblem].text}
				{#snippet action()}
					<Button variant="secondary" onclick={() => startLogin(reconnectPageId)}>
						<span aria-hidden="true">
							{@html LOGIN_PROBLEMS[loginProblem!].retry === 'Try again' ? refreshIcon : loginIcon}
						</span>
						{LOGIN_PROBLEMS[loginProblem!].retry}
					</Button>
				{/snippet}
			</Banner>
		{/if}

		{#if overviewQuery.isPending}
			<LoadingSkeleton variant="card" label="Loading your Facebook Pages" />
		{:else if overviewQuery.isError}
			<ErrorState
				title="Your Facebook Pages could not be loaded"
				description={overviewQuery.error.message}
				retry={() => overviewQuery.refetch()}
			/>
		{:else if overview}
			{#if !overview.configured}
				<Banner type="warning">
					Messenger isn't switched on for Uplift yet. Please contact support.
				</Banner>
			{/if}
			{#if connections.length === 0}
				<MessengerWelcome
					{loggingIn}
					disabled={!overview.configured}
					onLogin={() => startLogin()}
				/>
			{:else}
				<MessengerHubBanner
					pageCount={connections.length}
					{needsYou}
					newThisWeek={overview.new_conversations_this_week}
					facebookUserName={overview.facebook_user_name}
					{loggingIn}
					onConnect={() => startLogin()}
				/>
				<div class="messenger-settings__body">
					<MessengerPagesCard
						{connections}
						{defaultSavingId}
						{loggingIn}
						onConnect={() => startLogin()}
						onReconnect={(connection) => startLogin(connection.page_id)}
						onMakeDefault={makeDefault}
						onDisconnect={(connection) => (disconnectTarget = connection)}
						onTest={(connection) => startTest(connection.id)}
					/>
					<div class="messenger-settings__side">
						{#if activeTestId}
							<MessengerLiveTest
								connections={testable}
								connectionId={activeTestId}
								since={testSince}
								onPick={startTest}
							/>
						{/if}
						<MessengerGoodToKnow />
					</div>
				</div>
			{/if}
		{/if}
	</div>
</PageContainer>

{#if sessionId}
	<MessengerChoosePagesDialog
		{sessionId}
		preselectPageId={reconnectPageId}
		{connecting}
		failures={connectFailures}
		onConnect={connect}
		onLoginAgain={() => {
			const pageId = reconnectPageId;
			closeChooser();
			startLogin(pageId);
		}}
		onClose={closeChooser}
	/>
{/if}

{#if disconnectTarget}
	<ConfirmDialog
		open
		title={`Disconnect ${disconnectTarget.page_name}?`}
		icon={plugXIcon}
		tone="critical"
		destructive
		confirmLabel="Disconnect Page"
		loading={disconnecting}
		onConfirm={confirmDisconnect}
		onClose={() => {
			if (!disconnecting) disconnectTarget = null;
		}}
	>
		New Facebook messages to this Page will stop coming in, and staff can't reply on Messenger from
		it. Old conversations stay in Conversations. Reconnect later and the same threads carry on.
	</ConfirmDialog>
{/if}

<style lang="scss">
	.messenger-settings {
		display: grid;
		min-width: 0;
		gap: var(--space-large);

		&__heading :global(.page-header) {
			margin-bottom: 0;
		}
		&__heading {
			display: grid;
			gap: 14px;
		}
		&__body {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 360px;
			align-items: start;
			gap: var(--space-large);
		}
		&__side {
			display: grid;
			gap: var(--space-large);
		}
	}
	@media (max-width: 1100px) {
		.messenger-settings__body {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
