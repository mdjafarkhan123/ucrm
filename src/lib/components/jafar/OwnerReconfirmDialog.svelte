<script lang="ts">
	import { AlertDialog } from 'bits-ui';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';

	let {
		open = $bindable(false),
		title,
		description,
		confirmLabel = 'Confirm',
		onConfirm
	}: {
		open?: boolean;
		title: string;
		description: string;
		confirmLabel?: string;
		onConfirm: () => void;
	} = $props();

	let password = $state('');
	let submitting = $state(false);
	let errorMessage = $state('');

	function reset() {
		password = '';
		submitting = false;
		errorMessage = '';
	}

	$effect(() => {
		if (!open) reset();
	});

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (!password || submitting) return;

		submitting = true;
		errorMessage = '';
		try {
			const response = await fetch('/api/jafar/reconfirm', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ password })
			});
			const result = (await response.json()) as { error?: string };
			if (!response.ok) {
				errorMessage = result.error ?? 'The password is not correct.';
				return;
			}
			open = false;
			onConfirm();
		} catch {
			errorMessage = 'Reconfirmation could not be completed. Try again.';
		} finally {
			submitting = false;
		}
	}
</script>

<AlertDialog.Root bind:open>
	<AlertDialog.Portal>
		<AlertDialog.Overlay class="owner-reconfirm-dialog__overlay" />
		<AlertDialog.Content class="owner-reconfirm-dialog__content">
			<form onsubmit={submit}>
				<AlertDialog.Title level={2}>{title}</AlertDialog.Title>
				<AlertDialog.Description>{description}</AlertDialog.Description>
				<Input
					id="owner-reconfirm-password"
					label="Your password"
					type="password"
					autocomplete="current-password"
					bind:value={password}
					invalid={Boolean(errorMessage)}
					{errorMessage}
					disabled={submitting}
				/>
				<div class="owner-reconfirm-dialog__actions">
					<Button type="submit" variation="destructive" loading={submitting}>{confirmLabel}</Button>
					<AlertDialog.Cancel
						>{#snippet child({ props })}<Button
								{...props}
								type="button"
								variant="secondary"
								variation="subtle"
								disabled={submitting}>Cancel</Button
							>{/snippet}</AlertDialog.Cancel
					>
				</div>
			</form>
		</AlertDialog.Content>
	</AlertDialog.Portal>
</AlertDialog.Root>

<style lang="scss">
	:global(.owner-reconfirm-dialog__overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: var(--color-overlay);
	}
	:global(.owner-reconfirm-dialog__content) {
		position: fixed;
		top: 50%;
		left: 50%;
		z-index: var(--elevation-modal);
		width: min(calc(100vw - var(--space-large) * 2), 420px);
		max-height: calc(100dvh - var(--space-large) * 2);
		overflow: auto;
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
		transform: translate(-50%, -50%);
	}
	:global(.owner-reconfirm-dialog__content form) {
		display: grid;
		gap: var(--space-base);
	}
	:global(.owner-reconfirm-dialog__content [data-slot='alert-dialog-title']) {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tightest);
	}
	:global(.owner-reconfirm-dialog__content [data-slot='alert-dialog-description']) {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.owner-reconfirm-dialog__actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
</style>
