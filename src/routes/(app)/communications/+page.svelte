<script lang="ts">
	import { untrack } from 'svelte';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { supabase } from '$lib/supabase.client';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import SidePanel from '$lib/components/layout/SidePanel.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import AttachmentList from '$lib/components/communications/AttachmentList.svelte';
	import MessageDetailsDialog from '$lib/components/communications/MessageDetailsDialog.svelte';
	import ForwardEmailDialog from '$lib/components/communications/ForwardEmailDialog.svelte';
	import ConversationContextRail from '$lib/components/communications/ConversationContextRail.svelte';
	import ConversationComposer from '$lib/components/communications/ConversationComposer.svelte';
	import ChooseClientDialog from '$lib/components/communications/ChooseClientDialog.svelte';
	import ManualEmailDialog from '$lib/components/clients/ManualEmailDialog.svelte';
	import {
		cancelScheduledConversationReply,
		clientCommunicationHistoryKey,
		conversationContextKey,
		conversationCustomerEmail,
		conversationCustomerPhone,
		endWebsiteChatSession,
		fetchConversationContext,
		fetchInboundAttachmentDownloadUrl,
		fetchInboxMessages,
		fetchTextStopNotes,
		fetchOutboundAttachmentDownloadUrl,
		followConversation,
		groupMessagesByContact,
		inboxMessagesKey,
		isWebsiteChatMessage,
		markConversationRead,
		outboundEmailStatus,
		pendingSendStatus,
		placeTimelineNotes,
		resendInboxEmail,
		resolveInboundReview,
		resolveWebsiteChatIdentity,
		textStopNotesKey,
		unfollowConversation,
		type ConversationGroup,
		type InboundInboxMessage,
		type InboxView,
		type OutboundInboxMessage,
		type PendingOutboundSend,
		type TextStopNote,
		type TimelineNoteSlot,
		type WebsiteChatInboxMessage,
		type WebsiteChatInboxSession
	} from '$lib/communications/inbox';
	import { previewText } from '$lib/collaboration/format';
	import { clientDetailKey, fetchClient, fetchClients } from '$lib/clients/api';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil-plus.svg?raw';
	import emailIcon from '@tabler/icons/outline/mail.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import messagesIcon from '@tabler/icons/outline/messages.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import messageOffIcon from '@tabler/icons/outline/message-circle-off.svg?raw';
	import messageCheckIcon from '@tabler/icons/outline/message-circle-check.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let search = $state('');
	let searchDraft = $state('');
	let view = $state<InboxView>('team');
	let listTab = $state<'all' | 'unread'>('all');
	// The client Communication tab's "Open conversation" link lands here with `?client=<id>`, which is
	// exactly a linked group's own key -- a guarded (unresolved-sender) group is never linkable this way,
	// since it has no client_id yet.
	let selectedGroupKey = $state<string | null>(page.url.searchParams.get('client'));
	let resendTarget = $state<OutboundInboxMessage | null>(null);
	let cancelScheduledTarget = $state<OutboundInboxMessage | null>(null);
	let detailsMessage = $state<InboundInboxMessage | null>(null);
	let forwardTarget = $state<InboundInboxMessage | null>(null);
	let linkTarget = $state<ConversationGroup | null>(null);
	let dismissTarget = $state<ConversationGroup | null>(null);
	let linkError = $state('');
	let newConversationOpen = $state(false);
	let newConversationClientId = $state<string | null>(null);
	let timelineEl = $state<HTMLDivElement | null>(null);
	// This is deliberately driven by the reader's own scroll position, rather than by a message count:
	// a new arrival only needs a "Jump to latest" affordance when the reader has chosen to inspect older
	// messages. It also keeps the control honest on short conversations that do not overflow at all.
	let showJumpToLatest = $state(false);
	// Which composer shows for the selected conversation, when more than one channel is eligible.
	// Reset (below) only when the selected conversation itself changes, never on every background refetch.
	let activeChannel = $state<'email' | 'sms' | 'website_chat'>('email');
	let composerExpanded = $state(false);
	let composerGroupKey: string | null = null;
	let endSessionTarget = $state<ConversationGroup | null>(null);
	let resolveIdentityTarget = $state<ConversationGroup | null>(null);
	let resolveIdentityError = $state('');
	// The ≤1050px context-rail replacement (5F): the rail's own content relocates into this drawer below
	// the breakpoint instead of being rebuilt. Closes on every conversation switch so it never reopens
	// showing a stale customer.
	let contextPanelOpen = $state(false);

	const inboxQuery = createQuery(() => ({
		queryKey: inboxMessagesKey(search, view),
		queryFn: () => fetchInboxMessages(search, view),
		staleTime: 15_000
	}));
	const messages = $derived(inboxQuery.data?.messages ?? []);
	// Grouping runs over one already-fetched page (max 50 messages, no "load more" yet), so an O(n)
	// client-side pass is cheap; a grouped server query would need its own pagination shape (order by each
	// conversation's latest message, not by message) for no real benefit at today's volume.
	const groups = $derived(
		groupMessagesByContact(
			messages,
			inboxQuery.data?.website_chat ?? [],
			inboxQuery.data?.website_chat_sessions ?? []
		)
	);

	// The tab only filters which rows are listed. Selection stays keyed against the full `groups` array
	// (below) so a conversation that was open when it dropped out of Unread -- because opening it just
	// marked it read -- keeps its detail panel open instead of being yanked away mid-read.
	const visibleGroups = $derived(
		listTab === 'unread' ? groups.filter((group) => group.unreadCount > 0) : groups
	);
	const unreadGroupCount = $derived(groups.filter((group) => group.unreadCount > 0).length);

	// The conversation list is one Tab stop, not one per row -- with hundreds of conversations a keyboard user
	// would otherwise Tab through every one to reach the timeline. The stop is the row last focused, else the
	// open conversation, else the first row; arrow keys move between the rest.
	let focusedRowKey = $state<string | null>(null);
	const rowTabStopKey = $derived.by(() => {
		for (const key of [focusedRowKey, selectedGroup?.key]) {
			if (key && visibleGroups.some((group) => group.key === key)) return key;
		}
		return visibleGroups[0]?.key ?? null;
	});

	// HighLevel opens an unread conversation scrolled to what needs attention rather than always the
	// newest item overall -- the smallest version of that here is: default selection favors the first
	// conversation with an unread inbound message, falling back to the most recent conversation once the
	// user has picked something or nothing is unread.
	const firstUnreadGroup = $derived(groups.find((group) => group.unreadCount > 0) ?? null);
	const selectedGroup = $derived(
		groups.find((group) => group.key === selectedGroupKey) ?? firstUnreadGroup ?? groups[0] ?? null
	);

	const emailAvailable = $derived(Boolean(selectedGroup?.clientId));
	// SMS shares email's availability rule (both need only a known client) rather than a separate org
	// readiness gate: the blueprint keeps a known SMS conversation visible even when it cannot send yet,
	// replacing Send with a plain reason instead of hiding the channel (see docs/communications-sms-
	// product-ui-blueprint.md "Availability and blocked sending").
	const smsAvailable = $derived(Boolean(selectedGroup?.clientId));
	const chatAvailable = $derived(Boolean(selectedGroup?.chatSession));
	const canSend = $derived(inboxQuery.data?.can_send ?? false);
	type ComposerChannel = 'email' | 'sms' | 'website_chat';
	const composerChannels = $derived.by(() => {
		const channels: ComposerChannel[] = [];
		if (emailAvailable) channels.push('email');
		if (smsAvailable) channels.push('sms');
		if (chatAvailable) channels.push('website_chat');
		return channels;
	});

	function latestMessageChannel(group: ConversationGroup): 'email' | 'sms' | 'website_chat' {
		if (isWebsiteChatMessage(group.latest)) return 'website_chat';
		return group.latest.channel === 'sms' ? 'sms' : 'email';
	}

	// Resets the composer's channel tab only when the selected conversation itself changes (by key), not
	// on every background refetch that follows a Realtime invalidation -- otherwise a reply in progress on
	// one tab would keep getting yanked back whenever the other channel receives a new message.
	$effect(() => {
		const key = selectedGroup?.key;
		if (!key || key === composerGroupKey) return;
		untrack(() => {
			const group = groups.find((entry) => entry.key === key);
			if (!group) return;
			composerGroupKey = key;
			composerExpanded = false;
			if (!group.clientId) {
				activeChannel = 'website_chat';
			} else {
				activeChannel = latestMessageChannel(group);
			}
		});
	});

	// WC4.5: live delivery to staff is ids only -- the page invalidates and the permission-filtered read
	// fetches the content, so a staff socket never carries a message body (one socket per member, not per
	// conversation, would otherwise route around the assigned-only view the read enforces).
	$effect(() => {
		const organizationId = page.data.organization?.id;
		if (!organizationId) return;
		const channel = supabase.channel(`wc-org:${organizationId}`, { config: { private: true } });
		channel.on('broadcast', { event: 'website_chat_activity' }, () => {
			// A send of our own fires this broadcast too, and the composer already re-reads once the server
			// answers -- letting both through cost a second full inbox download per message sent. While one of
			// our sends is outstanding the refresh is already coming, so this stands down. Anything that
			// arrived from somebody else meanwhile is picked up by that same re-read, a moment later.
			if (untrack(() => pendingSend) !== null) return;
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] });
		});
		// R1 live inbox: the email side broadcasts ids-only on this same org topic when an inbound email
		// arrives or an outbound delivery intent changes status/outcome. The inbox query carries both the
		// list and the open thread's messages, so one invalidation refreshes both -- queued -> delivered,
		// bounces, and inbound replies land without a reload. Same stand-down while our own send is in
		// flight, for the same reason as above.
		channel.on('broadcast', { event: 'communication_inbox_activity' }, () => {
			if (untrack(() => pendingSend) !== null) return;
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] });
		});
		channel.subscribe();
		return () => {
			supabase.removeChannel(channel);
		};
	});

	// Part 5D's work-context panel: one client's identity, contact methods, and a small related-work set.
	// Loads independently of the timeline (which already has everything it needs from `inboxQuery`), so
	// switching conversations never blocks on this -- only the panel itself shows a skeleton.
	const contextQuery = createQuery(() => ({
		queryKey: conversationContextKey(selectedGroup?.clientId ?? ''),
		queryFn: () => fetchConversationContext(selectedGroup?.clientId as string),
		enabled: selectedGroup?.clientId !== null && selectedGroup?.clientId !== undefined,
		staleTime: 30_000
	}));

	// The "texts stopped / turned back on" lines that sit in the thread. Small and per customer, so it loads
	// with the conversation; a failed load just leaves the lines out rather than blocking the thread.
	const textStopNotesQuery = createQuery(() => ({
		queryKey: textStopNotesKey(selectedGroup?.clientId ?? ''),
		queryFn: () => fetchTextStopNotes(selectedGroup?.clientId as string),
		enabled: selectedGroup?.clientId !== null && selectedGroup?.clientId !== undefined,
		staleTime: 30_000
	}));

	const notePlacement = $derived(
		selectedGroup
			? placeTimelineNotes(
					selectedGroup.messages,
					textStopNotesQuery.data ?? [],
					(a, b) => calendarDay(a) === calendarDay(b)
				)
			: null
	);

	// Starting a new conversation needs the client's own contact methods, which the inbox page never loads --
	// it only ever knows the address a conversation already used. Fetching on demand keeps that cost off the
	// page load, and the key is the one the client pages already fill, so an already-visited client is instant.
	const newConversationClientQuery = createQuery(() => ({
		queryKey: clientDetailKey(newConversationClientId ?? ''),
		queryFn: () => fetchClient(newConversationClientId as string),
		enabled: newConversationClientId !== null,
		staleTime: 30_000
	}));

	// The picker's client list is behind a dialog, so it never loads with the page. Warming it on hover is
	// the standing rule for revealed content -- by the time the dialog opens the list is usually there.
	function prefetchClientPicker() {
		queryClient.prefetchQuery({
			queryKey: ['clients', 'picker', ''],
			queryFn: () =>
				fetchClients({ search: '', status: '', tagId: '', sort: 'updated_at', dir: 'desc' }),
			staleTime: 15_000
		});
	}

	function outboundIn(group: ConversationGroup, id: string) {
		return (
			group.messages.find(
				(message): message is OutboundInboxMessage =>
					!isWebsiteChatMessage(message) && message.direction === 'outbound' && message.id === id
			) ?? null
		);
	}

	function rowHeadline(group: ConversationGroup) {
		return isWebsiteChatMessage(group.latest) ? 'Website Chat' : group.latest.subject;
	}

	function rowPreview(group: ConversationGroup) {
		return previewText(
			isWebsiteChatMessage(group.latest) ? group.latest.body : group.latest.text_content
		);
	}

	function rowChannel(group: ConversationGroup): { label: string; icon: string } {
		if (isWebsiteChatMessage(group.latest)) return { label: 'Website chat', icon: messagesIcon };
		if (group.latest.channel === 'sms') return { label: 'SMS', icon: messageIcon };
		return { label: 'Email', icon: emailIcon };
	}

	// The email composer's default subject reuses the conversation's most recent email-shaped message --
	// neither a chat message nor an SMS has a subject line, so this skips backward past both the same way
	// `conversationCustomerEmail` skips a channel with no email address.
	function latestEmailSubject(group: ConversationGroup): string {
		for (let index = group.messages.length - 1; index >= 0; index -= 1) {
			const message = group.messages[index];
			if (!isWebsiteChatMessage(message) && message.channel !== 'sms') return message.subject;
		}
		return '';
	}

	const resendMutationState = createMutation(() => ({
		mutationFn: (email: OutboundInboxMessage) => resendInboxEmail(email.id, crypto.randomUUID()),
		onSuccess: (_result, email) => {
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] });
			// A resend is a new message on that client's history, cached under its own key (Part 5D).
			queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(email.client_id) });
			toast.success('Email sent');
			resendTarget = null;
		},
		onError: (error: Error) => toast.error('Could not resend the email', error.message)
	}));

	const cancelScheduledMutationState = createMutation(() => ({
		mutationFn: (email: OutboundInboxMessage) => cancelScheduledConversationReply(email.id),
		onSuccess: (_result, email) => {
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] });
			queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(email.client_id) });
			toast.success('Scheduled email cancelled');
			cancelScheduledTarget = null;
		},
		onError: (error: Error) => toast.error('Could not cancel the scheduled email', error.message)
	}));

	// Read state is per-conversation (per client), not per-message -- opening a conversation with an unread
	// inbound message marks it read as of now (docs/unified-inbox-behavior-contract.md: "opening alone does
	// not clear it; ... explicitly marking read ... may clear unread"). A guarded group has no client_id and
	// therefore no read-mark seam; it stays flagged until it's resolved to a client (Part 5C).
	const markReadMutationState = createMutation(() => ({
		mutationFn: (clientId: string) => markConversationRead(clientId),
		onSuccess: (_result, clientId) => {
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox', 'messages'] });
			// The client Communication tab renders the same unread styling from its own cached copy.
			queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(clientId) });
		},
		onError: (error: Error) => toast.error('Could not mark as read', error.message)
	}));

	function selectGroup(group: ConversationGroup) {
		selectedGroupKey = group.key;
		showJumpToLatest = false;
		// A stale rail from the previous conversation must not carry over -- the ≤1050px drawer is closed
		// on every switch, same as if it had never been opened.
		contextPanelOpen = false;
		if (group.clientId && group.unreadCount > 0) {
			markReadMutationState.mutate(group.clientId);
		}
	}

	// Following is self-service -- anyone who can already see this conversation may toggle it for
	// themselves, unlike assignment which changes someone else's workload.
	const followMutationState = createMutation(() => ({
		mutationFn: (input: { clientId: string; following: boolean }) =>
			input.following ? unfollowConversation(input.clientId) : followConversation(input.clientId),
		onSuccess: () => {
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] });
		},
		onError: (error: Error) => toast.error('Could not update following', error.message)
	}));

	// Resolving a guarded conversation is addressed by the sender's own address, since it has no client_id
	// yet. Linking covers every pending message from that sender at once -- exactly the row shown in the list.
	const resolveReviewMutationState = createMutation(() => ({
		mutationFn: (input: {
			senderEmail: string;
			resolution: 'link' | 'dismiss';
			clientId: string | null;
		}) => resolveInboundReview(input.senderEmail, input.resolution, input.clientId),
		onSuccess: (_result, input) => {
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] });
			// A link gives previously-guarded messages a client_id for the first time -- both of this
			// client's Part 5D caches (history tab, work-context panel) need to pick that history up.
			if (input.clientId) {
				queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(input.clientId) });
				queryClient.invalidateQueries({ queryKey: conversationContextKey(input.clientId) });
			}
			// The resolved conversation leaves this row behind either way, so drop the selection and let
			// the default land on whatever needs attention next.
			selectedGroupKey = null;
			contextPanelOpen = false;
			linkTarget = null;
			dismissTarget = null;
			linkError = '';
			if (input.resolution === 'link') {
				toast.success('Conversation linked', 'Its messages now belong to that client.');
			} else {
				toast.success('Conversation dismissed', 'It has left the inbox but is still on record.');
			}
		},
		onError: (error: Error, input) => {
			if (input.resolution === 'link') {
				linkError = error.message;
				return;
			}
			dismissTarget = null;
			toast.error('Could not dismiss the conversation', error.message);
		}
	}));

	// Ends a live Website Chat session from the staff side; the visitor's panel swaps to the ended state
	// over the same socket, no reload involved.
	const endSessionMutationState = createMutation(() => ({
		mutationFn: (sessionId: string) => endWebsiteChatSession(sessionId),
		onSuccess: () => {
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] });
			endSessionTarget = null;
			toast.success('Conversation ended', 'The visitor sees this conversation as ended.');
		},
		onError: (error: Error) => {
			endSessionTarget = null;
			toast.error('Could not end the conversation', error.message);
		}
	}));

	// Says which Client a conflicting-identity chat session belongs to. Unlike the email guarded flow,
	// there is no dismiss path -- the session already holds real messages and has already claimed an
	// allowance unit, so it always belongs to somebody.
	const resolveIdentityMutationState = createMutation(() => ({
		mutationFn: (input: { sessionId: string; clientId: string }) =>
			resolveWebsiteChatIdentity(input.sessionId, input.clientId),
		onSuccess: (_result, input) => {
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] });
			queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(input.clientId) });
			queryClient.invalidateQueries({ queryKey: conversationContextKey(input.clientId) });
			selectedGroupKey = null;
			contextPanelOpen = false;
			resolveIdentityTarget = null;
			resolveIdentityError = '';
			toast.success('Conversation linked', 'Its messages now belong to that client.');
		},
		onError: (error: Error) => {
			resolveIdentityError = error.message;
		}
	}));

	function scrollToMessage(id: string) {
		timelineEl?.querySelector(`[data-message-id="${CSS.escape(id)}"]`)?.scrollIntoView({
			behavior: 'smooth',
			block: 'center'
		});
	}

	// Where the timeline lands is an open-the-conversation decision, not something a background refetch
	// gets to redo. Opening anchors on the oldest unread inbound message -- the thing needing attention.
	// After that the timeline only follows new arrivals, and only while the reader is already parked at
	// the bottom, which is the standard chat "stick to bottom unless scrolled up" rule. Re-running the
	// anchor on every refetch is what threw the view back to the top of the thread after sending a reply:
	// the send invalidated, the messages array changed, and the effect re-anchored on an old unread.
	let anchoredKey: string | null = null;
	let anchoredLatestId: string | null = null;
	let stickToBottom = $state(true);
	// Read out by screen readers when a customer's message arrives in the conversation that is open. Only the
	// open conversation is announced, so a busy inbox never talks over the person while they read or type.
	let newMessageAnnouncement = $state('');

	// The composer owns the send -- its payload, its retry, its idempotency key -- and this only owns where
	// the in-flight bubble is drawn. It is stored against the conversation it was sent from, not against
	// whatever is selected when it settles, so a send still running while the user switches threads cannot
	// surface on somebody else's conversation.
	let pendingSend = $state<{ key: string; send: PendingOutboundSend } | null>(null);
	const visiblePendingSend = $derived(
		pendingSend && pendingSend.key === selectedGroup?.key ? pendingSend.send : null
	);

	function handlePendingChange(key: string, send: PendingOutboundSend | null) {
		if (send) {
			pendingSend = { key, send };
			return;
		}
		if (pendingSend?.key === key) pendingSend = null;
	}

	function handleTimelineScroll(event: Event) {
		const el = event.currentTarget as HTMLDivElement;
		stickToBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
		showJumpToLatest = !stickToBottom;
	}

	function scrollToLatest() {
		if (!timelineEl) return;
		stickToBottom = true;
		showJumpToLatest = false;
		const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
		timelineEl.scrollTo({
			top: timelineEl.scrollHeight,
			behavior: reduceMotion ? 'auto' : 'smooth'
		});
	}

	$effect(() => {
		const group = selectedGroup;
		const el = timelineEl;
		if (!group || !el) return;
		const key = group.key;
		// A send in flight is the newest thing on the thread, so it is what "latest" means here -- pressing
		// Send scrolls its bubble into view exactly as an arriving message would.
		const latestId = visiblePendingSend?.id ?? group.messages.at(-1)?.id ?? null;

		untrack(() => {
			if (anchoredKey !== key) {
				anchoredKey = key;
				anchoredLatestId = latestId;
				const target = group.messages.find(
					(message) => message.direction === 'inbound' && message.unread
				);
				const anchor = el.querySelector(
					`[data-message-id="${CSS.escape((target ?? group.messages.at(-1))?.id ?? '')}"]`
				);
				anchor?.scrollIntoView({ block: target ? 'center' : 'end' });
				stickToBottom = !target;
				return;
			}
			if (latestId === anchoredLatestId) return;
			// Sending is something the user just did on purpose, so it always scrolls to the message they
			// sent, even from a thread opened part-way up on an unread message. Only *arriving* messages have
			// to respect a reader who has deliberately scrolled back through history.
			const ownSend = visiblePendingSend?.id === latestId;
			anchoredLatestId = latestId;
			const latest = group.messages.at(-1);
			if (latest && latest.id === latestId && latest.direction === 'inbound') {
				newMessageAnnouncement = `New message from ${group.name}, ${formatWhen(latest.created_at)}`;
			}
			if (ownSend) {
				stickToBottom = true;
			}
			if (!stickToBottom) return;
			el.scrollTop = el.scrollHeight;
		});
	});

	// Arrow-key movement between conversation rows, matching listbox-style navigation -- Enter/Space still
	// selects, since these stay real buttons rather than switching to a non-native widget role. Attached to
	// each row button (an interactive element) rather than the `role="list"` container, which is not
	// interactive and must not carry a key handler.
	function handleRowKeydown(event: KeyboardEvent) {
		if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
		const list = (event.currentTarget as HTMLElement).closest('.communications__rows');
		if (!list) return;
		const rows = Array.from(list.querySelectorAll<HTMLButtonElement>('.communications__row'));
		const currentIndex = rows.indexOf(event.currentTarget as HTMLButtonElement);
		if (currentIndex === -1) return;
		event.preventDefault();
		const nextIndex =
			event.key === 'Home'
				? 0
				: event.key === 'End'
					? rows.length - 1
					: event.key === 'ArrowDown'
						? Math.min(currentIndex + 1, rows.length - 1)
						: Math.max(currentIndex - 1, 0);
		rows[nextIndex]?.focus();
	}

	function reviewBadge(message: InboundInboxMessage) {
		if (message.review_status === 'accepted') return null;
		if (message.review_reason === 'unknown_sender')
			return { label: 'Needs review — unknown sender', tone: 'warning' as const };
		if (message.review_reason === 'ambiguous_sender')
			return { label: 'Needs review — multiple matches', tone: 'warning' as const };
		if (message.review_reason === 'expired_alias')
			return { label: 'Needs review — link expired', tone: 'warning' as const };
		return { label: 'Needs review', tone: 'warning' as const };
	}

	function kindBadge(message: InboundInboxMessage) {
		if (message.message_kind === 'loop_detected')
			return { label: 'Automation paused', tone: 'critical' as const };
		if (message.message_kind === 'auto_response')
			return { label: 'Auto-response', tone: 'inactive' as const };
		if (message.message_kind === 'delivery_notice')
			return { label: 'Delivery notice', tone: 'inactive' as const };
		return null;
	}

	function formatWhen(value: string) {
		return new Intl.DateTimeFormat(undefined, {
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		}).format(new Date(value));
	}

	function calendarDay(value: string) {
		const date = new Date(value);
		return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
	}

	function formatTimelineDay(value: string) {
		const date = new Date(value);
		const today = new Date();
		const yesterday = new Date(Date.now() - 86_400_000);
		if (calendarDay(value) === calendarDay(today.toISOString())) return 'Today';
		if (calendarDay(value) === calendarDay(yesterday.toISOString())) return 'Yesterday';
		return new Intl.DateTimeFormat(undefined, {
			month: 'long',
			day: 'numeric',
			year: date.getFullYear() === today.getFullYear() ? undefined : 'numeric'
		}).format(date);
	}

	function sentByLabel(email: OutboundInboxMessage) {
		return email.send_kind === 'automated'
			? 'Sent automatically'
			: `Sent by ${email.created_by_name ?? 'a teammate'}`;
	}

	function replySubject(subject: string) {
		if (!subject.trim()) return '';
		return /^re:/i.test(subject.trim()) ? subject : `Re: ${subject}`;
	}

	function replyRecipient(group: ConversationGroup) {
		return contextQuery.data?.client.email ?? conversationCustomerEmail(group);
	}

	function replyPhone(group: ConversationGroup) {
		return contextQuery.data?.client.phone ?? conversationCustomerPhone(group);
	}

	// A 'system' part (the session ending) is narration, not a party in the conversation -- rendered as a
	// note rather than a bubble with a sender line, matching the visitor widget's own rendering.
	function chatSenderLabel(message: WebsiteChatInboxMessage) {
		if (message.sender_type === 'visitor') return message.sender_name ?? 'Visitor';
		if (message.sender_type === 'staff') return message.sender_name ?? 'A teammate';
		return null;
	}

	// The system part cannot name a person (website_chat_messages_sender_user_check), so "ended · who ·
	// when" can only come from `closed_by` on the session, never the part itself.
	function endedStateLabel(session: WebsiteChatInboxSession) {
		const who = session.closed_by_name ?? 'A teammate';
		return `This conversation ended · ${who} · ${formatWhen(session.closed_at ?? session.last_activity_at)}`;
	}

	function textStopLabel(note: TextStopNote) {
		const who = note.by_name ?? 'A teammate';
		const number = note.phone ? ` to ${note.phone}` : '';
		return note.kind === 'stopped'
			? `${who} stopped texts${number}`
			: `${who} turned texts back on${number}`;
	}

	function identitySuggestions(session: WebsiteChatInboxSession) {
		return session.candidates.map((candidate) => ({
			clientId: candidate.client_id,
			clientName: candidate.client_name,
			matchedOn: candidate.matched_on
		}));
	}
</script>

<!-- A team member stopping texts to a customer, or taking that stop back: narration in the thread, like the
     "conversation ended" line, not a message. Stopped and turned-on use different icons so they scan apart. -->
{#snippet textStopNote(slot: TimelineNoteSlot)}
	{@const note = slot.note}
	{#if slot.showDay}
		<div class="communications__date-divider" role="separator">
			<span>{formatTimelineDay(note.created_at)}</span>
		</div>
	{/if}
	<p
		class="communications__stop-note"
		class:communications__stop-note--stopped={note.kind === 'stopped'}
	>
		<span class="communications__stop-note-icon" aria-hidden="true"
			>{@html note.kind === 'stopped' ? messageOffIcon : messageCheckIcon}</span
		>
		<span>{textStopLabel(note)}</span>
		<time datetime={note.created_at}>{formatWhen(note.created_at)}</time>
		{#if note.note}<span class="communications__stop-note-reason">“{note.note}”</span>{/if}
	</p>
{/snippet}

<svelte:head><title>Communications · Contractor CRM</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<PageContainer variant="fill" class="communications">
	<!-- No page header here on purpose: GHL's Conversations screen has none, and the inbox needs the
	     vertical space. Jafar removed it 2026-08-25. -->
	<h1 class="sr-only">Communications</h1>
	<p class="sr-only" role="status" aria-live="polite">{newMessageAnnouncement}</p>
	{#if inboxQuery.isPending}
		<div class="communications__loading">
			<LoadingSkeleton variant="card" label="Loading inbox" /><LoadingSkeleton
				variant="card"
				label="Loading inbox"
			/><LoadingSkeleton variant="card" label="Loading inbox" />
		</div>
	{:else if inboxQuery.isError}
		<EmptyState
			title="Conversation history could not be loaded"
			description="Refresh the page and try again."
			icon={inboxIcon}
		/>
	{:else}
		<div
			class="communications__workspace"
			class:communications__workspace--single={groups.length === 0}
		>
			<aside class="communications__list" aria-label="Conversation history">
				<div class="communications__list-header">
					<div class="communications__inbox-identity">
						{#if inboxQuery.data?.can_view_team}
							<div class="communications__inbox-switcher" role="group" aria-label="Inbox view">
								<button
									type="button"
									class:communications__inbox-switcher-button--active={view === 'team'}
									class="communications__inbox-switcher-button"
									aria-pressed={view === 'team'}
									onclick={() => (view = 'team')}>Team Inbox</button
								>
								<button
									type="button"
									class:communications__inbox-switcher-button--active={view === 'mine'}
									class="communications__inbox-switcher-button"
									aria-pressed={view === 'mine'}
									onclick={() => (view = 'mine')}>My Inbox</button
								>
							</div>
						{:else}
							<h2>My Inbox</h2>
						{/if}
						<p>{visibleGroups.length} conversation{visibleGroups.length === 1 ? '' : 's'}</p>
					</div>
					<!-- This is the real, existing email flow. It remains in the list header as a compact action. -->
					<Button
						size="small"
						variant="secondary"
						onhover={prefetchClientPicker}
						onclick={() => (newConversationOpen = true)}
					>
						<span class="communications__compose-icon" aria-hidden="true">{@html pencilIcon}</span>
						<span class="communications__new-label">New</span>
					</Button>
				</div>
				<form
					class="communications__search"
					onsubmit={(event) => {
						event.preventDefault();
						search = searchDraft;
					}}
				>
					<label class="sr-only" for="communications-search">Search email or subject</label><input
						id="communications-search"
						type="search"
						bind:value={searchDraft}
						placeholder="Search email or subject"
					/><button
						class="communications__search-submit"
						type="submit"
						aria-label="Search email or subject"
					>
						<span aria-hidden="true">{@html searchIcon}</span>
					</button>
				</form>
				<div class="communications__list-tabs" role="group" aria-label="Conversation status">
					<button
						type="button"
						class:communications__list-tab--active={listTab === 'unread'}
						class="communications__list-tab"
						aria-pressed={listTab === 'unread'}
						onclick={() => (listTab = 'unread')}
					>
						Unread{#if unreadGroupCount > 0}
							<span>{unreadGroupCount}</span>
						{/if}
					</button>
					<button
						type="button"
						class:communications__list-tab--active={listTab === 'all'}
						class="communications__list-tab"
						aria-pressed={listTab === 'all'}
						onclick={() => (listTab = 'all')}>All</button
					>
				</div>
				{#if visibleGroups.length === 0}
					<EmptyState
						title={listTab === 'unread'
							? 'No unread conversations'
							: inboxQuery.data?.view === 'mine'
								? 'Nothing assigned to you yet'
								: 'No conversations yet'}
						description={listTab === 'unread'
							? 'Conversations you have not read or replied to will appear here.'
							: inboxQuery.data?.view === 'mine'
								? 'Conversations assigned to you or that you follow will appear here.'
								: 'Queued, sent, and received operational emails will appear here when they exist.'}
						icon={inboxIcon}
					/>
				{:else}
					<div class="communications__rows" role="list" aria-label="Conversations">
						{#each visibleGroups as group (group.key)}
							{@const channel = rowChannel(group)}
							{@const preview = rowPreview(group)}
							<div role="listitem">
								<button
									class:communications__row--selected={selectedGroup?.key === group.key}
									class:communications__row--unread={group.unreadCount > 0}
									class="communications__row"
									type="button"
									aria-current={selectedGroup?.key === group.key ? 'true' : undefined}
									tabindex={rowTabStopKey === group.key ? 0 : -1}
									onfocus={() => (focusedRowKey = group.key)}
									onclick={() => selectGroup(group)}
									onkeydown={handleRowKeydown}
								>
									<Avatar id={group.avatarId} name={group.name} size="base" />
									<span class="communications__row-copy">
										<span class="communications__row-heading">
											<span
												class="communications__row-channel"
												title={channel.label}
												aria-hidden="true">{@html channel.icon}</span
											>
											<strong>{group.name}</strong>
											{#if group.guarded}<Badge status="warning" size="small" dot={false}
													>Needs review</Badge
												>{/if}
										</span>
										<small class="communications__row-preview"
											><span>{rowHeadline(group)}</span>{#if preview}<span>{preview}</span
												>{/if}</small
										>
									</span>
									<span class="communications__row-end">
										<time datetime={group.latest.created_at}
											>{formatWhen(group.latest.created_at)}</time
										>
										{#if group.assignedToName}
											<span title={`Assigned to ${group.assignedToName}`}>
												<Avatar
													id={group.assignedTo ?? group.key}
													name={group.assignedToName}
													size="small"
												/>
											</span>
										{/if}
										{#if group.unreadCount > 0}
											<Badge size="small" dot={false}
												><span class="sr-only">{group.unreadCount} unread</span><span
													aria-hidden="true">{group.unreadCount}</span
												></Badge
											>
										{/if}
									</span>
								</button>
							</div>
						{/each}
					</div>
				{/if}
			</aside>

			{#if selectedGroup}
				{@const group = selectedGroup}
				{@const channel = rowChannel(group)}
				<main class="communications__message" aria-label="Conversation timeline">
					<header class="communications__thread-header">
						<div class="communications__recipient">
							<Avatar id={group.avatarId} name={group.name} size="base" />
							<div>
								<h2>{group.name}</h2>
								{#if group.clientId}
									<span class="communications__conversation-type">{channel.label} conversation</span
									>
								{:else}
									<span class="communications__unresolved-sender"
										>Needs review — not yet linked</span
									>
								{/if}
							</div>
						</div>
						<div class="communications__thread-actions">
							<!-- ≤1050px only (CSS-gated): the inline context rail is hidden there, so this is
							     the only way to reach assignment/follow/related-work below that width. -->
							<Button
								size="small"
								variant="secondary"
								class="communications__info-trigger"
								onclick={() => (contextPanelOpen = true)}
							>
								<span class="communications__info-icon" aria-hidden="true">{@html infoIcon}</span>
								Info
							</Button>
							{#if group.guarded && group.senderEmail}
								<Badge status="warning">Needs review</Badge>
								{#if inboxQuery.data?.can_manage_assignment}
									<Button size="small" variant="primary" onclick={() => (linkTarget = group)}
										>Link to a client</Button
									>
									<Button size="small" variant="secondary" onclick={() => (dismissTarget = group)}
										>Dismiss</Button
									>
								{/if}
							{:else if group.guarded && group.chatSession?.match_status === 'needs_review'}
								<Badge status="warning">Needs review</Badge>
							{/if}
							{#if group.chatSession && !group.chatSession.closed_at && canSend}
								<Button size="small" variant="secondary" onclick={() => (endSessionTarget = group)}
									>End conversation</Button
								>
							{/if}
						</div>
					</header>
					<!-- A scrolling area has to be reachable by keyboard so the arrow and Page keys can scroll it. -->
					<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
					<div
						class="communications__timeline"
						role="region"
						tabindex="0"
						aria-label={`Messages with ${group.name}`}
						bind:this={timelineEl}
						onscroll={handleTimelineScroll}
					>
						{#each group.messages as message, index (message.id)}
							{#each notePlacement?.before.get(message.id) ?? [] as slot (slot.note.id)}
								{@render textStopNote(slot)}
							{/each}
							{#if notePlacement?.messageShowsDay.get(message.id)}
								<div class="communications__date-divider" role="separator">
									<span>{formatTimelineDay(message.created_at)}</span>
								</div>
							{/if}
							{#if isWebsiteChatMessage(message) && index > 0}
								{@const previous = group.messages[index - 1]}
								{#if isWebsiteChatMessage(previous) && previous.session_id !== message.session_id}
									<div class="communications__chat-divider" role="separator">New conversation</div>
								{/if}
							{/if}
							{#if isWebsiteChatMessage(message)}
								{#if message.sender_type === 'system'}
									<p class="communications__chat-note" data-message-id={message.id}>
										{message.body}
									</p>
								{:else}
									<article
										class="communications__thread-message"
										class:communications__thread-message--outbound={message.direction ===
											'outbound'}
										class:communications__thread-message--unread={message.direction === 'inbound' &&
											message.unread}
										data-message-id={message.id}
									>
										<div class="communications__thread-message-meta">
											<span>{chatSenderLabel(message)}</span>
											<time datetime={message.created_at}>{formatWhen(message.created_at)}</time>
										</div>
										<p>{message.body}</p>
									</article>
								{/if}
							{:else}
								<article
									class="communications__thread-message"
									class:communications__thread-message--outbound={message.direction === 'outbound'}
									class:communications__thread-message--unread={message.direction === 'inbound' &&
										message.unread}
									class:communications__thread-message--email={message.channel === 'email'}
									data-message-id={message.id}
								>
									{#if message.channel === 'sms'}
										<!-- SMS reads as a text message, not a mail: no subject line, no Forward (an
										     email-only feature -- communication_forward_events has no channel of its
										     own). An outbound picture (Stage 6D-2) reuses the same AttachmentList as
										     email; an inbound picture isn't fetched yet (Stage 6D-1 descoped display),
										     so it shows as a plain notice instead of silently vanishing. -->
										{#if message.direction === 'outbound'}
											<div class="communications__thread-message-meta">
												<span>{sentByLabel(message)}</span>
												<time datetime={message.created_at}>{formatWhen(message.created_at)}</time>
											</div>
											<div class="communications__thread-message-badges">
												<Badge status={outboundEmailStatus(message).tone}
													>{outboundEmailStatus(message).label}</Badge
												>
												{#if message.can_resend}
													<Button
														size="small"
														variant="secondary"
														onclick={() => (resendTarget = message)}>Resend</Button
													>
												{/if}
											</div>
											<p>{message.text_content}</p>
											{#if message.resent_from_intent_id}<p
													class="communications__notice"
													role="status"
												>
													This is a resend of an earlier attempt.
												</p>{/if}
											{#if message.resent_into_intent_id}
												{@const newerAttempt = outboundIn(group, message.resent_into_intent_id)}
												{#if newerAttempt}
													<p class="communications__notice" role="status">
														This message was resent.
														<button
															type="button"
															class="communications__notice-action"
															onclick={() => scrollToMessage(newerAttempt.id)}
															>View the newer attempt</button
														>
													</p>
												{/if}
											{/if}
											{#if message.failure_message}<p class="communications__notice" role="status">
													{message.failure_message}
												</p>{/if}
											{#if message.quote_id}
												<p class="communications__notice communications__notice--quiet">
													Related work: <a
														href={resolve('/(app)/quotes/[id=uuid]', { id: message.quote_id })}
														>View quote</a
													>
												</p>
											{/if}
											{#if message.attachments.length > 0}
												<div class="communications__attachments">
													<AttachmentList
														attachments={message.attachments}
														fetchDownloadUrl={fetchOutboundAttachmentDownloadUrl}
													/>
												</div>
											{/if}
										{:else}
											{@const kind = kindBadge(message)}
											{@const review = reviewBadge(message)}
											<div class="communications__thread-message-meta">
												<span>{message.sender_name ?? message.sender_phone}</span>
												<time datetime={message.created_at}>{formatWhen(message.created_at)}</time>
											</div>
											<div class="communications__thread-message-badges">
												{#if review}<Badge status={review.tone}>{review.label}</Badge>{/if}
												{#if kind}<Badge status={kind.tone}>{kind.label}</Badge>{/if}
												<Button
													size="small"
													variant="secondary"
													onclick={() => (detailsMessage = message)}>Details</Button
												>
											</div>
											<p>{message.text_content}</p>
											{#if message.in_reply_to_intent_id}
												{@const replyTarget = outboundIn(group, message.in_reply_to_intent_id)}
												<p class="communications__notice" role="status">
													{#if replyTarget}
														In reply to
														<button
															type="button"
															class="communications__notice-action"
															onclick={() => scrollToMessage(replyTarget.id)}
															>{replyTarget.subject}</button
														>
													{:else}
														In reply to an earlier message on this thread.
													{/if}
												</p>
											{/if}
											{#if message.attachment_count > 0}
												<p class="communications__notice communications__notice--quiet">
													This text included a picture. Picture messages aren't shown yet.
												</p>
											{/if}
											{#if message.automation_suppressed}
												<p class="communications__notice communications__notice--quiet">
													Automation is suppressed for this message.
												</p>
											{/if}
										{/if}
									{:else if message.direction === 'outbound'}
										<div class="communications__thread-message-meta">
											<span>{sentByLabel(message)}</span>
											<time datetime={message.created_at}>{formatWhen(message.created_at)}</time>
										</div>
										<div class="communications__thread-message-badges">
											<Badge status={outboundEmailStatus(message).tone}
												>{outboundEmailStatus(message).label}</Badge
											>
											{#if message.can_resend}
												<Button
													size="small"
													variant="secondary"
													onclick={() => (resendTarget = message)}>Resend</Button
												>
											{/if}
											{#if message.can_cancel_scheduled}
												<Button
													size="small"
													variant="secondary"
													onclick={() => (cancelScheduledTarget = message)}>Cancel</Button
												>
											{/if}
										</div>
										<h3>{message.subject}</h3>
										<p>{message.text_content}</p>
										{#if message.resent_from_intent_id}<p
												class="communications__notice"
												role="status"
											>
												This is a resend of an earlier attempt.
											</p>{/if}
										{#if message.resent_into_intent_id}
											{@const newerAttempt = outboundIn(group, message.resent_into_intent_id)}
											{#if newerAttempt}
												<p class="communications__notice" role="status">
													This message was resent.
													<button
														type="button"
														class="communications__notice-action"
														onclick={() => scrollToMessage(newerAttempt.id)}
														>View the newer attempt</button
													>
												</p>
											{/if}
										{/if}
										{#if message.failure_message}<p class="communications__notice" role="status">
												{message.failure_message}
											</p>{/if}
										{#if message.quote_id}
											<p class="communications__notice communications__notice--quiet">
												Related work: <a
													href={resolve('/(app)/quotes/[id=uuid]', { id: message.quote_id })}
													>View quote</a
												>
											</p>
										{/if}
										{#if message.attachments.length > 0}
											<div class="communications__attachments">
												<AttachmentList
													attachments={message.attachments}
													fetchDownloadUrl={fetchOutboundAttachmentDownloadUrl}
												/>
											</div>
										{/if}
									{:else}
										{@const kind = kindBadge(message)}
										{@const review = reviewBadge(message)}
										<div class="communications__thread-message-meta">
											<span>{message.sender_name ?? message.sender_email}</span>
											<time datetime={message.created_at}>{formatWhen(message.created_at)}</time>
										</div>
										<div class="communications__thread-message-badges">
											{#if review}<Badge status={review.tone}>{review.label}</Badge>{/if}
											{#if kind}<Badge status={kind.tone}>{kind.label}</Badge>{/if}
											<Button
												size="small"
												variant="secondary"
												onclick={() => (detailsMessage = message)}>Details</Button
											>
											{#if inboxQuery.data?.can_forward && message.client_id !== null}
												<Button
													size="small"
													variant="secondary"
													onclick={() => (forwardTarget = message)}>Forward</Button
												>
											{/if}
										</div>
										<h3>{message.subject}</h3>
										<p>{message.text_content}</p>
										{#if message.in_reply_to_intent_id}
											{@const replyTarget = outboundIn(group, message.in_reply_to_intent_id)}
											<p class="communications__notice" role="status">
												{#if replyTarget}
													In reply to
													<button
														type="button"
														class="communications__notice-action"
														onclick={() => scrollToMessage(replyTarget.id)}
														>{replyTarget.subject}</button
													>
												{:else}
													In reply to an earlier message on this thread.
												{/if}
											</p>
										{/if}
										{#if message.attachment_count > 0}
											<div class="communications__attachments">
												<AttachmentList
													attachments={message.attachments}
													fetchDownloadUrl={fetchInboundAttachmentDownloadUrl}
												/>
											</div>
										{/if}
										{#if message.automation_suppressed}
											<p class="communications__notice communications__notice--quiet">
												Automation is suppressed for this message.
											</p>
										{/if}
									{/if}
								</article>
							{/if}
						{/each}
						{#each notePlacement?.trailing ?? [] as slot (slot.note.id)}
							{@render textStopNote(slot)}
						{/each}
						{#if visiblePendingSend}
							{@const send = visiblePendingSend}
							{@const mark = pendingSendStatus(send)}
							<article
								class="communications__thread-message communications__thread-message--outbound"
								class:communications__thread-message--pending={send.state === 'sending'}
								class:communications__thread-message--failed={send.state === 'failed'}
								class:communications__thread-message--email={send.channel === 'email'}
								data-message-id={send.id}
								aria-busy={send.state === 'sending'}
							>
								<div class="communications__thread-message-meta">
									<span>You</span>
									<time datetime={send.created_at}>{formatWhen(send.created_at)}</time>
								</div>
								{#if mark}
									<div class="communications__thread-message-badges">
										<Badge status={mark.tone}>{mark.label}</Badge>
										{#if send.state === 'failed'}
											<Button size="small" variant="secondary" onclick={send.retry}>Retry</Button>
										{/if}
									</div>
								{/if}
								{#if send.subject}<h3>{send.subject}</h3>{/if}
								<p>{send.body}</p>
								{#if send.state === 'failed' && send.error}
									<p class="communications__notice" role="alert">{send.error}</p>
								{/if}
							</article>
						{/if}
						{#if showJumpToLatest}
							<button class="communications__jump-to-latest" type="button" onclick={scrollToLatest}>
								<span aria-hidden="true">{@html arrowDownIcon}</span>
								Jump to latest
							</button>
						{/if}
					</div>
					{#if group.clientId || group.chatSession}
						{#key `${group.key}:${activeChannel}`}
							{#if !canSend}
								<p class="communications__no-permission">
									You do not have permission to reply to this conversation.
								</p>
							{:else}
								{#if group.guarded && group.chatSession?.match_status === 'needs_review' && inboxQuery.data?.can_manage_assignment}
									<div class="communications__resolve-banner">
										<span
											>This visitor's phone and email matched two different clients. Choose who this
											is to bring the conversation into their history.</span
										>
										<Button
											size="small"
											variant="primary"
											onclick={() => (resolveIdentityTarget = group)}>Resolve identity</Button
										>
									</div>
								{/if}
								{#if activeChannel === 'website_chat' && group.chatSession}
									{#if group.chatSession.closed_at}
										<p class="communications__chat-ended">{endedStateLabel(group.chatSession)}</p>
									{:else}
										<ConversationComposer
											sessionId={group.chatSession.id}
											clientId={group.clientId}
											channel="website_chat"
											channels={composerChannels}
											onChannelChange={(channel) => (activeChannel = channel)}
											bind:expanded={composerExpanded}
											onPendingChange={(send) => handlePendingChange(group.key, send)}
										/>
									{/if}
								{:else if activeChannel === 'sms' && group.clientId}
									<ConversationComposer
										clientId={group.clientId}
										channel="sms"
										defaultSubject=""
										recipientLabel={replyPhone(group)}
										channels={composerChannels}
										onChannelChange={(channel) => (activeChannel = channel)}
										bind:expanded={composerExpanded}
										onPendingChange={(send) => handlePendingChange(group.key, send)}
									/>
								{:else if group.clientId}
									<ConversationComposer
										clientId={group.clientId}
										channel="email"
										defaultSubject={replySubject(latestEmailSubject(group))}
										recipientLabel={replyRecipient(group)}
										channels={composerChannels}
										onChannelChange={(channel) => (activeChannel = channel)}
										bind:expanded={composerExpanded}
										onPendingChange={(send) => handlePendingChange(group.key, send)}
									/>
								{/if}
							{/if}
						{/key}
					{/if}
				</main>
				<aside class="communications__context" aria-label="Customer context">
					{@render contextPanel(group)}
				</aside>
			{/if}
		</div>
	{/if}
</PageContainer>
<!-- eslint-enable svelte/no-at-html-tags -->

<!-- Same markup and query as the inline rail above -- reused here for the ≤1050px SidePanel so the two
     never drift. -->
{#snippet contextPanel(group: ConversationGroup)}
	<ConversationContextRail
		{group}
		context={contextQuery}
		canManageAssignment={inboxQuery.data?.can_manage_assignment ?? false}
		followPending={followMutationState.isPending}
		onToggleFollow={() =>
			group.clientId &&
			followMutationState.mutate({ clientId: group.clientId, following: group.isFollowing })}
	/>
{/snippet}

{#if selectedGroup}
	<SidePanel
		open={contextPanelOpen}
		title={selectedGroup.name}
		subtitle="Customer context"
		onClose={() => (contextPanelOpen = false)}
	>
		{@render contextPanel(selectedGroup)}
	</SidePanel>
{/if}

{#if resendTarget}
	{@const target = resendTarget}
	<ConfirmDialog
		open
		title="Resend this email?"
		confirmLabel="Resend email"
		loading={resendMutationState.isPending}
		onConfirm={() => resendMutationState.mutate(target)}
		onClose={() => (resendTarget = null)}
	>
		<p>
			UCRM will recheck the recipient and sender before queueing a new attempt to
			<strong>{target.client_email}</strong>.
		</p>
	</ConfirmDialog>
{/if}

{#if cancelScheduledTarget}
	{@const target = cancelScheduledTarget}
	<ConfirmDialog
		open
		title="Cancel this scheduled email?"
		confirmLabel="Cancel email"
		destructive
		loading={cancelScheduledMutationState.isPending}
		onConfirm={() => cancelScheduledMutationState.mutate(target)}
		onClose={() => (cancelScheduledTarget = null)}
	>
		<p>
			This email to <strong>{target.client_email}</strong> will not be sent. You can write a new one any
			time.
		</p>
	</ConfirmDialog>
{/if}

{#if linkTarget && linkTarget.senderEmail}
	{@const target = linkTarget}
	<ChooseClientDialog
		open
		title="Link this conversation"
		confirmLabel="Link conversation"
		lead={`We could not match ${target.name} to anyone in your client list. Choose who this is, and every message from ${target.senderEmail} joins their conversation.`}
		notice={`${target.senderEmail} is saved as an extra email address on that client, so future replies from it are recognised straight away.`}
		pending={resolveReviewMutationState.isPending}
		errorMessage={linkError}
		onCancel={() => {
			linkTarget = null;
			linkError = '';
		}}
		onConfirm={(clientId) =>
			resolveReviewMutationState.mutate({
				senderEmail: target.senderEmail ?? '',
				resolution: 'link',
				clientId
			})}
	/>
{/if}

{#if resolveIdentityTarget}
	{@const target = resolveIdentityTarget}
	{#if target.chatSession}
		{@const session = target.chatSession}
		<ChooseClientDialog
			open
			title="Resolve identity"
			confirmLabel="Link conversation"
			lead={`${session.visitor_name}'s phone and email matched two different clients. Choose who this is, and this whole conversation joins their history.`}
			suggestions={identitySuggestions(session)}
			pending={resolveIdentityMutationState.isPending}
			errorMessage={resolveIdentityError}
			onCancel={() => {
				resolveIdentityTarget = null;
				resolveIdentityError = '';
			}}
			onConfirm={(clientId) =>
				resolveIdentityMutationState.mutate({ sessionId: session.id, clientId })}
		/>
	{/if}
{/if}

{#if endSessionTarget}
	{@const target = endSessionTarget}
	{#if target.chatSession}
		{@const session = target.chatSession}
		<ConfirmDialog
			open
			title="End this conversation?"
			confirmLabel="End conversation"
			loading={endSessionMutationState.isPending}
			onConfirm={() => endSessionMutationState.mutate(session.id)}
			onClose={() => (endSessionTarget = null)}
		>
			<p>The visitor sees this conversation as ended and cannot send another message here.</p>
		</ConfirmDialog>
	{/if}
{/if}

{#if newConversationOpen && !newConversationClientQuery.data}
	<ChooseClientDialog
		open
		title="New conversation"
		confirmLabel="Continue"
		lead="Who is this email for? Pick the client and you can write the message next."
		pending={newConversationClientQuery.isFetching}
		errorMessage={newConversationClientQuery.error?.message ?? ''}
		onCancel={() => {
			newConversationOpen = false;
			newConversationClientId = null;
		}}
		onConfirm={(clientId) => (newConversationClientId = clientId)}
	/>
{/if}

<!-- Reuses the client page's own email dialog rather than building a second composer: same command, same
     recipient rules, same allowance class. -->
{#if newConversationClientId && newConversationClientQuery.data}
	<ManualEmailDialog
		open
		client={newConversationClientQuery.data}
		onClose={() => {
			newConversationClientId = null;
			newConversationOpen = false;
		}}
	/>
{/if}

{#if dismissTarget && dismissTarget.senderEmail}
	{@const target = dismissTarget}
	<ConfirmDialog
		open
		title="Dismiss this conversation?"
		confirmLabel="Dismiss"
		destructive
		tone="critical"
		loading={resolveReviewMutationState.isPending}
		onConfirm={() =>
			resolveReviewMutationState.mutate({
				senderEmail: target.senderEmail ?? '',
				resolution: 'dismiss',
				clientId: null
			})}
		onClose={() => (dismissTarget = null)}
	>
		<p>
			Everything from <strong>{target.senderEmail}</strong> leaves your inbox for good. Nothing is deleted
			— the messages stay on record — but they will not come back to the review queue.
		</p>
	</ConfirmDialog>
{/if}

{#if detailsMessage}
	{@const message = detailsMessage}
	{@const replyTarget =
		selectedGroup && message.in_reply_to_intent_id
			? outboundIn(selectedGroup, message.in_reply_to_intent_id)
			: null}
	<MessageDetailsDialog
		{message}
		inReplyToSubject={replyTarget?.subject ?? null}
		onJumpToReplyTarget={replyTarget
			? () => {
					scrollToMessage(replyTarget.id);
					detailsMessage = null;
				}
			: undefined}
		onClose={() => (detailsMessage = null)}
	/>
{/if}

{#if forwardTarget && selectedGroup?.clientId}
	<ForwardEmailDialog
		clientId={selectedGroup.clientId}
		message={forwardTarget}
		onClose={() => (forwardTarget = null)}
	/>
{/if}

<style lang="scss">
	:global(.communications) {
		display: grid;
		gap: var(--space-base);
		/* No min-height here: the workspace below sizes itself to the viewport, and a taller floor on the
		   page container would only add dead space under it. */
	}
	.communications__loading {
		display: grid;
		grid-template-columns: 0.9fr 1.5fr 0.8fr;
		gap: var(--space-base);
	}
	.communications__loading :global(.skeleton) {
		min-height: 520px;
	}
	.communications__workspace {
		display: grid;
		grid-template-columns: minmax(284px, 0.82fr) minmax(360px, 1.5fr) minmax(340px, 0.85fr);
		/* GHL docks the composer to the bottom of the conversation panel, and this bound is what makes that
		   happen: pinned to the viewport, the timeline scrolls inside its own column instead of growing and
		   pushing the composer below the fold. Each column then needs min-height: 0 to be allowed to shrink,
		   since a grid item defaults to min-height: auto.
		   217px is everything around it, measured on this page: 145px above (top bar plus the app shell,
		   main, and page-container top padding) and 72px of bottom padding from those same three. */
		min-height: 420px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		overflow: hidden;
		background: var(--color-surface);
	}
	.communications__workspace--single {
		grid-template-columns: 1fr;
	}
	.communications__list {
		display: flex;
		min-height: 0;
		flex-direction: column;
		border-right: var(--border-base) solid var(--color-border);
	}
	.communications__workspace--single .communications__list {
		border-right: 0;
	}
	.communications__list-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		min-height: 60px;
		padding: var(--space-small) var(--space-slim);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.communications__inbox-identity {
		min-width: 0;
	}
	.communications__inbox-identity > p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
	}
	.communications__inbox-switcher {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.communications__inbox-switcher-button {
		position: relative;
		min-height: 32px;
		padding: var(--space-smallest) 0;
		border: 0;
		color: var(--color-text--secondary);
		font: inherit;
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		background: transparent;
		cursor: pointer;
	}
	.communications__inbox-switcher-button:hover,
	.communications__inbox-switcher-button:focus-visible,
	.communications__inbox-switcher-button--active {
		color: var(--color-heading);
	}
	.communications__inbox-switcher-button:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.communications__inbox-switcher-button--active::after {
		position: absolute;
		right: 0;
		bottom: 0;
		left: 0;
		height: 2px;
		background: var(--color-interactive);
		content: '';
	}
	.communications__compose-icon {
		display: inline-flex;
	}
	.communications__compose-icon :global(svg) {
		width: 16px;
		height: 16px;
	}
	.communications__list-header h2,
	.communications__message h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.communications__search {
		display: flex;
		align-items: center;
		gap: var(--space-smallest);
		margin: var(--space-small) var(--space-slim);
		padding: 0 var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		color: var(--color-icon--secondary);
		background: var(--color-surface--background--subtle);
	}
	.communications__search :global(svg) {
		width: 18px;
		height: 18px;
	}
	.communications__search input {
		width: 100%;
		min-height: 32px;
		border: 0;
		outline: 0;
		color: var(--color-text);
		background: transparent;
	}
	.communications__search:focus-within {
		border-color: var(--color-border--interactive);
		box-shadow: var(--shadow-focus);
	}
	.communications__search-submit {
		display: inline-flex;
		width: 28px;
		height: 28px;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		padding: 0;
		border: 0;
		border-radius: var(--radius-small);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
	}
	.communications__search-submit:hover,
	.communications__search-submit:focus-visible {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}
	.communications__search-submit:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.communications__search-submit :global(svg) {
		width: 16px;
		height: 16px;
	}
	.communications__list-tabs {
		display: flex;
		gap: var(--space-large);
		padding: 0 var(--space-slim);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.communications__list-tab {
		position: relative;
		display: inline-flex;
		min-height: 36px;
		align-items: center;
		gap: var(--space-smallest);
		padding: var(--space-smallest) 0;
		border: 0;
		color: var(--color-text--secondary);
		font: inherit;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		background: transparent;
		cursor: pointer;
	}
	.communications__list-tab:hover,
	.communications__list-tab:focus-visible,
	.communications__list-tab--active {
		color: var(--color-heading);
	}
	.communications__list-tab:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.communications__list-tab--active::after {
		position: absolute;
		right: 0;
		bottom: -1px;
		left: 0;
		height: 3px;
		background: var(--color-interactive);
		content: '';
	}
	.communications__list-tab span {
		display: inline-flex;
		min-width: 16px;
		height: 16px;
		align-items: center;
		justify-content: center;
		border-radius: var(--radius-pill);
		color: var(--color-surface);
		background: var(--color-interactive);
		font-size: 10px;
	}
	.communications__rows {
		flex: 1;
		min-height: 0;
		overflow-y: auto;
	}
	.communications__row {
		display: flex;
		width: 100%;
		gap: var(--space-small);
		padding: var(--space-small) var(--space-slim);
		border: 0;
		border-bottom: var(--border-base) solid var(--color-border);
		color: var(--color-text);
		background: var(--color-surface);
		text-align: left;
		cursor: pointer;
	}
	.communications__row:hover,
	.communications__row--selected {
		background: var(--color-surface--active);
	}
	/* Secondary text on the highlighted row falls below 4.5:1 in dark mode, so it steps up to full text colour. */
	.communications__row:hover .communications__row-preview,
	.communications__row:hover time,
	.communications__row--selected .communications__row-preview,
	.communications__row.communications__row--selected time {
		color: var(--color-text);
	}
	.communications__row--unread {
		background: var(--color-surface--background--subtle);
	}
	.communications__row:focus-visible {
		outline: none;
		box-shadow: inset 0 0 0 2px var(--color-focus);
	}
	.communications__row-copy {
		display: grid;
		min-width: 0;
		flex: 1;
		gap: 2px;
	}
	.communications__row-heading {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		min-width: 0;
	}
	.communications__row-heading strong {
		overflow: hidden;
		color: var(--color-heading);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.communications__row--unread .communications__row-heading strong {
		font-weight: 700;
	}
	.communications__row-channel {
		display: inline-flex;
		flex: 0 0 auto;
		color: var(--color-icon--secondary);
	}
	.communications__row-channel :global(svg) {
		width: 14px;
		height: 14px;
	}
	.communications__row-preview {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.communications__row-preview span + span::before {
		margin: 0 var(--space-smallest);
		content: '\00b7';
	}
	.communications__row time {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		white-space: nowrap;
	}
	.communications__row-end {
		display: flex;
		flex: 0 0 auto;
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-smallest);
	}
	.communications__message {
		display: flex;
		min-width: 0;
		min-height: 0;
		flex-direction: column;
	}
	.communications__message > header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-slim);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.communications__recipient {
		display: flex;
		min-width: 0;
		align-items: center;
		gap: var(--space-small);
	}
	.communications__unresolved-sender,
	.communications__conversation-type {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.communications__thread-actions {
		display: flex;
		flex: 0 0 auto;
		align-items: center;
		gap: var(--space-small);
	}
	/* Only reachable below 1050px, where the inline context rail is hidden -- see the width media query.
	   Doubled selector for specificity over Button's own base `.button { display: inline-flex }` rule,
	   which otherwise wins the cascade tie since both are single-class scoped/global selectors. */
	:global(.button.communications__info-trigger) {
		display: none;
	}
	.communications__info-icon {
		display: inline-flex;
	}
	.communications__info-icon :global(svg) {
		width: 16px;
		height: 16px;
	}
	.communications__timeline:focus-visible {
		outline: none;
		box-shadow: inset 0 0 0 2px var(--color-focus);
	}
	.communications__timeline {
		position: relative;
		display: flex;
		flex: 1;
		flex-direction: column;
		gap: var(--space-slim);
		padding: var(--space-large) clamp(var(--space-large), 5vw, var(--space-largest));
		background: var(--color-surface);
		overflow-y: auto;
	}
	.communications__thread-message {
		align-self: flex-start;
		width: fit-content;
		max-width: min(72%, 680px);
		padding: var(--space-slim) var(--space-base);
		border: 0;
		border-radius: var(--radius-large) var(--radius-large) var(--radius-large) var(--radius-small);
		background: var(--color-surface--background--subtle);
		box-shadow: inset 0 0 0 var(--border-base) var(--color-border);
	}
	.communications__thread-message--outbound {
		align-self: flex-end;
		border-radius: var(--radius-large) var(--radius-large) var(--radius-small) var(--radius-large);
		background: var(--color-interactive--background);
		box-shadow: none;
	}
	/* Email is a document-shaped record, not a chat bubble. It spans the timeline like GHL's mail cards
	   while the sender, delivery, forwarding and review controls above remain exactly the existing real
	   actions. SMS and Website Chat retain the smaller conversational geometry. */
	.communications__thread-message--email {
		align-self: stretch;
		width: auto;
		max-width: none;
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: inset 0 0 0 var(--border-base) var(--color-border);
	}
	.communications__thread-message--email.communications__thread-message--outbound {
		background: var(--color-surface);
	}
	.communications__thread-message--unread {
		box-shadow:
			inset 3px 0 0 var(--color-informative),
			inset 0 0 0 var(--border-base) var(--color-border);
	}
	/* Only a send still in flight reads as provisional -- muted, the way an unconfirmed message does in any
	   messenger. Once the server has accepted it the muting drops and it reads as an ordinary sent message,
	   which is what it is; the re-read that swaps in its stored row then changes nothing visible. A failure
	   takes the critical border, because at that point it is not in progress, it is something to act on. */
	.communications__thread-message--pending {
		opacity: 0.7;
		border-style: dashed;
	}
	.communications__thread-message--failed {
		box-shadow: inset 0 0 0 var(--border-thick) var(--color-critical);
	}
	.communications__thread-message-meta {
		display: flex;
		align-items: center;
		justify-content: flex-start;
		gap: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
	}
	.communications__thread-message-meta span {
		color: var(--color-text);
		font-weight: 600;
	}
	.communications__thread-message-meta time::before {
		margin-right: var(--space-small);
		content: '\00b7';
	}
	.communications__thread-message-badges {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
	.communications__thread-message h3 {
		margin-top: var(--space-small);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
	}
	.communications__thread-message p {
		margin-top: var(--space-smaller);
		white-space: pre-wrap;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		line-height: 1.45;
	}
	.communications__jump-to-latest {
		position: sticky;
		bottom: var(--space-slim);
		display: inline-flex;
		align-self: center;
		align-items: center;
		gap: var(--space-smaller);
		min-height: 32px;
		margin-top: auto;
		padding: var(--space-smallest) var(--space-slim);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-heading);
		font: inherit;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
		cursor: pointer;
	}
	.communications__jump-to-latest:hover,
	.communications__jump-to-latest:focus-visible {
		background: var(--color-surface--hover);
	}
	.communications__jump-to-latest:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.communications__jump-to-latest :global(svg) {
		width: 16px;
		height: 16px;
	}
	.communications__date-divider {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		width: 100%;
		margin: var(--space-base) 0 var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		text-align: center;
	}
	.communications__date-divider::before,
	.communications__date-divider::after {
		flex: 1;
		height: var(--border-base);
		background: var(--color-border);
		content: '';
	}
	.communications__date-divider span {
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-pill);
		background: var(--color-surface--background--subtle);
	}
	.communications__attachments {
		margin-top: var(--space-small);
	}
	.communications__notice {
		margin-top: var(--space-small);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
		font-size: var(--typography--fontSize-small);
	}
	.communications__notice--quiet {
		padding: 0;
		color: var(--color-text--secondary);
		background: none;
	}
	.communications__notice-action {
		padding: 0;
		border: 0;
		color: inherit;
		font: inherit;
		text-decoration: underline;
		background: none;
		cursor: pointer;
	}
	/* A `system` part narrates the conversation rather than speaking in it -- a centered note, not a bubble. */
	.communications__chat-note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
	.communications__stop-note {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: center;
		gap: var(--space-smaller);
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
	.communications__stop-note-icon {
		display: inline-flex;
		color: var(--color-text--secondary);
	}
	.communications__stop-note--stopped .communications__stop-note-icon {
		color: var(--color-warning--onSurface);
	}
	.communications__stop-note-icon :global(svg) {
		width: 1rem;
		height: 1rem;
	}
	.communications__stop-note-reason {
		font-style: italic;
	}
	.communications__chat-divider {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: var(--space-small) 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		text-align: center;
	}
	.communications__chat-divider::before,
	.communications__chat-divider::after {
		flex: 1;
		height: var(--border-base);
		background: var(--color-border);
		content: '';
	}
	.communications__chat-ended {
		margin: 0;
		padding: var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
	.communications__no-permission {
		margin: 0;
		padding: var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.communications__resolve-banner {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
		font-size: var(--typography--fontSize-small);
	}
	.communications__context {
		min-height: 0;
		border-left: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
		overflow: hidden;
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
	}
	@media (max-width: 1050px) {
		.communications__workspace {
			grid-template-columns: minmax(240px, 0.8fr) minmax(0, 1.4fr);
		}
		.communications__context {
			display: none;
		}
		:global(.button.communications__info-trigger) {
			display: inline-flex;
		}
	}
	@media (max-width: 700px) {
		.communications__loading,
		.communications__workspace {
			grid-template-columns: 1fr;
		}
		/* Stacked into one column there is nothing to dock against, so the page scrolls normally and the
		   composer sits at the end of the thread -- the usual mobile pattern. */
		.communications__workspace {
			height: auto;
		}
		.communications__list {
			border-right: 0;
			border-bottom: var(--border-base) solid var(--color-border);
			max-height: 330px;
		}
		.communications__message {
			min-height: 460px;
		}
		.communications__message > header {
			flex-wrap: wrap;
		}
		.communications__thread-actions {
			flex-wrap: wrap;
		}
		.communications__thread-message-meta {
			display: grid;
			gap: var(--space-smallest);
		}
		.communications__timeline {
			padding-inline: var(--space-base);
		}
		.communications__thread-message {
			max-width: 88%;
		}
		.communications__thread-message-meta time::before {
			display: none;
		}
	}
</style>
