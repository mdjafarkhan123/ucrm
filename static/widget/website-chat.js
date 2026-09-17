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

.wc-consent[hidden] { display: none; }

.wc-consent__label {
	display: block;
	font-weight: 600;
	color: var(--wc-color-text);
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
	let ue = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M18 6l-12 12\" /><path d=\"M6 6l12 12\" /></svg>", de = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M10 14l11 -11\" /><path d=\"M21 3l-6.5 18a.55 .55 0 0 1 -1 0l-3.5 -7l-7 -3.5a.55 .55 0 0 1 0 -1l18 -6.5\" /></svg>";
	function fe(e) {
		let t = e.trim().split(/\s+/).filter(Boolean);
		return t.length === 0 ? "?" : t.length === 1 ? t[0].slice(0, 2).toUpperCase() : `${t[0][0]}${t[t.length - 1][0]}`.toUpperCase();
	}
	function F(e, t) {
		let n = document.createElement(e);
		return n.className = t, n;
	}
	function I(e, t) {
		let n = F("span", `wc-avatar wc-avatar--${e}`);
		return n.setAttribute("aria-hidden", "true"), n.textContent = fe(t), n;
	}
	function pe(e) {
		try {
			return localStorage.getItem(s(e)) === "1";
		} catch {
			return !1;
		}
	}
	function me() {
		if (d) {
			ee = !0;
			try {
				localStorage.setItem(s(d.widgetId), "1");
			} catch {}
			$();
		}
	}
	let he = null;
	function L(e) {
		try {
			return he ??= new Intl.DisplayNames(void 0, { type: "region" }), he.of(e) ?? e;
		} catch {
			return e;
		}
	}
	function R(e) {
		return String.fromCodePoint(...[...e].map((e) => 127462 + e.toUpperCase().charCodeAt(0) - 65));
	}
	let ge = null;
	function _e() {
		let e = t;
		return e ? (ge ??= e.getCountries().map((t) => ({
			code: t,
			name: L(t),
			dial: `+${e.getCountryCallingCode(t)}`
		})).sort((e, t) => e.name.localeCompare(t.name)), ge) : [];
	}
	function ve() {
		let e = new Set(t?.getCountries() ?? []);
		for (let t of navigator.languages ?? [navigator.language]) {
			let n = new Intl.Locale(t).maximize().region;
			if (n && e.has(n)) return n;
		}
		return "US";
	}
	function z() {
		return crypto.randomUUID ? crypto.randomUUID() : `wc-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
	}
	function ye() {
		return {
			name: "",
			country: ve(),
			phone: "",
			email: "",
			message: "",
			consent: !1,
			idempotencyKey: z()
		};
	}
	function be(e) {
		let t = ye();
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
	function B() {
		if (!(!d || !h)) try {
			localStorage.setItem(c(d.widgetId), JSON.stringify(h));
		} catch {}
	}
	function xe() {
		if (d) try {
			localStorage.removeItem(c(d.widgetId));
		} catch {}
	}
	function Se() {
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
	let Ce = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
	function we(e) {
		let n = t?.parsePhoneNumberFromString(e.phone, e.country);
		return n?.isValid() ? n.number : null;
	}
	function Te(e) {
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
	function Ee(e) {
		let t = Te(e), n = {};
		return e.name.trim().length < 2 && (n.name = "Invalid value"), e.message.trim() || (n.message = "Invalid value"), (e.phone.trim() ? !we(e) : t.phone) && (n.phone = "Invalid value"), (e.email.trim() ? !Ce.test(e.email.trim()) : t.email) && (n.email = "Invalid value"), n;
	}
	function De(e) {
		let t = F("button", `wc-launcher wc-launcher--${e.launcherPosition}`);
		return t.type = "button", t.setAttribute("aria-label", `Open chat with ${e.businessName}`), t.innerHTML = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M3 20l1.3 -3.9c-2.324 -3.437 -1.426 -7.872 2.1 -10.374c3.526 -2.501 8.59 -2.296 11.845 .48c3.255 2.777 3.695 7.266 1.029 10.501c-2.666 3.235 -7.615 4.215 -11.574 2.293l-4.7 1\" /></svg>", t.addEventListener("pointerenter", V, { once: !0 }), t.addEventListener("focus", V, { once: !0 }), t.addEventListener("click", () => {
			m = !0, $();
		}), t;
	}
	function Oe(e, t) {
		let n = F("button", `wc-teaser wc-teaser--${e.launcherPosition}`);
		n.type = "button", n.addEventListener("pointerenter", V, { once: !0 }), n.addEventListener("focus", V, { once: !0 }), n.addEventListener("click", () => {
			m = !0, $();
		});
		let r = F("span", "wc-teaser__text");
		r.textContent = t;
		let i = F("span", "wc-teaser__dismiss");
		return i.setAttribute("role", "button"), i.setAttribute("tabindex", "0"), i.setAttribute("aria-label", "Dismiss"), i.innerHTML = ue, i.addEventListener("click", (e) => {
			e.stopPropagation(), me();
		}), i.addEventListener("keydown", (e) => {
			(e.key === "Enter" || e.key === " ") && (e.preventDefault(), e.stopPropagation(), me());
		}), n.append(I("medium", e.businessName), r, i), n;
	}
	function V() {
		r();
	}
	function ke() {
		let e = F("div", "wc-skeleton");
		e.setAttribute("aria-hidden", "true");
		for (let t of [
			40,
			40,
			40,
			64,
			44
		]) {
			let n = F("div", "wc-skeleton__bar");
			n.style.height = `${t}px`, e.appendChild(n);
		}
		return e;
	}
	function Ae(e, t) {
		let n = F("div", "wc-empty"), r = F("p", "wc-empty__title");
		if (r.textContent = e, n.appendChild(r), t) {
			let e = F("p", "wc-empty__description");
			e.textContent = t, n.appendChild(e);
		}
		return n;
	}
	let je = /* @__PURE__ */ new Map(), H = null, U = null, W = null, G = null, K = null, Me = null;
	function q(e, t, n = "") {
		let r = F("div", `wc-field ${n}`.trim()), i = F("p", "wc-field__error");
		return i.hidden = !0, r.append(t, i), je.set(e, {
			wrapper: r,
			error: i
		}), r;
	}
	function Ne(e, t = "text") {
		let n = F("input", "wc-input");
		return n.type = t, n.placeholder = e, n.setAttribute("aria-label", e), n.autocomplete = "off", n;
	}
	function J() {
		if (!h) return;
		let e = Ee(h);
		for (let [t, n] of je) {
			let r = _.has(t) ? e[t] : void 0;
			n.error.textContent = r ?? "", n.error.hidden = !r, n.wrapper.classList.toggle("wc-field--invalid", !!r);
		}
		Me && (Me.hidden = !h.phone.trim()), H && (H.disabled = g || Object.keys(e).length > 0), U && (U.textContent = v, U.hidden = !v);
	}
	function Pe(e) {
		if (!(!h || !t)) {
			if (h.country = e, G) {
				let t = G.querySelector(".wc-phone__flag");
				t && (t.textContent = R(e)), G.setAttribute("aria-label", `Country: ${L(e)}`);
			}
			W && (W.value = new t.AsYouType(e).input(h.phone), h.phone = W.value), B(), J();
		}
	}
	function Y() {
		K?.remove(), K = null, G?.setAttribute("aria-expanded", "false");
	}
	function Fe(e) {
		if (K) {
			Y();
			return;
		}
		let t = F("div", "wc-country"), n = F("input", "wc-country__search");
		n.type = "search", n.placeholder = "Search countries", n.setAttribute("aria-label", "Search countries");
		let r = F("ul", "wc-country__list");
		function i(e) {
			let t = e.trim().toLowerCase(), n = _e().filter((e) => !t || e.name.toLowerCase().includes(t) || e.code.toLowerCase().includes(t) || e.dial.includes(t));
			if (r.replaceChildren(), n.length === 0) {
				let e = F("li", "wc-country__empty");
				e.textContent = "No matching country", r.appendChild(e);
				return;
			}
			for (let e of n) {
				let t = document.createElement("li"), n = F("button", "wc-country__option");
				n.type = "button";
				let i = F("span", "wc-phone__flag");
				i.textContent = R(e.code);
				let a = F("span", "wc-country__name");
				a.textContent = e.name;
				let o = F("span", "wc-country__dial");
				o.textContent = e.dial, n.append(i, a, o), n.addEventListener("click", () => {
					Pe(e.code), Y(), W?.focus();
				}), t.appendChild(n), r.appendChild(t);
			}
		}
		n.addEventListener("input", () => i(n.value)), t.addEventListener("keydown", (e) => {
			e.key === "Escape" && (e.stopPropagation(), Y(), G?.focus());
		}), i(""), t.append(n, r), e.appendChild(t), K = t, G?.setAttribute("aria-expanded", "true"), n.focus();
		let a = (t) => {
			t.composedPath().includes(e) || (Y(), f?.removeEventListener("mousedown", a));
		};
		f?.addEventListener("mousedown", a);
	}
	function Ie() {
		let e = F("div", "wc-phone");
		G = F("button", "wc-phone__country"), G.type = "button", G.setAttribute("aria-haspopup", "listbox"), G.setAttribute("aria-expanded", "false");
		let n = F("span", "wc-phone__flag");
		return n.textContent = R(h.country), G.append(n), G.insertAdjacentHTML("beforeend", "<svg class=\"wc-phone__caret\" xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M6 9l6 6l6 -6\" /></svg>"), G.setAttribute("aria-label", `Country: ${L(h.country)}`), G.addEventListener("click", () => Fe(e)), W = Ne("Phone", "tel"), W.autocomplete = "tel", W.value = new t.AsYouType(h.country).input(h.phone), W.addEventListener("input", () => {
			if (!h || !W || !t) return;
			let e = W.value;
			if (e.trim().startsWith("+")) {
				let n = new t.AsYouType().input(e), r = t.parsePhoneNumberFromString(e);
				if (W.value = n, r?.country && r.country !== h.country) {
					h.country = r.country;
					let e = G?.querySelector(".wc-phone__flag");
					e && (e.textContent = R(r.country)), G?.setAttribute("aria-label", `Country: ${L(r.country)}`);
				}
			} else W.value = new t.AsYouType(h.country).input(e);
			h.phone = W.value, B(), J();
		}), W.addEventListener("blur", () => {
			_.add("phone"), J();
		}), e.append(G, W), q("phone", e);
	}
	function Le(t) {
		let n = document.createElement("form");
		n.className = "wc-form", n.noValidate = !0;
		let r = Ne("Name");
		r.autocomplete = "name", r.value = h.name, r.addEventListener("input", () => {
			h.name = r.value, B(), J();
		}), r.addEventListener("blur", () => {
			_.add("name"), J();
		});
		let i = Ne("E-mail", "email");
		i.autocomplete = "email", i.value = h.email, i.addEventListener("input", () => {
			h.email = i.value, B(), J();
		}), i.addEventListener("blur", () => {
			_.add("email"), J();
		});
		let a = F("textarea", "wc-textarea");
		a.placeholder = "I want to know more", a.setAttribute("aria-label", "Message"), a.maxLength = 5e3, a.value = h.message, a.addEventListener("input", () => {
			h.message = a.value, B(), J();
		}), a.addEventListener("blur", () => {
			_.add("message"), J();
		});
		let o = F("input", "wc-hp");
		o.type = "text", o.name = "company_website", o.tabIndex = -1, o.autocomplete = "off", o.setAttribute("aria-hidden", "true");
		let s = F("label", "wc-consent"), c = document.createElement("input");
		c.type = "checkbox", c.checked = h.consent, c.addEventListener("change", () => {
			h.consent = c.checked, B();
		});
		let l = F("span", "wc-consent__text"), u = F("strong", "wc-consent__label");
		if (u.textContent = "Text me about my request", l.append(u, ` ${e(t.businessName)}`), s.append(c, l), Me = s, U = F("p", "wc-form__banner"), U.hidden = !0, U.setAttribute("role", "alert"), H = F("button", "wc-send"), H.type = "submit", H.innerHTML = `<span>Send</span>${de}`, n.append(q("name", r), Ie(), q("email", i), q("message", a), o, s), t.privacyPolicyUrl) {
			let e = F("a", "wc-privacy");
			e.href = t.privacyPolicyUrl, e.target = "_blank", e.rel = "noopener noreferrer", e.textContent = "Privacy policy", n.appendChild(e);
		}
		return n.append(U, H), n.addEventListener("submit", (e) => {
			e.preventDefault(), ut();
		}), J(), n;
	}
	function Re(e) {
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
	function ze(e, t) {
		try {
			localStorage.setItem(l(e), JSON.stringify(t));
		} catch {}
	}
	function Be(e) {
		try {
			localStorage.removeItem(l(e)), localStorage.removeItem(u(e));
		} catch {}
	}
	function Ve(e) {
		try {
			return localStorage.getItem(u(e)) ?? "";
		} catch {
			return "";
		}
	}
	function He(e, t) {
		try {
			t ? localStorage.setItem(u(e), t) : localStorage.removeItem(u(e));
		} catch {}
	}
	function Ue(e, t) {
		return e.created_at === t.created_at ? e.id < t.id ? -1 : +(e.id > t.id) : e.created_at < t.created_at ? -1 : 1;
	}
	function X(e) {
		let t = !1;
		for (let n of e) if (!(!n || typeof n.id != "string" || ne.has(n.id)) && (ne.add(n.id), b.push(n), t = !0, n.direction === "inbound")) {
			let e = x.findIndex((e) => e.body === n.body);
			e !== -1 && x.splice(e, 1);
		}
		return t && b.sort(Ue), t;
	}
	function We(e) {
		let t = new Date(e), n = /* @__PURE__ */ new Date(), r = new Date(n);
		r.setDate(n.getDate() - 1);
		let i = (e, t) => e.toDateString() === t.toDateString();
		return i(t, n) ? "Today" : i(t, r) ? "Yesterday" : t.toLocaleDateString(void 0, {
			day: "numeric",
			month: "short",
			year: "numeric"
		});
	}
	function Ge(e) {
		return new Date(e).toLocaleTimeString(void 0, {
			hour: "numeric",
			minute: "2-digit"
		});
	}
	function Ke(e, t) {
		if (e.sender_type === "system") {
			let t = F("p", "wc-note");
			return t.textContent = e.body, t;
		}
		let n = e.direction === "outbound", r = F("div", `wc-msg wc-msg--${n ? "in" : "out"}`), i = F("div", "wc-msg__row");
		n && i.appendChild(I("base", t));
		let a = F("div", "wc-msg__bubble");
		a.textContent = e.body, i.appendChild(a);
		let o = F("p", "wc-msg__meta"), s = e.sender_type === "automation" ? `${t} · Automated` : t;
		return o.textContent = n ? `${s} · ${Ge(e.created_at)}` : Ge(e.created_at), r.append(i, o), r;
	}
	function qe(e) {
		let t = F("div", `wc-msg wc-msg--out ${e.status === "sending" ? "wc-msg--sending" : ""}`.trim()), n = F("div", "wc-msg__row"), r = F("div", "wc-msg__bubble");
		if (r.textContent = e.body, n.appendChild(r), t.appendChild(n), e.status === "failed") {
			let n = F("button", "wc-msg__retry");
			n.type = "button", n.textContent = "Not sent — tap to retry", n.addEventListener("click", () => void Qe(e)), t.appendChild(n);
		} else {
			let e = F("p", "wc-msg__meta");
			e.textContent = "Sending…", t.appendChild(e);
		}
		return t;
	}
	function Je() {
		return !M || M.scrollHeight - M.scrollTop - M.clientHeight < 60;
	}
	function Ye() {
		M && (M.scrollTop = M.scrollHeight);
	}
	function Z(e) {
		if (!D || !d) return;
		let t = e || Je(), n = [], r = "";
		for (let e of b) {
			let t = We(e.created_at);
			if (t !== r) {
				let e = F("span", "wc-day");
				e.textContent = t, n.push(e), r = t;
			}
			n.push(Ke(e, d.businessName));
		}
		for (let e of x) n.push(qe(e));
		D.replaceChildren(...n), O && (O.hidden = !T, O.disabled = C, O.textContent = C ? "Loading…" : "Load earlier messages"), k && (k.textContent = E, k.hidden = !E), et(), t && Ye();
	}
	async function Xe(e, t) {
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
			let t = await Xe(e);
			if (t === "rate_limited" || t === null || t.status !== "ok") return;
			let n = X(t.messages ?? []), r = !!t.closed_at;
			if (r !== S) {
				S = r, n = !0, $();
				return;
			}
			w || (T = t.has_more ?? !1, w = !0, n = !0), E && (E = "", n = !0), n && Z(!1);
		} catch {
			!w && !E && (E = "We can't load this conversation right now.", Z(!1));
		}
	}
	async function Ze() {
		if (!y || C || b.length === 0) return;
		C = !0, Z(!1);
		let e = b[0];
		try {
			let t = await Xe(30, e);
			if (t && t !== "rate_limited" && t.status === "ok") {
				let e = M?.scrollHeight ?? 0;
				X(t.messages ?? []), T = t.has_more ?? !1, C = !1, Z(!1), M && (M.scrollTop += M.scrollHeight - e);
				return;
			}
			E = t === "rate_limited" ? "That's a lot of requests at once. Please try again in a moment." : "We couldn't load older messages.";
		} catch {
			E = "We couldn't load older messages.";
		}
		C = !1, Z(!1);
	}
	async function Qe(e) {
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
					n.message_id && X([{
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
	function $e() {
		if (!d || !y || !A) return;
		let e = A.value.trim();
		if (!e || S) return;
		let t = {
			localId: z(),
			body: e,
			idempotencyKey: z(),
			status: "sending"
		};
		x.push(t), A.value = "", A.style.height = "auto", He(d.widgetId, ""), Z(!0), Qe(t);
	}
	function et() {
		j && A && (j.disabled = S || A.value.trim().length === 0);
	}
	function tt(e) {
		let t = F("div", "wc-composer");
		A = F("textarea", "wc-composer__input"), A.rows = 1, A.placeholder = "Message…", A.setAttribute("aria-label", "Message"), A.maxLength = 5e3, A.value = Ve(e.widgetId);
		let n = () => {
			A && (A.style.height = "auto", A.style.height = `${Math.min(A.scrollHeight, 120)}px`);
		};
		return A.addEventListener("input", () => {
			He(e.widgetId, A?.value ?? ""), n(), et();
		}), A.addEventListener("keydown", (e) => {
			e.key !== "Enter" || e.shiftKey || e.isComposing || (e.preventDefault(), $e());
		}), j = F("button", "wc-composer__send"), j.type = "button", j.setAttribute("aria-label", "Send message"), j.innerHTML = de, j.addEventListener("click", () => $e()), t.append(A, j), queueMicrotask(n), et(), t;
	}
	function nt(e) {
		let t = F("div", "wc-ended"), n = F("p", "wc-ended__text");
		n.textContent = "This conversation has ended.";
		let r = F("button", "wc-ended__restart");
		return r.type = "button", r.textContent = "Start a new conversation", r.addEventListener("click", () => {
			ct(), Be(e.widgetId), y = null, b = [], ne.clear(), x = [], S = !1, w = !1, T = !1, E = "", re = null, D = null, A = null, j = null, h = null, te = null, _ = /* @__PURE__ */ new Set(), $();
		}), t.append(n, r), t;
	}
	function rt(e) {
		let t = F("div", "wc-thread");
		O = F("button", "wc-earlier"), O.type = "button", O.textContent = "Load earlier messages", O.hidden = !0, O.addEventListener("click", () => void Ze());
		let n = F("div", "wc-intro"), r = F("div", "wc-intro__bubble");
		return r.textContent = e.greetingText || "Enter your question below and we will get right back to you.", n.append(I("base", e.businessName), r), D = F("div", "wc-thread__list"), D.setAttribute("role", "log"), D.setAttribute("aria-live", "polite"), D.setAttribute("aria-label", "Conversation"), k = F("p", "wc-thread__banner"), k.hidden = !0, k.setAttribute("role", "status"), t.append(O, n, D, k), t;
	}
	async function it() {
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
	function at() {
		se &&= (clearTimeout(se), null);
		let e = P, t = N;
		P = null, N = null, ie = 0;
		try {
			e?.unsubscribe(), t?.disconnect();
		} catch {}
	}
	async function ot() {
		if (!(!y || ae || P)) {
			ae = !0;
			try {
				let e = await it(), t = e ? await a() : null;
				if (!e || !t || !y || !m) return;
				N = new t.RealtimeClient(`${e.supabase_url}/realtime/v1`, { params: { apikey: e.supabase_key } }), await N.setAuth(e.supabase_key), ie = new Date(e.expires_at).getTime(), P = N.channel(e.channel_topic, { config: { private: !0 } }), P.on("broadcast", { event: "website_chat_message" }, (e) => {
					let t = e?.payload;
					t?.id && (X([t]) && Z(!1), t.sender_type === "system" && Q());
				}), P.subscribe((e) => {
					if (e === "SUBSCRIBED") {
						Q();
						return;
					}
					(e === "CHANNEL_ERROR" || e === "TIMED_OUT" || e === "CLOSED") && at();
				});
				let n = Math.max(ie - Date.now() - 6e4, 3e4);
				se = setTimeout(() => {
					at(), ot();
				}, n);
			} finally {
				ae = !1;
			}
		}
	}
	function st() {
		y && (ot(), oe ??= setInterval(() => {
			document.hidden || !m || P && P.state === "joined" || Q(10);
		}, 4e3));
	}
	function ct() {
		at(), oe &&= (clearInterval(oe), null);
	}
	function lt() {
		ce || (ce = !0, window.addEventListener("pagehide", () => ct()), window.addEventListener("pageshow", (e) => {
			!e.persisted || !m || !y || (Q(), st());
		}), document.addEventListener("visibilitychange", () => {
			document.hidden || !m || !y || (Q(), st());
		}));
	}
	async function ut() {
		if (!d || !h || g) return;
		if (_ = new Set(Object.keys(h)), Object.keys(Ee(h)).length > 0) {
			J();
			return;
		}
		g = !0, v = "", J();
		let e = we(h), t = {
			idempotency_key: h.idempotencyKey,
			name: h.name.trim(),
			...e ? { phone: e } : {},
			...h.email.trim() ? { email: h.email.trim() } : {},
			message: h.message.trim(),
			consent_transactional_sms: !!e && h.consent,
			attribution: Se()
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
				}, ze(d.widgetId, y), x = [{
					localId: z(),
					body: h.message.trim(),
					idempotencyKey: h.idempotencyKey,
					status: "sending"
				}], xe(), $();
				return;
			}
			v = e.status === 429 ? "That's a lot of messages at once. Please try again in a moment." : e.status === 409 || e.status === 503 ? "We can't take messages right now. Please try again later." : "Your message couldn't be sent. Please try again.";
		} catch {
			v = "Your message couldn't be sent. Please check your connection and try again.";
		} finally {
			g = !1, J();
		}
	}
	function dt(e) {
		let n = F("section", `wc-panel wc-panel--${e.launcherPosition}`);
		n.setAttribute("role", "dialog"), n.setAttribute("aria-label", `${e.businessName} chat`);
		let i = F("header", "wc-panel__header"), a = F("h2", "wc-panel__title");
		a.textContent = e.businessName;
		let o = F("button", "wc-panel__close");
		o.type = "button", o.setAttribute("aria-label", "Close chat"), o.innerHTML = ue, o.addEventListener("click", () => {
			m = !1, Y(), ct(), $();
		}), i.append(I("base", e.businessName), a, o);
		let s = F("div", "wc-panel__body"), c = F("footer", "wc-panel__footer"), l = document.createElement("em");
		if (l.textContent = e.businessName, c.append(document.createTextNode("Powered by "), l), e.status !== "live") return s.appendChild(Ae(e.status === "draft" ? "This chat isn't set up yet." : "This chat isn't available right now.")), n.append(i, s), n;
		if (y) return re ??= rt(e), s.appendChild(re), M = s, n.append(i, s), n.appendChild(S ? nt(e) : tt(e)), n.appendChild(c), Z(!0), w || Q(), st(), n;
		let u = F("div", "wc-intro"), d = F("div", "wc-intro__bubble");
		return d.textContent = e.greetingText || "Enter your question below and we will get right back to you.", u.append(I("base", e.businessName), d), s.append(u), t ? (h ??= be(e.widgetId), te ??= Le(e), s.appendChild(te)) : (s.appendChild(ke()), r().then(() => {
			m && $();
		})), n.append(i, s, c), n;
	}
	function $() {
		!f || !p || !d || (p.replaceChildren(), !m && !ee && d.status === "live" && d.teaserText && p.appendChild(Oe(d, d.teaserText)), p.appendChild(m ? dt(d) : De(d)));
	}
	function ft(e) {
		let t = document.createElement("div");
		t.id = "ucrm-website-chat", t.style.cssText = "all: initial; position: fixed; width: 0; height: 0; z-index: 2147483000;", document.body.appendChild(t), f = t.attachShadow({ mode: "open" });
		let n = document.createElement("style");
		n.textContent = le(e.brandColor || "#049a54"), p = document.createElement("div"), f.append(n, p), ee = pe(e.widgetId), y = Re(e.widgetId), lt(), $();
	}
	async function pt() {
		try {
			let e = await fetch(`${o}/api/webchat/config?token=${encodeURIComponent(i)}`, { credentials: "omit" });
			return e.status === 200 ? (await e.json()).config ?? null : null;
		} catch {
			return null;
		}
	}
	async function mt() {
		let e = await pt();
		e && (d = e, document.body ? ft(e) : document.addEventListener("DOMContentLoaded", () => ft(e)));
	}
	mt();
})();
//#endregion
