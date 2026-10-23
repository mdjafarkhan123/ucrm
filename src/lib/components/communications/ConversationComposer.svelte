<script lang="ts">
	import sendLaterIcon from '@tabler/icons/outline/clock.svg?raw';
	import EmailSenderLabel from '$lib/components/communications/EmailSenderLabel.svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Popover from '$lib/components/ui/Popover.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import ComposerChannelMenu from '$lib/components/communications/ComposerChannelMenu.svelte';
	import ConversationAttachments from '$lib/components/communications/ConversationAttachments.svelte';
	import ConversationLibraryAttachments from '$lib/components/communications/ConversationLibraryAttachments.svelte';
	import SnippetPickerButton from '$lib/components/communications/SnippetPickerButton.svelte';
	import EmailTemplatePickerButton from '$lib/components/communications/EmailTemplatePickerButton.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import type { CommunicationEmailTemplateListItem } from '$lib/communications/email-templates';
	import { tick } from 'svelte';
	import { Dialog as DialogPrimitive } from 'bits-ui';
	import { browser } from '$app/environment';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import minusIcon from '@tabler/icons/outline/minus.svg?raw';
	import maximizeIcon from '@tabler/icons/outline/arrows-maximize.svg?raw';
	import minimizeIcon from '@tabler/icons/outline/arrows-minimize.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import chevronUpIcon from '@tabler/icons/outline/chevron-up.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import replyIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';
	import windowOpenIcon from '@tabler/icons/outline/hourglass-high.svg?raw';
	import windowClosingIcon from '@tabler/icons/outline/alarm.svg?raw';
	import windowClosedIcon from '@tabler/icons/outline/hourglass-off.svg?raw';
	import unplugIcon from '@tabler/icons/outline/plug-connected-x.svg?raw';
	import criticalIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import pausedIcon from '@tabler/icons/outline/player-pause.svg?raw';
	import warningIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import informativeIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import type { InboxChannel } from '$lib/components/communications/inbox/ChannelMark.svelte';
	import {
		clientCommunicationHistoryKey,
		conversationMessagingKey,
		estimateSmsReply,
		fetchConversationMessaging,
		formatTimeLeft,
		type MessengerReplyWindow,
		sendConversationReply,
		sendConversationReplyMessenger,
		sendConversationReplySms,
		sendWebsiteChatStaffMessage,
		type OutboundAttachmentPayload,
		type PendingOutboundSend,
		type SmsReplyEstimate
	} from '$lib/communications/inbox';
	import type { FileListItem } from '$lib/files/api';

	type LibraryFile = Pick<FileListItem, 'id' | 'display_name' | 'mime_type' | 'size_bytes'>;

	// One reply composer for every channel -- email, SMS, and website chat share the same collapsed pill,
	// expand/minimize header, and footer toolbar. Only the fields a channel actually needs (subject,
	// attachments, the SMS cost estimate) render inside it. The parent remounts this with
	// {#key `${group.key}:${activeChannel}`} whenever the conversation OR its channel changes, so every
	// field resets for free instead of needing an effect.
	//
	// `onPendingChange` hands the in-flight send up to the timeline, which draws it as a bubble the moment
	// Send is pressed. The composer still owns the attempt (the payload, the retry, the idempotency key);
	// the page only renders what it is told.
	let {
		clientId,
		channel,
		sessionId = null,
		defaultSubject = '',
		initialBody = '',
		recipientLabel = '',
		customerName = '',
		channels,
		channelDetails = {},
		pageName = null,
		replyWindow = null,
		blocked = null,
		onChannelChange,
		onOpenDetails,
		expanded = $bindable(false),
		onPendingChange
	}: {
		clientId: string | null;
		channel: InboxChannel;
		sessionId?: string | null;
		defaultSubject?: string;
		/** A message written elsewhere for staff to review here, such as a file share's link. */
		initialBody?: string;
		recipientLabel?: string;
		/** Who the reply is to, for the placeholder ("Write your reply to Daniel…"). */
		customerName?: string;
		channels: InboxChannel[];
		/** Where each channel goes, or why it can't send now, for the channel menu. */
		channelDetails?: Partial<
			Record<InboxChannel, { address?: string; unavailable?: string | null }>
		>;
		/** Messenger: the Page the reply goes from, named in the channel pill. */
		pageName?: string | null;
		/** Messenger: the time Meta still allows a reply, shown as a chip on the tab strip. */
		replyWindow?: (MessengerReplyWindow & { pageDisconnected?: boolean }) | null;
		/** Why sending is blocked on this channel: a reason line above the words, and Send held. */
		blocked?: ComposerBlock | null;
		onChannelChange: (channel: InboxChannel) => void;
		/** Opens the Details panel, where Messaging (texts stopped) is managed. */
		onOpenDetails?: () => void;
		expanded?: boolean;
		onPendingChange?: (pending: PendingOutboundSend | null) => void;
	} = $props();

	type ComposerBlock = {
		tone: 'critical' | 'warning' | 'informative';
		text: string;
		/** A shorter line for the empty writing area; the reason itself when left out. */
		short?: string;
		/** The way out, as a link at the line's right ("Reply by text", "Reconnect in Settings"); words alone
		 * when there is nothing this person can press ("Ask an admin to add money"). */
		action?: { label: string; href?: string; onclick?: () => void };
		/** A more specific icon than the tone's own. */
		icon?: string;
	};

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// Seeding once is the point: {#key `${group.key}:${activeChannel}`} remounts this component when the
	// conversation or channel changes, so the initial value is always the right one.
	// svelte-ignore state_referenced_locally
	let subject = $state(defaultSubject);
	// svelte-ignore state_referenced_locally
	let body = $state(initialBody);
	let sending = $state(false);
	let uploading = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let attachmentsField = $state<ConversationAttachments>();
	// The writing area's slot for the files added with the paperclip, under the message words.
	let filesEl = $state<HTMLElement | null>(null);
	let libraryFiles = $state<LibraryFile[]>([]);
	let pendingTemplate = $state<CommunicationEmailTemplateListItem | null>(null);
	let estimate = $state<SmsReplyEstimate | null>(null);
	let estimating = $state(false);
	// Resolved from the sender alone (Stage 6D-2), independent of the cost estimate above, so the attach
	// button's visibility doesn't wait on the user typing anything.
	let mmsEligible = $state(false);
	// Part 7: the number this reply would go from couldn't renew. Known from the sender alone, like MMS
	// eligibility, so the reason line shows before anything is typed.
	let unpaidNumber = $state<{ text: string; name: string; canAddMoney: boolean } | null>(null);
	let bodyEl = $state<HTMLTextAreaElement | null>(null);

	// Texts go to the customer's primary number. When staff have stopped texts to it, or the customer replied
	// STOP, say so here and hold the Send button -- the server refuses the send either way. Shares its cache
	// with the Contact tab, so it is usually already there.
	const messaging = createQuery(() => ({
		queryKey: conversationMessagingKey(clientId as string),
		queryFn: () => fetchConversationMessaging(clientId as string),
		enabled: channel === 'sms' && Boolean(clientId),
		staleTime: 30_000
	}));
	const smsStopped = $derived.by(() => {
		if (channel !== 'sms') return false;
		const phones = messaging.data?.phones ?? [];
		return (phones.find((phone) => phone.is_primary) ?? phones[0])?.state === 'opted_out';
	});

	// The one reason this box can't send right now, drawn as the reason line (design `inputs.md`, Reason line).
	const reason = $derived<ComposerBlock | null>(
		blocked ??
			(smsStopped
				? {
						tone: 'critical',
						text: 'Texts to this customer are stopped.',
						action: onOpenDetails
							? { label: 'See Messaging in Details', onclick: onOpenDetails }
							: undefined
					}
				: unpaidNumber
					? {
							tone: 'critical',
							icon: pausedIcon,
							text: unpaidNumber.text,
							short: `Sending starts again once ${unpaidNumber.name} is renewed`,
							action: unpaidNumber.canAddMoney
								? { label: 'Add money', href: '/settings/communications/balance' }
								: { label: 'Ask an admin to add money' }
						}
					: null)
	);
	const reasonIcons = {
		critical: criticalIcon,
		warning: warningIcon,
		informative: informativeIcon
	};

	// Messenger's reply window, in words (design `inbox.md`, Reply-window chip).
	const windowChip = $derived.by(() => {
		if (channel !== 'messenger' || !replyWindow) return null;
		if (replyWindow.pageDisconnected)
			return {
				tone: 'critical',
				icon: unplugIcon,
				text: 'Page disconnected',
				short: 'Disconnected'
			};
		if (replyWindow.state === 'closed')
			return {
				tone: 'critical',
				icon: windowClosedIcon,
				text: 'Reply window closed',
				short: 'Closed'
			};
		// On a narrow chat the words shorten: "23 h 17 min left to reply on Messenger", "23 h left", "23 h".
		const hours = Math.floor(replyWindow.msLeft / 3_600_000);
		const roughly = hours > 0 ? `${hours} h` : formatTimeLeft(replyWindow.msLeft);
		return {
			tone: replyWindow.state === 'closing' ? 'warning' : 'informative',
			icon: replyWindow.state === 'closing' ? windowClosingIcon : windowOpenIcon,
			text: `${formatTimeLeft(replyWindow.msLeft)} left to reply on Messenger`,
			mid: `${roughly} left`,
			short: roughly
		};
	});

	const writePrompt = $derived(
		customerName ? `Write your reply to ${customerName.split(' ')[0]}…` : 'Write your reply…'
	);
	// When sending is held, the empty box says why instead.
	const placeholder = $derived(reason ? (reason.short ?? reason.text) : writePrompt);

	// The composer's live impact line (blueprint: "live characters, estimated segments and estimated
	// retail cost"), plus MMS eligibility for the attach-photo button. Debounced so every keystroke does not
	// fire a request; a token guards against a slower, stale response landing after a faster, newer one
	// already applied. Still fires on an empty draft (just less often -- only on mount or after clearing the
	// box) so eligibility resolves before the user has typed anything.
	let estimateToken = 0;
	$effect(() => {
		if (channel !== 'sms') {
			estimate = null;
			estimating = false;
			mmsEligible = false;
			unpaidNumber = null;
			return;
		}
		const text = body.trim();
		const token = ++estimateToken;
		estimating = Boolean(text);
		const handle = setTimeout(async () => {
			try {
				const result = await estimateSmsReply(clientId as string, text);
				if (token !== estimateToken) return;
				mmsEligible = result.mms_eligible;
				unpaidNumber =
					!result.ready && result.route_code === 'number_unpaid'
						? {
								text: result.reason,
								name: result.sender_name ?? 'this number',
								canAddMoney: result.can_add_money === true
							}
						: null;
				estimate = text ? result : null;
			} catch {
				if (token === estimateToken) estimate = null;
			} finally {
				if (token === estimateToken) estimating = false;
			}
		}, 400);
		return () => clearTimeout(handle);
	});

	function formatEstimateCost(ready: Extract<SmsReplyEstimate, { ready: true }>) {
		return (ready.cost_minor / 100).toLocaleString(undefined, {
			style: 'currency',
			currency: ready.currency
		});
	}

	// Chat has a real element ref and inserts at the caret, restoring focus there. Email/SMS appends --
	// the text stays editable either way, which is the contract's actual requirement.
	function insertSnippet(text: string) {
		if (channel !== 'website_chat' || !bodyEl) {
			body = body.trim().length > 0 ? `${body}\n${text}` : text;
			return;
		}
		const el = bodyEl;
		const start = el.selectionStart ?? body.length;
		const end = el.selectionEnd ?? body.length;
		body = body.slice(0, start) + text + body.slice(end);
		const caret = start + text.length;
		requestAnimationFrame(() => {
			el.focus();
			el.setSelectionRange(caret, caret);
		});
	}

	// A template seeds the whole draft, so it replaces subject and body rather than appending. If the user
	// has already started writing, confirm first -- otherwise apply straight away.
	const draftHasContent = $derived(
		body.trim().length > 0 || subject.trim() !== defaultSubject.trim()
	);

	function requestTemplate(template: CommunicationEmailTemplateListItem) {
		if (draftHasContent) {
			pendingTemplate = template;
			return;
		}
		applyTemplate(template);
	}

	function applyTemplate(template: CommunicationEmailTemplateListItem) {
		subject = template.subject;
		body = template.body;
		fieldErrors = {};
		formError = '';
		pendingTemplate = null;
	}

	// One attempt = one payload + one idempotency key, held so Retry replays exactly the same send rather
	// than minting a second one the endpoint would treat as a new message. Chat attempts only ever use
	// `body`; `subject` and `attachments` stay empty for that channel.
	type Attempt = {
		id: string;
		subject: string;
		body: string;
		attachments: OutboundAttachmentPayload[];
		libraryFileIds: string[];
	};

	function publish(
		state: 'sending' | 'sent' | 'failed',
		attempt: Attempt,
		extra: Partial<PendingOutboundSend> = {}
	) {
		onPendingChange?.({
			id: attempt.id,
			channel: channel as PendingOutboundSend['channel'],
			subject: channel === 'email' ? attempt.subject : null,
			body: attempt.body,
			created_at: new Date().toISOString(),
			state,
			status: null,
			error: '',
			retry: () => void deliver(attempt),
			...extra
		});
	}

	async function deliver(attempt: Attempt) {
		sending = true;
		publish('sending', attempt);
		try {
			if (channel === 'website_chat') {
				await sendWebsiteChatStaffMessage(sessionId as string, attempt.body, attempt.id);
				// The mark clears here, on acceptance, rather than after the re-read below -- the server has the
				// message, which is the fact the user is waiting on. Chat has no delivery status of its own, so an
				// accepted message simply reads as an ordinary sent bubble from this point.
				publish('sent', attempt);
			} else {
				const result =
					channel === 'messenger'
						? await sendConversationReplyMessenger(clientId as string, attempt.body, attempt.id)
						: channel === 'sms'
							? await sendConversationReplySms(
									clientId as string,
									attempt.body,
									attempt.attachments,
									attempt.id,
									attempt.libraryFileIds
								)
							: await sendConversationReply(
									clientId as string,
									attempt.subject,
									attempt.body,
									attempt.attachments,
									attempt.id,
									null,
									attempt.libraryFileIds
								);
				// The mark flips here, on acceptance, rather than after the re-read below. The server has taken
				// the message and told us what it did with it, which is the fact the user is waiting on -- making
				// them watch a full inbox re-read first added seconds of "Sending…" to a message already sent.
				publish('sent', attempt, { status: result.intent.status });
				toast.success(
					channel === 'sms' ? 'Text sent' : channel === 'messenger' ? 'Message sent' : 'Email sent'
				);
			}

			// The re-read still has to happen, but it now runs behind an already-confirmed bubble. Awaiting it
			// before dropping the bubble is what keeps the swap seamless: the real row is in the cache before
			// the bubble goes, so nothing blinks.
			//
			// The client Communication tab (Part 5D) caches under its own key, which the inbox invalidation
			// does not prefix-match -- without the second call a reply sent here would leave that tab showing
			// a stale page until something else happened to invalidate it.
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] }),
				clientId
					? queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(clientId) })
					: Promise.resolve()
			]);
			onPendingChange?.(null);
		} catch (error) {
			if (channel === 'website_chat') {
				publish('failed', attempt, { error: (error as Error).message });
			} else {
				const withFields = error as Error & { fieldErrors?: Record<string, string> };
				const rejectedFields = withFields.fieldErrors ?? {};
				// A validation rejection cannot succeed on replay, so there is nothing to retry: the draft goes
				// back into the composer where it can actually be corrected. Everything else -- offline, a
				// dropped connection, a server fault -- stays on the bubble as a retryable failure.
				if (Object.keys(rejectedFields).length > 0) {
					subject = attempt.subject;
					body = attempt.body;
					fieldErrors = rejectedFields;
					formError = withFields.message;
					attachmentsField?.reset();
					libraryFiles = [];
					onPendingChange?.(null);
				} else {
					publish('failed', attempt, { error: withFields.message });
				}
			}
		} finally {
			sending = false;
		}
	}

	function submit(event?: SubmitEvent) {
		event?.preventDefault();
		if (sending || uploading || reason) return;

		if (channel === 'website_chat') {
			const text = body.trim();
			if (!text) return;
			body = '';
			bodyEl?.focus();
			void deliver({
				id: crypto.randomUUID(),
				subject: '',
				body: text,
				attachments: [],
				libraryFileIds: []
			});
			return;
		}

		const nextErrors: Record<string, string> = {};
		if (channel === 'email' && !subject.trim()) nextErrors.subject = 'Enter a subject.';
		if (!body.trim()) nextErrors.body = 'Enter a message.';
		fieldErrors = nextErrors;
		if (Object.keys(nextErrors).length > 0) return;

		formError = '';
		const attempt: Attempt = {
			id: crypto.randomUUID(),
			subject,
			body,
			attachments: attachmentsField?.getAttachments() ?? [],
			libraryFileIds: libraryFiles.map((file) => file.id)
		};
		// Cleared up front, the way a messenger does: the message is now represented by its bubble in the
		// timeline, so leaving a copy in the box would read as if nothing had been sent.
		body = '';
		estimate = null;
		attachmentsField?.reset();
		libraryFiles = [];
		void deliver(attempt);
	}

	// "Send Later": email only -- see the migration note on enqueue_conversation_reply_email for why SMS is
	// excluded (its consent/quiet-hours/balance gates are all checked once, at enqueue time). This bypasses
	// the deliver()/onPendingChange bubble entirely: that machinery means "this is going out right now, here
	// is a live mark for it," which is the wrong story for something that will not go out for hours.
	let sendLaterOpen = $state(false);
	let sendLaterAnchor = $state<HTMLElement | null>(null);
	let scheduledAtInput = $state('');
	let scheduling = $state(false);

	// A minute of slack so the round trip through the datetime-local input (minute precision) never lands
	// exactly on "now" and trips the server's strictly-future check.
	function earliestScheduleValue() {
		const min = new Date(Date.now() + 60_000);
		min.setSeconds(0, 0);
		return new Date(min.getTime() - min.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);
	}

	function openSendLater() {
		if (!scheduledAtInput) scheduledAtInput = earliestScheduleValue();
		sendLaterOpen = true;
	}

	async function scheduleSend() {
		const when = new Date(scheduledAtInput);
		if (!scheduledAtInput || Number.isNaN(when.getTime()) || when.getTime() <= Date.now()) {
			formError = 'Choose a send time in the future.';
			return;
		}
		const nextErrors: Record<string, string> = {};
		if (!subject.trim()) nextErrors.subject = 'Enter a subject.';
		if (!body.trim()) nextErrors.body = 'Enter a message.';
		fieldErrors = nextErrors;
		if (Object.keys(nextErrors).length > 0) return;

		scheduling = true;
		formError = '';
		try {
			await sendConversationReply(
				clientId as string,
				subject,
				body,
				attachmentsField?.getAttachments() ?? [],
				crypto.randomUUID(),
				when.toISOString(),
				libraryFiles.map((file) => file.id)
			);
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] }),
				clientId
					? queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(clientId) })
					: Promise.resolve()
			]);
			toast.success('Email scheduled');
			body = '';
			attachmentsField?.reset();
			libraryFiles = [];
			scheduledAtInput = '';
			sendLaterOpen = false;
		} catch (error) {
			const withFields = error as Error & { fieldErrors?: Record<string, string> };
			if (withFields.fieldErrors && Object.keys(withFields.fieldErrors).length > 0) {
				fieldErrors = withFields.fieldErrors;
			}
			formError = withFields.message;
		} finally {
			scheduling = false;
		}
	}

	// Ctrl/Cmd+Enter sends on every channel, the way Gmail, Front and Help Scout do -- a modifier chord, so
	// it never fires by accident while typing. Chat also sends on plain Enter (Shift+Enter for a newline),
	// matching the visitor's own widget; email/SMS keep plain Enter as a newline. Enter that only confirms an
	// IME composition (Japanese, Chinese, Korean input) is not a send.
	const onMac = browser && /Mac|iPhone|iPad/.test(navigator.platform);
	const sendChord = onMac ? '\u2318 Enter' : 'Ctrl+Enter';
	// The shortcut hint beside Send: Enter alone in a chat, the modifier chord elsewhere.
	const sendHint = $derived(
		channel === 'website_chat' ? '\u21b5' : onMac ? '\u2318 \u21b5' : 'Ctrl \u21b5'
	);

	function handleKeydown(event: KeyboardEvent) {
		if (event.key !== 'Enter' || event.isComposing) return;
		const chord = event.ctrlKey || event.metaKey;
		if (!chord && (channel !== 'website_chat' || event.shiftKey)) return;
		event.preventDefault();
		submit();
	}

	// Full-screen is a display mode of the already-expanded draft, not a separate composer -- the same
	// subject/body state keeps typing when it pops out or back in.
	let popped = $state(false);

	let collapsedInputEl = $state<HTMLButtonElement | null>(null);

	// The button that was just used is removed from the page when the composer changes shape, which would
	// drop keyboard focus to the top of the document -- so focus is handed to whatever now stands in its place.
	function collapse() {
		expanded = false;
		popped = false;
		void tick().then(() => collapsedInputEl?.focus());
	}

	function expand() {
		expanded = true;
		requestAnimationFrame(() => bodyEl?.focus());
	}

	function setPopped(next: boolean) {
		popped = next;
		// Entering full screen is focused by the dialog's own open handler below, once its content exists.
		if (!next) void tick().then(() => bodyEl?.focus());
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet sendButton()}
	<Button
		type="submit"
		class="conversation-composer__send"
		label={channel === 'website_chat' ? 'Send' : `Send (${sendChord})`}
		aria-keyshortcuts={channel === 'website_chat' ? undefined : 'Control+Enter Meta+Enter'}
		loading={sending}
		disabled={uploading || Boolean(reason) || !body.trim()}
	>
		Send
		{@html sendIcon}
	</Button>
{/snippet}

{#snippet channelPill()}
	<ComposerChannelMenu
		{channel}
		{channels}
		details={channelDetails}
		{pageName}
		onSelect={onChannelChange}
	/>
{/snippet}

<!-- The reply box (design `inbox.md`, Reply box): a tab strip, the email's From and Subject, the reason line when
     sending is held, the words with their files, and a tool bar with the channel pill and Send. -->
{#snippet composerForm()}
	<form
		id="conversation-composer-expanded"
		class="conversation-composer__box conversation-composer__form"
		class:conversation-composer__form--popped={popped}
		onsubmit={submit}
	>
		<div class="conversation-composer__strip">
			<span class="conversation-composer__tab conversation-composer__tab--current">
				<span class="conversation-composer__tab-icon" aria-hidden="true">{@html replyIcon}</span>
				Reply
			</span>
			{#if windowChip}
				<span
					class="conversation-composer__chip conversation-composer__chip--{windowChip.tone}"
					title={windowChip.text}
				>
					<span class="conversation-composer__chip-icon" aria-hidden="true"
						>{@html windowChip.icon}</span
					>
					<span class="conversation-composer__chip-full">{windowChip.text}</span>
					<span class="conversation-composer__chip-mid" aria-hidden="true"
						>{windowChip.mid ?? windowChip.text}</span
					>
					<span class="conversation-composer__chip-short" aria-hidden="true"
						>{windowChip.short}</span
					>
				</span>
			{/if}
			<Button variant="quiet" size="small" iconOnly label="Minimize reply box" onclick={collapse}>
				{@html minusIcon}
			</Button>
			<Button
				variant="quiet"
				size="small"
				iconOnly
				label={popped ? 'Exit full screen' : 'Full screen'}
				onclick={() => setPopped(!popped)}
			>
				{@html popped ? minimizeIcon : maximizeIcon}
			</Button>
		</div>
		{#if channel === 'email' || channel === 'sms'}
			<p class="conversation-composer__row">
				<span class="conversation-composer__row-label">From</span>
				<span class="conversation-composer__route-from">
					{#if channel === 'sms'}
						{estimate?.ready ? estimate.sender_phone : 'Your business number'}
					{:else}
						<EmailSenderLabel kind="manual" />
					{/if}
				</span>
				<span class="conversation-composer__route-arrow" aria-hidden="true"
					>{@html arrowRightIcon}</span
				>
				<span class="conversation-composer__route-to">{recipientLabel}</span>
			</p>
		{/if}
		{#if channel === 'email'}
			<div
				class="conversation-composer__row"
				class:conversation-composer__row--invalid={Boolean(fieldErrors.subject)}
			>
				<label class="conversation-composer__row-label" for="conversation-composer-subject"
					>Subject</label
				>
				<input
					id="conversation-composer-subject"
					class="conversation-composer__subject"
					bind:value={subject}
					maxlength={998}
					aria-required="true"
					aria-invalid={Boolean(fieldErrors.subject)}
					aria-describedby={fieldErrors.subject ? 'conversation-composer-subject-error' : undefined}
					onkeydown={handleKeydown}
				/>
			</div>
			{#if fieldErrors.subject}<p
					id="conversation-composer-subject-error"
					class="conversation-composer__field-error"
					role="alert"
				>
					{fieldErrors.subject}
				</p>{/if}
		{/if}
		{#if reason}
			<div class="conversation-composer__reason-wrap">
				<p
					class="conversation-composer__reason conversation-composer__reason--{reason.tone}"
					role="status"
				>
					<span class="conversation-composer__reason-icon" aria-hidden="true"
						>{@html reason.icon ?? reasonIcons[reason.tone]}</span
					>
					<span class="conversation-composer__reason-text">{reason.text}</span>
					{#if reason.action?.href}
						<a class="conversation-composer__reason-link" href={reason.action.href}
							>{reason.action.label}<span aria-hidden="true">{@html arrowRightIcon}</span></a
						>
					{:else if reason.action?.onclick}
						<button
							type="button"
							class="conversation-composer__reason-link"
							onclick={reason.action.onclick}
							>{reason.action.label}<span aria-hidden="true">{@html arrowRightIcon}</span></button
						>
					{:else if reason.action}
						<span class="conversation-composer__reason-note">{reason.action.label}</span>
					{/if}
				</p>
			</div>
		{/if}
		<div
			class="conversation-composer__editor"
			class:conversation-composer__editor--invalid={Boolean(fieldErrors.body)}
		>
			<label class="sr-only" for="conversation-composer-body">Message</label>
			<textarea
				bind:this={bodyEl}
				id="conversation-composer-body"
				bind:value={body}
				{placeholder}
				disabled={Boolean(blocked)}
				maxlength={channel === 'sms' ? 1600 : channel === 'website_chat' ? 5000 : 20_000}
				rows="3"
				aria-required="true"
				aria-invalid={Boolean(fieldErrors.body)}
				aria-describedby={fieldErrors.body ? 'conversation-composer-body-error' : undefined}
				aria-keyshortcuts={channel === 'website_chat' ? 'Enter' : 'Control+Enter Meta+Enter'}
				onkeydown={handleKeydown}></textarea>
			<div class="conversation-composer__files" bind:this={filesEl}></div>
		</div>
		{#if fieldErrors.body}<p
				id="conversation-composer-body-error"
				class="conversation-composer__field-error"
				role="alert"
			>
				{fieldErrors.body}
			</p>{/if}
		{#if channel === 'sms'}
			<p class="conversation-composer__impact">
				{mmsEligible
					? 'A picture attaches as a real picture text. Other files send as a secure link in the text.'
					: 'A file attaches as a secure link in the text for this number.'}
			</p>
		{/if}
		{#if formError}<p class="conversation-composer__error" role="alert">{formError}</p>{/if}
		<footer class="conversation-composer__toolbar">
			{@render channelPill()}
			<!-- Messenger replies are words only for now, so it shows snippets but no files. -->
			{#if channel === 'email' || channel === 'sms' || channel === 'messenger' || channel === 'website_chat'}
				<span class="conversation-composer__divider" aria-hidden="true"></span>
				<div class="conversation-composer__tools">
					{#if channel === 'email' || channel === 'sms'}
						<ConversationAttachments
							bind:this={attachmentsField}
							variant={channel}
							triggerVariant="quiet"
							cardsTarget={filesEl}
							disabled={sending}
							onUploadingChange={(value) => (uploading = value)}
						/>
						<ConversationLibraryAttachments
							files={libraryFiles}
							onChange={(next) => (libraryFiles = next)}
							variant={channel}
							triggerVariant="quiet"
							disabled={sending}
							{clientId}
							clientLabel="This client's files"
						/>
					{/if}
					{#if channel === 'email'}
						<EmailTemplatePickerButton
							triggerVariant="quiet"
							disabled={sending}
							onApply={requestTemplate}
						/>
					{/if}
					<SnippetPickerButton triggerVariant="quiet" disabled={sending} onInsert={insertSnippet} />
				</div>
			{/if}
			<span class="conversation-composer__toolbar-end">
				{#if channel === 'sms'}
					<span class="conversation-composer__estimate">
						{#if estimating}
							Estimating…
						{:else if estimate?.ready}
							{body.length} character{body.length === 1 ? '' : 's'} · {estimate.segment_count} segment{estimate.segment_count ===
							1
								? ''
								: 's'} · {formatEstimateCost(estimate)}
						{:else if estimate && !estimate.ready}
							{estimate.reason}
						{:else}
							{body.length} character{body.length === 1 ? '' : 's'}
						{/if}
					</span>
				{/if}
				{#if !reason}
					<kbd class="conversation-composer__hint" aria-hidden="true">{sendHint}</kbd>
				{/if}
				{#if channel === 'email'}
					<div class="conversation-composer__send-group" bind:this={sendLaterAnchor}>
						{@render sendButton()}
						<Button
							class="conversation-composer__send-later-trigger"
							iconOnly
							label="More send options"
							disabled={sending || uploading}
							onclick={openSendLater}
						>
							{@html chevronDownIcon}
						</Button>
					</div>
					<Popover
						open={sendLaterOpen}
						anchor={sendLaterAnchor}
						title="Send later"
						icon={sendLaterIcon}
						iconTone="conversation"
						onClose={() => (sendLaterOpen = false)}
					>
						<div class="conversation-composer__send-later">
							<label for="conversation-composer-schedule">Send at</label>
							<input
								id="conversation-composer-schedule"
								type="datetime-local"
								bind:value={scheduledAtInput}
								min={earliestScheduleValue()}
							/>
							<Button type="button" variant="primary" loading={scheduling} onclick={scheduleSend}
								>Schedule send</Button
							>
						</div>
					</Popover>
				{:else}
					{@render sendButton()}
				{/if}
			</span>
		</footer>
	</form>
{/snippet}

<div class="conversation-composer">
	{#if !expanded}
		<!-- Minimized: one line in the same box, so the chat gets the room back. -->
		<div class="conversation-composer__box conversation-composer__collapsed">
			{@render channelPill()}
			<button
				type="button"
				bind:this={collapsedInputEl}
				class="conversation-composer__collapsed-input"
				aria-expanded="false"
				aria-controls="conversation-composer-expanded"
				onclick={expand}>{writePrompt}</button
			>
			<Button variant="quiet" size="small" iconOnly label="Open the reply box" onclick={expand}>
				{@html chevronUpIcon}
			</Button>
			<Button class="conversation-composer__collapsed-send" iconOnly label="Send" disabled>
				{@html sendIcon}
			</Button>
		</div>
	{:else if popped}
		<DialogPrimitive.Root
			open
			onOpenChange={(next) => {
				if (!next) setPopped(false);
			}}
		>
			<DialogPrimitive.Portal>
				<DialogPrimitive.Overlay class="conversation-composer__popout-overlay" />
				<DialogPrimitive.Content
					class="conversation-composer__popout-content"
					onOpenAutoFocus={(event) => {
						event.preventDefault();
						bodyEl?.focus();
					}}
					onCloseAutoFocus={(event) => event.preventDefault()}
					aria-label={(channel === 'email'
						? 'Email'
						: channel === 'sms'
							? 'Text message'
							: channel === 'messenger'
								? 'Messenger reply'
								: 'Chat message') + ' composer, full screen'}
				>
					{@render composerForm()}
				</DialogPrimitive.Content>
			</DialogPrimitive.Portal>
		</DialogPrimitive.Root>
	{:else}
		{@render composerForm()}
	{/if}
</div>
<!-- eslint-enable svelte/no-at-html-tags -->

{#if pendingTemplate}
	{@const template = pendingTemplate}
	<ConfirmDialog
		open
		title="Replace your draft?"
		confirmLabel="Replace"
		cancelLabel="Keep editing"
		onConfirm={() => applyTemplate(template)}
		onClose={() => (pendingTemplate = null)}
	>
		Applying <strong>{template.name}</strong> replaces the subject and message you've started.
	</ConfirmDialog>
{/if}

<style lang="scss">
	// The reply box sits in the chat card's foot (design `inbox.md`, Reply box).
	.conversation-composer {
		padding: var(--space-smaller) var(--space-medium) var(--space-medium);
	}

	.conversation-composer__box {
		display: flex;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: 12px;
		background: var(--color-surface);
		overflow: hidden;
		transition:
			border-color var(--timing-quick),
			box-shadow var(--timing-quick);
	}

	// While typing: a 1.5px green edge and a soft green glow.
	.conversation-composer__form:focus-within {
		border-color: var(--color-interactive);
		box-shadow:
			0 0 0 0.5px var(--color-interactive),
			0 0 0 4px color-mix(in srgb, var(--color-interactive) 12%, transparent);
	}

	.conversation-composer__collapsed {
		min-height: 52px;
		align-items: center;
		gap: var(--space-small);
		padding: 0 var(--space-small) 0 10px;
	}

	.conversation-composer__collapsed-input {
		min-width: 0;
		min-height: 36px;
		flex: 1;
		padding: 0 var(--space-smaller);
		overflow: hidden;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: transparent;
		font: inherit;
		font-size: var(--typography--fontSize-base);
		text-align: left;
		text-overflow: ellipsis;
		white-space: nowrap;
		cursor: text;

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	// The minimized line's send is a 36 square, held until the box is open and has words.
	.conversation-composer__collapsed :global(.conversation-composer__collapsed-send) {
		width: 36px;
		height: 36px;
	}

	.conversation-composer__form {
		flex-direction: column;
	}

	.conversation-composer__form--popped {
		flex: 1;
		min-width: 0;
		height: 100%;

		.conversation-composer__editor {
			flex: 1;
			min-height: 0;

			textarea {
				height: 100%;
				min-height: 100%;
				max-height: none;
			}
		}
	}

	:global(.conversation-composer__popout-overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: var(--color-overlay);
	}

	:global(.conversation-composer__popout-content) {
		position: fixed;
		inset: var(--space-large);
		z-index: var(--elevation-modal);
		display: flex;
		outline: none;
	}

	// Tab strip: Reply, then the reply-window chip, Minimize and Full screen at the right.
	.conversation-composer__strip {
		display: flex;
		min-height: 40px;
		align-items: stretch;
		gap: var(--space-smaller);
		padding: 0 var(--space-smaller) 0 var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);

		> :global(.button) {
			align-self: center;
		}
	}

	.conversation-composer__tab {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		margin-right: auto;
		padding: 0 10px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		white-space: nowrap;
	}

	.conversation-composer__tab--current {
		box-shadow: inset 0 -2px 0 var(--color-interactive);
		color: var(--color-heading);

		.conversation-composer__tab-icon {
			color: var(--color-interactive);
		}
	}

	.conversation-composer__tab-icon {
		display: inline-grid;
		place-items: center;

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.conversation-composer__chip {
		display: inline-flex;
		min-width: 0;
		height: 24px;
		align-self: center;
		align-items: center;
		gap: var(--space-smaller);
		margin-right: var(--space-smaller);
		padding: 0 var(--space-small);
		overflow: hidden;
		border: var(--border-base) solid var(--chip-edge);
		border-radius: var(--radius-circle);
		color: var(--chip-text);
		background: var(--chip-surface);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
		text-overflow: ellipsis;
		white-space: nowrap;

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.conversation-composer__chip-icon {
		display: inline-grid;
		flex: 0 0 auto;
		place-items: center;
	}

	@each $tone in informative, warning, critical {
		.conversation-composer__chip--#{$tone} {
			--chip-surface: var(--color-#{$tone}--surface);
			--chip-edge: var(--color-#{$tone}--surface-edge);
			--chip-text: var(--color-#{$tone}--onSurface);
		}
	}

	// From and Subject: two 44-high lines under the tabs, each with a hairline.
	.conversation-composer__row {
		display: flex;
		min-height: 44px;
		align-items: center;
		gap: var(--space-small);
		margin: 0;
		padding: 0 var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
		font-size: var(--typography--fontSize-base);
	}

	.conversation-composer__row--invalid {
		box-shadow: inset 0 -1px 0 var(--color-critical);
	}

	.conversation-composer__row-label {
		flex: 0 0 auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.conversation-composer__route-from {
		display: inline-flex;
		min-width: 0;
		flex: 0 1 auto;
		overflow: hidden;
		color: var(--color-text);
		font-weight: 500;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.conversation-composer__route-arrow {
		display: inline-flex;
		flex: 0 0 auto;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.conversation-composer__route-to {
		min-width: 0;
		overflow: hidden;
		color: var(--color-heading);
		font-weight: 600;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.conversation-composer__subject {
		min-width: 0;
		flex: 1;
		padding: 0;
		border: 0;
		outline: none;
		box-shadow: none;
		color: var(--color-heading);
		background: transparent;
		font: inherit;
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}

	// Why sending is held, with the way out at its right (design `inputs.md`, Reason line).
	.conversation-composer__reason-wrap {
		padding: 10px var(--space-slim) 0;
	}

	.conversation-composer__reason {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: 0;
		padding: var(--space-small) var(--space-slim);
		border-radius: var(--radius-base);
		color: var(--reason-text);
		background: var(--reason-surface);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
	}

	@each $tone in informative, warning, critical {
		.conversation-composer__reason--#{$tone} {
			--reason-surface: var(--color-#{$tone}--surface);
			--reason-text: var(--color-#{$tone}--onSurface);
		}
	}

	.conversation-composer__reason-icon {
		display: inline-grid;
		flex: 0 0 auto;
		place-items: center;

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.conversation-composer__reason-text {
		min-width: 0;
		flex: 1;
	}

	.conversation-composer__reason-note {
		flex: 0 0 auto;
		font-weight: 500;
	}

	.conversation-composer__reason-link {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		gap: 2px;
		padding: 0;
		border: 0;
		border-radius: var(--radius-small);
		color: var(--color-interactive);
		background: none;
		font: inherit;
		text-decoration: underline;
		text-underline-offset: 2px;
		cursor: pointer;

		span {
			display: inline-grid;
			place-items: center;
		}

		:global(svg) {
			width: 12px;
			height: 12px;
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	// The words: three lines tall when empty, growing as you type.
	.conversation-composer__editor {
		padding: var(--space-slim) var(--space-base) var(--space-small);

		textarea {
			display: block;
			width: 100%;
			min-height: calc(3lh);
			max-height: 40vh;
			padding: 0;
			border: 0;
			outline: none;
			box-shadow: none;
			color: var(--color-heading);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-base);
			line-height: 1.5;
			field-sizing: content;
			resize: none;

			&::placeholder {
				color: var(--color-text--secondary);
			}

			&:disabled {
				cursor: not-allowed;

				&::placeholder {
					color: var(--color-disabled);
				}
			}
		}
	}

	.conversation-composer__editor--invalid {
		box-shadow: inset 0 0 0 var(--border-base) var(--color-critical);
	}

	.conversation-composer__impact {
		margin: 0;
		padding: 0 var(--space-base) var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-overline);
	}

	.conversation-composer__field-error,
	.conversation-composer__error {
		margin: 0;
		padding: var(--space-smaller) var(--space-base) 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-overline);
	}

	// Tool bar: the channel pill, a divider, the quiet tools, then the shortcut hint and Send.
	.conversation-composer__toolbar {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-small) var(--space-small) var(--space-small) 10px;
	}

	.conversation-composer__divider {
		width: var(--border-base);
		height: 20px;
		flex: 0 0 auto;
		margin: 0 var(--space-smaller);
		background: var(--color-border);
	}

	.conversation-composer__tools {
		display: flex;
		min-width: 0;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-smaller);
	}

	.conversation-composer__toolbar-end {
		display: flex;
		min-width: 0;
		flex: 0 0 auto;
		align-items: center;
		gap: var(--space-small);
		margin-left: auto;
	}

	.conversation-composer__estimate {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-overline);
		font-weight: 500;
		white-space: nowrap;
	}

	.conversation-composer__hint {
		padding: 2px 6px;
		border-radius: var(--radius-small);
		color: var(--color-text--secondary);
		background: var(--color-surface--background);
		font: inherit;
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
		white-space: nowrap;
	}

	/* Send and its chevron read as one split button: the chevron sits flush against Send with a hairline
	   seam, and only the two outer ends are rounded. */
	.conversation-composer__send-group {
		display: flex;
		flex: 0 0 auto;
		align-items: stretch;

		:global(.conversation-composer__send) {
			border-top-right-radius: 0;
			border-bottom-right-radius: 0;
		}

		:global(.conversation-composer__send-later-trigger) {
			border-left-color: rgb(255 255 255 / 0.3);
			border-top-left-radius: 0;
			border-bottom-left-radius: 0;
		}
	}

	.conversation-composer__send-later {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		min-width: 220px;

		label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
		}

		input {
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-small);
			color: var(--color-text);
			background: var(--color-surface);
			font: inherit;
			font-size: var(--typography--fontSize-base);
		}
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
	}

	.conversation-composer__files:not(:empty) {
		padding: var(--space-small) 0 0;
	}

	// On a narrow chat card the words go first (design `inbox.md`, Narrow widths): the chip shortens, the
	// shortcut hint goes, then the tabs drop their icons.
	.conversation-composer__chip-mid,
	.conversation-composer__chip-short {
		display: none;
	}

	@container inbox-chat (max-width: 640px) {
		.conversation-composer__chip-full {
			display: none;
		}

		.conversation-composer__chip-mid {
			display: inline;
		}

		.conversation-composer__hint {
			display: none;
		}
	}

	@container inbox-chat (max-width: 480px) {
		.conversation-composer__chip-mid {
			display: none;
		}

		.conversation-composer__chip-short {
			display: inline;
		}

		.conversation-composer__tab-icon {
			display: none;
		}
	}

	@media (max-width: 560px) {
		.conversation-composer {
			padding-inline: var(--space-small);
		}

		.conversation-composer__estimate,
		.conversation-composer__hint {
			display: none;
		}
	}
</style>
