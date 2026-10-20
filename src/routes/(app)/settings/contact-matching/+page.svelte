<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import SettingsPageHeader from '$lib/components/settings/SettingsPageHeader.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchSettingsContactMatching,
		settingsContactMatchingKey,
		saveContactMatchingSettings,
		isSaveConflict,
		type ContactMatchPriority
	} from '$lib/settings/api';
	import usersGroupIcon from '@tabler/icons/outline/users-group.svg?raw';
	import gitMergeIcon from '@tabler/icons/outline/git-merge.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	// Settings → Contact matching: HighLevel's Contact deduplication preference. When a website chat or form
	// arrives with a phone that belongs to one client and an email that belongs to another, this decides which
	// client it joins. Neither client is changed; two records that are really one person are merged by hand.

	const EXPLANATIONS: Record<ContactMatchPriority, string> = {
		email:
			'The chat or form goes to the client who has that email. The phone number is only used when the email matches nobody.',
		phone:
			'The chat or form goes to the client who has that phone number. The email is only used when the phone matches nobody.'
	};

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsContactMatchingKey,
		queryFn: fetchSettingsContactMatching
	}));

	let priority = $state<ContactMatchPriority | null>(null);
	let savedPriority = $state<ContactMatchPriority | null>(null);
	let saving = $state(false);
	let errorMessage = $state('');
	let conflict = $state<{ editor_name: string | null; edited_at: string | null } | null>(null);
	let layout = $state<RecordFormLayout>();

	// One place the form shows why a save did not land — a plain error, or someone else getting there first.
	const saveError = $derived(
		conflict
			? `${conflict.editor_name ?? 'Someone else'} just changed this. Refresh the page to see their version before saving yours.`
			: errorMessage
	);

	$effect(() => {
		const matching = query.data?.contact_matching;
		if (!matching) return;
		untrack(() => {
			if (priority !== null) return;
			priority = matching.priority;
			savedPriority = matching.priority;
		});
	});

	const dirty = $derived(priority !== null && savedPriority !== null && priority !== savedPriority);

	beforeNavigate((navigation) => {
		if (!dirty) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});
	$effect(() => {
		function handler(event: BeforeUnloadEvent) {
			if (!dirty) return;
			event.preventDefault();
		}
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	function cancel() {
		priority = savedPriority;
		conflict = null;
		errorMessage = '';
	}

	async function save() {
		if (!query.data || priority === null) return;
		saving = true;
		errorMessage = '';
		conflict = null;

		const result = await saveContactMatchingSettings({
			expected_revision: query.data.contact_matching.revision,
			priority
		}).catch((error: Error) => {
			errorMessage = error.message;
			return null;
		});
		if (!result) {
			saving = false;
			return;
		}
		if (isSaveConflict(result)) {
			conflict = { editor_name: result.editor_name, edited_at: result.edited_at };
			saving = false;
			return;
		}

		savedPriority = priority;
		saving = false;
		toast.success('Contact matching saved.');
		await queryClient.invalidateQueries({ queryKey: settingsContactMatchingKey });
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->

<svelte:head><title>Contact matching · Settings · Contractor CRM</title></svelte:head>

{#if query.isPending || priority === null}
	<LoadingSkeleton variant="card" rows={2} />
{:else if query.isError}
	<ErrorState
		description="Contact matching settings could not be loaded."
		retry={() => query.refetch()}
	/>
{:else}
	{@const canEdit = query.data.permissions.edit}
	{@const editor = query.data.contact_matching.last_editor}

	<div class="contact-matching record-detail--cards">
		<SettingsPageHeader
			title="Contact matching"
			description=""
			icon={gitMergeIcon}
			tone="informative"
			presentation="communication"
		/>

		<RecordFormLayout
			title="Contact matching"
			icon={usersGroupIcon}
			bind:this={layout}
			error={saveError}
		>
			{#snippet main()}
				{#if !canEdit}
					<p class="contact-matching__readonly">
						Only owners and administrators can change this. {#if editor}Last changed by {editor.name ??
								'a teammate'}.{/if}
					</p>
				{/if}

				{#if priority !== null}
					<SectionBlock
						tone="inactive"
						title="When contact details point to two clients"
						hint="Sometimes a website chat or request form arrives with a phone number that belongs to one of your clients and an email that belongs to another. Choose which one wins."
						icon={usersGroupIcon}
						level={3}
					>
						<div class="contact-matching__body">
							<div class="contact-matching__choice">
								<SegmentedControl
									label="Match by"
									fullWidth
									options={[
										{ value: 'email', label: 'Email first' },
										{ value: 'phone', label: 'Phone first' }
									]}
									bind:value={
										() => priority ?? 'email', (value) => (priority = value as ContactMatchPriority)
									}
									disabled={!canEdit}
								/>
							</div>
							<div class="contact-matching__notes">
								<div class="contact-matching__note">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
									<IconTile icon={mailIcon} tone="informative" size={24} white />
									<p>{EXPLANATIONS[priority]}</p>
								</div>
								<div class="contact-matching__note">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
									<IconTile icon={gitMergeIcon} tone="informative" size={24} white />
									<p>
										Neither client's details are changed. If the two clients are really the same
										person, merge them from either client's page.
									</p>
								</div>
							</div>
						</div>
					</SectionBlock>
				{/if}
			{/snippet}

			{#snippet actions()}
				{#if canEdit}
					<div class="contact-matching__status" class:contact-matching__status--dirty={dirty}>
						<span class="contact-matching__status-dot" aria-hidden="true"></span>
						<span class="contact-matching__status-text">
							<strong>{dirty ? 'You have unsaved changes' : 'No unsaved changes'}</strong>
							<span
								>{dirty
									? 'Nothing is saved until you press Save.'
									: 'Change any field, then press Save.'}</span
							>
						</span>
					</div>
					<div class="contact-matching__buttons">
						<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
						<Button
							onclick={() => void save().finally(() => layout?.revealError())}
							disabled={!dirty || saving}
							loading={saving}
						>
							<span class="contact-matching__save">
								<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
								<span aria-hidden="true">{@html checkIcon}</span>Save
							</span>
						</Button>
					</div>
				{/if}
			{/snippet}
		</RecordFormLayout>
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.contact-matching {
		display: flex;
		flex-direction: column;
		gap: 20px;

		&__readonly {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
		}

		// The choice on the left, what it means on the right.
		&__body {
			display: grid;
			grid-template-columns: minmax(0, 380px) minmax(0, 1fr);
			align-items: start;
			gap: 24px;
		}
		&__choice :global(.segmented__caption) {
			color: var(--color-heading);
			font-size: 14px;
			font-weight: 600;
			text-transform: none;
			letter-spacing: 0;
		}
		&__notes {
			overflow: clip;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}
		&__note {
			display: flex;
			align-items: flex-start;
			gap: 12px;
			padding: 14px 16px;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
			p {
				margin: 0;
				color: var(--color-text);
				font-size: 14px;
				line-height: 1.45;
			}
		}

		// ---- Page frame: card straight on the app background, header drawn by the page. ----
		:global(.record-form__header) {
			display: none;
		}
		:global(.record-form__main) {
			padding: 0;
			border: 0;
			border-radius: 0;
			background: transparent;
			box-shadow: none;
			gap: 20px;
			overflow: visible;
		}
		:global(.record-form) {
			height: auto;
		}

		// Card header: the tinted icon tile beside the title and its quiet line.
		:global(.section-block > .section-block__title) {
			padding-left: 72px;
		}
		:global(.section-block:has(> .section-block__hint) > .section-block__hint) {
			margin-left: 72px;
		}
		// ---- Dark save bar with its own words, centred under the content like the design. ----
		:global(.sticky-action-bar) {
			max-width: 720px;
			margin-inline: auto;
			padding: 10px 10px 10px 20px;
			border-color: var(--color-base-blue--700);
			border-radius: 20px;
			background: var(--color-base-blue--900);
			color: var(--color-base-white);
			box-shadow: var(--shadow-high);
		}
		:global(.sticky-action-bar .button--secondary) {
			border-color: var(--color-base-blue--600);
			background: var(--color-base-blue--800);
			color: var(--color-base-white);
		}
		:global(.sticky-action-bar .button--secondary:disabled),
		:global(.sticky-action-bar .button--secondary.button--inactive) {
			opacity: 0.7;
		}

		&__status {
			display: flex;
			align-items: center;
			gap: 12px;
			min-width: 0;
		}
		&__status-dot {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 28px;
			height: 28px;
			border-radius: 14px;
			background: color-mix(in srgb, var(--color-base-white) 12%, transparent);

			&::after {
				content: '';
				width: 8px;
				height: 8px;
				border-radius: 50%;
				background: var(--color-base-blue--400);
			}
		}
		&__status--dirty &__status-dot {
			background: color-mix(in srgb, var(--color-base-yellow--400) 18%, transparent);

			&::after {
				background: var(--color-base-yellow--400);
			}
		}
		&__status-text {
			display: grid;
			min-width: 0;

			strong {
				color: var(--color-base-white);
				font-size: 14px;
				font-weight: 600;
			}
			span {
				color: var(--color-base-blue--300);
				font-size: 12px;
			}
		}
		&__buttons {
			display: flex;
			flex: 0 0 auto;
			gap: 8px;
		}
		&__save {
			display: inline-flex;
			align-items: center;
			gap: 6px;

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}
	}

	@media (max-width: 1079px) {
		.contact-matching__body {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
