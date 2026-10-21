<script lang="ts">
	import { untrack } from 'svelte';
	import InsertVariableMenu from './InsertVariableMenu.svelte';
	import {
		MARKETING_VARIABLE_TAG_LABELS,
		splitMarketingVariables,
		type MarketingVariable
	} from '$lib/marketing/campaign-content';
	import bracesIcon from '@tabler/icons/outline/braces.svg?raw';

	// A text field whose variables show as tags (design skill `layout.md` → New campaign · Email step): the
	// saved text keeps the plain `{{customer_first_name}}` form, the box draws each as a purple tag, and one
	// Backspace removes a whole tag so a variable can never be half-deleted. A contenteditable box is the
	// established way to put non-text pieces inside editable text (Mailchimp merge tags, HubSpot tokens);
	// everything typed, pasted or dropped goes in as plain text.
	let {
		value = $bindable(''),
		id,
		label,
		hideLabel = false,
		maxlength,
		multiline = false,
		placeholder = ''
	}: {
		/** The saved text, variables as `{{name}}`. */
		value?: string;
		id: string;
		label: string;
		/** The label is read out but not drawn (a block's own name already says what the box is). */
		hideLabel?: boolean;
		maxlength: number;
		/** A paragraph box: Enter starts a new line, and the Variable button sits under it. */
		multiline?: boolean;
		placeholder?: string;
	} = $props();

	let surface = $state<HTMLDivElement>();
	// The text the box last handed up, so the box redraws only when the value changed from outside.
	let lastValue = '';
	// Where the caret was when the box lost focus, for the Variable menu to insert at.
	let savedRange: Range | null = null;

	const remaining = $derived(maxlength - value.length);
	const countText = $derived(
		remaining < 0
			? `${Math.abs(remaining).toLocaleString('en')} too many`
			: `${remaining.toLocaleString('en')} left`
	);

	// A zero-width space keeps a place for the caret before a leading tag, after a trailing one and between two
	// (a browser cannot put the caret beside a tag that has no text next to it). It is never counted or saved.
	const ZWSP = '​';
	const NBSP = ' ';

	function createTag(variable: MarketingVariable): HTMLSpanElement {
		const tag = document.createElement('span');
		tag.className = 'variable-field__tag';
		tag.contentEditable = 'false';
		tag.dataset.variable = variable;
		tag.innerHTML = bracesIcon.replace(/>\s+</g, '><');
		tag.firstElementChild?.setAttribute('aria-hidden', 'true');
		const word = document.createElement('span');
		word.textContent = MARKETING_VARIABLE_TAG_LABELS[variable];
		tag.append(word);
		return tag;
	}

	function isTag(node: Node | null | undefined): node is HTMLElement {
		return node instanceof HTMLElement && 'variable' in node.dataset;
	}

	function nodesFor(text: string): Node[] {
		return splitMarketingVariables(text).map((part) =>
			part.kind === 'variable' ? createTag(part.variable) : document.createTextNode(part.text)
		);
	}

	// Every tag gets a text node on each side to hold the caret. A caret space is only ever a node of its own:
	// once real text is typed beside it the space goes, so one Backspace always removes a visible character.
	function padTags() {
		if (!surface) return;
		surface.normalize();
		for (const node of surface.childNodes) {
			if (node.nodeType !== Node.TEXT_NODE) continue;
			const text = node as Text;
			const real = text.data.replaceAll(ZWSP, '') !== '';
			// Deleting from the end keeps the caret's own position right.
			for (let at = text.data.length - 1; at >= (real ? 0 : 1); at--) {
				if (text.data[at] === ZWSP) text.deleteData(at, 1);
			}
		}
		surface.normalize();
		for (const tag of surface.querySelectorAll<HTMLElement>('[data-variable]')) {
			if (tag.previousSibling?.nodeType !== Node.TEXT_NODE) tag.before(document.createTextNode(ZWSP));
			if (tag.nextSibling?.nodeType !== Node.TEXT_NODE) tag.after(document.createTextNode(ZWSP));
		}
	}

	// A line break at the very end shows only when something follows it, so an end marker holds the line open.
	function holdTrailingLine() {
		if (!surface) return;
		const marker = surface.querySelector('br[data-end]');
		const previous = marker ? marker.previousSibling : surface.lastChild;
		const endsInBreak =
			previous?.nodeType === Node.TEXT_NODE && Boolean(previous.nodeValue?.endsWith('\n'));
		if (endsInBreak && !marker) {
			const end = document.createElement('br');
			end.dataset.end = '';
			surface.append(end);
		} else if (!endsInBreak && marker) {
			marker.remove();
		}
	}

	function draw(text: string) {
		if (!surface) return;
		surface.replaceChildren(...nodesFor(text));
		padTags();
		holdTrailingLine();
		lastValue = text;
		savedRange = null;
	}

	// The saved text of some nodes: tags become `{{name}}`, the caret spaces and the browser's own line-break
	// placeholders are dropped (every real line break is a "\n" in the text).
	function readFrom(root: ParentNode): string {
		let text = '';
		for (const node of root.childNodes) {
			if (node.nodeType === Node.TEXT_NODE) text += node.nodeValue ?? '';
			else if (isTag(node)) text += `{{${node.dataset.variable}}}`;
			else if (node instanceof HTMLElement && node.tagName !== 'BR') text += node.textContent ?? '';
		}
		return text.replaceAll(ZWSP, '').replaceAll(NBSP, ' ');
	}

	function read(): string {
		return surface ? readFrom(surface) : '';
	}

	function commit() {
		if (!surface) return;
		// Every real line break is a "\n" in the text, so a placeholder <br> from the browser has no business here.
		for (const br of surface.querySelectorAll('br:not([data-end])')) br.remove();
		let text = read();
		if (!multiline) text = text.replace(/\s*\n+\s*/g, ' ');
		// A box emptied by the keyboard must be truly empty so its placeholder comes back.
		if (text === '' && surface.childNodes.length > 0) {
			surface.replaceChildren();
		} else {
			padTags();
			holdTrailingLine();
		}
		lastValue = text;
		value = text;
	}

	// Redraw when the text changed from outside (a saved draft opening, the journey resetting it).
	$effect(() => {
		const next = value;
		untrack(() => {
			if (surface && next !== lastValue) draw(next);
		});
	});

	function rangeInBox(): Range | null {
		const selection = window.getSelection();
		if (!surface || !selection || selection.rangeCount === 0) return null;
		const range = selection.getRangeAt(0);
		return surface.contains(range.commonAncestorContainer) ? range : null;
	}

	function insertText(raw: string) {
		if (!surface) return;
		surface.focus();
		const range = rangeInBox() ?? liveSavedRange() ?? endRange();
		let text = multiline ? raw.replace(/\r\n?/g, '\n') : raw.replace(/\s*[\r\n]+\s*/g, ' ');
		// Room is what the saved text has left once the selection is replaced.
		const replaced = readFrom(range.cloneContents()).length;
		text = text.slice(0, Math.max(0, maxlength - (read().length - replaced)));
		if (!text && replaced === 0) return;

		range.deleteContents();
		const nodes = nodesFor(text);
		range.insertNode(nodes.reduce((all, node) => (all.append(node), all), document.createDocumentFragment()));
		padTags();
		// The caret goes after what was put in: for a tag, into the text node that follows it.
		const last = nodes.at(-1);
		if (last?.isConnected) {
			const next = isTag(last) ? last.nextSibling : null;
			if (next) range.setStart(next, 0);
			else range.setStartAfter(last);
		}
		range.collapse(true);
		const selection = window.getSelection();
		selection?.removeAllRanges();
		selection?.addRange(range);
		commit();
	}

	// The tag right beside the caret, if nothing but caret spaces lies between them.
	function tagBeside(range: Range, direction: 'before' | 'after'): HTMLElement | null {
		const { startContainer: node, startOffset: offset } = range;
		const step = direction === 'before' ? 'previousSibling' : 'nextSibling';
		let candidate: Node | null;
		if (node.nodeType === Node.TEXT_NODE) {
			const data = node.nodeValue ?? '';
			const between = direction === 'before' ? data.slice(0, offset) : data.slice(offset);
			if (between.replaceAll(ZWSP, '') !== '') return null;
			candidate = node[step];
		} else {
			candidate = node.childNodes[direction === 'before' ? offset - 1 : offset] ?? null;
		}
		while (
			candidate?.nodeType === Node.TEXT_NODE &&
			(candidate.nodeValue ?? '').replaceAll(ZWSP, '') === ''
		) {
			candidate = candidate[step];
		}
		return isTag(candidate) ? candidate : null;
	}

	// One Backspace or Delete next to a tag removes the whole tag.
	function handleKeyDown(event: KeyboardEvent) {
		if (event.key !== 'Backspace' && event.key !== 'Delete') return;
		const range = rangeInBox();
		if (!range || !range.collapsed) return;
		const tag = tagBeside(range, event.key === 'Backspace' ? 'before' : 'after');
		if (!tag) return;
		event.preventDefault();
		range.setStartBefore(tag);
		range.collapse(true);
		tag.remove();
		commit();
		// Back where the tag was; an emptied box takes the caret at its start.
		const caret = surface?.contains(range.startContainer) ? range : endRange();
		if (caret === range && !surface?.firstChild) caret.selectNodeContents(surface as HTMLElement);
		const selection = window.getSelection();
		selection?.removeAllRanges();
		selection?.addRange(caret);
	}

	// The remembered caret, unless a redraw has since replaced the nodes it pointed into.
	function liveSavedRange(): Range | null {
		return savedRange && surface?.contains(savedRange.commonAncestorContainer) ? savedRange : null;
	}

	function endRange(): Range {
		const range = document.createRange();
		range.selectNodeContents(surface as HTMLElement);
		range.collapse(false);
		return range;
	}

	function handleBeforeInput(event: InputEvent) {
		const type = event.inputType;
		if (type === 'insertParagraph' || type === 'insertLineBreak') {
			event.preventDefault();
			if (multiline) insertText('\n');
		} else if (type === 'insertFromPaste' || type === 'insertFromDrop') {
			event.preventDefault();
			insertText(event.dataTransfer?.getData('text/plain') ?? '');
		} else if (type === 'insertText' && event.data) {
			// Past the limit nothing more goes in (a selection being typed over frees its own room).
			const range = rangeInBox();
			const selected = range ? readFrom(range.cloneContents()).length : 0;
			if (read().length - selected + event.data.length > maxlength) event.preventDefault();
		}
	}

	function handleBlur() {
		savedRange = rangeInBox()?.cloneRange() ?? savedRange;
		if (!surface) return;
		// Typed-out `{{names}}` become tags once the box is left.
		const tags = surface.querySelectorAll('[data-variable]').length;
		const expected = splitMarketingVariables(value).filter(
			(part) => part.kind === 'variable'
		).length;
		if (tags !== expected) draw(value);
	}

	function remember() {
		const range = rangeInBox();
		if (range) savedRange = range.cloneRange();
	}

	$effect(() => {
		document.addEventListener('selectionchange', remember);
		return () => document.removeEventListener('selectionchange', remember);
	});

	const labelId = $derived(`${id}-label`);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class={['variable-field', multiline && 'variable-field--multiline']}>
	{#if !hideLabel}
		<div class="variable-field__label-row">
			<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
			<span class="variable-field__label" id={labelId} onclick={() => surface?.focus()}
				>{label}</span
			>
			<span class="variable-field__count" class:variable-field__count--over={remaining < 0}
				>{countText}</span
			>
		</div>
	{/if}

	<div class="variable-field__box">
		<div
			bind:this={surface}
			{id}
			class="variable-field__surface"
			contenteditable="true"
			role="textbox"
			tabindex="0"
			aria-multiline={multiline}
			aria-labelledby={hideLabel ? undefined : labelId}
			aria-label={hideLabel ? label : undefined}
			data-placeholder={placeholder}
			spellcheck="true"
			onbeforeinput={handleBeforeInput}
			onkeydown={handleKeyDown}
			oninput={commit}
			onblur={handleBlur}
		></div>
		{#if !multiline}
			<InsertVariableMenu onInsert={insertText} label={`Insert a variable into ${label}`} />
		{/if}
	</div>

	{#if multiline}
		<div class="variable-field__under">
			<InsertVariableMenu
				variant="labelled"
				onInsert={insertText}
				label={`Insert a variable into ${label}`}
			/>
			<span class="variable-field__count" class:variable-field__count--over={remaining < 0}
				>{countText}</span
			>
		</div>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.variable-field {
		display: flex;
		flex-direction: column;
		gap: 6px;
		min-width: 0;

		&__label-row {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__count {
			flex: none;
			margin-left: auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;

			&--over {
				color: var(--color-critical--onSurface);
			}
		}

		// The same box as every field: white, the soft grey edge, the focus ring when anything inside has focus.
		&__box {
			display: flex;
			align-items: center;
			gap: var(--space-smaller);
			min-height: 40px;
			padding: 0 6px 0 8px;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			&:hover {
				border-color: var(--color-border--interactive--hover);
			}
			&:focus-within {
				box-shadow: var(--shadow-focus);
			}
		}

		&__surface {
			flex: 1;
			min-width: 0;
			padding: 8px 0;
			outline: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			line-height: 24px;
			overflow: hidden;
			white-space: pre;

			// Nothing typed: the hint shows through.
			&:empty::before {
				content: attr(data-placeholder);
				color: var(--color-text--secondary);
				pointer-events: none;
			}
		}

		&--multiline &__box {
			align-items: flex-start;
			padding: 10px 12px;
		}
		&--multiline &__surface {
			min-height: 104px;
			padding: 0;
			white-space: pre-wrap;
			overflow-wrap: anywhere;
		}

		&__under {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		// The tags are drawn by script, so their rule reaches them by class.
		:global(.variable-field__tag) {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			height: 24px;
			margin-inline: 1px;
			padding: 0 8px;
			border: var(--border-base) solid var(--color-growth--surface-edge);
			border-radius: 6px;
			color: var(--color-growth--onSurface);
			background: var(--color-growth--surface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			line-height: 1;
			vertical-align: middle;
			user-select: none;
			white-space: nowrap;

			:global(svg) {
				width: 12px;
				height: 12px;
				color: var(--color-growth);
			}
		}
	}
</style>
