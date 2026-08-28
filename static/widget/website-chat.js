//#region src/widget/website-chat.ts
var e = null, t = null;
function n() {
	return t ??= import("./website-chat-phone.js").then((t) => e = t).catch(() => null), t;
}
var r = null;
function i() {
	return r ??= import("./website-chat-realtime.js").then((e) => e).catch(() => null), r;
}
(function() {
	let t = Array.from(document.querySelectorAll("script[data-widget-token]")), r = (t.find((e) => e.src === import.meta.url) ?? t[0] ?? null)?.getAttribute("data-widget-token") ?? "";
	if (!r) return;
	let a = new URL(import.meta.url, window.location.href).origin, o = (e) => `ucrm-wc-teaser-dismissed-${e}`, s = (e) => `ucrm-wc-draft-${e}`, c = (e) => `ucrm-wc-session-${e}`, l = (e) => `ucrm-wc-composer-${e}`, u = null, d = null, f = null, p = !1, ee = !0, m = null, h = !1, g = /* @__PURE__ */ new Set(), _ = "", te = null, v = null, y = [], ne = /* @__PURE__ */ new Set(), b = [], x = !1, S = !1, C = !1, w = !1, T = "", re = null, E = null, D = null, O = null, k = null, A = null, j = null, M = null, N = null, ie = 0, ae = !1, oe = null, se = null, ce = !1;
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
	function P(e, t) {
		let n = document.createElement(e);
		return n.className = t, n;
	}
	function F(e, t) {
		let n = P("span", `wc-avatar wc-avatar--${e}`);
		return n.setAttribute("aria-hidden", "true"), n.textContent = fe(t), n;
	}
	function pe(e) {
		try {
			return localStorage.getItem(o(e)) === "1";
		} catch {
			return !1;
		}
	}
	function me() {
		if (u) {
			ee = !0;
			try {
				localStorage.setItem(o(u.widgetId), "1");
			} catch {}
			$();
		}
	}
	let he = null;
	function I(e) {
		try {
			return he ??= new Intl.DisplayNames(void 0, { type: "region" }), he.of(e) ?? e;
		} catch {
			return e;
		}
	}
	function L(e) {
		return String.fromCodePoint(...[...e].map((e) => 127462 + e.toUpperCase().charCodeAt(0) - 65));
	}
	let ge = null;
	function _e() {
		let t = e;
		return t ? (ge ??= t.getCountries().map((e) => ({
			code: e,
			name: I(e),
			dial: `+${t.getCountryCallingCode(e)}`
		})).sort((e, t) => e.name.localeCompare(t.name)), ge) : [];
	}
	function ve() {
		let t = new Set(e?.getCountries() ?? []);
		for (let e of navigator.languages ?? [navigator.language]) {
			let n = new Intl.Locale(e).maximize().region;
			if (n && t.has(n)) return n;
		}
		return "US";
	}
	function R() {
		return crypto.randomUUID ? crypto.randomUUID() : `wc-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
	}
	function ye() {
		return {
			name: "",
			country: ve(),
			phone: "",
			email: "",
			message: "",
			consent: !0,
			idempotencyKey: R()
		};
	}
	function be(e) {
		let t = ye();
		try {
			let n = localStorage.getItem(s(e));
			if (!n) return t;
			let r = JSON.parse(n);
			return {
				name: typeof r.name == "string" ? r.name : "",
				country: r.country || t.country,
				phone: typeof r.phone == "string" ? r.phone : "",
				email: typeof r.email == "string" ? r.email : "",
				message: typeof r.message == "string" ? r.message : "",
				consent: r.consent !== !1,
				idempotencyKey: r.idempotencyKey || t.idempotencyKey
			};
		} catch {
			return t;
		}
	}
	function z() {
		if (!(!u || !m)) try {
			localStorage.setItem(s(u.widgetId), JSON.stringify(m));
		} catch {}
	}
	function xe() {
		if (u) try {
			localStorage.removeItem(s(u.widgetId));
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
	function we(t) {
		let n = e?.parsePhoneNumberFromString(t.phone, t.country);
		return n?.isValid() ? n.number : null;
	}
	function Te(e) {
		let t = u?.contactRequirement ?? "either";
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
		let t = P("button", `wc-launcher wc-launcher--${e.launcherPosition}`);
		return t.type = "button", t.setAttribute("aria-label", `Open chat with ${e.businessName}`), t.innerHTML = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M3 20l1.3 -3.9c-2.324 -3.437 -1.426 -7.872 2.1 -10.374c3.526 -2.501 8.59 -2.296 11.845 .48c3.255 2.777 3.695 7.266 1.029 10.501c-2.666 3.235 -7.615 4.215 -11.574 2.293l-4.7 1\" /></svg>", t.addEventListener("pointerenter", B, { once: !0 }), t.addEventListener("focus", B, { once: !0 }), t.addEventListener("click", () => {
			p = !0, $();
		}), t;
	}
	function Oe(e, t) {
		let n = P("button", `wc-teaser wc-teaser--${e.launcherPosition}`);
		n.type = "button", n.addEventListener("pointerenter", B, { once: !0 }), n.addEventListener("focus", B, { once: !0 }), n.addEventListener("click", () => {
			p = !0, $();
		});
		let r = P("span", "wc-teaser__text");
		r.textContent = t;
		let i = P("span", "wc-teaser__dismiss");
		return i.setAttribute("role", "button"), i.setAttribute("tabindex", "0"), i.setAttribute("aria-label", "Dismiss"), i.innerHTML = ue, i.addEventListener("click", (e) => {
			e.stopPropagation(), me();
		}), i.addEventListener("keydown", (e) => {
			(e.key === "Enter" || e.key === " ") && (e.preventDefault(), e.stopPropagation(), me());
		}), n.append(F("medium", e.businessName), r, i), n;
	}
	function B() {
		n();
	}
	function ke() {
		let e = P("div", "wc-skeleton");
		e.setAttribute("aria-hidden", "true");
		for (let t of [
			40,
			40,
			40,
			64,
			44
		]) {
			let n = P("div", "wc-skeleton__bar");
			n.style.height = `${t}px`, e.appendChild(n);
		}
		return e;
	}
	function Ae(e, t) {
		let n = P("div", "wc-empty"), r = P("p", "wc-empty__title");
		if (r.textContent = e, n.appendChild(r), t) {
			let e = P("p", "wc-empty__description");
			e.textContent = t, n.appendChild(e);
		}
		return n;
	}
	let je = /* @__PURE__ */ new Map(), V = null, H = null, U = null, W = null, G = null;
	function K(e, t, n = "") {
		let r = P("div", `wc-field ${n}`.trim()), i = P("p", "wc-field__error");
		return i.hidden = !0, r.append(t, i), je.set(e, {
			wrapper: r,
			error: i
		}), r;
	}
	function Me(e, t = "text") {
		let n = P("input", "wc-input");
		return n.type = t, n.placeholder = e, n.setAttribute("aria-label", e), n.autocomplete = "off", n;
	}
	function q() {
		if (!m) return;
		let e = Ee(m);
		for (let [t, n] of je) {
			let r = g.has(t) ? e[t] : void 0;
			n.error.textContent = r ?? "", n.error.hidden = !r, n.wrapper.classList.toggle("wc-field--invalid", !!r);
		}
		V && (V.disabled = h || Object.keys(e).length > 0), H && (H.textContent = _, H.hidden = !_);
	}
	function Ne(t) {
		if (!(!m || !e)) {
			if (m.country = t, W) {
				let e = W.querySelector(".wc-phone__flag");
				e && (e.textContent = L(t)), W.setAttribute("aria-label", `Country: ${I(t)}`);
			}
			U && (U.value = new e.AsYouType(t).input(m.phone), m.phone = U.value), z(), q();
		}
	}
	function J() {
		G?.remove(), G = null, W?.setAttribute("aria-expanded", "false");
	}
	function Pe(e) {
		if (G) {
			J();
			return;
		}
		let t = P("div", "wc-country"), n = P("input", "wc-country__search");
		n.type = "search", n.placeholder = "Search countries", n.setAttribute("aria-label", "Search countries");
		let r = P("ul", "wc-country__list");
		function i(e) {
			let t = e.trim().toLowerCase(), n = _e().filter((e) => !t || e.name.toLowerCase().includes(t) || e.code.toLowerCase().includes(t) || e.dial.includes(t));
			if (r.replaceChildren(), n.length === 0) {
				let e = P("li", "wc-country__empty");
				e.textContent = "No matching country", r.appendChild(e);
				return;
			}
			for (let e of n) {
				let t = document.createElement("li"), n = P("button", "wc-country__option");
				n.type = "button";
				let i = P("span", "wc-phone__flag");
				i.textContent = L(e.code);
				let a = P("span", "wc-country__name");
				a.textContent = e.name;
				let o = P("span", "wc-country__dial");
				o.textContent = e.dial, n.append(i, a, o), n.addEventListener("click", () => {
					Ne(e.code), J(), U?.focus();
				}), t.appendChild(n), r.appendChild(t);
			}
		}
		n.addEventListener("input", () => i(n.value)), t.addEventListener("keydown", (e) => {
			e.key === "Escape" && (e.stopPropagation(), J(), W?.focus());
		}), i(""), t.append(n, r), e.appendChild(t), G = t, W?.setAttribute("aria-expanded", "true"), n.focus();
		let a = (t) => {
			t.composedPath().includes(e) || (J(), d?.removeEventListener("mousedown", a));
		};
		d?.addEventListener("mousedown", a);
	}
	function Fe() {
		let t = P("div", "wc-phone");
		W = P("button", "wc-phone__country"), W.type = "button", W.setAttribute("aria-haspopup", "listbox"), W.setAttribute("aria-expanded", "false");
		let n = P("span", "wc-phone__flag");
		return n.textContent = L(m.country), W.append(n), W.insertAdjacentHTML("beforeend", "<svg class=\"wc-phone__caret\" xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M6 9l6 6l6 -6\" /></svg>"), W.setAttribute("aria-label", `Country: ${I(m.country)}`), W.addEventListener("click", () => Pe(t)), U = Me("Phone", "tel"), U.autocomplete = "tel", U.value = new e.AsYouType(m.country).input(m.phone), U.addEventListener("input", () => {
			if (!m || !U || !e) return;
			let t = U.value;
			if (t.trim().startsWith("+")) {
				let n = new e.AsYouType().input(t), r = e.parsePhoneNumberFromString(t);
				if (U.value = n, r?.country && r.country !== m.country) {
					m.country = r.country;
					let e = W?.querySelector(".wc-phone__flag");
					e && (e.textContent = L(r.country)), W?.setAttribute("aria-label", `Country: ${I(r.country)}`);
				}
			} else U.value = new e.AsYouType(m.country).input(t);
			m.phone = U.value, z(), q();
		}), U.addEventListener("blur", () => {
			g.add("phone"), q();
		}), t.append(W, U), K("phone", t);
	}
	function Ie(e) {
		let t = document.createElement("form");
		t.className = "wc-form", t.noValidate = !0;
		let n = Me("Name");
		n.autocomplete = "name", n.value = m.name, n.addEventListener("input", () => {
			m.name = n.value, z(), q();
		}), n.addEventListener("blur", () => {
			g.add("name"), q();
		});
		let r = Me("E-mail", "email");
		r.autocomplete = "email", r.value = m.email, r.addEventListener("input", () => {
			m.email = r.value, z(), q();
		}), r.addEventListener("blur", () => {
			g.add("email"), q();
		});
		let i = P("textarea", "wc-textarea");
		i.placeholder = "I want to know more", i.setAttribute("aria-label", "Message"), i.maxLength = 5e3, i.value = m.message, i.addEventListener("input", () => {
			m.message = i.value, z(), q();
		}), i.addEventListener("blur", () => {
			g.add("message"), q();
		});
		let a = P("input", "wc-hp");
		a.type = "text", a.name = "company_website", a.tabIndex = -1, a.autocomplete = "off", a.setAttribute("aria-hidden", "true");
		let o = P("label", "wc-consent"), s = document.createElement("input");
		s.type = "checkbox", s.checked = m.consent, s.addEventListener("change", () => {
			m.consent = s.checked, z();
		});
		let c = P("span", "wc-consent__text");
		if (c.textContent = "By submitting you agree to receive SMS or e-mails for the provided channel. Rates may be applied.", o.append(s, c), H = P("p", "wc-form__banner"), H.hidden = !0, H.setAttribute("role", "alert"), V = P("button", "wc-send"), V.type = "submit", V.innerHTML = `<span>Send</span>${de}`, t.append(K("name", n), Fe(), K("email", r), K("message", i), a, o), e.privacyPolicyUrl) {
			let n = P("a", "wc-privacy");
			n.href = e.privacyPolicyUrl, n.target = "_blank", n.rel = "noopener noreferrer", n.textContent = "Privacy policy", t.appendChild(n);
		}
		return t.append(H, V), t.addEventListener("submit", (e) => {
			e.preventDefault(), ct();
		}), q(), t;
	}
	function Le(e) {
		try {
			let t = localStorage.getItem(c(e));
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
	function Re(e, t) {
		try {
			localStorage.setItem(c(e), JSON.stringify(t));
		} catch {}
	}
	function ze(e) {
		try {
			localStorage.removeItem(c(e)), localStorage.removeItem(l(e));
		} catch {}
	}
	function Be(e) {
		try {
			return localStorage.getItem(l(e)) ?? "";
		} catch {
			return "";
		}
	}
	function Ve(e, t) {
		try {
			t ? localStorage.setItem(l(e), t) : localStorage.removeItem(l(e));
		} catch {}
	}
	function He(e, t) {
		return e.created_at === t.created_at ? e.id < t.id ? -1 : +(e.id > t.id) : e.created_at < t.created_at ? -1 : 1;
	}
	function Y(e) {
		let t = !1;
		for (let n of e) if (!(!n || typeof n.id != "string" || ne.has(n.id)) && (ne.add(n.id), y.push(n), t = !0, n.direction === "inbound")) {
			let e = b.findIndex((e) => e.body === n.body);
			e !== -1 && b.splice(e, 1);
		}
		return t && y.sort(He), t;
	}
	function Ue(e) {
		let t = new Date(e), n = /* @__PURE__ */ new Date(), r = new Date(n);
		r.setDate(n.getDate() - 1);
		let i = (e, t) => e.toDateString() === t.toDateString();
		return i(t, n) ? "Today" : i(t, r) ? "Yesterday" : t.toLocaleDateString(void 0, {
			day: "numeric",
			month: "short",
			year: "numeric"
		});
	}
	function We(e) {
		return new Date(e).toLocaleTimeString(void 0, {
			hour: "numeric",
			minute: "2-digit"
		});
	}
	function Ge(e, t) {
		if (e.sender_type === "system") {
			let t = P("p", "wc-note");
			return t.textContent = e.body, t;
		}
		let n = e.direction === "outbound", r = P("div", `wc-msg wc-msg--${n ? "in" : "out"}`), i = P("div", "wc-msg__row");
		n && i.appendChild(F("base", t));
		let a = P("div", "wc-msg__bubble");
		a.textContent = e.body, i.appendChild(a);
		let o = P("p", "wc-msg__meta"), s = e.sender_type === "automation" ? `${t} · Automated` : t;
		return o.textContent = n ? `${s} · ${We(e.created_at)}` : We(e.created_at), r.append(i, o), r;
	}
	function Ke(e) {
		let t = P("div", `wc-msg wc-msg--out ${e.status === "sending" ? "wc-msg--sending" : ""}`.trim()), n = P("div", "wc-msg__row"), r = P("div", "wc-msg__bubble");
		if (r.textContent = e.body, n.appendChild(r), t.appendChild(n), e.status === "failed") {
			let n = P("button", "wc-msg__retry");
			n.type = "button", n.textContent = "Not sent — tap to retry", n.addEventListener("click", () => void Ze(e)), t.appendChild(n);
		} else {
			let e = P("p", "wc-msg__meta");
			e.textContent = "Sending…", t.appendChild(e);
		}
		return t;
	}
	function qe() {
		return !j || j.scrollHeight - j.scrollTop - j.clientHeight < 60;
	}
	function Je() {
		j && (j.scrollTop = j.scrollHeight);
	}
	function X(e) {
		if (!E || !u) return;
		let t = e || qe(), n = [], r = "";
		for (let e of y) {
			let t = Ue(e.created_at);
			if (t !== r) {
				let e = P("span", "wc-day");
				e.textContent = t, n.push(e), r = t;
			}
			n.push(Ge(e, u.businessName));
		}
		for (let e of b) n.push(Ke(e));
		E.replaceChildren(...n), D && (D.hidden = !w, D.disabled = S, D.textContent = S ? "Loading…" : "Load earlier messages"), O && (O.textContent = T, O.hidden = !T), Q(), t && Je();
	}
	async function Ye(e, t) {
		if (!v) return null;
		let n = new URLSearchParams({
			token: r,
			page_size: String(e)
		});
		t && (n.set("before_created_at", t.created_at), n.set("before_id", t.id));
		let i = await fetch(`${a}/api/webchat/sessions/messages?${n.toString()}`, {
			credentials: "omit",
			headers: { authorization: `Bearer ${v.sessionToken}` }
		});
		return i.status === 429 ? "rate_limited" : i.status === 200 ? await i.json() : null;
	}
	async function Z(e = 30) {
		if (v) try {
			let t = await Ye(e);
			if (t === "rate_limited" || t === null || t.status !== "ok") return;
			let n = Y(t.messages ?? []), r = !!t.closed_at;
			if (r !== x) {
				x = r, n = !0, $();
				return;
			}
			C || (w = t.has_more ?? !1, C = !0, n = !0), T && (T = "", n = !0), n && X(!1);
		} catch {
			!C && !T && (T = "We can't load this conversation right now.", X(!1));
		}
	}
	async function Xe() {
		if (!v || S || y.length === 0) return;
		S = !0, X(!1);
		let e = y[0];
		try {
			let t = await Ye(30, e);
			if (t && t !== "rate_limited" && t.status === "ok") {
				let e = j?.scrollHeight ?? 0;
				Y(t.messages ?? []), w = t.has_more ?? !1, S = !1, X(!1), j && (j.scrollTop += j.scrollHeight - e);
				return;
			}
			T = t === "rate_limited" ? "That's a lot of requests at once. Please try again in a moment." : "We couldn't load older messages.";
		} catch {
			T = "We couldn't load older messages.";
		}
		S = !1, X(!1);
	}
	async function Ze(e) {
		if (v) {
			e.status = "sending", T = "", X(!1);
			try {
				let t = await fetch(`${a}/api/webchat/messages?token=${encodeURIComponent(r)}`, {
					method: "POST",
					credentials: "omit",
					headers: {
						"content-type": "application/json",
						authorization: `Bearer ${v.sessionToken}`
					},
					body: JSON.stringify({
						message: e.body,
						idempotency_key: e.idempotencyKey
					})
				});
				if (t.status === 200) {
					let n = await t.json();
					n.message_id && Y([{
						id: n.message_id,
						direction: "inbound",
						sender_type: "visitor",
						body: e.body,
						created_at: (/* @__PURE__ */ new Date()).toISOString()
					}]);
					let r = b.indexOf(e);
					r !== -1 && b.splice(r, 1), X(!0);
					return;
				}
				if (t.status === 409) {
					e.status = "failed", x = !0, T = "This conversation has ended.", $();
					return;
				}
				e.status = "failed", t.status === 429 && (T = "That's a lot of messages at once. Please try again in a moment.");
			} catch {
				e.status = "failed";
			}
			X(!1);
		}
	}
	function Qe() {
		if (!u || !v || !k) return;
		let e = k.value.trim();
		if (!e || x) return;
		let t = {
			localId: R(),
			body: e,
			idempotencyKey: R(),
			status: "sending"
		};
		b.push(t), k.value = "", k.style.height = "auto", Ve(u.widgetId, ""), X(!0), Ze(t);
	}
	function Q() {
		A && k && (A.disabled = x || k.value.trim().length === 0);
	}
	function $e(e) {
		let t = P("div", "wc-composer");
		k = P("textarea", "wc-composer__input"), k.rows = 1, k.placeholder = "Message…", k.setAttribute("aria-label", "Message"), k.maxLength = 5e3, k.value = Be(e.widgetId);
		let n = () => {
			k && (k.style.height = "auto", k.style.height = `${Math.min(k.scrollHeight, 120)}px`);
		};
		return k.addEventListener("input", () => {
			Ve(e.widgetId, k?.value ?? ""), n(), Q();
		}), k.addEventListener("keydown", (e) => {
			e.key !== "Enter" || e.shiftKey || e.isComposing || (e.preventDefault(), Qe());
		}), A = P("button", "wc-composer__send"), A.type = "button", A.setAttribute("aria-label", "Send message"), A.innerHTML = de, A.addEventListener("click", () => Qe()), t.append(k, A), queueMicrotask(n), Q(), t;
	}
	function et(e) {
		let t = P("div", "wc-ended"), n = P("p", "wc-ended__text");
		n.textContent = "This conversation has ended.";
		let r = P("button", "wc-ended__restart");
		return r.type = "button", r.textContent = "Start a new conversation", r.addEventListener("click", () => {
			ot(), ze(e.widgetId), v = null, y = [], ne.clear(), b = [], x = !1, C = !1, w = !1, T = "", re = null, E = null, k = null, A = null, m = null, te = null, g = /* @__PURE__ */ new Set(), $();
		}), t.append(n, r), t;
	}
	function tt(e) {
		let t = P("div", "wc-thread");
		D = P("button", "wc-earlier"), D.type = "button", D.textContent = "Load earlier messages", D.hidden = !0, D.addEventListener("click", () => void Xe());
		let n = P("div", "wc-intro"), r = P("div", "wc-intro__bubble");
		return r.textContent = e.greetingText || "Enter your question below and we will get right back to you.", n.append(F("base", e.businessName), r), E = P("div", "wc-thread__list"), E.setAttribute("role", "log"), E.setAttribute("aria-live", "polite"), E.setAttribute("aria-label", "Conversation"), O = P("p", "wc-thread__banner"), O.hidden = !0, O.setAttribute("role", "status"), t.append(D, n, E, O), t;
	}
	async function nt() {
		if (!v) return null;
		try {
			let e = await fetch(`${a}/api/webchat/sessions/realtime?token=${encodeURIComponent(r)}`, {
				method: "POST",
				credentials: "omit",
				headers: { authorization: `Bearer ${v.sessionToken}` }
			});
			if (e.status !== 200) return null;
			let t = await e.json();
			return !t.channel_topic || !t.expires_at || !t.supabase_url ? null : t;
		} catch {
			return null;
		}
	}
	function rt() {
		se &&= (clearTimeout(se), null);
		let e = N, t = M;
		N = null, M = null, ie = 0;
		try {
			e?.unsubscribe(), t?.disconnect();
		} catch {}
	}
	async function it() {
		if (!(!v || ae || N)) {
			ae = !0;
			try {
				let e = await nt(), t = e ? await i() : null;
				if (!e || !t || !v || !p) return;
				M = new t.RealtimeClient(`${e.supabase_url}/realtime/v1`, { params: { apikey: e.supabase_key } }), await M.setAuth(e.supabase_key), ie = new Date(e.expires_at).getTime(), N = M.channel(e.channel_topic, { config: { private: !0 } }), N.on("broadcast", { event: "website_chat_message" }, (e) => {
					let t = e?.payload;
					t?.id && (Y([t]) && X(!1), t.sender_type === "system" && Z());
				}), N.subscribe((e) => {
					if (e === "SUBSCRIBED") {
						Z();
						return;
					}
					(e === "CHANNEL_ERROR" || e === "TIMED_OUT" || e === "CLOSED") && rt();
				});
				let n = Math.max(ie - Date.now() - 6e4, 3e4);
				se = setTimeout(() => {
					rt(), it();
				}, n);
			} finally {
				ae = !1;
			}
		}
	}
	function at() {
		v && (it(), oe ??= setInterval(() => {
			document.hidden || !p || N && N.state === "joined" || Z(10);
		}, 4e3));
	}
	function ot() {
		rt(), oe &&= (clearInterval(oe), null);
	}
	function st() {
		ce || (ce = !0, window.addEventListener("pagehide", () => ot()), window.addEventListener("pageshow", (e) => {
			!e.persisted || !p || !v || (Z(), at());
		}), document.addEventListener("visibilitychange", () => {
			document.hidden || !p || !v || (Z(), at());
		}));
	}
	async function ct() {
		if (!u || !m || h) return;
		if (g = new Set(Object.keys(m)), Object.keys(Ee(m)).length > 0) {
			q();
			return;
		}
		h = !0, _ = "", q();
		let e = we(m), t = {
			idempotency_key: m.idempotencyKey,
			name: m.name.trim(),
			...e ? { phone: e } : {},
			...m.email.trim() ? { email: m.email.trim() } : {},
			message: m.message.trim(),
			consent_transactional_sms: m.consent,
			attribution: Se()
		};
		try {
			let e = await fetch(`${a}/api/webchat/sessions?token=${encodeURIComponent(r)}`, {
				method: "POST",
				credentials: "omit",
				headers: { "content-type": "application/json" },
				body: JSON.stringify(t)
			});
			if (e.status === 200) {
				let t = await e.json();
				if (!t.session_id || !t.session_token) {
					_ = "Your message couldn't be sent. Please try again.";
					return;
				}
				v = {
					sessionId: t.session_id,
					sessionToken: t.session_token
				}, Re(u.widgetId, v), b = [{
					localId: R(),
					body: m.message.trim(),
					idempotencyKey: m.idempotencyKey,
					status: "sending"
				}], xe(), $();
				return;
			}
			_ = e.status === 429 ? "That's a lot of messages at once. Please try again in a moment." : e.status === 409 || e.status === 503 ? "We can't take messages right now. Please try again later." : "Your message couldn't be sent. Please try again.";
		} catch {
			_ = "Your message couldn't be sent. Please check your connection and try again.";
		} finally {
			h = !1, q();
		}
	}
	function lt(t) {
		let r = P("section", `wc-panel wc-panel--${t.launcherPosition}`);
		r.setAttribute("role", "dialog"), r.setAttribute("aria-label", `${t.businessName} chat`);
		let i = P("header", "wc-panel__header"), a = P("h2", "wc-panel__title");
		a.textContent = t.businessName;
		let o = P("button", "wc-panel__close");
		o.type = "button", o.setAttribute("aria-label", "Close chat"), o.innerHTML = ue, o.addEventListener("click", () => {
			p = !1, J(), ot(), $();
		}), i.append(F("base", t.businessName), a, o);
		let s = P("div", "wc-panel__body"), c = P("footer", "wc-panel__footer"), l = document.createElement("em");
		if (l.textContent = t.businessName, c.append(document.createTextNode("Powered by "), l), t.status !== "live") return s.appendChild(Ae(t.status === "draft" ? "This chat isn't set up yet." : "This chat isn't available right now.")), r.append(i, s), r;
		if (v) return re ??= tt(t), s.appendChild(re), j = s, r.append(i, s), r.appendChild(x ? et(t) : $e(t)), r.appendChild(c), X(!0), C || Z(), at(), r;
		let u = P("div", "wc-intro"), d = P("div", "wc-intro__bubble");
		return d.textContent = t.greetingText || "Enter your question below and we will get right back to you.", u.append(F("base", t.businessName), d), s.append(u), e ? (m ??= be(t.widgetId), te ??= Ie(t), s.appendChild(te)) : (s.appendChild(ke()), n().then(() => {
			p && $();
		})), r.append(i, s, c), r;
	}
	function $() {
		!d || !f || !u || (f.replaceChildren(), !p && !ee && u.status === "live" && u.teaserText && f.appendChild(Oe(u, u.teaserText)), f.appendChild(p ? lt(u) : De(u)));
	}
	function ut(e) {
		let t = document.createElement("div");
		t.id = "ucrm-website-chat", t.style.cssText = "all: initial; position: fixed; width: 0; height: 0; z-index: 2147483000;", document.body.appendChild(t), d = t.attachShadow({ mode: "open" });
		let n = document.createElement("style");
		n.textContent = le(e.brandColor || "#049a54"), f = document.createElement("div"), d.append(n, f), ee = pe(e.widgetId), v = Le(e.widgetId), st(), $();
	}
	async function dt() {
		try {
			let e = await fetch(`${a}/api/webchat/config?token=${encodeURIComponent(r)}`, { credentials: "omit" });
			return e.status === 200 ? (await e.json()).config ?? null : null;
		} catch {
			return null;
		}
	}
	async function ft() {
		let e = await dt();
		e && (u = e, document.body ? ut(e) : document.addEventListener("DOMContentLoaded", () => ut(e)));
	}
	ft();
})();
//#endregion
