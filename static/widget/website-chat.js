function e(e) {
	return `I agree to receive text messages from ${e} about my request, quotes and appointments. Message frequency varies. Message and data rates may apply. Reply STOP to opt out or HELP for help. Consent is not a condition of purchase.`;
}
//#endregion
//#region src/widget/website-chat.ts
var t = null, n = null;
function r() {
	return n ??= import("./website-chat-phone.js").then((e) => t = e).catch(() => null), n;
}
var i = null;
function a() {
	return i ??= import("./website-chat-realtime.js").then((e) => e).catch(() => null), i;
}
(function() {
	let n = Array.from(document.querySelectorAll("script[data-widget-token]")), i = (n.find((e) => e.src === import.meta.url) ?? n[0] ?? null)?.getAttribute("data-widget-token") ?? "";
	if (!i) return;
	let o = new URL(import.meta.url, window.location.href).origin, s = (e) => `ucrm-wc-teaser-dismissed-${e}`, c = (e) => `ucrm-wc-draft-${e}`, l = (e) => `ucrm-wc-session-${e}`, u = (e) => `ucrm-wc-composer-${e}`, d = null, f = null, p = null, m = !1, ee = !0, h = null, g = !1, _ = /* @__PURE__ */ new Set(), v = "", te = null, y = null, b = [], ne = /* @__PURE__ */ new Set(), x = [], S = !1, C = !1, w = !1, T = !1, E = "", re = null, D = null, O = null, k = null, A = null, j = null, M = null, N = null, P = null, ie = 0, ae = !1, oe = null, se = null, ce = !1;
	function le(e) {
		return `
:host {
	all: initial;

	--wc-color-brand: ${e};
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
	function F(e) {
		return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${e}</svg>`;
	}
	let ue = F("<path d=\"M3 20l1.3 -3.9c-2.324 -3.437 -1.426 -7.872 2.1 -10.374c3.526 -2.501 8.59 -2.296 11.845 .48c3.255 2.777 3.695 7.266 1.029 10.501c-2.666 3.235 -7.615 4.215 -11.574 2.293l-4.7 1\"/>"), de = F("<path d=\"M6 9l6 6l6 -6\"/>"), fe = F("<path d=\"M18 6l-12 12\"/><path d=\"M6 6l12 12\"/>"), pe = F("<path d=\"M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0\"/><path d=\"M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2\"/>"), me = F("<path d=\"M3 7a2 2 0 0 1 2 -2h14a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-10\"/><path d=\"M3 7l9 6l9 -6\"/>"), he = F("<path d=\"M5 12l5 5l10 -10\"/>"), ge = F("<path d=\"M3 10a7 7 0 1 0 14 0a7 7 0 1 0 -14 0\"/><path d=\"M21 21l-6 -6\"/>"), I = F("<path d=\"M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0\"/><path d=\"M12 8v4\"/><path d=\"M12 16h.01\"/>"), _e = F("<path d=\"M5 12l14 0\"/><path d=\"M13 18l6 -6\"/><path d=\"M13 6l6 6\"/>"), ve = F("<path d=\"M12 5l0 14\"/><path d=\"M18 11l-6 -6\"/><path d=\"M6 11l6 -6\"/>"), ye = F("<path d=\"M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-6\"/><path d=\"M11 16a1 1 0 1 0 2 0a1 1 0 0 0 -2 0\"/><path d=\"M8 11v-4a4 4 0 1 1 8 0v4\"/>"), be = F("<path d=\"M13.593 19.855a9.96 9.96 0 0 1 -5.893 -.855l-4.7 1l1.3 -3.9c-2.324 -3.437 -1.426 -7.872 2.1 -10.374c3.526 -2.501 8.59 -2.296 11.845 .48c2.128 1.816 3.053 4.363 2.693 6.813\"/><path d=\"M22 22l-5 -5\"/><path d=\"M17 22l5 -5\"/>"), xe = F("<path d=\"M12.007 19.98a9.869 9.869 0 0 1 -4.307 -.98l-4.7 1l1.3 -3.9c-2.324 -3.437 -1.426 -7.872 2.1 -10.374c3.526 -2.501 8.59 -2.296 11.845 .48c1.992 1.7 2.93 4.04 2.747 6.34\"/><path d=\"M16 19h6\"/><path d=\"M19 16v6\"/>"), Se = F("<path d=\"M8.595 4.577c3.223 -1.176 7.025 -.61 9.65 1.63c2.982 2.543 3.601 6.523 1.636 9.66m-1.908 2.109c-2.787 2.19 -6.89 2.666 -10.273 1.024l-4.7 1l1.3 -3.9c-2.229 -3.296 -1.494 -7.511 1.68 -10.057\"/><path d=\"M3 3l18 18\"/>");
	function Ce(e) {
		let t = e.trim().split(/\s+/).filter(Boolean);
		return t.length === 0 ? "?" : t.length === 1 ? t[0].slice(0, 2).toUpperCase() : `${t[0][0]}${t[t.length - 1][0]}`.toUpperCase();
	}
	function L(e, t) {
		let n = document.createElement(e);
		return n.className = t, n;
	}
	function R(e, t) {
		let n = L("span", `wc-logo wc-logo--${e}`);
		if (n.setAttribute("aria-hidden", "true"), n.textContent = Ce(t.businessName), t.logoPath) {
			let e = document.createElement("img");
			e.alt = "", e.decoding = "async", e.src = `${o}${t.logoPath}`, e.addEventListener("load", () => {
				n.classList.add("wc-logo--image"), n.replaceChildren(e);
			});
		}
		return n;
	}
	function we(e) {
		try {
			return localStorage.getItem(s(e)) === "1";
		} catch {
			return !1;
		}
	}
	function Te() {
		if (d) {
			ee = !0;
			try {
				localStorage.setItem(s(d.widgetId), "1");
			} catch {}
			$();
		}
	}
	let Ee = null;
	function De(e) {
		try {
			return Ee ??= new Intl.DisplayNames(void 0, { type: "region" }), Ee.of(e) ?? e;
		} catch {
			return e;
		}
	}
	function Oe(e) {
		return String.fromCodePoint(...[...e].map((e) => 127462 + e.toUpperCase().charCodeAt(0) - 65));
	}
	let ke = null;
	function Ae() {
		let e = t;
		return e ? (ke ??= e.getCountries().map((t) => ({
			code: t,
			name: De(t),
			dial: `+${e.getCountryCallingCode(t)}`
		})).sort((e, t) => e.name.localeCompare(t.name)), ke) : [];
	}
	function je() {
		let e = new Set(t?.getCountries() ?? []);
		for (let t of navigator.languages ?? [navigator.language]) {
			let n = new Intl.Locale(t).maximize().region;
			if (n && e.has(n)) return n;
		}
		return "US";
	}
	function Me() {
		return crypto.randomUUID ? crypto.randomUUID() : `wc-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
	}
	function Ne() {
		return {
			name: "",
			country: je(),
			phone: "",
			email: "",
			message: "",
			consent: !1,
			idempotencyKey: Me()
		};
	}
	function Pe(e) {
		let t = Ne();
		try {
			let n = localStorage.getItem(c(e));
			if (!n) return t;
			let r = JSON.parse(n);
			return {
				name: typeof r.name == "string" ? r.name : "",
				country: r.country || t.country,
				phone: typeof r.phone == "string" ? r.phone : "",
				email: typeof r.email == "string" ? r.email : "",
				message: typeof r.message == "string" ? r.message : "",
				consent: r.consent === !0,
				idempotencyKey: r.idempotencyKey || t.idempotencyKey
			};
		} catch {
			return t;
		}
	}
	function z() {
		if (!(!d || !h)) try {
			localStorage.setItem(c(d.widgetId), JSON.stringify(h));
		} catch {}
	}
	function Fe() {
		if (d) try {
			localStorage.removeItem(c(d.widgetId));
		} catch {}
	}
	function Ie() {
		let e = {}, t = (e) => e.slice(0, 512);
		e.landing_page = t(location.href), document.referrer && (e.referrer = t(document.referrer));
		let n = new URLSearchParams(location.search);
		for (let r of [
			"utm_source",
			"utm_medium",
			"utm_campaign",
			"utm_term",
			"utm_content",
			"gclid",
			"fbclid"
		]) {
			let i = n.get(r);
			i && (e[r] = t(i));
		}
		return e;
	}
	let Le = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
	function Re(e) {
		let n = t?.parsePhoneNumberFromString(e.phone, e.country);
		return n?.isValid() ? n.number : null;
	}
	function ze(e) {
		let t = d?.contactRequirement ?? "either";
		return t === "phone" ? {
			phone: !0,
			email: !1
		} : t === "email" ? {
			phone: !1,
			email: !0
		} : {
			phone: !e.email.trim(),
			email: !e.phone.trim()
		};
	}
	function Be(e) {
		let t = ze(e), n = {};
		return e.name.trim().length < 2 && (n.name = "Enter your full name."), e.message.trim() || (n.message = "Tell us what you need help with."), e.phone.trim() ? Re(e) || (n.phone = "Enter the whole phone number, including the area code.") : t.phone && (n.phone = d?.contactRequirement === "either" ? "Add a phone number or an email so we can reply." : "Add a phone number so we can reply."), e.email.trim() ? Le.test(e.email.trim()) || (n.email = "Enter an email like name@example.com.") : t.email && d?.contactRequirement !== "either" && (n.email = "Add an email so we can reply."), n;
	}
	function Ve() {
		m = !0, $();
	}
	function He() {
		m = !1, X(), Vt(), $();
	}
	function Ue(e) {
		let t = L("button", `wc-launcher wc-launcher--${e.launcherPosition}${m ? " wc-launcher--open" : ""}`);
		return t.type = "button", m ? (t.setAttribute("aria-label", "Close chat"), t.innerHTML = de, t.addEventListener("click", He), t) : (t.setAttribute("aria-label", `Message ${e.businessName}`), t.innerHTML = `${ue}<span>Message us</span>`, t.addEventListener("pointerenter", Ge, { once: !0 }), t.addEventListener("focus", Ge, { once: !0 }), t.addEventListener("click", Ve), t);
	}
	function We(e, t) {
		let n = L("div", `wc-teaser wc-teaser--${e.launcherPosition}`), r = L("button", "wc-teaser__dismiss");
		r.type = "button", r.setAttribute("aria-label", "Dismiss"), r.innerHTML = fe, r.addEventListener("click", Te);
		let i = L("button", "wc-teaser__bubble");
		i.type = "button", i.addEventListener("pointerenter", Ge, { once: !0 }), i.addEventListener("focus", Ge, { once: !0 }), i.addEventListener("click", Ve);
		let a = L("span", "wc-teaser__who"), o = document.createElement("span");
		o.textContent = e.businessName, a.append(R(24, e), o);
		let s = L("span", "wc-teaser__text");
		return s.textContent = t, i.append(a, s), n.append(r, i), n;
	}
	function Ge() {
		r();
	}
	function Ke() {
		let e = L("button", "wc-close");
		return e.type = "button", e.setAttribute("aria-label", "Close chat"), e.innerHTML = fe, e.addEventListener("click", He), e;
	}
	function qe(e) {
		let t = L("div", "wc-hero"), n = L("div", "wc-hero__top"), r = L("span", "wc-hero__tile");
		r.appendChild(R(32, e)), n.append(r, Ke());
		let i = L("div", "wc-hero__words"), a = L("p", "wc-hero__business");
		a.textContent = e.businessName;
		let o = L("h2", "wc-hero__greeting");
		return o.textContent = e.greetingText || "Hi there! How can we help?", i.append(a, o), t.append(n, i), t;
	}
	function Je(e) {
		let t = L("footer", "wc-footer");
		if (e.privacyPolicyUrl) {
			t.insertAdjacentHTML("beforeend", ye);
			let n = L("a", "wc-privacy");
			n.href = e.privacyPolicyUrl, n.target = "_blank", n.rel = "noopener noreferrer", n.textContent = "Privacy policy";
			let r = document.createElement("span");
			r.textContent = "·", r.setAttribute("aria-hidden", "true"), t.append(n, r);
		}
		let n = document.createElement("span");
		return n.textContent = `Powered by ${e.businessName}`, t.appendChild(n), t;
	}
	function Ye() {
		let e = L("div", "wc-skeleton");
		e.setAttribute("aria-hidden", "true");
		for (let [t, n] of [
			[14, "40%"],
			[84, "100%"],
			[14, "50%"],
			[132, "100%"],
			[48, "100%"]
		]) {
			let r = L("div", "wc-skeleton__bar");
			r.style.height = `${t}px`, r.style.width = n, e.appendChild(r);
		}
		return e;
	}
	function Xe(e) {
		let t = L("div", "wc-empty"), n = L("span", "wc-tile wc-tile--48");
		n.innerHTML = Se;
		let r = L("p", "wc-empty__title");
		return r.textContent = e, t.append(n, r), t;
	}
	let Ze = null, B = null, V = null, H = null, Qe = /* @__PURE__ */ new Map(), U = null, $e = !1, W = null, G = null, K = null, q = null, J = null, et = null;
	function tt(e, t, n = "text") {
		let r = L("input", "wc-input");
		return r.type = n, r.placeholder = e, r.setAttribute("aria-label", t), r.autocomplete = "off", r;
	}
	function nt(e, t, n) {
		let r = L("div", `wc-row${e === "phone" ? " wc-row--phone" : ""}`);
		typeof t == "string" ? r.insertAdjacentHTML("beforeend", t) : r.appendChild(t);
		let i = L("span", "wc-row__alert");
		return i.innerHTML = I, r.append(n, i), Qe.set(e, r), r;
	}
	function rt(e, t) {
		if (!e) return;
		let n = t.filter((e) => !!e);
		e.replaceChildren(...n.map((e) => {
			let t = L("p", "wc-error");
			return t.innerHTML = I, t.append(e), t;
		})), e.hidden = n.length === 0;
	}
	function it() {
		U && (g === $e && U.childElementCount > 0 || ($e = g, U.classList.toggle("wc-send--sending", g), U.setAttribute("aria-busy", String(g)), U.innerHTML = g ? "<span class=\"wc-spinner\" aria-hidden=\"true\"></span><span>Sending…</span>" : `<span>Send message</span><span class="wc-send__well">${_e}</span>`));
	}
	function Y() {
		if (!h) return;
		let e = Be(h), t = (t) => _.has(t) ? e[t] : void 0;
		Ze?.classList.toggle("wc-box--invalid", !!t("message")), rt(B, [t("message")]);
		let n = [
			"name",
			"phone",
			"email"
		].map((e) => {
			let n = t(e);
			return Qe.get(e)?.classList.toggle("wc-row--invalid", !!n), n;
		});
		V?.classList.toggle("wc-box--invalid", n.some(Boolean)), rt(H, n), et && (et.hidden = !h.phone.trim()), it(), U && (U.disabled = g || Object.keys(e).length > 0), W && G && (G.textContent = v, W.hidden = !v);
	}
	function at(e) {
		if (!q || !t) return;
		let n = L("span", "wc-flag");
		n.textContent = Oe(e);
		let r = document.createElement("span");
		r.textContent = `+${t.getCountryCallingCode(e)}`, q.replaceChildren(n, r), q.insertAdjacentHTML("beforeend", de), q.setAttribute("aria-label", `Country: ${De(e)}`);
	}
	function ot(e) {
		!h || !t || (h.country = e, at(e), K && (K.value = new t.AsYouType(e).input(h.phone), h.phone = K.value), z(), Y());
	}
	function X() {
		J?.remove(), J = null, q?.setAttribute("aria-expanded", "false");
	}
	function st(e) {
		if (J) {
			X();
			return;
		}
		let t = L("div", "wc-country"), n = L("label", "wc-country__search");
		n.innerHTML = ge;
		let r = document.createElement("input");
		r.type = "search", r.placeholder = "Search countries", r.setAttribute("aria-label", "Search countries"), n.appendChild(r);
		let i = L("ul", "wc-country__list");
		function a(e) {
			let t = e.trim().toLowerCase(), n = Ae().filter((e) => !t || e.name.toLowerCase().includes(t) || e.code.toLowerCase().includes(t) || e.dial.includes(t));
			if (i.replaceChildren(), n.length === 0) {
				let e = L("li", "wc-country__empty");
				e.textContent = "No matching country", i.appendChild(e);
				return;
			}
			for (let e of n) {
				let t = e.code === h?.country, n = document.createElement("li"), r = L("button", `wc-country__option${t ? " wc-country__option--chosen" : ""}`);
				r.type = "button";
				let a = L("span", "wc-flag");
				a.textContent = Oe(e.code);
				let o = L("span", "wc-country__name");
				o.textContent = e.name;
				let s = L("span", "wc-country__dial");
				s.textContent = e.dial, r.append(a, o, s), t && r.insertAdjacentHTML("beforeend", he), r.addEventListener("click", () => {
					ot(e.code), X(), K?.focus();
				}), n.appendChild(r), i.appendChild(n);
			}
		}
		r.addEventListener("input", () => a(r.value)), t.addEventListener("keydown", (e) => {
			e.key === "Escape" && (e.stopPropagation(), X(), q?.focus());
		}), a(""), t.append(n, i), e.appendChild(t), J = t, q?.setAttribute("aria-expanded", "true"), i.querySelector(".wc-country__option--chosen")?.scrollIntoView({ block: "nearest" }), r.focus();
		let o = (e) => {
			e.composedPath().includes(t) || e.composedPath().includes(q) || (X(), f?.removeEventListener("mousedown", o));
		};
		f?.addEventListener("mousedown", o);
	}
	function ct(e) {
		return q = L("button", "wc-country-button"), q.type = "button", q.setAttribute("aria-haspopup", "listbox"), q.setAttribute("aria-expanded", "false"), at(h.country), q.addEventListener("click", () => {
			V && st(V);
		}), K = tt(e.contactRequirement === "email" ? "Phone (optional)" : "Phone number", "Phone", "tel"), K.autocomplete = "tel", K.value = new t.AsYouType(h.country).input(h.phone), K.addEventListener("input", () => {
			if (!h || !K || !t) return;
			let e = K.value;
			if (e.trim().startsWith("+")) {
				let n = new t.AsYouType().input(e), r = t.parsePhoneNumberFromString(e);
				K.value = n, r?.country && r.country !== h.country && (h.country = r.country, at(r.country));
			} else K.value = new t.AsYouType(h.country).input(e);
			h.phone = K.value, z(), Y();
		}), K.addEventListener("blur", () => {
			_.add("phone"), Y();
		}), nt("phone", q, K);
	}
	function lt(e) {
		return e === "phone" ? "Phone needed" : e === "email" ? "Email needed" : "Phone or email";
	}
	function ut(e, t) {
		let n = L("div", "wc-group"), r = L("div", "wc-group__head"), i = L("span", "wc-group__label");
		if (i.textContent = e, r.appendChild(i), t) {
			let e = L("span", "wc-group__hint");
			e.textContent = t, r.appendChild(e);
		}
		return n.appendChild(r), n;
	}
	function dt(t) {
		let n = document.createElement("form");
		n.className = "wc-card", n.noValidate = !0;
		let r = ut("Your message"), i = L("textarea", "wc-textarea");
		i.placeholder = "What can we help you with?", i.setAttribute("aria-label", "Your message"), i.maxLength = 5e3, i.value = h.message, i.addEventListener("input", () => {
			h.message = i.value, z(), Y();
		}), i.addEventListener("blur", () => {
			_.add("message"), Y();
		}), Ze = L("div", "wc-box"), Ze.appendChild(i), B = L("div", "wc-errors"), B.hidden = !0, r.append(Ze, B);
		let a = tt("Your name", "Your name");
		a.autocomplete = "name", a.value = h.name, a.addEventListener("input", () => {
			h.name = a.value, z(), Y();
		}), a.addEventListener("blur", () => {
			_.add("name"), Y();
		});
		let o = tt(t.contactRequirement === "email" ? "Email" : "Email (optional)", "Email", "email");
		o.autocomplete = "email", o.value = h.email, o.addEventListener("input", () => {
			h.email = o.value, z(), Y();
		}), o.addEventListener("blur", () => {
			_.add("email"), Y();
		});
		let s = ut("How should we reply?", lt(t.contactRequirement));
		V = L("div", "wc-box"), V.append(nt("name", pe, a), ct(t), nt("email", me, o)), H = L("div", "wc-errors"), H.hidden = !0, s.append(V, H);
		let c = L("input", "wc-hp");
		c.type = "text", c.name = "company_website", c.tabIndex = -1, c.autocomplete = "off", c.setAttribute("aria-hidden", "true");
		let l = L("label", "wc-consent"), u = document.createElement("input");
		u.type = "checkbox", u.checked = h.consent, u.addEventListener("change", () => {
			h.consent = u.checked, z();
		});
		let d = L("span", "wc-consent__words"), f = L("strong", "wc-consent__label");
		f.textContent = "Text me about my request";
		let p = L("span", "wc-consent__text");
		return p.textContent = e(t.businessName), d.append(f, p), l.append(u, d), et = l, W = L("div", "wc-banner"), W.hidden = !0, W.setAttribute("role", "alert"), W.innerHTML = I, G = document.createElement("span"), W.appendChild(G), U = L("button", "wc-send"), U.type = "submit", n.append(r, s, c, l, W, U), n.addEventListener("submit", (e) => {
			e.preventDefault(), Ut();
		}), Y(), n;
	}
	function ft(e) {
		try {
			let t = localStorage.getItem(l(e));
			if (!t) return null;
			let n = JSON.parse(t);
			return typeof n.sessionId != "string" || typeof n.sessionToken != "string" ? null : {
				sessionId: n.sessionId,
				sessionToken: n.sessionToken
			};
		} catch {
			return null;
		}
	}
	function pt(e, t) {
		try {
			localStorage.setItem(l(e), JSON.stringify(t));
		} catch {}
	}
	function mt(e) {
		try {
			localStorage.removeItem(l(e)), localStorage.removeItem(u(e));
		} catch {}
	}
	function ht(e) {
		try {
			return localStorage.getItem(u(e)) ?? "";
		} catch {
			return "";
		}
	}
	function gt(e, t) {
		try {
			t ? localStorage.setItem(u(e), t) : localStorage.removeItem(u(e));
		} catch {}
	}
	function _t(e, t) {
		return e.created_at === t.created_at ? e.id < t.id ? -1 : +(e.id > t.id) : e.created_at < t.created_at ? -1 : 1;
	}
	function vt(e) {
		let t = !1;
		for (let n of e) if (!(!n || typeof n.id != "string" || ne.has(n.id)) && (ne.add(n.id), b.push(n), t = !0, n.direction === "inbound")) {
			let e = x.findIndex((e) => e.body === n.body);
			e !== -1 && x.splice(e, 1);
		}
		return t && b.sort(_t), t;
	}
	function yt(e) {
		let t = new Date(e), n = /* @__PURE__ */ new Date(), r = new Date(n);
		r.setDate(n.getDate() - 1);
		let i = (e, t) => e.toDateString() === t.toDateString();
		return i(t, n) ? "Today" : i(t, r) ? "Yesterday" : t.toLocaleDateString(void 0, {
			day: "numeric",
			month: "short",
			year: "numeric"
		});
	}
	function bt(e) {
		return new Date(e).toLocaleTimeString(void 0, {
			hour: "numeric",
			minute: "2-digit"
		});
	}
	function xt(e, t) {
		return e.sender_type === "automation" ? `${t} · Automated` : t;
	}
	function St(e, t, n, r) {
		let i = L("div", "wc-msg");
		t === "in" && i.appendChild(n ? R(24, r) : L("span", "wc-msg__space"));
		let a = L("div", "wc-msg__bubble");
		return a.textContent = e, i.appendChild(a), i;
	}
	function Ct(e) {
		let t = L("p", "wc-meta");
		return t.textContent = e, t;
	}
	function wt(e, t) {
		let n = e[0].direction === "outbound" ? "in" : "out", r = L("div", `wc-run wc-run--${n}`);
		e.forEach((i, a) => {
			r.appendChild(St(i.body, n, a === e.length - 1, t));
		});
		let i = e[e.length - 1];
		return r.appendChild(Ct(n === "in" ? `${xt(i, t.businessName)} · ${bt(i.created_at)}` : bt(i.created_at))), r;
	}
	function Tt(e) {
		let t = L("div", "wc-run wc-run--in");
		return t.append(St(e.greetingText || "Hi there! Tell us what you need and we will get right back to you.", "in", !0, e), Ct(e.businessName)), t;
	}
	function Et(e, t) {
		let n = L("div", "wc-run wc-run--out"), r = St(e.body, "out", !1, t);
		if (e.status === "failed") {
			r.insertAdjacentHTML("afterbegin", I);
			let t = L("button", "wc-retry");
			t.type = "button", t.innerHTML = "Not sent · <span>Tap to retry</span>", t.addEventListener("click", () => void jt(e)), n.append(r, t);
		} else r.classList.add("wc-msg--sending"), n.append(r, Ct("Sending…"));
		return n;
	}
	function Dt() {
		return !M || M.scrollHeight - M.scrollTop - M.clientHeight < 60;
	}
	function Ot() {
		M && (M.scrollTop = M.scrollHeight);
	}
	function Z(e) {
		if (!D || !d) return;
		let t = d, n = e || Dt(), r = [], i = "", a = [], o = () => {
			a.length && r.push(wt(a, t)), a = [];
		}, s = T;
		for (let e of b) {
			let n = yt(e.created_at);
			if (n !== i) {
				o();
				let t = L("p", "wc-day");
				t.textContent = `${n} · ${bt(e.created_at)}`, r.push(t), i = n;
			}
			if (s ||= (r.push(Tt(t)), !0), e.sender_type === "system") {
				o();
				let t = L("p", "wc-note");
				t.textContent = e.body, r.push(t);
				continue;
			}
			let c = a[a.length - 1];
			c && (c.direction !== e.direction || xt(c, t.businessName) !== xt(e, t.businessName)) && o(), a.push(e);
		}
		o(), s || r.push(Tt(t));
		for (let e of x) r.push(Et(e, t));
		D.replaceChildren(...r), O && (O.hidden = !T, O.disabled = C, O.innerHTML = `${ve}<span>${C ? "Loading…" : "Load earlier messages"}</span>`), k && (k.textContent = E, k.hidden = !E), Nt(), n && Ot();
	}
	async function kt(e, t) {
		if (!y) return null;
		let n = new URLSearchParams({
			token: i,
			page_size: String(e)
		});
		t && (n.set("before_created_at", t.created_at), n.set("before_id", t.id));
		let r = await fetch(`${o}/api/webchat/sessions/messages?${n.toString()}`, {
			credentials: "omit",
			headers: { authorization: `Bearer ${y.sessionToken}` }
		});
		return r.status === 429 ? "rate_limited" : r.status === 200 ? await r.json() : null;
	}
	async function Q(e = 30) {
		if (y) try {
			let t = await kt(e);
			if (t === "rate_limited" || t === null || t.status !== "ok") return;
			let n = vt(t.messages ?? []), r = !!t.closed_at;
			if (r !== S) {
				S = r, n = !0, $();
				return;
			}
			w || (T = t.has_more ?? !1, w = !0, n = !0), E && (E = "", n = !0), n && Z(!1);
		} catch {
			!w && !E && (E = "We can't load this conversation right now.", Z(!1));
		}
	}
	async function At() {
		if (!y || C || b.length === 0) return;
		C = !0, Z(!1);
		let e = b[0];
		try {
			let t = await kt(30, e);
			if (t && t !== "rate_limited" && t.status === "ok") {
				let e = M?.scrollHeight ?? 0;
				vt(t.messages ?? []), T = t.has_more ?? !1, C = !1, Z(!1), M && (M.scrollTop += M.scrollHeight - e);
				return;
			}
			E = t === "rate_limited" ? "That's a lot of requests at once. Please try again in a moment." : "We couldn't load older messages.";
		} catch {
			E = "We couldn't load older messages.";
		}
		C = !1, Z(!1);
	}
	async function jt(e) {
		if (y) {
			e.status = "sending", E = "", Z(!1);
			try {
				let t = await fetch(`${o}/api/webchat/messages?token=${encodeURIComponent(i)}`, {
					method: "POST",
					credentials: "omit",
					headers: {
						"content-type": "application/json",
						authorization: `Bearer ${y.sessionToken}`
					},
					body: JSON.stringify({
						message: e.body,
						idempotency_key: e.idempotencyKey
					})
				});
				if (t.status === 200) {
					let n = await t.json();
					n.message_id && vt([{
						id: n.message_id,
						direction: "inbound",
						sender_type: "visitor",
						body: e.body,
						created_at: (/* @__PURE__ */ new Date()).toISOString()
					}]);
					let r = x.indexOf(e);
					r !== -1 && x.splice(r, 1), Z(!0);
					return;
				}
				if (t.status === 409) {
					e.status = "failed", S = !0, E = "This conversation has ended.", $();
					return;
				}
				e.status = "failed", t.status === 429 && (E = "That's a lot of messages at once. Please try again in a moment.");
			} catch {
				e.status = "failed";
			}
			Z(!1);
		}
	}
	function Mt() {
		if (!d || !y || !A) return;
		let e = A.value.trim();
		if (!e || S) return;
		let t = {
			localId: Me(),
			body: e,
			idempotencyKey: Me(),
			status: "sending"
		};
		x.push(t), A.value = "", A.style.height = "auto", gt(d.widgetId, ""), Z(!0), jt(t);
	}
	function Nt() {
		j && A && (j.disabled = S || A.value.trim().length === 0);
	}
	function Pt(e) {
		let t = L("div", "wc-composer");
		A = L("textarea", "wc-composer__input"), A.rows = 1, A.placeholder = "Message…", A.setAttribute("aria-label", "Message"), A.maxLength = 5e3, A.value = ht(e.widgetId);
		let n = () => {
			A && (A.style.height = "auto", A.style.height = `${Math.min(A.scrollHeight, 120)}px`);
		};
		A.addEventListener("input", () => {
			gt(e.widgetId, A?.value ?? ""), n(), Nt();
		}), A.addEventListener("keydown", (e) => {
			e.key !== "Enter" || e.shiftKey || e.isComposing || (e.preventDefault(), Mt());
		}), j = L("button", "wc-composer__send"), j.type = "button", j.setAttribute("aria-label", "Send message"), j.innerHTML = ve, j.addEventListener("click", () => Mt());
		let r = L("div", "wc-composer__pill");
		return r.append(A, j), t.appendChild(r), queueMicrotask(n), Nt(), t;
	}
	function Ft(e) {
		let t = L("div", "wc-ended"), n = L("span", "wc-tile wc-tile--40");
		n.innerHTML = be;
		let r = L("p", "wc-ended__text");
		r.textContent = "This conversation has ended.";
		let i = L("button", "wc-ended__restart");
		return i.type = "button", i.innerHTML = `${xe}<span>Start a new conversation</span>`, i.addEventListener("click", () => {
			Vt(), mt(e.widgetId), y = null, b = [], ne.clear(), x = [], S = !1, w = !1, T = !1, E = "", re = null, D = null, A = null, j = null, h = null, te = null, _ = /* @__PURE__ */ new Set(), $();
		}), t.append(n, r, i), t;
	}
	function It() {
		let e = L("div", "wc-thread");
		return O = L("button", "wc-earlier"), O.type = "button", O.innerHTML = `${ve}<span>Load earlier messages</span>`, O.hidden = !0, O.addEventListener("click", () => void At()), D = L("div", "wc-thread__list"), D.setAttribute("role", "log"), D.setAttribute("aria-live", "polite"), D.setAttribute("aria-label", "Conversation"), k = L("p", "wc-thread__banner"), k.hidden = !0, k.setAttribute("role", "status"), e.append(O, D, k), e;
	}
	async function Lt() {
		if (!y) return null;
		try {
			let e = await fetch(`${o}/api/webchat/sessions/realtime?token=${encodeURIComponent(i)}`, {
				method: "POST",
				credentials: "omit",
				headers: { authorization: `Bearer ${y.sessionToken}` }
			});
			if (e.status !== 200) return null;
			let t = await e.json();
			return !t.channel_topic || !t.expires_at || !t.supabase_url ? null : t;
		} catch {
			return null;
		}
	}
	function Rt() {
		se &&= (clearTimeout(se), null);
		let e = P, t = N;
		P = null, N = null, ie = 0;
		try {
			e?.unsubscribe(), t?.disconnect();
		} catch {}
	}
	async function zt() {
		if (!(!y || ae || P)) {
			ae = !0;
			try {
				let e = await Lt(), t = e ? await a() : null;
				if (!e || !t || !y || !m) return;
				N = new t.RealtimeClient(`${e.supabase_url}/realtime/v1`, { params: { apikey: e.supabase_key } }), await N.setAuth(e.supabase_key), ie = new Date(e.expires_at).getTime(), P = N.channel(e.channel_topic, { config: { private: !0 } }), P.on("broadcast", { event: "website_chat_message" }, (e) => {
					let t = e?.payload;
					t?.id && (vt([t]) && Z(!1), t.sender_type === "system" && Q());
				}), P.subscribe((e) => {
					if (e === "SUBSCRIBED") {
						Q();
						return;
					}
					(e === "CHANNEL_ERROR" || e === "TIMED_OUT" || e === "CLOSED") && Rt();
				});
				let n = Math.max(ie - Date.now() - 6e4, 3e4);
				se = setTimeout(() => {
					Rt(), zt();
				}, n);
			} finally {
				ae = !1;
			}
		}
	}
	function Bt() {
		y && (zt(), oe ??= setInterval(() => {
			document.hidden || !m || P && P.state === "joined" || Q(10);
		}, 4e3));
	}
	function Vt() {
		Rt(), oe &&= (clearInterval(oe), null);
	}
	function Ht() {
		ce || (ce = !0, window.addEventListener("pagehide", () => Vt()), window.addEventListener("pageshow", (e) => {
			!e.persisted || !m || !y || (Q(), Bt());
		}), document.addEventListener("visibilitychange", () => {
			document.hidden || !m || !y || (Q(), Bt());
		}));
	}
	async function Ut() {
		if (!d || !h || g) return;
		if (_ = new Set(Object.keys(h)), Object.keys(Be(h)).length > 0) {
			Y();
			return;
		}
		g = !0, v = "", Y();
		let e = Re(h), t = {
			idempotency_key: h.idempotencyKey,
			name: h.name.trim(),
			...e ? { phone: e } : {},
			...h.email.trim() ? { email: h.email.trim() } : {},
			message: h.message.trim(),
			consent_transactional_sms: !!e && h.consent,
			attribution: Ie()
		};
		try {
			let e = await fetch(`${o}/api/webchat/sessions?token=${encodeURIComponent(i)}`, {
				method: "POST",
				credentials: "omit",
				headers: { "content-type": "application/json" },
				body: JSON.stringify(t)
			});
			if (e.status === 200) {
				let t = await e.json();
				if (!t.session_id || !t.session_token) {
					v = "Your message couldn't be sent. Please try again.";
					return;
				}
				y = {
					sessionId: t.session_id,
					sessionToken: t.session_token
				}, pt(d.widgetId, y), x = [{
					localId: Me(),
					body: h.message.trim(),
					idempotencyKey: h.idempotencyKey,
					status: "sending"
				}], Fe(), $();
				return;
			}
			v = e.status === 429 ? "That's a lot of messages at once. Please try again in a moment." : e.status === 409 || e.status === 503 ? "We can't take messages right now. Please try again later." : "Your message couldn't be sent. Please try again.";
		} catch {
			v = "Your message couldn't be sent. Please check your connection and try again.";
		} finally {
			g = !1, Y();
		}
	}
	function Wt(e) {
		let n = L("section", `wc-panel wc-panel--${e.launcherPosition}`);
		if (n.setAttribute("role", "dialog"), n.setAttribute("aria-label", `${e.businessName} chat`), e.status === "live" && y) {
			n.classList.add("wc-panel--chat");
			let t = L("header", "wc-chat-top"), r = L("div", "wc-chat-top__who"), i = L("h2", "wc-chat-top__name");
			i.textContent = e.businessName;
			let a = L("p", "wc-chat-top__promise");
			a.textContent = "We'll reply right here", r.append(i, a), t.append(R(40, e), r, Ke());
			let o = L("div", "wc-panel__scroll");
			return re ??= It(), o.appendChild(re), M = o, n.append(t, o), n.appendChild(S ? Ft(e) : Pt(e)), n.appendChild(Je(e)), Z(!0), w || Q(), Bt(), n;
		}
		let i = L("div", "wc-panel__scroll"), a = L("div", "wc-card-space");
		if (i.append(qe(e), a), n.appendChild(i), e.status !== "live") {
			let t = L("div", "wc-card");
			return t.appendChild(Xe(e.status === "draft" ? "This chat isn't set up yet." : "This chat isn't available right now.")), a.style.paddingBottom = "12px", a.appendChild(t), n;
		}
		if (t) h ??= Pe(e.widgetId), te ??= dt(e), a.appendChild(te);
		else {
			let e = L("div", "wc-card");
			e.appendChild(Ye()), a.appendChild(e), r().then(() => {
				m && $();
			});
		}
		return i.appendChild(Je(e)), n;
	}
	function $() {
		!f || !p || !d || (p.replaceChildren(), !m && !ee && d.status === "live" && d.teaserText && p.appendChild(We(d, d.teaserText)), m && p.appendChild(Wt(d)), p.appendChild(Ue(d)));
	}
	function Gt(e) {
		let t = document.createElement("div");
		t.id = "ucrm-website-chat", t.style.cssText = "all: initial; position: fixed; width: 0; height: 0; z-index: 2147483000;", document.body.appendChild(t), f = t.attachShadow({ mode: "open" });
		let n = document.createElement("style");
		n.textContent = le(e.brandColor || "#049a54"), p = document.createElement("div"), f.append(n, p), ee = we(e.widgetId), y = ft(e.widgetId), Ht(), $();
	}
	async function Kt() {
		try {
			let e = await fetch(`${o}/api/webchat/config?token=${encodeURIComponent(i)}`, { credentials: "omit" });
			return e.status === 200 ? (await e.json()).config ?? null : null;
		} catch {
			return null;
		}
	}
	async function qt() {
		let e = await Kt();
		e && (d = e, document.body ? Gt(e) : document.addEventListener("DOMContentLoaded", () => Gt(e)));
	}
	qt();
})();
//#endregion
