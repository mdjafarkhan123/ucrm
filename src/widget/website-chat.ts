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
import { SERVICE_SMS_CONSENT_LABEL, serviceSmsConsentDescription } from '../lib/forms/sms-consent';

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
	logoPath?: string | null;
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
	// A field only starts showing its mistake once the visitor has actually left it or tried to
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
	// from. Keep these in step with `src/lib/styles/_variables.scss` when a token changes. The look
	// follows the approved Pencil board (Batch 66, Welcome card) and `layout.md` § Website chat widget.
	//
	// Light palette only, on purpose: the widget is organization-branded furniture on someone
	// else's website, so it should not flip to a dark theme because the visitor's OS is dark while
	// the page around it stays light.

	function styles(brandColor: string) {
		return `
:host {
	all: initial;

	--wc-color-brand: ${brandColor};
	--wc-color-brand--deep: color-mix(in srgb, var(--wc-color-brand) 78%, #000000);
	--wc-color-brand--glow: color-mix(in srgb, var(--wc-color-brand) 35%, transparent);
	--wc-color-on-brand: #ffffff;
	--wc-color-on-brand--soft: rgba(255, 255, 255, 0.82);
	--wc-color-on-brand--well: rgba(255, 255, 255, 0.18);
	--wc-color-on-brand--key: rgba(255, 255, 255, 0.15);
	--wc-color-surface: #ffffff;
	--wc-color-surface-hover: #f9f8f6;
	--wc-color-surface-subtle: #f9f8f6;
	--wc-color-border: #dadfe2;
	--wc-color-border-interactive: #dadfe2;
	--wc-color-heading: #032b3a;
	--wc-color-text: #233d48;
	--wc-color-text-secondary: #49646f;
	--wc-color-icon: #233d48;
	--wc-color-icon-secondary: #84979f;
	--wc-color-inactive: #49646f;
	--wc-color-inactive-surface: #eef1f2;
	--wc-color-focus: #84979f;
	--wc-color-critical: #d24232;
	--wc-color-critical-surface: #faecea;
	--wc-color-critical-on-surface: #7a0c00;
	--wc-color-placeholder: #49646f;
	--wc-color-skeleton: #eef1f2;

	--wc-font-size-smaller: 12px;
	--wc-font-size-base: 14px;
	--wc-font-size-large: 16px;
	--wc-font-size-largest: 24px;
	--wc-line-height-base: 1.25;
	--wc-line-height-text: 1.45;
	--wc-shadow-panel: 0px 20px 48px 0px rgba(3, 43, 58, 0.18), 0px 2px 6px 0px rgba(3, 43, 58, 0.08);
	--wc-shadow-card: 0px 4px 14px 0px rgba(3, 43, 58, 0.08);
	--wc-shadow-pop: 0px 12px 28px 0px rgba(3, 43, 58, 0.16);
	--wc-shadow-teaser: 0px 12px 30px 0px rgba(3, 43, 58, 0.12), 0px 0px 0px 1px var(--wc-color-border);
	--wc-shadow-key: 0px 2px 6px 0px rgba(3, 43, 58, 0.12), 0px 0px 0px 1px var(--wc-color-border);
	--wc-shadow-launcher: 0px 8px 20px 0px var(--wc-color-brand--glow), 0px 2px 4px 0px rgba(0, 0, 0, 0.1);
	--wc-shadow-focus: 0px 0px 0px 2px var(--wc-color-surface), 0px 0px 0px 4px var(--wc-color-focus);
	--wc-timing-base: 0.2s;
}

*, *::before, *::after {
	box-sizing: border-box;
	margin: 0;
	padding: 0;
	font-family: Inter, ui-sans-serif, system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
	-webkit-font-smoothing: antialiased;
}

button { font: inherit; cursor: pointer; }
svg { display: block; flex: 0 0 auto; }
[hidden] { display: none !important; }

/* -- Logo mark: the Branding logo, or the business's initials on its colour -- */

.wc-logo {
	display: inline-flex;
	flex: 0 0 auto;
	align-items: center;
	justify-content: center;
	background: var(--wc-color-brand);
	color: var(--wc-color-on-brand);
	font-weight: 700;
	overflow: hidden;
}

.wc-logo--image { background: var(--wc-color-surface); }
.wc-logo img { width: 100%; height: 100%; object-fit: contain; }

.wc-logo--24 { width: 24px; height: 24px; border-radius: 7px; font-size: 10px; }
.wc-logo--32 { width: 32px; height: 32px; border-radius: 8px; font-size: var(--wc-font-size-smaller); }
.wc-logo--40 { width: 40px; height: 40px; border-radius: 12px; font-size: var(--wc-font-size-base); }

/* -- Launcher -- */

.wc-launcher {
	position: fixed;
	bottom: 24px;
	display: inline-flex;
	align-items: center;
	gap: 10px;
	height: 52px;
	padding: 0 22px 0 18px;
	border: none;
	border-radius: 999px;
	background: var(--wc-color-brand);
	color: var(--wc-color-on-brand);
	font-size: var(--wc-font-size-large);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
	box-shadow: var(--wc-shadow-launcher);
	transition: transform var(--wc-timing-base) ease-out, filter var(--wc-timing-base) ease-out;
}

.wc-launcher:hover { transform: translateY(-1px); filter: brightness(1.05); }
.wc-launcher:active { transform: translateY(0); filter: brightness(0.95); }

.wc-launcher:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-launcher), var(--wc-shadow-focus);
}

.wc-launcher svg { width: 22px; height: 22px; }

.wc-launcher--open {
	justify-content: center;
	width: 52px;
	padding: 0;
}

.wc-launcher--bottom_right { right: 24px; }
.wc-launcher--bottom_left { left: 24px; }

/* -- Teaser: a speech bubble pointing at the launcher -- */

.wc-teaser {
	position: fixed;
	bottom: 96px;
	display: flex;
	flex-direction: column;
	align-items: flex-end;
	gap: 12px;
	width: 300px;
	animation: wc-teaser-in var(--wc-timing-base) ease-out;
}

.wc-teaser--bottom_right { right: 24px; }
.wc-teaser--bottom_left { left: 24px; align-items: flex-start; }

.wc-teaser__bubble {
	display: flex;
	flex-direction: column;
	gap: 8px;
	width: 100%;
	padding: 14px 16px 16px;
	border: none;
	border-radius: 20px 20px 4px 20px;
	background: var(--wc-color-surface);
	box-shadow: var(--wc-shadow-teaser);
	text-align: left;
	transition: transform var(--wc-timing-base) ease-out;
}

.wc-teaser--bottom_left .wc-teaser__bubble { border-radius: 20px 20px 20px 4px; }
.wc-teaser__bubble:hover { transform: translateY(-1px); }

.wc-teaser__bubble:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-teaser), var(--wc-shadow-focus);
}

.wc-teaser__who {
	display: flex;
	align-items: center;
	gap: 8px;
	font-size: var(--wc-font-size-smaller);
	font-weight: 700;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-heading);
}

.wc-teaser__text {
	font-size: var(--wc-font-size-large);
	font-weight: 500;
	line-height: 1.4;
	color: var(--wc-color-heading);
}

.wc-teaser__dismiss {
	display: grid;
	place-items: center;
	width: 28px;
	height: 28px;
	border: none;
	border-radius: 999px;
	background: var(--wc-color-surface);
	color: var(--wc-color-icon);
	box-shadow: var(--wc-shadow-key);
}

.wc-teaser__dismiss:hover { background: var(--wc-color-surface-hover); }

.wc-teaser__dismiss:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-key), var(--wc-shadow-focus);
}

.wc-teaser__dismiss svg { width: 14px; height: 14px; }

@keyframes wc-teaser-in {
	from { opacity: 0; transform: translateY(8px); }
	to { opacity: 1; transform: translateY(0); }
}

/* -- Panel -- */

.wc-panel {
	position: fixed;
	bottom: 92px;
	display: flex;
	flex-direction: column;
	width: min(392px, calc(100vw - 48px));
	max-height: min(720px, calc(100vh - 116px));
	border: 1px solid var(--wc-color-border);
	border-radius: 24px;
	background: var(--wc-color-surface-subtle);
	box-shadow: var(--wc-shadow-panel);
	overflow: hidden;
	animation: wc-panel-in var(--wc-timing-base) ease-out;
}

.wc-panel--chat { height: min(680px, calc(100vh - 116px)); background: var(--wc-color-surface); }

.wc-panel--bottom_right { right: 24px; }
.wc-panel--bottom_left { left: 24px; }

@keyframes wc-panel-in {
	from { opacity: 0; transform: translateY(12px); }
	to { opacity: 1; transform: translateY(0); }
}

.wc-panel__scroll {
	flex: 1;
	min-height: 0;
	overflow-y: auto;
}

.wc-close {
	display: grid;
	place-items: center;
	flex: 0 0 auto;
	width: 32px;
	height: 32px;
	border: none;
	border-radius: 10px;
	background: var(--wc-color-on-brand--key);
	color: var(--wc-color-on-brand);
	transition: background var(--wc-timing-base) ease-out;
}

.wc-close:hover { background: rgba(255, 255, 255, 0.25); }

.wc-close:focus-visible {
	outline: transparent;
	box-shadow: 0 0 0 2px var(--wc-color-on-brand);
}

.wc-close svg { width: 16px; height: 16px; }

/* -- Welcome top -- */

.wc-hero {
	display: flex;
	flex-direction: column;
	padding: 20px 20px 69px 24px;
	background:
		radial-gradient(120% 160% at 95% 0%, rgba(255, 255, 255, 0.2), rgba(255, 255, 255, 0) 60%),
		linear-gradient(200deg, var(--wc-color-brand), var(--wc-color-brand--deep));
	color: var(--wc-color-on-brand);
}

.wc-hero__top {
	display: flex;
	align-items: flex-start;
	justify-content: space-between;
}

.wc-hero__tile {
	display: grid;
	place-items: center;
	width: 44px;
	height: 44px;
	border-radius: 12px;
	background: var(--wc-color-surface);
}

.wc-hero__words {
	display: flex;
	flex-direction: column;
	gap: 6px;
	padding: 18px 4px 0 0;
}

.wc-hero__business {
	font-size: var(--wc-font-size-base);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-on-brand--soft);
}

.wc-hero__greeting {
	font-size: var(--wc-font-size-largest);
	font-weight: 700;
	line-height: 1.2;
	letter-spacing: -0.5px;
	color: var(--wc-color-on-brand);
	overflow-wrap: anywhere;
}

/* -- Card -- */

.wc-card-space { margin-top: -49px; padding: 0 12px; }

.wc-card {
	display: flex;
	flex-direction: column;
	gap: 14px;
	padding: 18px;
	border: 1px solid var(--wc-color-border);
	border-radius: 20px;
	background: var(--wc-color-surface);
	box-shadow: var(--wc-shadow-card);
}

.wc-group { display: flex; flex-direction: column; gap: 6px; }

.wc-group__head {
	display: flex;
	align-items: baseline;
	justify-content: space-between;
	gap: 8px;
}

.wc-group__label {
	font-size: var(--wc-font-size-base);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-heading);
}

.wc-group__hint {
	font-size: var(--wc-font-size-smaller);
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-text-secondary);
}

.wc-box {
	position: relative;
	border: 1px solid var(--wc-color-border-interactive);
	border-radius: 10px;
	background: var(--wc-color-surface);
	transition: border-color var(--wc-timing-base) ease-out, box-shadow var(--wc-timing-base) ease-out;
}

.wc-box:focus-within {
	border-color: var(--wc-color-brand);
	box-shadow: 0 0 0 1px var(--wc-color-brand);
}

/* Declared after the focus rule on purpose: a box that is both focused and wrong must stay red. Focus
   tells the visitor where they are; the mistake is the more important of the two to keep visible. */
.wc-box--invalid,
.wc-box--invalid:focus-within {
	border-color: var(--wc-color-critical);
	box-shadow: 0 0 0 0.5px var(--wc-color-critical);
}

.wc-textarea {
	display: block;
	width: 100%;
	height: 84px;
	padding: 10px 12px;
	border: none;
	border-radius: 10px;
	background: transparent;
	font-size: var(--wc-font-size-base);
	line-height: var(--wc-line-height-text);
	color: var(--wc-color-heading);
	resize: none;
}

.wc-row {
	display: flex;
	align-items: center;
	gap: 10px;
	min-height: 44px;
	padding: 0 12px;
}

.wc-row + .wc-row { border-top: 1px solid var(--wc-color-border); }
.wc-row--phone { padding-left: 6px; }
.wc-row > svg { width: 16px; height: 16px; color: var(--wc-color-icon-secondary); }

.wc-row__alert { display: none; color: var(--wc-color-critical); }
.wc-row--invalid .wc-row__alert { display: block; }
.wc-row__alert svg { width: 16px; height: 16px; }

.wc-input {
	flex: 1;
	min-width: 0;
	height: 42px;
	border: none;
	background: transparent;
	font-size: var(--wc-font-size-base);
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-heading);
}

.wc-input::placeholder,
.wc-textarea::placeholder,
.wc-composer__input::placeholder { color: var(--wc-color-placeholder); opacity: 1; }

.wc-input:focus-visible,
.wc-textarea:focus-visible { outline: transparent; }

.wc-errors { display: flex; flex-direction: column; gap: 2px; }

.wc-error {
	display: flex;
	align-items: center;
	gap: 6px;
	font-size: var(--wc-font-size-smaller);
	line-height: var(--wc-line-height-text);
	color: var(--wc-color-critical);
}

.wc-error svg { width: 12px; height: 12px; }

/* -- Phone country -- */

.wc-country-button {
	display: inline-flex;
	align-items: center;
	gap: 4px;
	flex: 0 0 auto;
	height: 32px;
	padding: 0 6px 0 8px;
	border: none;
	border-radius: 8px;
	background: var(--wc-color-surface-subtle);
	font-size: var(--wc-font-size-base);
	font-weight: 600;
	color: var(--wc-color-heading);
}

.wc-country-button:hover { filter: brightness(0.97); }

.wc-country-button[aria-expanded='true'] {
	box-shadow: inset 0 0 0 1.5px var(--wc-color-brand);
}

.wc-country-button:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-focus);
}

.wc-country-button svg { width: 14px; height: 14px; color: var(--wc-color-icon-secondary); }

/* Emoji flags render as flags on macOS, iOS and Android and fall back to the country's two
   letters on Windows, which still reads correctly beside the dial code. */
.wc-flag { font-size: var(--wc-font-size-large); line-height: 1; letter-spacing: -1px; font-weight: 400; }

.wc-country {
	position: absolute;
	z-index: 2;
	top: 92px;
	left: -1px;
	display: flex;
	flex-direction: column;
	gap: 4px;
	width: min(260px, 100%);
	padding: 6px;
	border-radius: 12px;
	background: var(--wc-color-surface);
	box-shadow: var(--wc-shadow-pop), 0 0 0 1px var(--wc-color-border);
}

.wc-country__search {
	display: flex;
	align-items: center;
	gap: 8px;
	height: 36px;
	padding: 0 10px;
	border: 1px solid var(--wc-color-border-interactive);
	border-radius: 8px;
}

.wc-country__search:focus-within { border-color: var(--wc-color-brand); }
.wc-country__search svg { width: 14px; height: 14px; color: var(--wc-color-icon-secondary); }

.wc-country__search input {
	flex: 1;
	min-width: 0;
	border: none;
	background: transparent;
	font-size: var(--wc-font-size-base);
	color: var(--wc-color-heading);
}

.wc-country__search input:focus-visible { outline: transparent; }
.wc-country__search input::-webkit-search-cancel-button { -webkit-appearance: none; }

.wc-country__list {
	max-height: 216px;
	overflow-y: auto;
	list-style: none;
}

.wc-country__option {
	display: flex;
	align-items: center;
	gap: 10px;
	width: 100%;
	height: 36px;
	padding: 0 10px;
	border: none;
	border-radius: 8px;
	background: none;
	text-align: left;
	font-size: var(--wc-font-size-base);
	font-weight: 500;
	color: var(--wc-color-heading);
}

.wc-country__option:hover,
.wc-country__option:focus-visible,
.wc-country__option--chosen { outline: transparent; background: var(--wc-color-surface-hover); }

.wc-country__option--chosen .wc-country__name { font-weight: 600; }
.wc-country__name { flex: 1; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }

.wc-country__dial {
	flex: 0 0 auto;
	font-size: var(--wc-font-size-smaller);
	font-weight: 600;
	color: var(--wc-color-text-secondary);
}

.wc-country__option svg { width: 14px; height: 14px; color: var(--wc-color-brand); }

.wc-country__empty {
	padding: 10px;
	font-size: var(--wc-font-size-base);
	color: var(--wc-color-text-secondary);
}

/* -- The "Text me" agreement -- */

.wc-consent {
	display: flex;
	align-items: flex-start;
	gap: 10px;
	padding: 12px;
	border-radius: 12px;
	background: var(--wc-color-surface-subtle);
	cursor: pointer;
}

.wc-consent input {
	flex: 0 0 auto;
	width: 18px;
	height: 18px;
	margin-top: 1px;
	accent-color: var(--wc-color-brand);
	cursor: pointer;
}

.wc-consent__words { display: flex; flex-direction: column; gap: 2px; }

.wc-consent__label {
	font-size: var(--wc-font-size-base);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-heading);
}

.wc-consent__text {
	font-size: var(--wc-font-size-smaller);
	line-height: var(--wc-line-height-text);
	color: var(--wc-color-text-secondary);
}

/* -- Couldn't send -- */

.wc-banner {
	display: flex;
	align-items: flex-start;
	gap: 8px;
	padding: 10px 12px;
	border: 1px solid color-mix(in srgb, var(--wc-color-critical) 30%, transparent);
	border-radius: 10px;
	background: var(--wc-color-critical-surface);
	font-size: var(--wc-font-size-base);
	font-weight: 500;
	line-height: var(--wc-line-height-text);
	color: var(--wc-color-critical-on-surface);
}

.wc-banner svg { width: 16px; height: 16px; margin-top: 2px; color: var(--wc-color-critical); }

/* -- Send -- */

.wc-send {
	display: flex;
	align-items: center;
	justify-content: space-between;
	gap: 8px;
	height: 48px;
	padding: 0 8px 0 20px;
	border: none;
	border-radius: 14px;
	background: var(--wc-color-brand);
	color: var(--wc-color-on-brand);
	font-size: var(--wc-font-size-large);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
	transition: filter var(--wc-timing-base) ease-out, opacity var(--wc-timing-base) ease-out;
}

.wc-send:not(:disabled):hover { filter: brightness(1.06); }
.wc-send:not(:disabled):active { filter: brightness(0.94); }
.wc-send:disabled { opacity: 0.45; cursor: not-allowed; }

.wc-send:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-focus);
}

.wc-send__well {
	display: grid;
	place-items: center;
	width: 32px;
	height: 32px;
	border-radius: 10px;
	background: var(--wc-color-on-brand--well);
}

.wc-send__well svg { width: 18px; height: 18px; }

.wc-send--sending,
.wc-send--sending:disabled { justify-content: center; gap: 10px; opacity: 0.85; cursor: progress; }

.wc-spinner {
	width: 18px;
	height: 18px;
	border: 2px solid rgba(255, 255, 255, 0.35);
	border-top-color: var(--wc-color-on-brand);
	border-radius: 999px;
	animation: wc-spin 0.8s linear infinite;
}

@keyframes wc-spin { to { transform: rotate(360deg); } }

.wc-hp {
	position: absolute;
	width: 1px;
	height: 1px;
	padding: 0;
	border: 0;
	opacity: 0;
	pointer-events: none;
}

/* -- Footer -- */

.wc-footer {
	display: flex;
	flex-wrap: wrap;
	align-items: center;
	justify-content: center;
	gap: 6px;
	flex: 0 0 auto;
	padding: 14px 16px;
	font-size: var(--wc-font-size-smaller);
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-text-secondary);
}

.wc-panel--chat .wc-footer { padding-top: 10px; }
.wc-footer svg { width: 12px; height: 12px; color: var(--wc-color-icon-secondary); }

/* The widget credits the contractor, never UCRM -- a contractor's customers see only the
   contractor (website-chat-behavior-contract.md). */
.wc-privacy {
	font-weight: 600;
	color: var(--wc-color-text);
	text-decoration: underline;
}

.wc-privacy:hover { color: var(--wc-color-heading); }

.wc-privacy:focus-visible {
	outline: transparent;
	border-radius: 4px;
	box-shadow: var(--wc-shadow-focus);
}

/* -- Loading and unavailable -- */

.wc-skeleton { display: flex; flex-direction: column; gap: 10px; }

.wc-skeleton__bar {
	border-radius: 10px;
	background: linear-gradient(90deg, var(--wc-color-skeleton) 25%, var(--wc-color-surface-subtle) 50%, var(--wc-color-skeleton) 75%);
	background-size: 200% 100%;
	animation: wc-shimmer 1.4s ease-in-out infinite;
}

@keyframes wc-shimmer {
	from { background-position: 100% 0; }
	to { background-position: -100% 0; }
}

.wc-empty {
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 12px;
	padding: 22px 0;
	text-align: center;
}

.wc-tile {
	display: grid;
	place-items: center;
	border: 1px solid var(--wc-color-border);
	border-radius: 12px;
	background: var(--wc-color-inactive-surface);
	color: var(--wc-color-inactive);
}

.wc-tile--48 { width: 48px; height: 48px; }
.wc-tile--48 svg { width: 24px; height: 24px; }
.wc-tile--40 { width: 40px; height: 40px; border-radius: 10px; }
.wc-tile--40 svg { width: 20px; height: 20px; }

.wc-empty__title {
	font-size: var(--wc-font-size-base);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-heading);
}

/* -- Conversation top -- */

.wc-chat-top {
	display: flex;
	align-items: center;
	gap: 12px;
	flex: 0 0 auto;
	padding: 14px 14px 14px 16px;
	border-bottom: 1px solid var(--wc-color-border);
	background: var(--wc-color-surface);
}

.wc-chat-top__who { display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0; }

.wc-chat-top__name {
	font-size: var(--wc-font-size-large);
	font-weight: 700;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-heading);
	overflow: hidden;
	white-space: nowrap;
	text-overflow: ellipsis;
}

.wc-chat-top__promise {
	font-size: var(--wc-font-size-smaller);
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-text-secondary);
}

.wc-chat-top .wc-close { background: var(--wc-color-surface-subtle); color: var(--wc-color-icon); }
.wc-chat-top .wc-close:hover { background: var(--wc-color-skeleton); }
.wc-chat-top .wc-close:focus-visible { box-shadow: var(--wc-shadow-focus); }

/* -- Conversation -- */

.wc-thread { display: flex; flex-direction: column; gap: 6px; padding: 14px 16px 16px; }
.wc-thread__list { display: flex; flex-direction: column; gap: 6px; }

.wc-earlier {
	display: inline-flex;
	align-items: center;
	gap: 6px;
	align-self: center;
	margin: 4px 0;
	padding: 2px 6px;
	border: none;
	border-radius: 6px;
	background: none;
	font-size: var(--wc-font-size-smaller);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-text);
}

.wc-earlier:hover { background: var(--wc-color-surface-hover); }
.wc-earlier:disabled { opacity: 0.55; cursor: progress; }
.wc-earlier svg { width: 14px; height: 14px; color: var(--wc-color-icon); }

.wc-earlier:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-focus);
}

.wc-day {
	align-self: center;
	padding: 4px 0;
	font-size: var(--wc-font-size-smaller);
	font-weight: 500;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-text-secondary);
}

/* A system line -- a session ending, for instance -- is narration, not a party in the conversation,
   so it reads as centred text rather than as anyone's bubble. */
.wc-note {
	align-self: center;
	max-width: 90%;
	padding: 4px 0;
	font-size: var(--wc-font-size-smaller);
	line-height: var(--wc-line-height-text);
	color: var(--wc-color-text-secondary);
	text-align: center;
}

.wc-run { display: flex; flex-direction: column; gap: 4px; padding: 4px 0; }
.wc-run--in { align-items: flex-start; }
.wc-run--out { align-items: flex-end; }

.wc-msg { display: flex; align-items: flex-end; gap: 8px; max-width: 100%; }
.wc-msg__space { width: 24px; flex: 0 0 auto; }

.wc-msg__bubble {
	max-width: 272px;
	padding: 10px 14px;
	font-size: var(--wc-font-size-base);
	line-height: var(--wc-line-height-text);
	white-space: pre-wrap;
	overflow-wrap: anywhere;
}

/* The visitor's own words sit on the right in the contractor's brand colour; the contractor answers
   on the left, beside its logo, exactly as every messenger a visitor has ever used. */
.wc-run--in .wc-msg__bubble {
	border-radius: 18px 18px 18px 6px;
	background: var(--wc-color-surface-subtle);
	color: var(--wc-color-heading);
}

.wc-run--out .wc-msg__bubble {
	border-radius: 18px 18px 6px 18px;
	background: var(--wc-color-brand);
	color: var(--wc-color-on-brand);
}

.wc-msg--sending .wc-msg__bubble { opacity: 0.65; }
.wc-msg > svg { width: 18px; height: 18px; color: var(--wc-color-critical); align-self: center; }

.wc-meta {
	font-size: var(--wc-font-size-smaller);
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-text-secondary);
}

.wc-run--in .wc-meta { padding-left: 32px; }

.wc-retry {
	padding: 0;
	border: none;
	background: none;
	font-size: var(--wc-font-size-smaller);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-critical);
}

.wc-retry span { text-decoration: underline; }

.wc-retry:focus-visible {
	outline: transparent;
	border-radius: 4px;
	box-shadow: var(--wc-shadow-focus);
}

.wc-thread__banner {
	align-self: center;
	padding: 8px 12px;
	border-radius: 10px;
	background: var(--wc-color-critical-surface);
	font-size: var(--wc-font-size-smaller);
	line-height: var(--wc-line-height-text);
	color: var(--wc-color-critical-on-surface);
	text-align: center;
}

/* -- Message box -- */

.wc-composer { flex: 0 0 auto; padding: 4px 12px; background: var(--wc-color-surface); }

.wc-composer__pill {
	display: flex;
	align-items: center;
	gap: 8px;
	min-height: 48px;
	padding: 6px 6px 6px 18px;
	border: 1px solid var(--wc-color-border-interactive);
	border-radius: 24px;
	background: var(--wc-color-surface);
}

.wc-composer__pill:focus-within {
	border-color: var(--wc-color-brand);
	box-shadow: 0 0 0 1px var(--wc-color-brand);
}

.wc-composer__input {
	flex: 1;
	max-height: 120px;
	padding: 2px 0;
	border: none;
	background: transparent;
	font-size: var(--wc-font-size-base);
	line-height: var(--wc-line-height-text);
	color: var(--wc-color-heading);
	resize: none;
	overflow-y: auto;
}

.wc-composer__input:focus-visible { outline: transparent; }

.wc-composer__send {
	display: grid;
	place-items: center;
	flex: 0 0 auto;
	align-self: flex-end;
	width: 36px;
	height: 36px;
	border: none;
	border-radius: 999px;
	background: var(--wc-color-brand);
	color: var(--wc-color-on-brand);
}

.wc-composer__send:disabled { opacity: 0.45; cursor: not-allowed; }
.wc-composer__send:not(:disabled):hover { filter: brightness(1.06); }

.wc-composer__send:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-focus);
}

.wc-composer__send svg { width: 18px; height: 18px; }

/* -- Ended -- */

.wc-ended {
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 12px;
	flex: 0 0 auto;
	margin: 4px 12px 0;
	padding: 18px;
	border-radius: 16px;
	background: var(--wc-color-surface-subtle);
	text-align: center;
}

.wc-ended__text {
	font-size: var(--wc-font-size-base);
	font-weight: 600;
	line-height: var(--wc-line-height-base);
	color: var(--wc-color-heading);
}

.wc-ended__restart {
	display: flex;
	align-items: center;
	justify-content: center;
	gap: 8px;
	width: 100%;
	height: 44px;
	border: none;
	border-radius: 12px;
	background: var(--wc-color-brand);
	color: var(--wc-color-on-brand);
	font-size: var(--wc-font-size-large);
	font-weight: 600;
	box-shadow: var(--wc-shadow-card);
}

.wc-ended__restart:hover { filter: brightness(1.06); }
.wc-ended__restart svg { width: 18px; height: 18px; }

.wc-ended__restart:focus-visible {
	outline: transparent;
	box-shadow: var(--wc-shadow-focus);
}

@media (max-width: 480px) {
	.wc-panel,
	.wc-panel--chat {
		inset: 0;
		width: 100%;
		height: 100%;
		max-height: none;
		border: none;
		border-radius: 0;
	}
}

@media (prefers-reduced-motion: reduce) {
	.wc-launcher,
	.wc-teaser__bubble { transition: none; }
	.wc-teaser,
	.wc-panel { animation: none; }
	.wc-skeleton__bar,
	.wc-spinner { animation-duration: 3s; }
}
`;
	}

	// -- Icons ----------------------------------------------------------------------------------
	// Tabler outline, inlined: the widget cannot reach the app's icon pipeline from a host page.

	function icon(paths: string) {
		return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
	}

	const messageIcon = icon(
		'<path d="M3 20l1.3 -3.9c-2.324 -3.437 -1.426 -7.872 2.1 -10.374c3.526 -2.501 8.59 -2.296 11.845 .48c3.255 2.777 3.695 7.266 1.029 10.501c-2.666 3.235 -7.615 4.215 -11.574 2.293l-4.7 1"/>'
	);
	const chevronDownIcon = icon('<path d="M6 9l6 6l6 -6"/>');
	const closeIcon = icon('<path d="M18 6l-12 12"/><path d="M6 6l12 12"/>');
	const userIcon = icon(
		'<path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/><path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>'
	);
	const mailIcon = icon(
		'<path d="M3 7a2 2 0 0 1 2 -2h14a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-10"/><path d="M3 7l9 6l9 -6"/>'
	);
	const checkIcon = icon('<path d="M5 12l5 5l10 -10"/>');
	const searchIcon = icon(
		'<path d="M3 10a7 7 0 1 0 14 0a7 7 0 1 0 -14 0"/><path d="M21 21l-6 -6"/>'
	);
	const alertIcon = icon(
		'<path d="M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0"/><path d="M12 8v4"/><path d="M12 16h.01"/>'
	);
	const arrowRightIcon = icon('<path d="M5 12l14 0"/><path d="M13 18l6 -6"/><path d="M13 6l6 6"/>');
	const arrowUpIcon = icon('<path d="M12 5l0 14"/><path d="M18 11l-6 -6"/><path d="M6 11l6 -6"/>');
	const lockIcon = icon(
		'<path d="M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-6"/><path d="M11 16a1 1 0 1 0 2 0a1 1 0 0 0 -2 0"/><path d="M8 11v-4a4 4 0 1 1 8 0v4"/>'
	);
	const endedIcon = icon(
		'<path d="M13.593 19.855a9.96 9.96 0 0 1 -5.893 -.855l-4.7 1l1.3 -3.9c-2.324 -3.437 -1.426 -7.872 2.1 -10.374c3.526 -2.501 8.59 -2.296 11.845 .48c2.128 1.816 3.053 4.363 2.693 6.813"/><path d="M22 22l-5 -5"/><path d="M17 22l5 -5"/>'
	);
	const newChatIcon = icon(
		'<path d="M12.007 19.98a9.869 9.869 0 0 1 -4.307 -.98l-4.7 1l1.3 -3.9c-2.324 -3.437 -1.426 -7.872 2.1 -10.374c3.526 -2.501 8.59 -2.296 11.845 .48c1.992 1.7 2.93 4.04 2.747 6.34"/><path d="M16 19h6"/><path d="M19 16v6"/>'
	);
	const unavailableIcon = icon(
		'<path d="M8.595 4.577c3.223 -1.176 7.025 -.61 9.65 1.63c2.982 2.543 3.601 6.523 1.636 9.66m-1.908 2.109c-2.787 2.19 -6.89 2.666 -10.273 1.024l-4.7 1l1.3 -3.9c-2.229 -3.296 -1.494 -7.511 1.68 -10.057"/><path d="M3 3l18 18"/>'
	);

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

	// The business's logo from Branding when it has one, its initials on its brand colour when it does not
	// -- or when the host page's own rules (a strict CSP, say) stop the picture from loading.
	function logoMark(size: 24 | 32 | 40, widget: WidgetPublicConfig) {
		const el = element('span', `wc-logo wc-logo--${size}`);
		el.setAttribute('aria-hidden', 'true');
		el.textContent = initials(widget.businessName);
		if (widget.logoPath) {
			const image = document.createElement('img');
			image.alt = '';
			image.decoding = 'async';
			image.src = `${appOrigin}${widget.logoPath}`;
			image.addEventListener('load', () => {
				el.classList.add('wc-logo--image');
				el.replaceChildren(image);
			});
		}
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
			// Unticked, as HighLevel's A2P-compliant widget and our own forms are: typing a phone number never
			// grants SMS consent by itself.
			consent: false,
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
				consent: parsed.consent === true,
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

	// Each mistake says how to fix it, in plain words (approved with Batch 66). It still never explains
	// which shapes the server accepts beyond what any visitor needs to know to get it right.
	function validate(current: IdentityDraft) {
		const needed = requiredIdentifiers(current);
		const errors: Partial<Record<keyof IdentityDraft, string>> = {};

		// Two characters, not one: `clients.display_name` refuses a single character, so a one-letter
		// name would be accepted here and then fail on the server.
		if (current.name.trim().length < 2) errors.name = 'Enter your full name.';
		if (!current.message.trim()) errors.message = 'Tell us what you need help with.';
		if (current.phone.trim()) {
			if (!phoneE164(current)) errors.phone = 'Enter the whole phone number, including the area code.';
		} else if (needed.phone) {
			errors.phone =
				config?.contactRequirement === 'either'
					? 'Add a phone number or an email so we can reply.'
					: 'Add a phone number so we can reply.';
		}
		if (current.email.trim()) {
			if (!emailPattern.test(current.email.trim())) errors.email = 'Enter an email like name@example.com.';
		} else if (needed.email && config?.contactRequirement !== 'either') {
			errors.email = 'Add an email so we can reply.';
		}

		return errors;
	}

	// -- Rendering ------------------------------------------------------------------------------

	function openPanel() {
		panelOpen = true;
		render();
	}

	function closePanel() {
		panelOpen = false;
		closeCountryPopup();
		// A closed panel keeps its session but holds no socket: the connection exists to feed a
		// thread somebody is looking at, and reopening reads the conversation back anyway.
		stopTransport();
		render();
	}

	// A "Message us" pill while closed; a round chevron that folds the panel away while open.
	function renderLauncher(widget: WidgetPublicConfig) {
		const button = element(
			'button',
			`wc-launcher wc-launcher--${widget.launcherPosition}${panelOpen ? ' wc-launcher--open' : ''}`
		);
		button.type = 'button';
		if (panelOpen) {
			button.setAttribute('aria-label', 'Close chat');
			button.innerHTML = chevronDownIcon;
			button.addEventListener('click', closePanel);
			return button;
		}
		button.setAttribute('aria-label', `Message ${widget.businessName}`);
		button.innerHTML = `${messageIcon}<span>Message us</span>`;
		// The form's phone field needs a module we deliberately did not ship up front. Hovering the
		// launcher is the earliest honest signal that someone means to open it, so the download starts
		// there and is usually finished before the click lands.
		button.addEventListener('pointerenter', prefetchPhone, { once: true });
		button.addEventListener('focus', prefetchPhone, { once: true });
		button.addEventListener('click', openPanel);
		return button;
	}

	function renderTeaser(widget: WidgetPublicConfig, text: string) {
		const teaser = element('div', `wc-teaser wc-teaser--${widget.launcherPosition}`);

		// Its own round key above the bubble, so it is a real button beside the bubble rather than one
		// nested inside it.
		const dismiss = element('button', 'wc-teaser__dismiss');
		dismiss.type = 'button';
		dismiss.setAttribute('aria-label', 'Dismiss');
		dismiss.innerHTML = closeIcon;
		dismiss.addEventListener('click', dismissTeaser);

		// A button, not a div with a click handler: the whole bubble is one activatable thing, so the
		// browser gives us Enter/Space and the right role for free.
		const bubble = element('button', 'wc-teaser__bubble');
		bubble.type = 'button';
		bubble.addEventListener('pointerenter', prefetchPhone, { once: true });
		bubble.addEventListener('focus', prefetchPhone, { once: true });
		bubble.addEventListener('click', openPanel);

		const who = element('span', 'wc-teaser__who');
		const name = document.createElement('span');
		name.textContent = widget.businessName;
		who.append(logoMark(24, widget), name);

		const message = element('span', 'wc-teaser__text');
		message.textContent = text;
		bubble.append(who, message);

		teaser.append(dismiss, bubble);
		return teaser;
	}

	function prefetchPhone() {
		void loadPhone();
	}

	function closeButton() {
		const close = element('button', 'wc-close');
		close.type = 'button';
		close.setAttribute('aria-label', 'Close chat');
		close.innerHTML = closeIcon;
		close.addEventListener('click', closePanel);
		return close;
	}

	// The brand-coloured welcome top: logo on a white tile, the close key, the business name and its
	// greeting as the big question. The card below overlaps its lower edge.
	function renderHero(widget: WidgetPublicConfig) {
		const hero = element('div', 'wc-hero');
		const top = element('div', 'wc-hero__top');
		const tile = element('span', 'wc-hero__tile');
		tile.appendChild(logoMark(32, widget));
		top.append(tile, closeButton());

		const words = element('div', 'wc-hero__words');
		const business = element('p', 'wc-hero__business');
		business.textContent = widget.businessName;
		const greeting = element('h2', 'wc-hero__greeting');
		greeting.textContent = widget.greetingText || 'Hi there! How can we help?';
		words.append(business, greeting);

		hero.append(top, words);
		return hero;
	}

	function renderFooter(widget: WidgetPublicConfig) {
		const footer = element('footer', 'wc-footer');
		if (widget.privacyPolicyUrl) {
			footer.insertAdjacentHTML('beforeend', lockIcon);
			const privacy = element('a', 'wc-privacy');
			privacy.href = widget.privacyPolicyUrl;
			privacy.target = '_blank';
			privacy.rel = 'noopener noreferrer';
			privacy.textContent = 'Privacy policy';
			const dot = document.createElement('span');
			dot.textContent = '·';
			dot.setAttribute('aria-hidden', 'true');
			footer.append(privacy, dot);
		}
		const credit = document.createElement('span');
		credit.textContent = `Powered by ${widget.businessName}`;
		footer.appendChild(credit);
		return footer;
	}

	// Shown only when a click beat the download -- the panel opens immediately either way, and swaps
	// this for the real form as soon as the module lands. Shaped like the card it stands in for.
	function renderFormSkeleton() {
		const skeleton = element('div', 'wc-skeleton');
		skeleton.setAttribute('aria-hidden', 'true');
		for (const [height, width] of [
			[14, '40%'],
			[84, '100%'],
			[14, '50%'],
			[132, '100%'],
			[48, '100%']
		] as const) {
			const bar = element('div', 'wc-skeleton__bar');
			bar.style.height = `${height}px`;
			bar.style.width = width;
			skeleton.appendChild(bar);
		}
		return skeleton;
	}

	function renderEmptyState(title: string) {
		const empty = element('div', 'wc-empty');
		const tile = element('span', 'wc-tile wc-tile--48');
		tile.innerHTML = unavailableIcon;
		const heading = element('p', 'wc-empty__title');
		heading.textContent = title;
		empty.append(tile, heading);
		return empty;
	}

	// -- Identity form: DOM -------------------------------------------------------------------------
	//
	// The form is built once and then mutated in place. Re-rendering it per keystroke, the way the
	// shell re-renders the launcher, would throw away the caret position and the open country list on
	// every character typed.

	let messageBox: HTMLDivElement | null = null;
	let messageErrors: HTMLDivElement | null = null;
	let contactBox: HTMLDivElement | null = null;
	let contactErrors: HTMLDivElement | null = null;
	const contactRows = new Map<keyof IdentityDraft, HTMLDivElement>();
	let sendButton: HTMLButtonElement | null = null;
	let sendShowsSending = false;
	let bannerNode: HTMLDivElement | null = null;
	let bannerText: HTMLSpanElement | null = null;
	let phoneInput: HTMLInputElement | null = null;
	let countryButton: HTMLButtonElement | null = null;
	let countryPopup: HTMLDivElement | null = null;
	let consentNode: HTMLLabelElement | null = null;

	function textInput(placeholder: string, label: string, type = 'text') {
		const input = element('input', 'wc-input');
		input.type = type;
		input.placeholder = placeholder;
		input.setAttribute('aria-label', label);
		input.autocomplete = 'off';
		return input;
	}

	// One row of the joined contact box: its icon, its input, and the alert mark a mistake shows.
	function contactRow(name: keyof IdentityDraft, lead: HTMLElement | string, input: HTMLInputElement) {
		const row = element('div', `wc-row${name === 'phone' ? ' wc-row--phone' : ''}`);
		if (typeof lead === 'string') row.insertAdjacentHTML('beforeend', lead);
		else row.appendChild(lead);
		const alert = element('span', 'wc-row__alert');
		alert.innerHTML = alertIcon;
		row.append(input, alert);
		contactRows.set(name, row);
		return row;
	}

	function paintErrors(container: HTMLDivElement | null, lines: (string | undefined)[]) {
		if (!container) return;
		const shown = lines.filter((line): line is string => Boolean(line));
		container.replaceChildren(
			...shown.map((line) => {
				const error = element('p', 'wc-error');
				error.innerHTML = alertIcon;
				error.append(line);
				return error;
			})
		);
		container.hidden = shown.length === 0;
	}

	function paintSendButton() {
		if (!sendButton) return;
		if (submitting === sendShowsSending && sendButton.childElementCount > 0) return;
		sendShowsSending = submitting;
		sendButton.classList.toggle('wc-send--sending', submitting);
		sendButton.setAttribute('aria-busy', String(submitting));
		sendButton.innerHTML = submitting
			? '<span class="wc-spinner" aria-hidden="true"></span><span>Sending…</span>'
			: `<span>Send message</span><span class="wc-send__well">${arrowRightIcon}</span>`;
	}

	function syncForm() {
		if (!draft) return;
		const errors = validate(draft);
		const shown = (name: keyof IdentityDraft) => (touched.has(name) ? errors[name] : undefined);

		messageBox?.classList.toggle('wc-box--invalid', Boolean(shown('message')));
		paintErrors(messageErrors, [shown('message')]);

		const contact = (['name', 'phone', 'email'] as const).map((name) => {
			const message = shown(name);
			contactRows.get(name)?.classList.toggle('wc-row--invalid', Boolean(message));
			return message;
		});
		contactBox?.classList.toggle('wc-box--invalid', contact.some(Boolean));
		paintErrors(contactErrors, contact);

		// The service-SMS box only means something once there is a number to text.
		if (consentNode) consentNode.hidden = !draft.phone.trim();
		paintSendButton();
		if (sendButton) sendButton.disabled = submitting || Object.keys(errors).length > 0;
		if (bannerNode && bannerText) {
			bannerText.textContent = formBanner;
			bannerNode.hidden = !formBanner;
		}
	}

	function paintCountryButton(code: CountryCode) {
		if (!countryButton || !phone) return;
		const flag = element('span', 'wc-flag');
		flag.textContent = countryFlag(code);
		const dial = document.createElement('span');
		dial.textContent = `+${phone.getCountryCallingCode(code)}`;
		countryButton.replaceChildren(flag, dial);
		countryButton.insertAdjacentHTML('beforeend', chevronDownIcon);
		countryButton.setAttribute('aria-label', `Country: ${countryName(code)}`);
	}

	function setCountry(code: CountryCode) {
		if (!draft || !phone) return;
		draft.country = code;
		paintCountryButton(code);
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
		const searchBox = element('label', 'wc-country__search');
		searchBox.innerHTML = searchIcon;
		const search = document.createElement('input');
		search.type = 'search';
		search.placeholder = 'Search countries';
		search.setAttribute('aria-label', 'Search countries');
		searchBox.appendChild(search);

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
				const chosen = entry.code === draft?.country;
				const item = document.createElement('li');
				const option = element(
					'button',
					`wc-country__option${chosen ? ' wc-country__option--chosen' : ''}`
				);
				option.type = 'button';
				const flag = element('span', 'wc-flag');
				flag.textContent = countryFlag(entry.code);
				const name = element('span', 'wc-country__name');
				name.textContent = entry.name;
				const dial = element('span', 'wc-country__dial');
				dial.textContent = entry.dial;
				option.append(flag, name, dial);
				if (chosen) option.insertAdjacentHTML('beforeend', checkIcon);
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
		popup.append(searchBox, list);
		anchor.appendChild(popup);
		countryPopup = popup;
		countryButton?.setAttribute('aria-expanded', 'true');
		list.querySelector('.wc-country__option--chosen')?.scrollIntoView({ block: 'nearest' });
		search.focus();

		// Listening on the shadow root, not the document: a click inside a shadow tree is retargeted to
		// the host element by the time it reaches the page, so a document-level listener could not tell
		// "inside the picker" from "outside" it.
		const onOutside = (event: Event) => {
			if (event.composedPath().includes(popup) || event.composedPath().includes(countryButton!)) {
				return;
			}
			closeCountryPopup();
			shadow?.removeEventListener('mousedown', onOutside);
		};
		shadow?.addEventListener('mousedown', onOutside);
	}

	function buildPhoneRow(widget: WidgetPublicConfig) {
		countryButton = element('button', 'wc-country-button');
		countryButton.type = 'button';
		countryButton.setAttribute('aria-haspopup', 'listbox');
		countryButton.setAttribute('aria-expanded', 'false');
		paintCountryButton(draft!.country);
		countryButton.addEventListener('click', () => {
			if (contactBox) openCountryPopup(contactBox);
		});

		const optional = widget.contactRequirement === 'email';
		phoneInput = textInput(optional ? 'Phone (optional)' : 'Phone number', 'Phone', 'tel');
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
					paintCountryButton(parsed.country);
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

		return contactRow('phone', countryButton, phoneInput);
	}

	function replyHint(requirement: ContactRequirement) {
		if (requirement === 'phone') return 'Phone needed';
		if (requirement === 'email') return 'Email needed';
		return 'Phone or email';
	}

	function group(label: string, hint?: string) {
		const wrapper = element('div', 'wc-group');
		const head = element('div', 'wc-group__head');
		const title = element('span', 'wc-group__label');
		title.textContent = label;
		head.appendChild(title);
		if (hint) {
			const quiet = element('span', 'wc-group__hint');
			quiet.textContent = hint;
			head.appendChild(quiet);
		}
		wrapper.appendChild(head);
		return wrapper;
	}

	function buildForm(widget: WidgetPublicConfig) {
		const form = document.createElement('form');
		form.className = 'wc-card';
		form.noValidate = true;

		// Message first: what the visitor came to say, before who they are.
		const messageGroup = group('Your message');
		const message = element('textarea', 'wc-textarea');
		message.placeholder = 'What can we help you with?';
		message.setAttribute('aria-label', 'Your message');
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
		messageBox = element('div', 'wc-box');
		messageBox.appendChild(message);
		messageErrors = element('div', 'wc-errors');
		messageErrors.hidden = true;
		messageGroup.append(messageBox, messageErrors);

		const name = textInput('Your name', 'Your name');
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

		const emailRequired = widget.contactRequirement === 'email';
		const email = textInput(emailRequired ? 'Email' : 'Email (optional)', 'Email', 'email');
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

		const replyGroup = group('How should we reply?', replyHint(widget.contactRequirement));
		contactBox = element('div', 'wc-box');
		contactBox.append(
			contactRow('name', userIcon, name),
			buildPhoneRow(widget),
			contactRow('email', mailIcon, email)
		);
		contactErrors = element('div', 'wc-errors');
		contactErrors.hidden = true;
		replyGroup.append(contactBox, contactErrors);

		// Honeypot: off-screen, unlabelled and never focusable, so only a script fills it in. The route
		// answers a filled one with the same silent refusal a bad token gets.
		const honeypot = element('input', 'wc-hp');
		honeypot.type = 'text';
		honeypot.name = 'company_website';
		honeypot.tabIndex = -1;
		honeypot.autocomplete = 'off';
		honeypot.setAttribute('aria-hidden', 'true');

		// Optional service-SMS consent, the same words the public forms show. The server rebuilds this wording
		// from the business name and stores it as the evidence, so what is shown here must stay in step.
		const consent = element('label', 'wc-consent');
		const consentBox = document.createElement('input');
		consentBox.type = 'checkbox';
		consentBox.checked = draft!.consent;
		consentBox.addEventListener('change', () => {
			draft!.consent = consentBox.checked;
			saveDraft();
		});
		const consentWords = element('span', 'wc-consent__words');
		const consentLabel = element('strong', 'wc-consent__label');
		consentLabel.textContent = SERVICE_SMS_CONSENT_LABEL;
		const consentText = element('span', 'wc-consent__text');
		consentText.textContent = serviceSmsConsentDescription(widget.businessName);
		consentWords.append(consentLabel, consentText);
		consent.append(consentBox, consentWords);
		consentNode = consent;

		bannerNode = element('div', 'wc-banner');
		bannerNode.hidden = true;
		bannerNode.setAttribute('role', 'alert');
		bannerNode.innerHTML = alertIcon;
		bannerText = document.createElement('span');
		bannerNode.appendChild(bannerText);

		sendButton = element('button', 'wc-send');
		sendButton.type = 'submit';

		form.append(messageGroup, replyGroup, honeypot, consent, bannerNode, sendButton);

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

	// Who is speaking is never left ambiguous: a reply carries the contractor's name, and an automated
	// one says so rather than passing as a person.
	function speakerOf(message: ChatMessage, businessName: string) {
		return message.sender_type === 'automation' ? `${businessName} · Automated` : businessName;
	}

	// One bubble. A business bubble keeps a logo-wide space on its left so a run lines up, and only the
	// last bubble of the run shows the logo itself.
	function bubbleRow(body: string, side: 'in' | 'out', showLogo: boolean, widget: WidgetPublicConfig) {
		const row = element('div', 'wc-msg');
		if (side === 'in') {
			row.appendChild(showLogo ? logoMark(24, widget) : element('span', 'wc-msg__space'));
		}
		const bubble = element('div', 'wc-msg__bubble');
		bubble.textContent = body;
		row.appendChild(bubble);
		return row;
	}

	function metaLine(text: string) {
		const meta = element('p', 'wc-meta');
		meta.textContent = text;
		return meta;
	}

	// Consecutive messages from the same speaker on the same day sit together as one run, the way every
	// messenger groups them: one logo, one name-and-time line under the last bubble.
	function renderRun(run: ChatMessage[], widget: WidgetPublicConfig) {
		const side = run[0].direction === 'outbound' ? 'in' : 'out';
		const node = element('div', `wc-run wc-run--${side}`);
		run.forEach((message, index) => {
			node.appendChild(bubbleRow(message.body, side, index === run.length - 1, widget));
		});
		const last = run[run.length - 1];
		node.appendChild(
			metaLine(
				side === 'in'
					? `${speakerOf(last, widget.businessName)} · ${timeLabel(last.created_at)}`
					: timeLabel(last.created_at)
			)
		);
		return node;
	}

	// The business's greeting opens the conversation as its first bubble, the way a messenger keeps its
	// opening line rather than dropping it once the conversation starts.
	function renderGreeting(widget: WidgetPublicConfig) {
		const node = element('div', 'wc-run wc-run--in');
		node.append(
			bubbleRow(
				widget.greetingText || 'Hi there! Tell us what you need and we will get right back to you.',
				'in',
				true,
				widget
			),
			metaLine(widget.businessName)
		);
		return node;
	}

	function renderPending(item: PendingMessage, widget: WidgetPublicConfig) {
		const node = element('div', 'wc-run wc-run--out');
		const row = bubbleRow(item.body, 'out', false, widget);
		if (item.status === 'failed') {
			row.insertAdjacentHTML('afterbegin', alertIcon);
			const retry = element('button', 'wc-retry');
			retry.type = 'button';
			retry.innerHTML = 'Not sent · <span>Tap to retry</span>';
			retry.addEventListener('click', () => void deliver(item));
			node.append(row, retry);
		} else {
			row.classList.add('wc-msg--sending');
			node.append(row, metaLine('Sending…'));
		}
		return node;
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
		const widget = config;
		const wasAtBottom = stick || nearBottom();

		const nodes: Node[] = [];
		let lastDay = '';
		let run: ChatMessage[] = [];
		const flush = () => {
			if (run.length) nodes.push(renderRun(run, widget));
			run = [];
		};

		// The greeting belongs at the very start, so it waits until there is nothing older left to load.
		let greeted = hasMoreHistory;
		for (const message of messages) {
			const day = dayLabel(message.created_at);
			if (day !== lastDay) {
				flush();
				const line = element('p', 'wc-day');
				line.textContent = `${day} · ${timeLabel(message.created_at)}`;
				nodes.push(line);
				lastDay = day;
			}
			if (!greeted) {
				nodes.push(renderGreeting(widget));
				greeted = true;
			}
			// A system line narrates the conversation rather than speaking in it.
			if (message.sender_type === 'system') {
				flush();
				const note = element('p', 'wc-note');
				note.textContent = message.body;
				nodes.push(note);
				continue;
			}
			const previous = run[run.length - 1];
			if (
				previous &&
				(previous.direction !== message.direction ||
					speakerOf(previous, widget.businessName) !== speakerOf(message, widget.businessName))
			) {
				flush();
			}
			run.push(message);
		}
		flush();
		if (!greeted) nodes.push(renderGreeting(widget));
		for (const item of pending) nodes.push(renderPending(item, widget));

		listNode.replaceChildren(...nodes);

		if (earlierButton) {
			earlierButton.hidden = !hasMoreHistory;
			earlierButton.disabled = historyLoading;
			earlierButton.innerHTML = `${arrowUpIcon}<span>${historyLoading ? 'Loading…' : 'Load earlier messages'}</span>`;
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
		composerSend.innerHTML = arrowUpIcon;
		composerSend.addEventListener('click', () => sendComposerMessage());

		const pill = element('div', 'wc-composer__pill');
		pill.append(composerInput, composerSend);
		composer.appendChild(pill);
		queueMicrotask(grow);
		syncComposer();
		return composer;
	}

	function buildEnded(widget: WidgetPublicConfig) {
		const ended = element('div', 'wc-ended');
		const tile = element('span', 'wc-tile wc-tile--40');
		tile.innerHTML = endedIcon;
		const text = element('p', 'wc-ended__text');
		text.textContent = 'This conversation has ended.';
		const restart = element('button', 'wc-ended__restart');
		restart.type = 'button';
		restart.innerHTML = `${newChatIcon}<span>Start a new conversation</span>`;
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
		ended.append(tile, text, restart);
		return ended;
	}

	function buildThread() {
		const thread = element('div', 'wc-thread');

		earlierButton = element('button', 'wc-earlier');
		earlierButton.type = 'button';
		earlierButton.innerHTML = `${arrowUpIcon}<span>Load earlier messages</span>`;
		earlierButton.hidden = true;
		earlierButton.addEventListener('click', () => void loadEarlier());

		listNode = element('div', 'wc-thread__list');
		// Polite, not assertive: a reply arriving should be announced after whatever the visitor is
		// currently doing, never on top of it.
		listNode.setAttribute('role', 'log');
		listNode.setAttribute('aria-live', 'polite');
		listNode.setAttribute('aria-label', 'Conversation');

		bannerLine = element('p', 'wc-thread__banner');
		bannerLine.hidden = true;
		bannerLine.setAttribute('role', 'status');

		thread.append(earlierButton, listNode, bannerLine);
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
			consent_transactional_sms: Boolean(e164) && draft.consent,
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

		// An accepted conversation replaces the welcome card entirely: a slim white top, the thread in the
		// scrolling middle, the message box pinned beneath it, and the footer below both.
		if (widget.status === 'live' && session) {
			panel.classList.add('wc-panel--chat');
			const top = element('header', 'wc-chat-top');
			const who = element('div', 'wc-chat-top__who');
			const name = element('h2', 'wc-chat-top__name');
			name.textContent = widget.businessName;
			const promise = element('p', 'wc-chat-top__promise');
			promise.textContent = "We'll reply right here";
			who.append(name, promise);
			top.append(logoMark(40, widget), who, closeButton());

			const body = element('div', 'wc-panel__scroll');
			threadNode ??= buildThread();
			body.appendChild(threadNode);
			scrollNode = body;
			panel.append(top, body);
			panel.appendChild(sessionClosed ? buildEnded(widget) : buildComposer(widget));
			panel.appendChild(renderFooter(widget));

			paintThread(true);
			if (!historyLoaded) void refreshLatest();
			startTransport();
			return panel;
		}

		// Everything else is the welcome top with one white card overlapping it.
		const body = element('div', 'wc-panel__scroll');
		const space = element('div', 'wc-card-space');
		body.append(renderHero(widget), space);
		panel.appendChild(body);

		if (widget.status !== 'live') {
			const card = element('div', 'wc-card');
			card.appendChild(
				renderEmptyState(
					widget.status === 'draft'
						? "This chat isn't set up yet."
						: "This chat isn't available right now."
				)
			);
			space.style.paddingBottom = '12px';
			space.appendChild(card);
			return panel;
		}

		if (!phone) {
			const card = element('div', 'wc-card');
			card.appendChild(renderFormSkeleton());
			space.appendChild(card);
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
			space.appendChild(formNode);
		}

		body.appendChild(renderFooter(widget));
		return panel;
	}

	function render() {
		if (!shadow || !stage || !config) return;
		stage.replaceChildren();

		const showTeaser =
			!panelOpen && !teaserDismissed && config.status === 'live' && !!config.teaserText;

		if (showTeaser) stage.appendChild(renderTeaser(config, config.teaserText as string));
		if (panelOpen) stage.appendChild(renderPanel(config));
		stage.appendChild(renderLauncher(config));
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
