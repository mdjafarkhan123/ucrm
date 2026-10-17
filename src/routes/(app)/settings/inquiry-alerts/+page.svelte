<script lang="ts">
	import { untrack } from 'svelte';
	import { SvelteSet } from 'svelte/reactivity';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import SettingsPageHeader from '$lib/components/settings/SettingsPageHeader.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { settingsHomeKey } from '$lib/settings/api';
	import {
		fetchInquiryAlertSettings,
		inquiryAlertSettingsKey,
		saveInquiryAlertRecipients,
		type InquiryAlertMember
	} from '$lib/team/notifications';
	import bellIcon from '@tabler/icons/outline/bell-ringing.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	// Who hears about a new website inquiry — Jobber's settings-level team notification: pick people, save.
	// Nobody chosen still alerts the account owner, so an inquiry is never silently missed.
	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: inquiryAlertSettingsKey,
		queryFn: fetchInquiryAlertSettings
	}));

	const chosen = new SvelteSet<string>();
	let savedIds = $state<string[] | null>(null);
	let saving = $state(false);
	let errorMessage = $state('');
	let layout = $state<RecordFormLayout>();

	function receivableChosen(members: InquiryAlertMember[]) {
		return members.filter((member) => member.chosen && member.can_receive).map((m) => m.user_id);
	}

	function reset(ids: string[]) {
		chosen.clear();
		for (const id of ids) chosen.add(id);
		savedIds = ids;
	}

	$effect(() => {
		const members = query.data?.members;
		if (!members) return;
		untrack(() => {
			if (savedIds === null) reset(receivableChosen(members));
		});
	});

	const dirty = $derived(
		savedIds !== null && (savedIds.length !== chosen.size || savedIds.some((id) => !chosen.has(id)))
	);

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

	function toggle(userId: string, checked: boolean) {
		if (checked) chosen.add(userId);
		else chosen.delete(userId);
	}

	function cancel() {
		if (savedIds) reset(savedIds);
		errorMessage = '';
	}

	async function save() {
		saving = true;
		errorMessage = '';
		try {
			const result = await saveInquiryAlertRecipients([...chosen]);
			queryClient.setQueryData(inquiryAlertSettingsKey, result);
			reset(receivableChosen(result.members));
			toast.success('Inquiry alerts saved.');
			void queryClient.invalidateQueries({ queryKey: settingsHomeKey });
		} catch (error) {
			errorMessage = error instanceof Error ? error.message : 'Inquiry alerts could not be saved.';
		} finally {
			saving = false;
		}
	}

	function memberName(member: InquiryAlertMember) {
		return member.full_name ?? member.email ?? 'Team member';
	}

	function memberDescription(member: InquiryAlertMember) {
		const role = member.role.charAt(0).toUpperCase() + member.role.slice(1);
		const details = [role, member.full_name ? member.email : null].filter(Boolean).join(' · ');
		if (member.can_receive) return details;
		return `${details} — can't see every request, so can't be chosen. Change their access in Team.`;
	}
</script>

<svelte:head><title>Inquiry alerts · Settings · Contractor CRM</title></svelte:head>

{#if query.isError}
	<ErrorState description="Inquiry alerts could not be loaded." retry={() => query.refetch()} />
{:else if query.isPending || savedIds === null}
	<LoadingSkeleton variant="card" rows={3} />
{:else}
	{@const members = query.data.members}
	{@const owner = members.find((member) => member.role === 'owner')}

	<PageContainer variant="open">
		<div class="inquiry-alerts record-detail--cards">
			<SettingsPageHeader
				title="Inquiry alerts"
				description="When someone sends a request form or starts a chat on your website, the people you choose get an alert in the bell at the top of the app and by email, so a new customer hears back fast."
				icon={bellIcon}
				tone="task"
				presentation="communication"
			/>

			<RecordFormLayout title="Inquiry alerts" bind:this={layout} error={errorMessage}>
				{#snippet main()}
					{#if chosen.size === 0}
						<!-- eslint-disable svelte/no-at-html-tags -->
						<div class="inquiry-alerts__banner" role="status">
							<span class="inquiry-alerts__banner-icon" aria-hidden="true">{@html alertIcon}</span>
							<p>
								Nobody is chosen, so only the account owner{owner
									? ` (${memberName(owner)})`
									: ''} is alerted. Choose the people who answer new customers.
							</p>
						</div>
						<!-- eslint-enable svelte/no-at-html-tags -->
					{/if}

					<SectionBlock
						title="Who gets alerted"
						hint="Only people who can see every request can be chosen."
						icon={usersIcon}
						id="inquiry-alerts-who"
						level={3}
						class="section-block--flush"
					>
						<ul class="inquiry-alerts__list" role="group" aria-labelledby="inquiry-alerts-who-title">
							{#each members as member (member.user_id)}
								<li
									class="inquiry-alerts__item"
									class:inquiry-alerts__item--locked={!member.can_receive}
								>
									<Checkbox
										id={`inquiry-alert-${member.user_id}`}
										label={memberName(member)}
										description={memberDescription(member)}
										hideLabel
										checked={chosen.has(member.user_id)}
										disabled={!member.can_receive || saving}
										onchange={(checked) => toggle(member.user_id, checked)}
									/>
									<span class="inquiry-alerts__avatar" aria-hidden="true">
										<Avatar id={member.user_id} name={memberName(member)} />
									</span>
									<span class="inquiry-alerts__who" aria-hidden="true">
										<strong>
											{memberName(member)}
											{#if !member.can_receive}
												<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
												<span class="inquiry-alerts__lock">{@html lockIcon}</span>
											{/if}
										</strong>
										<span>{memberDescription(member)}</span>
									</span>
								</li>
							{/each}
						</ul>
					</SectionBlock>
				{/snippet}

				{#snippet actions()}
					<div class="inquiry-alerts__status" class:inquiry-alerts__status--dirty={dirty}>
						<span class="inquiry-alerts__status-dot" aria-hidden="true"></span>
						<span class="inquiry-alerts__status-text">
							<strong>{dirty ? 'You have unsaved changes' : 'No unsaved changes'}</strong>
							<span
								>{dirty
									? 'Nothing is saved until you press Save.'
									: 'Change any field, then press Save.'}</span
							>
						</span>
					</div>
					<div class="inquiry-alerts__buttons">
						<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
						<Button
							onclick={() => void save().finally(() => layout?.revealError())}
							disabled={!dirty || saving}
							loading={saving}
						>
							<span class="inquiry-alerts__save">
								<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
								<span aria-hidden="true">{@html checkIcon}</span>Save
							</span>
						</Button>
					</div>
				{/snippet}
			</RecordFormLayout>
		</div>
	</PageContainer>
{/if}

<style lang="scss">
	.inquiry-alerts {
		display: flex;
		flex-direction: column;
		gap: 20px;

		// ---- The shared form frame drops its white sheet and header so the card sits on the page. ----
		:global(.record-form) {
			height: auto;
		}
		:global(.record-form__header) {
			display: none;
		}
		:global(.record-form__main > :empty) {
			display: none;
		}
		:global(.record-form__main) {
			gap: 20px;
			padding: 0;
			border: 0;
			border-radius: 0;
			background: transparent;
			box-shadow: none;
			overflow: visible;
		}

		// ---- Card header: framed icon tile beside the title and its quiet line. ----
		:global(.section-block > .section-block__title) {
			padding-left: 72px;
		}
		&.record-detail--cards :global(.section-block:has(> .section-block__hint) > .section-block__hint) {
			margin-left: 72px;
		}
		:global(.section-block .section-block__icon) {
			position: absolute;
			top: 20px;
			left: 24px;
			display: grid;
			place-items: center;
			width: 36px;
			height: 36px;
			border-radius: 11px;
			background: var(--color-informative--surface);
		}
		:global(.section-block .section-block__icon svg) {
			width: 18px;
			height: 18px;
			color: var(--color-informative--onSurface);
		}

		// ---- Member rows ----
		&__list {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__item {
			display: flex;
			align-items: center;
			gap: 14px;
			padding: 16px 24px;
			border-top: var(--border-base) solid var(--color-border);

			// The checkbox's own label and description stay for screen readers; the row draws its own text.
			:global(.checkbox__description) {
				position: absolute;
				width: 1px;
				height: 1px;
				overflow: hidden;
				clip-path: inset(50%);
				white-space: nowrap;
			}
			:global(.avatar) {
				--avatar-bg: var(--color-surface--background);
				--avatar-fg: var(--color-text--secondary);
			}
		}
		&__avatar {
			display: inline-flex;
			flex: 0 0 auto;
		}
		&__who {
			display: grid;
			min-width: 0;
			gap: 2px;

			strong {
				display: flex;
				align-items: center;
				gap: 6px;
				color: var(--color-heading);
				font-size: 14px;
				font-weight: 600;
			}
			span {
				color: var(--color-text--secondary);
				font-size: 13px;
				font-weight: 500;
			}
		}
		&__item--locked &__who strong {
			color: var(--color-text--secondary);
		}
		&__item--locked &__avatar {
			opacity: 0.6;
		}
		&__lock {
			display: inline-flex;

			:global(svg) {
				width: 13px;
				height: 13px;
			}
		}

		&__banner {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);

			p {
				flex: 1;
				margin: 0;
			}
		}

		&__banner-icon {
			display: inline-grid;
			flex: 0 0 auto;
			place-items: center;
			padding: var(--space-smaller);
			border-radius: var(--radius-circle);
			color: var(--color-surface);
			background: var(--color-warning);

			:global(svg) {
				display: block;
				width: 20px;
				height: 20px;
			}
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
</style>
