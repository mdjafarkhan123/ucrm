<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import StickyActionBar from './StickyActionBar.svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	// The save bar every detail page uses. A detail page is read-first: this stays out of the way until a
	// block is opened for editing, then appears at the bottom to save or throw away everything staged so
	// far. Blocks that save the moment they are clicked — tags, notes, attachments — stay outside the
	// draft, so this bar never claims to be saving them.
	//
	// Opening a block and changing something are two different things, and the bar owns what each one
	// means so every detail page behaves the same way. Opening one shows the bar, because Cancel is the
	// only way back out of an editor. Save stays greyed out until something has actually changed, so it
	// never offers to write a change nobody made.
	//
	// The look is the concept's floating save bar (Pencil "Record page frame"): a dot and a short state on the
	// left — grey while nothing has changed, amber once something has or while saving, red when the save
	// failed — with the hint beside it.
	let {
		editing = false,
		dirty,
		saving = false,
		error = '',
		message = 'You have changes waiting to be saved.',
		editingMessage = 'Make your changes, then save them here.',
		saveLabel = 'Save changes',
		onSave,
		onCancel
	}: {
		/** True while any block is open for editing, changed or not. Shows the bar so Cancel is reachable. */
		editing?: boolean;
		/** True once a block has staged a real change. Shows the bar, and enables Save. */
		dirty: boolean;
		saving?: boolean;
		/** Shown in place of the message when a save fails. */
		error?: string;
		message?: string;
		/** Shown while a block is open but nothing has changed yet. */
		editingMessage?: string;
		saveLabel?: string;
		onSave: () => void;
		onCancel: () => void;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if editing || dirty}
	<StickyActionBar concept>
		<p
			class={[
				'detail-edit-bar__status',
				error
					? 'detail-edit-bar__status--failed'
					: (dirty || saving) && 'detail-edit-bar__status--changed'
			]}
			role="status"
		>
			<span class="detail-edit-bar__dot" aria-hidden="true"></span>
			<span class="detail-edit-bar__state"
				>{error
					? "Couldn't save"
					: saving
						? 'Saving…'
						: dirty
							? 'Changes not saved yet'
							: 'Editing'}</span
			>
			<span class="detail-edit-bar__hint"
				>{error || (saving ? 'Saving your changes.' : dirty ? message : editingMessage)}</span
			>
		</p>
		<div class="detail-edit-bar__buttons">
			<Button variant="secondary" onclick={onCancel} disabled={saving}>Cancel</Button>
			<Button variant="primary" onclick={onSave} loading={saving} disabled={!dirty}>
				<span class="detail-edit-bar__icon" aria-hidden="true">{@html checkIcon}</span>
				{saveLabel}
			</Button>
		</div>
	</StickyActionBar>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.detail-edit-bar {
		&__status {
			--detail-edit-bar-dot: var(--color-inactive);
			display: flex;
			flex: 1 1 auto;
			min-width: 0;
			align-items: center;
			gap: var(--space-small);

			&--changed {
				--detail-edit-bar-dot: var(--color-warning);
			}

			&--failed {
				--detail-edit-bar-dot: var(--color-critical);
			}
		}

		&__dot {
			flex: 0 0 auto;
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
			background: var(--detail-edit-bar-dot);
		}

		&__state {
			flex: 0 0 auto;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__hint {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__status--failed &__hint {
			color: var(--color-critical--onSurface);
			font-weight: 600;
		}

		&__icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__buttons {
			display: flex;
			flex: 0 0 auto;
			gap: var(--space-small);
		}
	}
</style>
