<script lang="ts">
	import { untrack } from 'svelte';
	import { SvelteSet } from 'svelte/reactivity';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
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

	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Inquiry alerts' }]}
	/>

	<RecordFormLayout title="Inquiry alerts" icon={bellIcon} bind:this={layout} error={errorMessage}>
		{#snippet main()}
			<p class="inquiry-alerts__intro">
				When someone sends a request form or starts a chat on your website, the people you choose
				get an alert in the bell at the top of the app and by email, so a new customer hears back
				fast.
			</p>

			{#if chosen.size === 0}
				<!-- eslint-disable svelte/no-at-html-tags -->
				<div class="inquiry-alerts__banner" role="status">
					<span class="inquiry-alerts__banner-icon" aria-hidden="true">{@html alertIcon}</span>
					<p>
						Nobody is chosen, so only the account owner{owner ? ` (${memberName(owner)})` : ''} is alerted.
						Choose the people who answer new customers.
					</p>
				</div>
				<!-- eslint-enable svelte/no-at-html-tags -->
			{/if}

			<SectionBlock
				title="Who gets alerted"
				hint="Only people who can see every request can be chosen."
				form
				level={3}
			>
				<ul class="inquiry-alerts__list">
					{#each members as member (member.user_id)}
						<li class="inquiry-alerts__item">
							<Checkbox
								id={`inquiry-alert-${member.user_id}`}
								label={memberName(member)}
								description={memberDescription(member)}
								checked={chosen.has(member.user_id)}
								disabled={!member.can_receive || saving}
								onchange={(checked) => toggle(member.user_id, checked)}
							/>
						</li>
					{/each}
				</ul>
			</SectionBlock>
		{/snippet}

		{#snippet actions()}
			<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
			<Button
				onclick={() => void save().finally(() => layout?.revealError())}
				disabled={!dirty || saving}
				loading={saving}>Save</Button
			>
		{/snippet}
	</RecordFormLayout>
{/if}

<style lang="scss">
	.inquiry-alerts {
		&__intro {
			margin: 0;
			color: var(--color-text--secondary);
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

		&__list {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			padding: var(--space-base) 0;
			border-bottom: var(--border-base) solid var(--color-border);

			&:last-child {
				border-bottom: 0;
			}
		}
	}
</style>
