/**
 * UCRM Website Chat -- public Contact Widget shell.
 *
 * Plain TypeScript, no framework, no dependencies, Shadow DOM isolated. This file is built on its
 * own by `vite.config.widget.ts` into `static/widget/website-chat.js` and is the exact script a
 * contractor pastes into their site. It shares nothing with the app: no layout, no `app.scss`, no
 * SvelteKit runtime. Everything it draws lives behind a shadow boundary that starts at
 * `all: initial`, so the host page cannot restyle our widget and our widget cannot restyle the
 * host page.
 *
 * WC3 built the shell -- launcher, teaser, panel frame. WC4.3 added the identity form inside that
 * panel: Name / Phone / E-mail / message, the consent line, and the contractor's footer, following
 * HighLevel's form (`Design/Website Chat/highlevel-identity-form.jpg`). It stops where HighLevel's
 * does not serve us: a submitted form leads into a conversation, never into a dead-end "Thank You!".
 *
 * WC4.4 Stage C is that conversation -- timeline, composer, session restore, and the live transport.
 * The messenger half follows Intercom rather than HighLevel (`Design/Website Chat/evidence-notes.md`):
 * a persistent two-way thread the visitor can come back to, not a lead form that thanks you and ends.
 * Updates arrive on a private per-session Realtime channel, with a ~4s poll as the fallback whenever
 * the socket is unavailable; both feed one list that dedupes by message id.
 *
 * It is built as an ES module, so the embed snippet is `<script type="module" async src=...>`. That
 * is what lets the phone-number metadata load only when someone actually opens the panel.
 */

import type { CountryCode } from 'libphonenumber-js/min';

// libphonenumber's metadata was 170 kB of the 180 kB this file used to weigh, loaded on every page
// view of a contractor's site to serve one field of a form most visitors never open. It is imported
// lazily instead: prefetched when the launcher is hovered, awaited when the panel opens. Splitting
// it out is what makes this build an ES module -- a classic script cannot code-split.
type PhoneModule = typeof import('./phone');

let phone: PhoneModule | null = null;
let phoneRequest: Promise<PhoneModule | null> | null = null;

function loadPhone() {
	phoneRequest ??= import('./phone').then((module) => (phone = module)).catch(() => null);
	return phoneRequest;
}

// The Realtime client, split the same way and for the same reason. It is needed only by a visitor who
// already has a conversation open, which is a small fraction of the people who load a contractor's
// page at all, so it must never sit in the widget's first byte.
type RealtimeModule = typeof import('./realtime');

let realtime: RealtimeModule | null = null;
let realtimeRequest: Promise<RealtimeModule | null> | null = null;

function loadRealtime() {
	realtimeRequest ??= import('./realtime').then((module) => (realtime = module)).catch(() => null);
	return realtimeRequest;
}

type LauncherPosition = 'bottom_left' | 'bottom_right';
type WidgetStatus = 'live' | 'draft' | 'disabled' | 'suspended' | 'not_entitled';
type ContactRequirement = 'phone' | 'email' | 'either';

type WidgetPublicConfig = {
	widgetId: string;
	businessName: string;
	brandColor: string | null;
	launcherPosition: LauncherPosition;
	teaserText: string | null;
	greetingText: string | null;
	contactRequirement: ContactRequirement;
	privacyPolicyUrl: string | null;
	status: WidgetStatus;
};

// One accepted conversation, as the browser remembers it. The token is the visitor's only proof of
// who they are; losing it strands a conversation the contractor has already paid for.
type SessionRecord = {
	sessionId: string;
	sessionToken: string;
};

type ChatMessage = {
	id: string;
	direction: 'inbound' | 'outbound';
	sender_type: 'visitor' | 'staff' | 'system' | 'automation';
	body: string;
	created_at: string;
};

// A message the visitor has written but the server has not confirmed. It carries its own idempotency
// key for the whole of its life, so a retry after a failed send replays rather than posts twice.
type PendingMessage = {
	localId: string;
	body: string;
	idempotencyKey: string;
	status: 'sending' | 'failed';
};

type IdentityDraft = {
	name: string;
	country: CountryCode;
	phone: string;
	email: string;
	message: string;
	consent: boolean;
	idempotencyKey: string;
};

(function () {
	// `document.currentScript` is null inside a module script, so this finds its own tag by matching
	// the module's own URL, falling back to the first tag carrying our attribute.
	const tags = Array.from(
		document.querySelectorAll<HTMLScriptElement>('script[data-widget-token]')
	);
	const scriptEl = tags.find((tag) => tag.src === import.meta.url) ?? tags[0] ?? null;
	const widgetToken = scriptEl?.getAttribute('data-widget-token') ?? '';
	if (!widgetToken) return;

	// The URL this module was itself served from tells us which UCRM instance to ask -- this script
	// is not hand-copied host to host, it is served by us alongside the app, so its own origin is
	// always right without a build-time constant to keep in sync.
	const appOrigin = new URL(import.meta.url, window.location.href).origin;
	const teaserDismissedKey = (widgetId: string) => `ucrm-wc-teaser-dismissed-${widgetId}`;
	const draftKey = (widgetId: string) => `ucrm-wc-draft-${widgetId}`;
	// Written on acceptance and read on every load: this is what makes a conversation survive a refresh,
	// a navigation and a browser restart. The token only exists in the one response that created it, so
	// losing it strands a conversation the contractor has already paid for.
	const sessionKey = (widgetId: string) => `ucrm-wc-session-${widgetId}`;
	// The composer's unsent text, kept separately from the identity draft: the contract promises an
	// unsent draft survives a reload, and by this point the identity draft is long gone.
	const composerKey = (widgetId: string) => `ucrm-wc-composer-${widgetId}`;

	let config: WidgetPublicConfig | null = null;
	let shadow: ShadowRoot | null = null;
	let stage: HTMLDivElement | null = null;
	let panelOpen = false;
	let teaserDismissed = true;

	let draft: IdentityDraft | null = null;
	let submitting = false;
	let accepted = false;
	// A field only starts showing "Invalid value" once the visitor has actually left it or tried to
	// send. Validating while someone is still typing their email calls them wrong mid-word.
	let touched = new Set<keyof IdentityDraft>();
	let formBanner = '';
	// Built once and reused, so closing and reopening the panel keeps what was typed, the chosen
	// country and the caret -- without a round trip through storage.
	let formNode: HTMLFormElement | null = null;

	// -- Conversation state ---------------------------------------------------------------------
	//
	// `messages` is the confirmed thread, oldest first; `pending` is what the visitor has written and
	// the server has not confirmed yet. They are drawn as one list. Everything that can add a message --
	// session restore, the poll, the socket, and the visitor's own send -- goes through `absorb()`, which
	// dedupes by id, so the same message arriving twice by two transports is drawn once.
	let session: SessionRecord | null = null;
	let messages: ChatMessage[] = [];
	const seenIds = new Set<string>();
	let pending: PendingMessage[] = [];
	let sessionClosed = false;
	let historyLoading = false;
	let historyLoaded = false;
	let hasMoreHistory = false;
	let threadBanner = '';

	// Built once and mutated in place, like the form: rebuilding the thread on every keystroke would
	// throw away the composer's caret and the visitor's scroll position.
	let threadNode: HTMLDivElement | null = null;
	let listNode: HTMLDivElement | null = null;
	let earlierButton: HTMLButtonElement | null = null;
	let bannerLine: HTMLParagraphElement | null = null;
	let composerNode: HTMLDivElement | null = null;
	let composerInput: HTMLTextAreaElement | null = null;
	let composerSend: HTMLButtonElement | null = null;
	let scrollNode: HTMLDivElement | null = null;

	// -- Transport state ------------------------------------------------------------------------
	let socket: InstanceType<RealtimeModule['RealtimeClient']> | null = null;
	let channel: ReturnType<InstanceType<RealtimeModule['RealtimeClient']>['channel']> | null = null;
	let grantExpiresAt = 0;
	let connecting = false;
	let pollTimer: ReturnType<typeof setInterval> | null = null;
	let remintTimer: ReturnType<typeof setTimeout> | null = null;
	let listenersBound = false;

	// -- Tokens ---------------------------------------------------------------------------------
	//
	// The app's design tokens, copied as literal values because this bundle cannot import
	// `_variables.scss` -- there is no SCSS pipeline out here and no `:root` of ours to inherit
	// from. Keep these in step with `src/lib/styles/_variables.scss` when a token changes.
	//
	// Light palette only, on purpose: the widget is organization-branded furniture on someone
	// else's website, so it should not flip to a dark theme because the visitor's OS is dark while
	// the page around it stays light.

	function styles(brandColor: string) {
		return `
:host {
	all: initial;

	--wc-color-brand: ${brandColor};
	--wc-color-surface: #ffffff;
	--wc-color-surface-hover: #f9f8f6;
	--wc-color-surface-subtle: #f9f8f6;
	--wc-color-border: #dadfe2;
	--wc-color-heading: #032b3a;
	--wc-color-text: #233d48;
	--wc-color-icon: #233d48;
	--wc-color-icon-secondary: #84979f;
	--wc-color-on-brand: #ffffff;
	--wc-color-focus: #84979f;
	--wc-color-critical: #d24232;
	--wc-color-placeholder: #84979f;

	--wc-space-base: 16px;
	--wc-space-large: 24px;
	--wc-radius-small: 4px;
	--wc-radius-base: 8px;
	--wc-radius-large: 16px;
	--wc-font-size-base: 14px;
	--wc-font-size-large: 16px;
	--wc-line-height-base: 1.25;
	--wc-shadow-base: 0px 1px 4px 0px #0000001a, 0px 4px 12px 0px #0000000d;
	--wc-shadow-high: 0px 16px 16px 0px #00000013, 0px 0px 8px 0px #0000000d;
	--wc-shadow-focus: 0px 0px 0px 2px var(--wc-color-surface), 0px 0px 0px 4px var(--wc-color-focus);
	--wc-timing-base: 0.2s;
}

*, *::before, *::after {
	box-sizing: border-box;
	margin: 0;
	padding: 0;
	font-family: Inter, Helvetica, Arial, sans-serif;
	-webkit-font-smoothing: antialiased;
}

button { font: inherit; cursor: pointer; }
svg { display: block; }

.wc-avatar {
	display: inline-flex;
	flex: 0 0 auto;
	align-items: center;
	justify-content: center;
	border-radius: 100%;
	background: var(--wc-color-brand);
	color: var(--wc-color-on-brand);
	font-weight: 600;
	overflow: hidden;
}

.wc-avatar--base { width: 32px; height: 32px; font-size: 12px; }
.wc-avatar--medium { width: 40px; height: 40px; font-size: var(--wc-font-size-base); }

/* -- Launcher -- */

.wc-launcher {
	position: fixed;
	bottom: var(--wc-space-large);
	display: grid;
	place-items: center;
	width: 56px;
	height: 56px;
	border: none;
	border-radius: 100%;
	background: var(--wc-color-brand);
	color: var(--wc-color-on-brand);
	box-shadow: var(--wc-shadow-high);
	transition: transform var(--wc-timing-base) ease-out;
}

.wc-launcher:hover { transform: scale(1.05); }

.wc-launcher:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-high), var(--wc-shadow-focus);
}

.wc-launcher svg { width: 28px; height: 28px; }

.wc-launcher--bottom_right { right: var(--wc-space-large); }
.wc-launcher--bottom_left { left: var(--wc-space-large); }

/* -- Teaser -- */

.wc-teaser {
	position: fixed;
	bottom: 84px;
	display: flex;
	align-items: center;
	gap: var(--wc-space-base);
	max-width: 280px;
	padding: var(--wc-space-base);
	border: none;
	border-radius: var(--wc-radius-large);
	background: var(--wc-color-surface);
	box-shadow: var(--wc-shadow-base);
	text-align: left;
	animation: wc-teaser-in var(--wc-timing-base) ease-out;
}

.wc-teaser:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-base), var(--wc-shadow-focus);
}

.wc-teaser--bottom_right { right: var(--wc-space-large); }
.wc-teaser--bottom_left { left: var(--wc-space-large); }

.wc-teaser__text {
	flex: 1;
	font-size: var(--wc-font-size-base);
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-text);
}

.wc-teaser__dismiss {
	display: grid;
	place-items: center;
	flex: 0 0 auto;
	width: 20px;
	height: 20px;
	border: none;
	background: none;
	color: var(--wc-color-icon-secondary);
}

.wc-teaser__dismiss:hover { color: var(--wc-color-icon); }

.wc-teaser__dismiss:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-focus);
}

.wc-teaser__dismiss svg { width: 16px; height: 16px; }

@keyframes wc-teaser-in {
	from { opacity: 0; transform: translateY(8px); }
	to { opacity: 1; transform: translateY(0); }
}

/* -- Panel -- */

.wc-panel {
	position: fixed;
	bottom: var(--wc-space-large);
	display: flex;
	flex-direction: column;
	width: min(360px, calc(100vw - 2 * var(--wc-space-large)));
	height: min(600px, calc(100vh - 2 * var(--wc-space-large)));
	border-radius: var(--wc-radius-base);
	background: var(--wc-color-surface);
	box-shadow: var(--wc-shadow-high);
	overflow: hidden;
}

.wc-panel--bottom_right { right: var(--wc-space-large); }
.wc-panel--bottom_left { left: var(--wc-space-large); }

.wc-panel__header {
	display: flex;
	align-items: center;
	gap: var(--wc-space-base);
	flex: 0 0 auto;
	padding: var(--wc-space-base);
	border-bottom: 1px solid var(--wc-color-border);
	background: var(--wc-color-surface-subtle);
}

.wc-panel__title {
	flex: 1;
	font-size: var(--wc-font-size-large);
	font-weight: 700;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-heading);
	overflow: hidden;
	white-space: nowrap;
	text-overflow: ellipsis;
}

.wc-panel__close {
	display: grid;
	place-items: center;
	flex: 0 0 auto;
	width: 28px;
	height: 28px;
	border: none;
	border-radius: var(--wc-radius-small);
	background: none;
	color: var(--wc-color-icon-secondary);
}

.wc-panel__close:hover {
	color: var(--wc-color-icon);
	background: var(--wc-color-surface-hover);
}

.wc-panel__close:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-focus);
}

.wc-panel__close svg { width: 20px; height: 20px; }

.wc-panel__body {
	flex: 1;
	overflow-y: auto;
	padding: var(--wc-space-base);
}

.wc-panel__footer {
	flex: 0 0 auto;
	padding: 8px var(--wc-space-base);
	border-top: 1px solid var(--wc-color-border);
	background: var(--wc-color-surface-subtle);
	text-align: center;
	font-size: 11px;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-icon-secondary);
}

/* The widget credits the contractor, never UCRM -- a contractor's customers see only the
   contractor (website-chat-behavior-contract.md). */
.wc-panel__footer em { font-style: normal; font-weight: 600; color: var(--wc-color-text); }

/* -- Identity form -- */

.wc-intro {
	display: flex;
	align-items: flex-start;
	gap: 8px;
	margin-bottom: 12px;
}

.wc-intro__bubble {
	padding: 10px 12px;
	border-radius: var(--wc-radius-base);
	background: var(--wc-color-surface-subtle);
	font-size: var(--wc-font-size-base);
	line-height: 1.45;
	color: var(--wc-color-text);
}

.wc-form { display: flex; flex-direction: column; gap: 10px; }

.wc-field { display: flex; flex-direction: column; gap: 4px; }

.wc-input,
.wc-textarea {
	width: 100%;
	padding: 10px 12px;
	border: 1px solid var(--wc-color-border);
	border-radius: var(--wc-radius-small);
	background: var(--wc-color-surface);
	font-size: var(--wc-font-size-base);
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-text);
}

.wc-input::placeholder,
.wc-textarea::placeholder { color: var(--wc-color-placeholder); }

.wc-input:focus-visible,
.wc-textarea:focus-visible {
	outline: transparent;
	border-color: var(--wc-color-brand);
	box-shadow: 0 0 0 1px var(--wc-color-brand);
}

.wc-textarea { min-height: 64px; resize: vertical; }

.wc-field--invalid .wc-input,
.wc-field--invalid .wc-textarea,
.wc-field--invalid .wc-phone { border-color: var(--wc-color-critical); }

.wc-field__error {
	font-size: 12px;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-critical);
}

/* -- Phone control -- */

.wc-phone {
	display: flex;
	align-items: stretch;
	position: relative;
	border: 1px solid var(--wc-color-border);
	border-radius: var(--wc-radius-small);
	background: var(--wc-color-surface);
}

.wc-phone:focus-within {
	border-color: var(--wc-color-brand);
	box-shadow: 0 0 0 1px var(--wc-color-brand);
}

.wc-phone .wc-input { border: none; box-shadow: none; padding-left: 4px; }
.wc-phone .wc-input:focus-visible { box-shadow: none; }

/* Declared after the focus rules on purpose: a field that is both focused and invalid must stay red.
   Focus tells the visitor where they are; the error tells them something is wrong, and that is the
   more important of the two to keep visible. */
.wc-field--invalid .wc-input:focus-visible,
.wc-field--invalid .wc-textarea:focus-visible,
.wc-field--invalid .wc-phone:focus-within {
	border-color: var(--wc-color-critical);
	box-shadow: 0 0 0 1px var(--wc-color-critical);
}

.wc-field--invalid .wc-phone .wc-input:focus-visible { box-shadow: none; }

.wc-phone__country {
	display: flex;
	align-items: center;
	gap: 4px;
	flex: 0 0 auto;
	padding: 0 4px 0 10px;
	border: none;
	background: none;
	font-size: var(--wc-font-size-base);
	color: var(--wc-color-text);
}

.wc-phone__country:focus-visible {
	outline: transparent;
	border-radius: var(--wc-radius-small);
	box-shadow: var(--wc-shadow-focus);
}

/* Emoji flags render as flags on macOS, iOS and Android and fall back to the country's two
   letters on Windows, which still reads correctly beside the dial code. */
.wc-phone__flag { font-size: var(--wc-font-size-large); line-height: 1; letter-spacing: -1px; }
.wc-phone__caret { width: 12px; height: 12px; color: var(--wc-color-icon-secondary); }

.wc-country {
	position: absolute;
	z-index: 2;
	top: calc(100% + 4px);
	left: 0;
	width: min(280px, 100%);
	border: 1px solid var(--wc-color-border);
	border-radius: var(--wc-radius-base);
	background: var(--wc-color-surface);
	box-shadow: var(--wc-shadow-base);
	overflow: hidden;
}

.wc-country__search {
	width: 100%;
	padding: 8px 12px;
	border: none;
	border-bottom: 1px solid var(--wc-color-border);
	font-size: var(--wc-font-size-base);
	color: var(--wc-color-text);
}

.wc-country__search:focus-visible { outline: transparent; }

.wc-country__list {
	max-height: 220px;
	overflow-y: auto;
	list-style: none;
}

.wc-country__option {
	display: flex;
	align-items: center;
	gap: 8px;
	width: 100%;
	padding: 8px 12px;
	border: none;
	background: none;
	text-align: left;
	font-size: var(--wc-font-size-base);
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-text);
}

.wc-country__option:hover,
.wc-country__option:focus-visible { outline: transparent; background: var(--wc-color-surface-hover); }

.wc-country__name { flex: 1; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.wc-country__dial { flex: 0 0 auto; color: var(--wc-color-icon-secondary); }
.wc-country__empty { padding: 12px; font-size: var(--wc-font-size-base); color: var(--wc-color-icon-secondary); }

/* -- Consent, privacy, send -- */

.wc-consent {
	display: flex;
	align-items: flex-start;
	gap: 8px;
	padding: 8px;
	border-radius: var(--wc-radius-small);
	background: var(--wc-color-surface-subtle);
}

.wc-consent input {
	flex: 0 0 auto;
	width: 16px;
	height: 16px;
	margin-top: 1px;
	accent-color: var(--wc-color-brand);
}

.wc-consent__text {
	font-size: 12px;
	line-height: 1.45;
	color: var(--wc-color-icon-secondary);
}

.wc-privacy {
	font-size: 12px;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-icon-secondary);
	text-decoration: underline;
}

.wc-privacy:hover { color: var(--wc-color-text); }

.wc-send {
	display: flex;
	align-items: center;
	justify-content: center;
	gap: 8px;
	padding: 10px 16px;
	border: none;
	border-radius: var(--wc-radius-small);
	background: var(--wc-color-brand);
	color: var(--wc-color-on-brand);
	font-size: var(--wc-font-size-base);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
}

.wc-send:disabled { opacity: 0.55; cursor: not-allowed; }
.wc-send:not(:disabled):hover { filter: brightness(0.94); }

.wc-send:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-focus);
}

.wc-send svg { width: 16px; height: 16px; }

.wc-form__banner {
	padding: 10px;
	border-radius: var(--wc-radius-small);
	background: var(--wc-color-surface-subtle);
	font-size: 12px;
	line-height: 1.45;
	color: var(--wc-color-critical);
}

.wc-hp {
	position: absolute;
	width: 1px;
	height: 1px;
	padding: 0;
	border: 0;
	opacity: 0;
	pointer-events: none;
}

/* -- Conversation -- */

.wc-thread { display: flex; flex-direction: column; gap: 12px; }

.wc-thread__list { display: flex; flex-direction: column; gap: 10px; }

.wc-earlier {
	align-self: center;
	padding: 6px 12px;
	border: 1px solid var(--wc-color-border);
	border-radius: 100px;
	background: var(--wc-color-surface);
	font-size: 12px;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-text);
}

.wc-earlier:hover { background: var(--wc-color-surface-hover); }
.wc-earlier:disabled { opacity: 0.55; cursor: not-allowed; }

.wc-earlier:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-focus);
}

.wc-day {
	align-self: center;
	padding: 2px 10px;
	border-radius: 100px;
	background: var(--wc-color-surface-subtle);
	font-size: 11px;
	font-weight: 600;
	line-height: 1.6;
	color: var(--wc-color-icon-secondary);
}

/* A system line -- a session ending, for instance -- is narration, not a party in the conversation,
   so it reads as centred text rather than as anyone's bubble. */
.wc-note {
	align-self: center;
	max-width: 90%;
	font-size: 12px;
	line-height: 1.45;
	color: var(--wc-color-icon-secondary);
	text-align: center;
}

.wc-msg { display: flex; flex-direction: column; gap: 2px; max-width: 85%; }

/* The visitor's own words sit on the right in the contractor's brand colour; the contractor answers
   on the left, with their avatar, exactly as every messenger a visitor has ever used. */
.wc-msg--out { align-self: flex-end; align-items: flex-end; }
.wc-msg--in { align-self: flex-start; align-items: flex-start; }

.wc-msg__row { display: flex; align-items: flex-end; gap: 8px; }

.wc-msg__bubble {
	padding: 10px 12px;
	border-radius: var(--wc-radius-base);
	font-size: var(--wc-font-size-base);
	line-height: 1.45;
	white-space: pre-wrap;
	word-break: break-word;
}

.wc-msg--out .wc-msg__bubble {
	background: var(--wc-color-brand);
	color: var(--wc-color-on-brand);
}

.wc-msg--in .wc-msg__bubble {
	background: var(--wc-color-surface-subtle);
	color: var(--wc-color-text);
}

.wc-msg--sending .wc-msg__bubble { opacity: 0.65; }

.wc-msg__meta {
	font-size: 11px;
	line-height: 1.45;
	color: var(--wc-color-icon-secondary);
}

.wc-msg--in .wc-msg__meta { padding-left: 40px; }

.wc-msg__retry {
	padding: 0;
	border: none;
	background: none;
	font-size: 11px;
	line-height: 1.45;
	color: var(--wc-color-critical);
	text-decoration: underline;
}

.wc-msg__retry:focus-visible {
	outline: transparent;
	border-radius: var(--wc-radius-small);
	box-shadow: var(--wc-shadow-focus);
}

.wc-thread__banner {
	align-self: center;
	padding: 8px 10px;
	border-radius: var(--wc-radius-small);
	background: var(--wc-color-surface-subtle);
	font-size: 12px;
	line-height: 1.45;
	color: var(--wc-color-critical);
	text-align: center;
}

/* -- Composer -- */

.wc-composer {
	display: flex;
	align-items: flex-end;
	gap: 8px;
	flex: 0 0 auto;
	padding: 10px var(--wc-space-base);
	border-top: 1px solid var(--wc-color-border);
	background: var(--wc-color-surface);
}

.wc-composer__input {
	flex: 1;
	max-height: 120px;
	padding: 10px 12px;
	border: 1px solid var(--wc-color-border);
	border-radius: var(--wc-radius-large);
	background: var(--wc-color-surface);
	font-size: var(--wc-font-size-base);
	line-height: 1.45;
	color: var(--wc-color-text);
	resize: none;
	overflow-y: auto;
}

.wc-composer__input::placeholder { color: var(--wc-color-placeholder); }

.wc-composer__input:focus-visible {
	outline: transparent;
	border-color: var(--wc-color-brand);
	box-shadow: 0 0 0 1px var(--wc-color-brand);
}

.wc-composer__send {
	display: grid;
	place-items: center;
	flex: 0 0 auto;
	width: 40px;
	height: 40px;
	border: none;
	border-radius: 100%;
	background: var(--wc-color-brand);
	color: var(--wc-color-on-brand);
}

.wc-composer__send:disabled { opacity: 0.55; cursor: not-allowed; }
.wc-composer__send:not(:disabled):hover { filter: brightness(0.94); }

.wc-composer__send:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-focus);
}

.wc-composer__send svg { width: 18px; height: 18px; }

/* -- Ended session -- */

.wc-ended {
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 8px;
	flex: 0 0 auto;
	padding: 12px var(--wc-space-base);
	border-top: 1px solid var(--wc-color-border);
	background: var(--wc-color-surface-subtle);
	text-align: center;
}

.wc-ended__text {
	font-size: 12px;
	line-height: 1.45;
	color: var(--wc-color-icon-secondary);
}

.wc-ended__restart {
	padding: 8px 14px;
	border: 1px solid var(--wc-color-border);
	border-radius: var(--wc-radius-small);
	background: var(--wc-color-surface);
	font-size: var(--wc-font-size-base);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-text);
}

.wc-ended__restart:hover { background: var(--wc-color-surface-hover); }

.wc-ended__restart:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-focus);
}

.wc-skeleton { display: flex; flex-direction: column; gap: 10px; }

.wc-skeleton__bar {
	border-radius: var(--wc-radius-base);
	background: var(--wc-color-surface-subtle);
}

.wc-empty { text-align: center; }

.wc-empty__title {
	font-size: var(--wc-font-size-large);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-heading);
}

.wc-empty__description {
	margin-top: 8px;
	font-size: var(--wc-font-size-base);
	line-height: 1.5;
	color: var(--wc-color-text);
}

@media (max-width: 480px) {
	.wc-panel {
		inset: 0;
		width: 100%;
		height: 100%;
		border-radius: 0;
	}
}

@media (prefers-reduced-motion: reduce) {
	.wc-launcher { transition: none; }
	.wc-teaser { animation: none; }
}
`;
	}

	// -- Icons ----------------------------------------------------------------------------------
	// Tabler outline, inlined: the widget cannot reach the app's icon pipeline from a host page.

	const messageIcon = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 20l1.3 -3.9c-2.324 -3.437 -1.426 -7.872 2.1 -10.374c3.526 -2.501 8.59 -2.296 11.845 .48c3.255 2.777 3.695 7.266 1.029 10.501c-2.666 3.235 -7.615 4.215 -11.574 2.293l-4.7 1" /></svg>`;
	const closeIcon = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 6l-12 12" /><path d="M6 6l12 12" /></svg>`;
	const caretIcon = `<svg class="wc-phone__caret" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6l6 -6" /></svg>`;
	const sendIcon = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 14l11 -11" /><path d="M21 3l-6.5 18a.55 .55 0 0 1 -1 0l-3.5 -7l-7 -3.5a.55 .55 0 0 1 0 -1l18 -6.5" /></svg>`;

	// -- Helpers --------------------------------------------------------------------------------

	// Matches `initials()` in `src/lib/collaboration/format.ts` so the widget's avatar reads the
	// same as the organization's avatar everywhere else in the product.
	function initials(name: string) {
		const parts = name.trim().split(/\s+/).filter(Boolean);
		if (parts.length === 0) return '?';
		if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
		return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
	}

	function element<K extends keyof HTMLElementTagNameMap>(
		tag: K,
		className: string
	): HTMLElementTagNameMap[K] {
		const el = document.createElement(tag);
		el.className = className;
		return el;
	}

	function avatar(size: 'base' | 'medium', businessName: string) {
		const el = element('span', `wc-avatar wc-avatar--${size}`);
		el.setAttribute('aria-hidden', 'true');
		el.textContent = initials(businessName);
		return el;
	}

	function readTeaserDismissed(widgetId: string) {
		try {
			return localStorage.getItem(teaserDismissedKey(widgetId)) === '1';
		} catch {
			// A private window or blocked storage just means the teaser shows again next visit.
			return false;
		}
	}

	function dismissTeaser() {
		if (!config) return;
		teaserDismissed = true;
		try {
			localStorage.setItem(teaserDismissedKey(config.widgetId), '1');
		} catch {
			// Best-effort remember.
		}
		render();
	}

	// -- Identity form: data ----------------------------------------------------------------------

	// Country names come from the browser's own Intl data and flags from the two regional-indicator
	// code points, so the widget ships no country table at all -- only libphonenumber's dial codes.
	let regionNames: Intl.DisplayNames | null = null;
	function countryName(code: string) {
		try {
			regionNames ??= new Intl.DisplayNames(undefined, { type: 'region' });
			return regionNames.of(code) ?? code;
		} catch {
			return code;
		}
	}

	function countryFlag(code: string) {
		return String.fromCodePoint(
			...[...code].map((letter) => 0x1f1e6 + letter.toUpperCase().charCodeAt(0) - 65)
		);
	}

	// Built on first use -- after the phone module has loaded -- and then kept: it is ~250 Intl
	// lookups plus a sort, and the picker can be opened many times in one visit.
	let countries: { code: string; name: string; dial: string }[] | null = null;
	function countryList() {
		const loaded = phone;
		if (!loaded) return [];
		countries ??= loaded
			.getCountries()
			.map((code) => ({
				code,
				name: countryName(code),
				dial: `+${loaded.getCountryCallingCode(code)}`
			}))
			.sort((a, b) => a.name.localeCompare(b.name));
		return countries;
	}

	// A suggestion, never a decision -- the visitor can always change it (contract § Visitor identity).
	// The browser's locale is read locally; no IP lookup and no third-party call.
	function suggestedCountry(): CountryCode {
		const supported = new Set<string>(phone?.getCountries() ?? []);
		for (const locale of navigator.languages ?? [navigator.language]) {
			const region = new Intl.Locale(locale).maximize().region;
			if (region && supported.has(region)) return region as CountryCode;
		}
		return 'US';
	}

	function newIdempotencyKey() {
		if (crypto.randomUUID) return crypto.randomUUID();
		return `wc-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
	}

	function emptyDraft(): IdentityDraft {
		return {
			name: '',
			country: suggestedCountry(),
			phone: '',
			email: '',
			message: '',
			// Checked by default, exactly as HighLevel's is: this is service consent for the channel the
			// visitor themselves just offered, not a marketing opt-in.
			consent: true,
			idempotencyKey: newIdempotencyKey()
		};
	}

	function readDraft(widgetId: string): IdentityDraft {
		const fresh = emptyDraft();
		try {
			const stored = localStorage.getItem(draftKey(widgetId));
			if (!stored) return fresh;
			const parsed = JSON.parse(stored) as Partial<IdentityDraft>;
			return {
				name: typeof parsed.name === 'string' ? parsed.name : '',
				country: (parsed.country as CountryCode) || fresh.country,
				phone: typeof parsed.phone === 'string' ? parsed.phone : '',
				email: typeof parsed.email === 'string' ? parsed.email : '',
				message: typeof parsed.message === 'string' ? parsed.message : '',
				consent: parsed.consent !== false,
				// Reusing the stored key is the point: if the previous attempt committed but its answer
				// never reached the browser, retrying with the same key replays it instead of paying for
				// a second conversation.
				idempotencyKey: parsed.idempotencyKey || fresh.idempotencyKey
			};
		} catch {
			return fresh;
		}
	}

	function saveDraft() {
		if (!config || !draft) return;
		try {
			localStorage.setItem(draftKey(config.widgetId), JSON.stringify(draft));
		} catch {
			// Private window or blocked storage: the draft simply does not survive a reload.
		}
	}

	function clearDraft() {
		if (!config) return;
		try {
			localStorage.removeItem(draftKey(config.widgetId));
		} catch {
			// Nothing to do.
		}
	}

	// Landing page, referrer and campaign parameters, captured at submit. Bounded to well under the
	// route's 20-key / 512-character ceiling so a long marketing URL can never fail the whole send.
	function attribution() {
		const captured: Record<string, string> = {};
		const clip = (value: string) => value.slice(0, 512);
		captured.landing_page = clip(location.href);
		if (document.referrer) captured.referrer = clip(document.referrer);
		const params = new URLSearchParams(location.search);
		for (const key of [
			'utm_source',
			'utm_medium',
			'utm_campaign',
			'utm_term',
			'utm_content',
			'gclid',
			'fbclid'
		]) {
			const value = params.get(key);
			if (value) captured[key] = clip(value);
		}
		return captured;
	}

	// -- Identity form: validation ------------------------------------------------------------------

	const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

	function phoneE164(current: IdentityDraft) {
		const parsed = phone?.parsePhoneNumberFromString(current.phone, current.country);
		return parsed?.isValid() ? parsed.number : null;
	}

	// Which identifiers this widget insists on. `either` needs one of the two, and once the visitor
	// starts filling one in, that is the one that has to be valid.
	function requiredIdentifiers(current: IdentityDraft) {
		const requirement = config?.contactRequirement ?? 'either';
		if (requirement === 'phone') return { phone: true, email: false };
		if (requirement === 'email') return { phone: false, email: true };
		return { phone: !current.email.trim(), email: !current.phone.trim() };
	}

	// "Invalid value" is HighLevel's literal wording, kept deliberately: the visitor is on a
	// contractor's marketing site, and a public form must not explain what shapes it accepts.
	function validate(current: IdentityDraft) {
		const needed = requiredIdentifiers(current);
		const errors: Partial<Record<keyof IdentityDraft, string>> = {};

		// Two characters, not one: `clients.display_name` refuses a single character, so a one-letter
		// name would be accepted here and then fail on the server.
		if (current.name.trim().length < 2) errors.name = 'Invalid value';
		if (!current.message.trim()) errors.message = 'Invalid value';
		if (current.phone.trim() ? !phoneE164(current) : needed.phone) errors.phone = 'Invalid value';
		if (current.email.trim() ? !emailPattern.test(current.email.trim()) : needed.email)
			errors.email = 'Invalid value';

		return errors;
	}

	// -- Rendering ------------------------------------------------------------------------------

	function renderLauncher(widget: WidgetPublicConfig) {
		const button = element('button', `wc-launcher wc-launcher--${widget.launcherPosition}`);
		button.type = 'button';
		button.setAttribute('aria-label', `Open chat with ${widget.businessName}`);
		button.innerHTML = messageIcon;
		// The form's phone field needs a module we deliberately did not ship up front. Hovering the
		// launcher is the earliest honest signal that someone means to open it, so the download starts
		// there and is usually finished before the click lands.
		button.addEventListener('pointerenter', prefetchPhone, { once: true });
		button.addEventListener('focus', prefetchPhone, { once: true });
		button.addEventListener('click', () => {
			panelOpen = true;
			render();
		});
		return button;
	}

	function renderTeaser(widget: WidgetPublicConfig, text: string) {
		// A button, not a div with a click handler: the whole teaser is one activatable thing, so
		// the browser gives us Enter/Space and the right role for free.
		const teaser = element('button', `wc-teaser wc-teaser--${widget.launcherPosition}`);
		teaser.type = 'button';
		teaser.addEventListener('pointerenter', prefetchPhone, { once: true });
		teaser.addEventListener('focus', prefetchPhone, { once: true });
		teaser.addEventListener('click', () => {
			panelOpen = true;
			render();
		});

		const message = element('span', 'wc-teaser__text');
		message.textContent = text;

		const dismiss = element('span', 'wc-teaser__dismiss');
		dismiss.setAttribute('role', 'button');
		dismiss.setAttribute('tabindex', '0');
		dismiss.setAttribute('aria-label', 'Dismiss');
		dismiss.innerHTML = closeIcon;
		// Nested inside the teaser button, so a real <button> would be invalid HTML -- this stays a
		// span carrying the button role, and stops the click from opening the panel it sits on.
		dismiss.addEventListener('click', (event) => {
			event.stopPropagation();
			dismissTeaser();
		});
		dismiss.addEventListener('keydown', (event) => {
			if (event.key !== 'Enter' && event.key !== ' ') return;
			event.preventDefault();
			event.stopPropagation();
			dismissTeaser();
		});

		teaser.append(avatar('medium', widget.businessName), message, dismiss);
		return teaser;
	}

	function prefetchPhone() {
		void loadPhone();
	}

	// Shown only when a click beat the download -- the panel opens immediately either way, and swaps
	// this for the real form as soon as the module lands.
	function renderFormSkeleton() {
		const skeleton = element('div', 'wc-skeleton');
		skeleton.setAttribute('aria-hidden', 'true');
		for (const height of [40, 40, 40, 64, 44]) {
			const bar = element('div', 'wc-skeleton__bar');
			bar.style.height = `${height}px`;
			skeleton.appendChild(bar);
		}
		return skeleton;
	}

	function renderEmptyState(title: string, description?: string) {
		const empty = element('div', 'wc-empty');
		const heading = element('p', 'wc-empty__title');
		heading.textContent = title;
		empty.appendChild(heading);
		if (description) {
			const text = element('p', 'wc-empty__description');
			text.textContent = description;
			empty.appendChild(text);
		}
		return empty;
	}

	// -- Identity form: DOM -------------------------------------------------------------------------
	//
	// The form is built once and then mutated in place. Re-rendering it per keystroke, the way the
	// shell re-renders the launcher, would throw away the caret position and the open country list on
	// every character typed.

	type FieldRefs = {
		wrapper: HTMLDivElement;
		error: HTMLParagraphElement;
	};

	const fieldRefs = new Map<keyof IdentityDraft, FieldRefs>();
	let sendButton: HTMLButtonElement | null = null;
	let bannerNode: HTMLParagraphElement | null = null;
	let phoneInput: HTMLInputElement | null = null;
	let countryButton: HTMLButtonElement | null = null;
	let countryPopup: HTMLDivElement | null = null;

	function field(name: keyof IdentityDraft, control: HTMLElement, extraClass = '') {
		const wrapper = element('div', `wc-field ${extraClass}`.trim());
		const error = element('p', 'wc-field__error');
		error.hidden = true;
		wrapper.append(control, error);
		fieldRefs.set(name, { wrapper, error });
		return wrapper;
	}

	function textInput(placeholder: string, type = 'text') {
		const input = element('input', 'wc-input');
		input.type = type;
		input.placeholder = placeholder;
		input.setAttribute('aria-label', placeholder);
		input.autocomplete = 'off';
		return input;
	}

	function syncForm() {
		if (!draft) return;
		const errors = validate(draft);

		for (const [name, refs] of fieldRefs) {
			const message = touched.has(name) ? errors[name] : undefined;
			refs.error.textContent = message ?? '';
			refs.error.hidden = !message;
			refs.wrapper.classList.toggle('wc-field--invalid', Boolean(message));
		}

		if (sendButton) sendButton.disabled = submitting || Object.keys(errors).length > 0;
		if (bannerNode) {
			bannerNode.textContent = formBanner;
			bannerNode.hidden = !formBanner;
		}
	}

	function setCountry(code: CountryCode) {
		if (!draft || !phone) return;
		draft.country = code;
		if (countryButton) {
			const flag = countryButton.querySelector('.wc-phone__flag');
			if (flag) flag.textContent = countryFlag(code);
			countryButton.setAttribute('aria-label', `Country: ${countryName(code)}`);
		}
		// Re-run the formatter so an already-typed number regroups for the new country.
		if (phoneInput) {
			phoneInput.value = new phone.AsYouType(code).input(draft.phone);
			draft.phone = phoneInput.value;
		}
		saveDraft();
		syncForm();
	}

	function closeCountryPopup() {
		countryPopup?.remove();
		countryPopup = null;
		countryButton?.setAttribute('aria-expanded', 'false');
	}

	function openCountryPopup(anchor: HTMLElement) {
		if (countryPopup) {
			closeCountryPopup();
			return;
		}
		const popup = element('div', 'wc-country');
		const search = element('input', 'wc-country__search');
		search.type = 'search';
		search.placeholder = 'Search countries';
		search.setAttribute('aria-label', 'Search countries');

		const list = element('ul', 'wc-country__list');

		function paint(query: string) {
			const needle = query.trim().toLowerCase();
			const matches = countryList().filter(
				(entry) =>
					!needle ||
					entry.name.toLowerCase().includes(needle) ||
					entry.code.toLowerCase().includes(needle) ||
					entry.dial.includes(needle)
			);
			list.replaceChildren();
			if (matches.length === 0) {
				const empty = element('li', 'wc-country__empty');
				empty.textContent = 'No matching country';
				list.appendChild(empty);
				return;
			}
			for (const entry of matches) {
				const item = document.createElement('li');
				const option = element('button', 'wc-country__option');
				option.type = 'button';
				const flag = element('span', 'wc-phone__flag');
				flag.textContent = countryFlag(entry.code);
				const name = element('span', 'wc-country__name');
				name.textContent = entry.name;
				const dial = element('span', 'wc-country__dial');
				dial.textContent = entry.dial;
				option.append(flag, name, dial);
				option.addEventListener('click', () => {
					setCountry(entry.code as CountryCode);
					closeCountryPopup();
					phoneInput?.focus();
				});
				item.appendChild(option);
				list.appendChild(item);
			}
		}

		search.addEventListener('input', () => paint(search.value));
		popup.addEventListener('keydown', (event) => {
			if (event.key !== 'Escape') return;
			event.stopPropagation();
			closeCountryPopup();
			countryButton?.focus();
		});

		paint('');
		popup.append(search, list);
		anchor.appendChild(popup);
		countryPopup = popup;
		countryButton?.setAttribute('aria-expanded', 'true');
		search.focus();

		// Listening on the shadow root, not the document: a click inside a shadow tree is retargeted to
		// the host element by the time it reaches the page, so a document-level listener could not tell
		// "inside the picker" from "outside" it.
		const onOutside = (event: Event) => {
			if (event.composedPath().includes(anchor)) return;
			closeCountryPopup();
			shadow?.removeEventListener('mousedown', onOutside);
		};
		shadow?.addEventListener('mousedown', onOutside);
	}

	function buildPhoneField() {
		const shell = element('div', 'wc-phone');

		countryButton = element('button', 'wc-phone__country');
		countryButton.type = 'button';
		countryButton.setAttribute('aria-haspopup', 'listbox');
		countryButton.setAttribute('aria-expanded', 'false');
		const flag = element('span', 'wc-phone__flag');
		flag.textContent = countryFlag(draft!.country);
		countryButton.append(flag);
		countryButton.insertAdjacentHTML('beforeend', caretIcon);
		countryButton.setAttribute('aria-label', `Country: ${countryName(draft!.country)}`);
		countryButton.addEventListener('click', () => openCountryPopup(shell));

		phoneInput = textInput('Phone', 'tel');
		phoneInput.autocomplete = 'tel';
		phoneInput.value = new phone!.AsYouType(draft!.country).input(draft!.phone);
		phoneInput.addEventListener('input', () => {
			if (!draft || !phoneInput || !phone) return;
			// A visitor who types their own international prefix has told us their country -- honour it
			// rather than reformatting their number into the suggested one.
			const typed = phoneInput.value;
			if (typed.trim().startsWith('+')) {
				const detected = new phone.AsYouType().input(typed);
				const parsed = phone.parsePhoneNumberFromString(typed);
				phoneInput.value = detected;
				if (parsed?.country && parsed.country !== draft.country) {
					draft.country = parsed.country;
					const currentFlag = countryButton?.querySelector('.wc-phone__flag');
					if (currentFlag) currentFlag.textContent = countryFlag(parsed.country);
					countryButton?.setAttribute('aria-label', `Country: ${countryName(parsed.country)}`);
				}
			} else {
				phoneInput.value = new phone.AsYouType(draft.country).input(typed);
			}
			draft.phone = phoneInput.value;
			saveDraft();
			syncForm();
		});
		phoneInput.addEventListener('blur', () => {
			touched.add('phone');
			syncForm();
		});

		shell.append(countryButton, phoneInput);
		return field('phone', shell);
	}

	function buildForm(widget: WidgetPublicConfig) {
		const form = document.createElement('form');
		form.className = 'wc-form';
		form.noValidate = true;

		const name = textInput('Name');
		// `name`, not `given-name`: one field holding the whole name is what the browser autofills here.
		name.autocomplete = 'name';
		name.value = draft!.name;
		name.addEventListener('input', () => {
			draft!.name = name.value;
			saveDraft();
			syncForm();
		});
		name.addEventListener('blur', () => {
			touched.add('name');
			syncForm();
		});

		const email = textInput('E-mail', 'email');
		email.autocomplete = 'email';
		email.value = draft!.email;
		email.addEventListener('input', () => {
			draft!.email = email.value;
			saveDraft();
			syncForm();
		});
		email.addEventListener('blur', () => {
			touched.add('email');
			syncForm();
		});

		const message = element('textarea', 'wc-textarea');
		message.placeholder = 'I want to know more';
		message.setAttribute('aria-label', 'Message');
		message.maxLength = 5000;
		message.value = draft!.message;
		message.addEventListener('input', () => {
			draft!.message = message.value;
			saveDraft();
			syncForm();
		});
		message.addEventListener('blur', () => {
			touched.add('message');
			syncForm();
		});

		// Honeypot: off-screen, unlabelled and never focusable, so only a script fills it in. The route
		// answers a filled one with the same silent refusal a bad token gets.
		const honeypot = element('input', 'wc-hp');
		honeypot.type = 'text';
		honeypot.name = 'company_website';
		honeypot.tabIndex = -1;
		honeypot.autocomplete = 'off';
		honeypot.setAttribute('aria-hidden', 'true');

		const consent = element('label', 'wc-consent');
		const consentBox = document.createElement('input');
		consentBox.type = 'checkbox';
		consentBox.checked = draft!.consent;
		consentBox.addEventListener('change', () => {
			draft!.consent = consentBox.checked;
			saveDraft();
		});
		const consentText = element('span', 'wc-consent__text');
		consentText.textContent =
			'By submitting you agree to receive SMS or e-mails for the provided channel. Rates may be applied.';
		consent.append(consentBox, consentText);

		bannerNode = element('p', 'wc-form__banner');
		bannerNode.hidden = true;
		bannerNode.setAttribute('role', 'alert');

		sendButton = element('button', 'wc-send');
		sendButton.type = 'submit';
		sendButton.innerHTML = `<span>Send</span>${sendIcon}`;

		form.append(
			field('name', name),
			buildPhoneField(),
			field('email', email),
			field('message', message),
			honeypot,
			consent
		);

		if (widget.privacyPolicyUrl) {
			const privacy = element('a', 'wc-privacy');
			privacy.href = widget.privacyPolicyUrl;
			privacy.target = '_blank';
			privacy.rel = 'noopener noreferrer';
			privacy.textContent = 'Privacy policy';
			form.appendChild(privacy);
		}

		form.append(bannerNode, sendButton);

		form.addEventListener('submit', (event) => {
			event.preventDefault();
			void submitFirstMessage();
		});

		syncForm();
		return form;
	}

	// -- Conversation: stored session ---------------------------------------------------------------

	function readSession(widgetId: string): SessionRecord | null {
		try {
			const stored = localStorage.getItem(sessionKey(widgetId));
			if (!stored) return null;
			const parsed = JSON.parse(stored) as Partial<SessionRecord>;
			if (typeof parsed.sessionId !== 'string' || typeof parsed.sessionToken !== 'string') {
				return null;
			}
			return { sessionId: parsed.sessionId, sessionToken: parsed.sessionToken };
		} catch {
			// A private window, blocked storage, or something else's key under our name. Either way the
			// visitor simply starts a new conversation; the old one is safe on the server.
			return null;
		}
	}

	function writeSession(widgetId: string, record: SessionRecord) {
		try {
			localStorage.setItem(sessionKey(widgetId), JSON.stringify(record));
		} catch {
			// Without storage the session cannot be restored after a reload; the conversation itself is
			// already safely accepted server-side.
		}
	}

	function forgetSession(widgetId: string) {
		try {
			localStorage.removeItem(sessionKey(widgetId));
			localStorage.removeItem(composerKey(widgetId));
		} catch {
			// Nothing to do.
		}
	}

	function readComposerDraft(widgetId: string) {
		try {
			return localStorage.getItem(composerKey(widgetId)) ?? '';
		} catch {
			return '';
		}
	}

	function saveComposerDraft(widgetId: string, text: string) {
		try {
			if (text) localStorage.setItem(composerKey(widgetId), text);
			else localStorage.removeItem(composerKey(widgetId));
		} catch {
			// The draft simply does not survive a reload.
		}
	}

	// -- Conversation: the message list ---------------------------------------------------------------

	function messageOrder(a: ChatMessage, b: ChatMessage) {
		if (a.created_at === b.created_at) return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
		return a.created_at < b.created_at ? -1 : 1;
	}

	// The single door every transport comes through -- restore, poll, socket, and the visitor's own
	// send. Returns whether anything actually changed, so a poll that finds nothing new repaints
	// nothing.
	function absorb(incoming: ChatMessage[]) {
		let changed = false;
		for (const message of incoming) {
			if (!message || typeof message.id !== 'string' || seenIds.has(message.id)) continue;
			seenIds.add(message.id);
			messages.push(message);
			changed = true;

			// The visitor's own message coming back from the server: the optimistic bubble it replaces
			// is matched by body, because a pending message has no id to match on until this arrives.
			if (message.direction === 'inbound') {
				const index = pending.findIndex((item) => item.body === message.body);
				if (index !== -1) pending.splice(index, 1);
			}
		}
		if (changed) messages.sort(messageOrder);
		return changed;
	}

	function dayLabel(value: string) {
		const date = new Date(value);
		const today = new Date();
		const yesterday = new Date(today);
		yesterday.setDate(today.getDate() - 1);
		const same = (a: Date, b: Date) => a.toDateString() === b.toDateString();
		if (same(date, today)) return 'Today';
		if (same(date, yesterday)) return 'Yesterday';
		return date.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
	}

	function timeLabel(value: string) {
		return new Date(value).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
	}

	function renderMessage(message: ChatMessage, businessName: string) {
		// A system line narrates the conversation rather than speaking in it.
		if (message.sender_type === 'system') {
			const note = element('p', 'wc-note');
			note.textContent = message.body;
			return note;
		}

		const outbound = message.direction === 'outbound';
		const row = element('div', `wc-msg wc-msg--${outbound ? 'in' : 'out'}`);

		const line = element('div', 'wc-msg__row');
		if (outbound) line.appendChild(avatar('base', businessName));
		const bubble = element('div', 'wc-msg__bubble');
		bubble.textContent = message.body;
		line.appendChild(bubble);

		const meta = element('p', 'wc-msg__meta');
		// Who is speaking is never left ambiguous: a reply carries the contractor's name, and an
		// automated one says so rather than passing as a person.
		const speaker =
			message.sender_type === 'automation' ? `${businessName} · Automated` : businessName;
		meta.textContent = outbound
			? `${speaker} · ${timeLabel(message.created_at)}`
			: timeLabel(message.created_at);

		row.append(line, meta);
		return row;
	}

	function renderPending(item: PendingMessage) {
		const row = element(
			'div',
			`wc-msg wc-msg--out ${item.status === 'sending' ? 'wc-msg--sending' : ''}`.trim()
		);
		const line = element('div', 'wc-msg__row');
		const bubble = element('div', 'wc-msg__bubble');
		bubble.textContent = item.body;
		line.appendChild(bubble);
		row.appendChild(line);

		if (item.status === 'failed') {
			const retry = element('button', 'wc-msg__retry');
			retry.type = 'button';
			retry.textContent = 'Not sent — tap to retry';
			retry.addEventListener('click', () => void deliver(item));
			row.appendChild(retry);
		} else {
			const meta = element('p', 'wc-msg__meta');
			meta.textContent = 'Sending…';
			row.appendChild(meta);
		}
		return row;
	}

	function nearBottom() {
		if (!scrollNode) return true;
		return scrollNode.scrollHeight - scrollNode.scrollTop - scrollNode.clientHeight < 60;
	}

	function scrollToBottom() {
		if (scrollNode) scrollNode.scrollTop = scrollNode.scrollHeight;
	}

	// Redraws the whole list rather than diffing it. A page is at most 50 messages of plain text with
	// no inputs inside, so there is nothing to lose to a rebuild and nothing to get wrong in a diff.
	function paintThread(stick: boolean) {
		if (!listNode || !config) return;
		const wasAtBottom = stick || nearBottom();

		const nodes: Node[] = [];
		let lastDay = '';
		for (const message of messages) {
			const day = dayLabel(message.created_at);
			if (day !== lastDay) {
				const separator = element('span', 'wc-day');
				separator.textContent = day;
				nodes.push(separator);
				lastDay = day;
			}
			nodes.push(renderMessage(message, config.businessName));
		}
		for (const item of pending) nodes.push(renderPending(item));

		listNode.replaceChildren(...nodes);

		if (earlierButton) {
			earlierButton.hidden = !hasMoreHistory;
			earlierButton.disabled = historyLoading;
			earlierButton.textContent = historyLoading ? 'Loading…' : 'Load earlier messages';
		}
		if (bannerLine) {
			bannerLine.textContent = threadBanner;
			bannerLine.hidden = !threadBanner;
		}
		syncComposer();

		if (wasAtBottom) scrollToBottom();
	}

	// -- Conversation: reading ------------------------------------------------------------------------

	type MessagesResponse = {
		status?: string;
		closed_at?: string | null;
		messages?: ChatMessage[];
		has_more?: boolean;
	};

	async function fetchMessages(pageSize: number, cursor?: ChatMessage) {
		if (!session) return null;
		const query = new URLSearchParams({ token: widgetToken, page_size: String(pageSize) });
		if (cursor) {
			query.set('before_created_at', cursor.created_at);
			query.set('before_id', cursor.id);
		}
		const response = await fetch(`${appOrigin}/api/webchat/sessions/messages?${query.toString()}`, {
			credentials: 'omit',
			headers: { authorization: `Bearer ${session.sessionToken}` }
		});
		if (response.status === 429) return 'rate_limited' as const;
		if (response.status !== 200) return null;
		return (await response.json()) as MessagesResponse;
	}

	// The newest page. Used for the first paint of a restored session, for every poll, and for the
	// catch-up when a hidden tab comes back to the foreground.
	async function refreshLatest(pageSize = 30) {
		if (!session) return;
		try {
			const result = await fetchMessages(pageSize);
			if (result === 'rate_limited' || result === null || result.status !== 'ok') return;

			let changed = absorb(result.messages ?? []);
			const closed = Boolean(result.closed_at);
			if (closed !== sessionClosed) {
				sessionClosed = closed;
				changed = true;
				// The composer and the ended block are siblings of the thread, so this one is a full
				// re-render rather than a repaint of the list.
				render();
				return;
			}
			// `has_more` describes the page that was asked for, so it is trusted on the first read and
			// left alone by later polls, which never look past the newest page.
			if (!historyLoaded) {
				hasMoreHistory = result.has_more ?? false;
				historyLoaded = true;
				changed = true;
			}
			if (threadBanner) {
				threadBanner = '';
				changed = true;
			}
			if (changed) paintThread(false);
		} catch {
			// Refused, offline, or this domain is no longer allowed -- all indistinguishable from here,
			// because a refusal is a 204 with no CORS header. The session is never discarded on that
			// evidence; the thread says it could not load and keeps trying.
			if (!historyLoaded && !threadBanner) {
				threadBanner = "We can't load this conversation right now.";
				paintThread(false);
			}
		}
	}

	async function loadEarlier() {
		if (!session || historyLoading || messages.length === 0) return;
		historyLoading = true;
		paintThread(false);
		const oldest = messages[0];
		try {
			const result = await fetchMessages(30, oldest);
			if (result && result !== 'rate_limited' && result.status === 'ok') {
				// Keyset paging: the anchor is the oldest row already held, never an offset.
				const before = scrollNode?.scrollHeight ?? 0;
				absorb(result.messages ?? []);
				hasMoreHistory = result.has_more ?? false;
				historyLoading = false;
				paintThread(false);
				// Keep the visitor looking at the message they were reading rather than jumping them to
				// the top of the page that was just inserted above it.
				if (scrollNode) scrollNode.scrollTop += scrollNode.scrollHeight - before;
				return;
			}
			threadBanner =
				result === 'rate_limited'
					? "That's a lot of requests at once. Please try again in a moment."
					: "We couldn't load older messages.";
		} catch {
			threadBanner = "We couldn't load older messages.";
		}
		historyLoading = false;
		paintThread(false);
	}

	// -- Conversation: sending ------------------------------------------------------------------------

	async function deliver(item: PendingMessage) {
		if (!session) return;
		item.status = 'sending';
		threadBanner = '';
		paintThread(false);

		try {
			const response = await fetch(
				`${appOrigin}/api/webchat/messages?token=${encodeURIComponent(widgetToken)}`,
				{
					method: 'POST',
					credentials: 'omit',
					headers: {
						'content-type': 'application/json',
						authorization: `Bearer ${session.sessionToken}`
					},
					body: JSON.stringify({ message: item.body, idempotency_key: item.idempotencyKey })
				}
			);

			if (response.status === 200) {
				const result = (await response.json()) as { message_id?: string };
				// Settle the bubble from the id the route just returned rather than waiting for the
				// socket or the poll to bring the same message back.
				if (result.message_id) {
					absorb([
						{
							id: result.message_id,
							direction: 'inbound',
							sender_type: 'visitor',
							body: item.body,
							created_at: new Date().toISOString()
						}
					]);
				}
				const index = pending.indexOf(item);
				if (index !== -1) pending.splice(index, 1);
				paintThread(true);
				return;
			}

			if (response.status === 409) {
				// The conversation was ended while this was in flight.
				item.status = 'failed';
				sessionClosed = true;
				threadBanner = 'This conversation has ended.';
				render();
				return;
			}

			item.status = 'failed';
			if (response.status === 429) {
				threadBanner = "That's a lot of messages at once. Please try again in a moment.";
			}
		} catch {
			item.status = 'failed';
		}
		paintThread(false);
	}

	function sendComposerMessage() {
		if (!config || !session || !composerInput) return;
		const body = composerInput.value.trim();
		if (!body || sessionClosed) return;

		const item: PendingMessage = {
			localId: newIdempotencyKey(),
			body,
			// Held for the life of the message: a retry replays the same key, so a send that actually
			// succeeded but whose answer never reached the browser can never post twice.
			idempotencyKey: newIdempotencyKey(),
			status: 'sending'
		};
		pending.push(item);
		composerInput.value = '';
		composerInput.style.height = 'auto';
		saveComposerDraft(config.widgetId, '');
		paintThread(true);
		void deliver(item);
	}

	function syncComposer() {
		if (composerSend && composerInput) {
			composerSend.disabled = sessionClosed || composerInput.value.trim().length === 0;
		}
	}

	function buildComposer(widget: WidgetPublicConfig) {
		const composer = element('div', 'wc-composer');

		composerInput = element('textarea', 'wc-composer__input');
		composerInput.rows = 1;
		composerInput.placeholder = 'Message…';
		composerInput.setAttribute('aria-label', 'Message');
		composerInput.maxLength = 5000;
		composerInput.value = readComposerDraft(widget.widgetId);

		const grow = () => {
			if (!composerInput) return;
			composerInput.style.height = 'auto';
			composerInput.style.height = `${Math.min(composerInput.scrollHeight, 120)}px`;
		};

		composerInput.addEventListener('input', () => {
			saveComposerDraft(widget.widgetId, composerInput?.value ?? '');
			grow();
			syncComposer();
		});
		composerInput.addEventListener('keydown', (event) => {
			// Enter sends, Shift+Enter starts a new line -- the convention every messenger uses. An
			// in-progress IME composition must never be cut off by it.
			if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
			event.preventDefault();
			sendComposerMessage();
		});

		composerSend = element('button', 'wc-composer__send');
		composerSend.type = 'button';
		composerSend.setAttribute('aria-label', 'Send message');
		composerSend.innerHTML = sendIcon;
		composerSend.addEventListener('click', () => sendComposerMessage());

		composer.append(composerInput, composerSend);
		queueMicrotask(grow);
		syncComposer();
		return composer;
	}

	function buildEnded(widget: WidgetPublicConfig) {
		const ended = element('div', 'wc-ended');
		const text = element('p', 'wc-ended__text');
		text.textContent = 'This conversation has ended.';
		const restart = element('button', 'wc-ended__restart');
		restart.type = 'button';
		restart.textContent = 'Start a new conversation';
		restart.addEventListener('click', () => {
			// A new session, not a reopened one: the contract is explicit that a later inquiry creates a
			// fresh session linked to the same Client. The transcript stays on the server either way.
			stopTransport();
			forgetSession(widget.widgetId);
			session = null;
			messages = [];
			seenIds.clear();
			pending = [];
			sessionClosed = false;
			historyLoaded = false;
			hasMoreHistory = false;
			threadBanner = '';
			threadNode = null;
			listNode = null;
			composerNode = null;
			composerInput = null;
			composerSend = null;
			draft = null;
			formNode = null;
			touched = new Set();
			accepted = false;
			render();
		});
		ended.append(text, restart);
		return ended;
	}

	function buildThread(widget: WidgetPublicConfig) {
		const thread = element('div', 'wc-thread');

		earlierButton = element('button', 'wc-earlier');
		earlierButton.type = 'button';
		earlierButton.textContent = 'Load earlier messages';
		earlierButton.hidden = true;
		earlierButton.addEventListener('click', () => void loadEarlier());

		// The contractor's own greeting stays at the top of the thread, the way a messenger keeps its
		// opening line rather than dropping it once the conversation starts.
		const intro = element('div', 'wc-intro');
		const introBubble = element('div', 'wc-intro__bubble');
		introBubble.textContent =
			widget.greetingText || 'Enter your question below and we will get right back to you.';
		intro.append(avatar('base', widget.businessName), introBubble);

		listNode = element('div', 'wc-thread__list');
		// Polite, not assertive: a reply arriving should be announced after whatever the visitor is
		// currently doing, never on top of it.
		listNode.setAttribute('role', 'log');
		listNode.setAttribute('aria-live', 'polite');
		listNode.setAttribute('aria-label', 'Conversation');

		bannerLine = element('p', 'wc-thread__banner');
		bannerLine.hidden = true;
		bannerLine.setAttribute('role', 'status');

		thread.append(earlierButton, intro, listNode, bannerLine);
		return thread;
	}

	// -- Conversation: transport ----------------------------------------------------------------------
	//
	// Two ways for a reply to arrive, one list to arrive into. The socket is primary -- a private
	// per-session channel the server grants by handing out its topic (WC4.4 Stage B) -- and the ~4s poll
	// is the fallback for every case where it is unavailable: a refused mint, a blocked websocket, a
	// corporate proxy, or the seconds before the channel has joined. Whichever gets there first wins;
	// `absorb()` throws the duplicate away.

	type RealtimeGrant = {
		channel_topic: string;
		expires_at: string;
		supabase_url: string;
		supabase_key: string;
	};

	async function mintGrant(): Promise<RealtimeGrant | null> {
		if (!session) return null;
		try {
			const response = await fetch(
				`${appOrigin}/api/webchat/sessions/realtime?token=${encodeURIComponent(widgetToken)}`,
				{
					method: 'POST',
					credentials: 'omit',
					headers: { authorization: `Bearer ${session.sessionToken}` }
				}
			);
			if (response.status !== 200) return null;
			const payload = (await response.json()) as Partial<RealtimeGrant>;
			if (!payload.channel_topic || !payload.expires_at || !payload.supabase_url) return null;
			return payload as RealtimeGrant;
		} catch {
			// No channel this time. The visitor never learns there was meant to be one -- the poll is
			// already carrying the conversation.
			return null;
		}
	}

	function dropChannel() {
		if (remintTimer) {
			clearTimeout(remintTimer);
			remintTimer = null;
		}
		// Let go of the references before tearing anything down. `unsubscribe()` drives the channel to
		// `CLOSED` synchronously, and the status callback that hears it calls straight back into here:
		// with `channel` still set, that second call unsubscribes the same channel again and recurses
		// until the stack gives out. Clearing first makes the re-entrant call a no-op.
		const closingChannel = channel;
		const closingSocket = socket;
		channel = null;
		socket = null;
		grantExpiresAt = 0;
		try {
			closingChannel?.unsubscribe();
			closingSocket?.disconnect();
		} catch {
			// Already gone.
		}
	}

	async function connectSocket() {
		if (!session || connecting || channel) return;
		connecting = true;
		try {
			const grant = await mintGrant();
			const module = grant ? await loadRealtime() : null;
			// The panel may have been closed, or the session ended, while the grant and the client were
			// in flight. Do not open a socket nobody is watching.
			if (!grant || !module || !session || !panelOpen) return;

			// The publishable key is the same one every signed-in page of this application already ships:
			// it names the project, never a person, and authorizes nothing on its own. The authorization
			// is the topic, which the database handed out against this session's own secret.
			socket = new module.RealtimeClient(`${grant.supabase_url}/realtime/v1`, {
				params: { apikey: grant.supabase_key }
			});
			await socket.setAuth(grant.supabase_key);

			grantExpiresAt = new Date(grant.expires_at).getTime();
			channel = socket.channel(grant.channel_topic, { config: { private: true } });
			channel.on(
				'broadcast',
				{ event: 'website_chat_message' },
				(message: { payload?: unknown }) => {
					const incoming = message?.payload as ChatMessage | undefined;
					if (!incoming?.id) return;
					if (absorb([incoming])) paintThread(false);
					// A system line is how the conversation narrates what happened to it -- being ended,
					// above all -- the way Intercom writes a `close` part into the thread rather than
					// inventing a second channel for it. The line itself carries no state, so the read
					// that owns `closed_at` settles what it meant. Without this the poll would be the
					// only thing that ever noticed, and the poll stands down while the socket is joined.
					if (incoming.sender_type === 'system') void refreshLatest();
				}
			);
			channel.subscribe((status: string) => {
				if (status === 'SUBSCRIBED') {
					// Anything said between the last read and the channel joining is not on the socket --
					// it was published before anyone was listening. One catch-up read closes that gap.
					void refreshLatest();
					return;
				}
				if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
					// Nothing to recover by hand: the poll is already running, and the next reconnect
					// attempt mints a fresh grant rather than reusing one that may have expired.
					dropChannel();
				}
			});

			// Re-mint a minute before the grant dies, so a long-open panel never falls silently off its
			// own channel. The mint reuses the live topic when it still has time left, so this is a
			// cheap call rather than a rotation.
			const lead = Math.max(grantExpiresAt - Date.now() - 60_000, 30_000);
			remintTimer = setTimeout(() => {
				dropChannel();
				void connectSocket();
			}, lead);
		} finally {
			connecting = false;
		}
	}

	function startTransport() {
		if (!session) return;
		void connectSocket();
		pollTimer ??= setInterval(() => {
			// A hidden tab reads nothing: every read is a rate-limit write on the server, and a
			// background tab has nobody looking at it. The visibility handler catches it up on return.
			if (document.hidden || !panelOpen) return;
			// While the socket is joined it is the transport; the poll only covers for it.
			if (channel && channel.state === 'joined') return;
			void refreshLatest(10);
		}, 4000);
	}

	function stopTransport() {
		dropChannel();
		if (pollTimer) {
			clearInterval(pollTimer);
			pollTimer = null;
		}
	}

	// Session end, tab close and navigation all have to let go of the socket, not just an unmount:
	// `pagehide` is the one event that fires for all three, including a bfcache freeze on mobile.
	function bindLifecycleListeners() {
		if (listenersBound) return;
		listenersBound = true;

		window.addEventListener('pagehide', () => stopTransport());
		// Coming back is `startTransport`, not `connectSocket`: `pagehide` cleared the poll timer as well
		// as the socket, and a page restored from bfcache never re-renders the panel that started them.
		// Reconnecting only the socket would leave the visitor with no fallback at all -- precisely when
		// the socket is the half that might not come back. `startTransport` is idempotent.
		window.addEventListener('pageshow', (event) => {
			if (!event.persisted || !panelOpen || !session) return;
			void refreshLatest();
			startTransport();
		});
		document.addEventListener('visibilitychange', () => {
			if (document.hidden || !panelOpen || !session) return;
			void refreshLatest();
			startTransport();
		});
	}

	async function submitFirstMessage() {
		if (!config || !draft || submitting) return;

		// Everything counts as touched from here on, so a send attempt shows every outstanding problem
		// at once instead of one field at a time.
		touched = new Set(Object.keys(draft) as (keyof IdentityDraft)[]);
		if (Object.keys(validate(draft)).length > 0) {
			syncForm();
			return;
		}

		submitting = true;
		formBanner = '';
		syncForm();

		const e164 = phoneE164(draft);
		const payload = {
			idempotency_key: draft.idempotencyKey,
			name: draft.name.trim(),
			...(e164 ? { phone: e164 } : {}),
			...(draft.email.trim() ? { email: draft.email.trim() } : {}),
			message: draft.message.trim(),
			consent_transactional_sms: draft.consent,
			attribution: attribution()
		};

		try {
			const response = await fetch(
				`${appOrigin}/api/webchat/sessions?token=${encodeURIComponent(widgetToken)}`,
				{
					method: 'POST',
					credentials: 'omit',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(payload)
				}
			);

			if (response.status === 200) {
				const result = (await response.json()) as { session_id?: string; session_token?: string };
				if (!result.session_id || !result.session_token) {
					formBanner = "Your message couldn't be sent. Please try again.";
					return;
				}
				session = { sessionId: result.session_id, sessionToken: result.session_token };
				writeSession(config.widgetId, session);

				// The message that was just accepted, shown as a pending bubble so the panel has
				// something in it the instant the form goes away. The first read replaces it with the
				// real row, matched by body, exactly as an ordinary send is.
				pending = [
					{
						localId: newIdempotencyKey(),
						body: draft.message.trim(),
						idempotencyKey: draft.idempotencyKey,
						status: 'sending'
					}
				];
				accepted = true;
				clearDraft();
				render();
				return;
			}

			// Every readable refusal, in the route's own words. A 204 carries no CORS header at all, so
			// the page cannot even read its status -- it lands here as an opaque response.
			if (response.status === 429) {
				formBanner = "That's a lot of messages at once. Please try again in a moment.";
			} else if (response.status === 409 || response.status === 503) {
				formBanner = "We can't take messages right now. Please try again later.";
			} else {
				formBanner = "Your message couldn't be sent. Please try again.";
			}
		} catch {
			formBanner = "Your message couldn't be sent. Please check your connection and try again.";
		} finally {
			submitting = false;
			syncForm();
		}
	}

	function renderPanel(widget: WidgetPublicConfig) {
		const panel = element('section', `wc-panel wc-panel--${widget.launcherPosition}`);
		panel.setAttribute('role', 'dialog');
		panel.setAttribute('aria-label', `${widget.businessName} chat`);

		const header = element('header', 'wc-panel__header');
		const title = element('h2', 'wc-panel__title');
		title.textContent = widget.businessName;

		const close = element('button', 'wc-panel__close');
		close.type = 'button';
		close.setAttribute('aria-label', 'Close chat');
		close.innerHTML = closeIcon;
		close.addEventListener('click', () => {
			panelOpen = false;
			closeCountryPopup();
			// A closed panel keeps its session but holds no socket: the connection exists to feed a
			// thread somebody is looking at, and reopening reads the conversation back anyway.
			stopTransport();
			render();
		});

		header.append(avatar('base', widget.businessName), title, close);

		const body = element('div', 'wc-panel__body');

		const footer = element('footer', 'wc-panel__footer');
		const credit = document.createElement('em');
		credit.textContent = widget.businessName;
		footer.append(document.createTextNode('Powered by '), credit);

		if (widget.status !== 'live') {
			body.appendChild(
				renderEmptyState(
					widget.status === 'draft'
						? "This chat isn't set up yet."
						: "This chat isn't available right now."
				)
			);
			panel.append(header, body);
			return panel;
		}

		// An accepted conversation replaces the form entirely: thread in the scrolling body, composer
		// pinned beneath it, and the footer below both.
		if (session) {
			threadNode ??= buildThread(widget);
			body.appendChild(threadNode);
			scrollNode = body;
			panel.append(header, body);
			panel.appendChild(sessionClosed ? buildEnded(widget) : buildComposer(widget));
			panel.appendChild(footer);

			paintThread(true);
			if (!historyLoaded) void refreshLatest();
			startTransport();
			return panel;
		}

		// One intro line above the fields, as HighLevel's form has, using the contractor's own greeting.
		const intro = element('div', 'wc-intro');
		const introBubble = element('div', 'wc-intro__bubble');
		introBubble.textContent =
			widget.greetingText || 'Enter your question below and we will get right back to you.';
		intro.append(avatar('base', widget.businessName), introBubble);
		body.append(intro);

		if (!phone) {
			body.appendChild(renderFormSkeleton());
			void loadPhone().then(() => {
				// A visitor who closed the panel while it loaded gets the form on their next open, not a
				// panel that reopens itself under them.
				if (panelOpen) render();
			});
		} else {
			// The draft is read here rather than at mount: it needs a suggested country, which needs the
			// module that only exists once the panel has been opened.
			draft ??= readDraft(widget.widgetId);
			formNode ??= buildForm(widget);
			body.appendChild(formNode);
		}

		panel.append(header, body, footer);
		return panel;
	}

	function render() {
		if (!shadow || !stage || !config) return;
		stage.replaceChildren();

		const showTeaser =
			!panelOpen && !teaserDismissed && config.status === 'live' && !!config.teaserText;

		if (showTeaser) stage.appendChild(renderTeaser(config, config.teaserText as string));
		stage.appendChild(panelOpen ? renderPanel(config) : renderLauncher(config));
	}

	function mount(widget: WidgetPublicConfig) {
		const host = document.createElement('div');
		host.id = 'ucrm-website-chat';
		// `all: initial` here too, inline, so the host page's own `div {}` rules cannot give this
		// element a size, a margin or a background before the shadow boundary even applies. The
		// host itself is a zero-size anchor; everything inside it is position: fixed.
		host.style.cssText = 'all: initial; position: fixed; width: 0; height: 0; z-index: 2147483000;';
		document.body.appendChild(host);

		shadow = host.attachShadow({ mode: 'open' });
		const sheet = document.createElement('style');
		sheet.textContent = styles(widget.brandColor || '#049a54');
		stage = document.createElement('div');
		shadow.append(sheet, stage);

		teaserDismissed = readTeaserDismissed(widget.widgetId);
		// Session restore: a recognized browser comes back into its own conversation rather than into an
		// empty form, across refreshes, navigation and browser restarts.
		session = readSession(widget.widgetId);
		bindLifecycleListeners();
		render();
	}

	async function fetchConfig(): Promise<WidgetPublicConfig | null> {
		try {
			const response = await fetch(
				`${appOrigin}/api/webchat/config?token=${encodeURIComponent(widgetToken)}`,
				// No custom headers and no credentials: this stays a CORS "simple request", so there
				// is no preflight round trip before the widget can appear.
				{ credentials: 'omit' }
			);
			if (response.status !== 200) return null;
			const payload = (await response.json()) as { config?: WidgetPublicConfig };
			return payload.config ?? null;
		} catch {
			// Refused, rate-limited, offline, or this domain is not on the widget's allowlist. The
			// widget simply never appears -- a contractor's website must never show a broken box
			// because our end had a bad day.
			return null;
		}
	}

	async function start() {
		const widget = await fetchConfig();
		if (!widget) return;
		config = widget;

		if (document.body) mount(widget);
		else document.addEventListener('DOMContentLoaded', () => mount(widget));
	}

	void start();
})();
