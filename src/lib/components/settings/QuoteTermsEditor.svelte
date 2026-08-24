<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import boldIcon from '@tabler/icons/outline/bold.svg?raw';
	import italicIcon from '@tabler/icons/outline/italic.svg?raw';
	import linkIcon from '@tabler/icons/outline/link.svg?raw';
	import unlinkIcon from '@tabler/icons/outline/unlink.svg?raw';
	import h2Icon from '@tabler/icons/outline/h-2.svg?raw';
	import h3Icon from '@tabler/icons/outline/h-3.svg?raw';
	import pilcrowIcon from '@tabler/icons/outline/pilcrow.svg?raw';
	import listIcon from '@tabler/icons/outline/list.svg?raw';
	import listNumbersIcon from '@tabler/icons/outline/list-numbers.svg?raw';

	// A small formatting box for the one place in the app that needs paragraphs, headings, lists, bold,
	// italic, and links and nothing else — the server's own sanitizer allow-lists exactly this set, so the
	// toolbar only offers what would survive the round trip anyway. `document.execCommand` is deprecated but
	// still the pragmatic no-dependency way to drive a contenteditable box for a set this small; the server
	// stays the real security boundary regardless of what this produces.
	let {
		value = $bindable(''),
		id,
		disabled = false
	}: {
		value?: string;
		id: string;
		disabled?: boolean;
	} = $props();

	let editor = $state<HTMLDivElement | null>(null);
	let focused = $state(false);
	let linkPromptOpen = $state(false);
	let linkUrl = $state('');
	let savedSelection: Range | null = null;

	let activeBold = $state(false);
	let activeItalic = $state(false);
	let activeLink = $state(false);
	let activeBlock = $state('p');

	// External updates (load, Cancel, a fresh save's sanitized echo) only touch the DOM while the user isn't
	// mid-edit — otherwise a re-render would yank the caret, the same rule MoneyInput and Business Profile's
	// timezone field already follow for a plain input.
	$effect(() => {
		if (!editor || focused) return;
		const next = value || '';
		if (editor.innerHTML !== next) editor.innerHTML = next;
	});

	function handleInput() {
		if (!editor) return;
		value = editor.innerHTML;
	}

	function refreshToolbarState() {
		if (!editor) return;
		const selection = window.getSelection();
		if (!selection || !selection.anchorNode || !editor.contains(selection.anchorNode)) return;
		activeBold = document.queryCommandState('bold');
		activeItalic = document.queryCommandState('italic');
		const anchor =
			selection.anchorNode instanceof Element
				? selection.anchorNode
				: selection.anchorNode.parentElement;
		activeLink = Boolean(anchor?.closest('a'));
		activeBlock = (document.queryCommandValue('formatBlock') || 'p').toLowerCase();
	}

	$effect(() => {
		document.addEventListener('selectionchange', refreshToolbarState);
		return () => document.removeEventListener('selectionchange', refreshToolbarState);
	});

	function focusEditor() {
		editor?.focus();
	}

	function exec(command: string, arg?: string) {
		if (disabled || !editor) return;
		focusEditor();
		document.execCommand('styleWithCSS', false, 'false');
		document.execCommand(command, false, arg);
		handleInput();
		refreshToolbarState();
	}

	function toggleBlock(tag: 'p' | 'h2' | 'h3') {
		exec('formatBlock', `<${tag}>`);
	}

	// mousedown (not click) fires before the browser would otherwise move focus off the editor and collapse
	// the selection, which is what every toolbar button needs preserved to act on the right text.
	function preserveSelection(event: MouseEvent) {
		event.preventDefault();
	}

	function openLinkPrompt() {
		if (disabled || !editor) return;
		const selection = window.getSelection();
		if (selection && selection.rangeCount > 0 && editor.contains(selection.anchorNode)) {
			savedSelection = selection.getRangeAt(0).cloneRange();
		}
		linkUrl = '';
		linkPromptOpen = true;
	}

	function applyLink() {
		if (!editor) return;
		const url = linkUrl.trim();
		if (!url) {
			linkPromptOpen = false;
			return;
		}
		focusEditor();
		if (savedSelection) {
			const selection = window.getSelection();
			selection?.removeAllRanges();
			selection?.addRange(savedSelection);
		}
		document.execCommand('createLink', false, url);
		handleInput();
		linkPromptOpen = false;
		refreshToolbarState();
	}

	function cancelLinkPrompt() {
		linkPromptOpen = false;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="quote-terms-editor" class:quote-terms-editor--disabled={disabled}>
	<div
		class="quote-terms-editor__toolbar"
		role="toolbar"
		aria-label="Formatting"
		aria-controls={id}
	>
		<button
			type="button"
			class="quote-terms-editor__tool"
			class:quote-terms-editor__tool--active={activeBlock === 'p' || activeBlock === 'div'}
			title="Paragraph"
			{disabled}
			onmousedown={preserveSelection}
			onclick={() => toggleBlock('p')}><span aria-hidden="true">{@html pilcrowIcon}</span></button
		>
		<button
			type="button"
			class="quote-terms-editor__tool"
			class:quote-terms-editor__tool--active={activeBlock === 'h2'}
			title="Heading"
			{disabled}
			onmousedown={preserveSelection}
			onclick={() => toggleBlock('h2')}><span aria-hidden="true">{@html h2Icon}</span></button
		>
		<button
			type="button"
			class="quote-terms-editor__tool"
			class:quote-terms-editor__tool--active={activeBlock === 'h3'}
			title="Subheading"
			{disabled}
			onmousedown={preserveSelection}
			onclick={() => toggleBlock('h3')}><span aria-hidden="true">{@html h3Icon}</span></button
		>
		<span class="quote-terms-editor__divider" aria-hidden="true"></span>
		<button
			type="button"
			class="quote-terms-editor__tool"
			class:quote-terms-editor__tool--active={activeBold}
			title="Bold"
			{disabled}
			onmousedown={preserveSelection}
			onclick={() => exec('bold')}><span aria-hidden="true">{@html boldIcon}</span></button
		>
		<button
			type="button"
			class="quote-terms-editor__tool"
			class:quote-terms-editor__tool--active={activeItalic}
			title="Italic"
			{disabled}
			onmousedown={preserveSelection}
			onclick={() => exec('italic')}><span aria-hidden="true">{@html italicIcon}</span></button
		>
		<span class="quote-terms-editor__divider" aria-hidden="true"></span>
		<button
			type="button"
			class="quote-terms-editor__tool"
			title="Bullet list"
			{disabled}
			onmousedown={preserveSelection}
			onclick={() => exec('insertUnorderedList')}
			><span aria-hidden="true">{@html listIcon}</span></button
		>
		<button
			type="button"
			class="quote-terms-editor__tool"
			title="Numbered list"
			{disabled}
			onmousedown={preserveSelection}
			onclick={() => exec('insertOrderedList')}
			><span aria-hidden="true">{@html listNumbersIcon}</span></button
		>
		<span class="quote-terms-editor__divider" aria-hidden="true"></span>
		<button
			type="button"
			class="quote-terms-editor__tool"
			class:quote-terms-editor__tool--active={activeLink}
			title="Link"
			{disabled}
			onmousedown={preserveSelection}
			onclick={openLinkPrompt}><span aria-hidden="true">{@html linkIcon}</span></button
		>
		{#if activeLink}
			<button
				type="button"
				class="quote-terms-editor__tool"
				title="Remove link"
				{disabled}
				onmousedown={preserveSelection}
				onclick={() => exec('unlink')}><span aria-hidden="true">{@html unlinkIcon}</span></button
			>
		{/if}
	</div>

	{#if linkPromptOpen}
		<div class="quote-terms-editor__link-prompt">
			<Input
				id={`${id}-link-url`}
				label="Link URL"
				size="small"
				type="url"
				placeholder="https://example.com"
				bind:value={linkUrl}
				onkeydown={(event: KeyboardEvent) => {
					if (event.key === 'Enter') applyLink();
					if (event.key === 'Escape') cancelLinkPrompt();
				}}
			/>
			<Button size="small" onclick={applyLink}>Add</Button>
			<Button size="small" variant="tertiary" onclick={cancelLinkPrompt}>Cancel</Button>
		</div>
	{/if}

	<div
		bind:this={editor}
		{id}
		class="quote-terms-editor__surface"
		contenteditable={!disabled}
		data-placeholder="No terms and conditions yet. This is copied into every new quote draft."
		role="textbox"
		aria-multiline="true"
		oninput={handleInput}
		onfocus={() => (focused = true)}
		onblur={() => (focused = false)}
	></div>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.quote-terms-editor {
		display: flex;
		flex-direction: column;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		overflow: hidden;

		&:focus-within {
			box-shadow: var(--shadow-focus);
		}

		&--disabled {
			background: var(--color-disabled--secondary);
		}

		&__toolbar {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-smallest);
			padding: var(--space-smaller);
			border-bottom: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background);
		}

		&__tool {
			display: grid;
			width: 30px;
			height: 30px;
			place-items: center;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-small);
			color: var(--color-text--secondary);
			background: transparent;
			cursor: pointer;

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			&:hover:not(:disabled) {
				color: var(--color-heading);
				background: var(--color-surface--hover);
			}
			&:disabled {
				color: var(--color-disabled);
				cursor: not-allowed;
			}
			&--active {
				color: var(--color-interactive);
				border-color: var(--color-interactive);
				background: var(--color-surface);
			}
		}

		&__divider {
			width: var(--border-base);
			height: 20px;
			margin: 0 var(--space-smallest);
			background: var(--color-border);
		}

		&__link-prompt {
			display: flex;
			align-items: flex-end;
			gap: var(--space-small);
			padding: var(--space-small);
			border-bottom: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background);

			:global(.input) {
				flex: 1;
			}
		}

		&__surface {
			min-height: 180px;
			padding: var(--space-base);
			color: var(--color-heading);
			background: var(--color-surface);
			line-height: var(--typography--lineHeight-large);
			overflow-y: auto;

			&:focus {
				outline: none;
			}

			:global(p) {
				margin: 0 0 var(--space-small);
			}
			:global(h2) {
				margin: var(--space-base) 0 var(--space-small);
				font-size: var(--typography--fontSize-large);
				font-weight: 700;
			}
			:global(h3) {
				margin: var(--space-base) 0 var(--space-small);
				font-size: var(--typography--fontSize-base);
				font-weight: 700;
			}
			:global(ul),
			:global(ol) {
				margin: 0 0 var(--space-small);
				padding-left: var(--space-large);
			}
			:global(a) {
				color: var(--color-interactive);
			}

			&:empty::before {
				content: attr(data-placeholder);
				color: var(--color-text--secondary);
			}
		}
	}
</style>
