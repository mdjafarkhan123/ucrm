<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import WeeklyHoursEditor from '$lib/components/settings/WeeklyHoursEditor.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { timeFromString, timeToString } from '$lib/components/ui/date-time';
	import {
		fetchSettingsBusiness,
		settingsBusinessKey,
		saveBusinessHours,
		isSaveConflict,
		type BusinessHourPeriod,
		type SettingsBusiness
	} from '$lib/settings/api';
	import { blankDay, closedWeek, suggestedWeek, type DayState } from '$lib/settings/weekly-hours';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsBusinessKey,
		queryFn: fetchSettingsBusiness
	}));

	type Mode = 'weekly' | 'appointment_only';

	function daysFromPeriods(periods: BusinessHourPeriod[]): DayState[] {
		return [0, 1, 2, 3, 4, 5, 6].map((weekday) => {
			const rows = periods
				.filter((period) => period.weekday === weekday)
				.sort((a, b) => a.period_index - b.period_index);
			const open = rows.some((row) => row.is_open);
			if (!open) return blankDay(false);
			const is24h = rows.some((row) => row.is_open_24h);
			return {
				isOpen: true,
				is24h,
				periods: is24h
					? []
					: rows
							.filter((row) => row.opens_at && row.closes_at)
							.map((row) => ({
								start: timeFromString(row.opens_at),
								end: timeFromString(row.closes_at)
							}))
			};
		});
	}

	let started = $state(false);
	let mode = $state<Mode>('weekly');
	let days = $state<DayState[] | null>(null);
	let savedSnapshot = $state('');
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
		const business = query.data;
		if (!business) return;
		untrack(() => {
			if (days !== null) return;
			if (business.hours.mode === 'not_configured') return;
			started = true;
			mode = business.hours.mode;
			days =
				business.hours.mode === 'weekly' ? daysFromPeriods(business.hours.periods) : closedWeek();
			savedSnapshot = snapshot();
		});
	});

	function snapshot() {
		return JSON.stringify({
			mode,
			days: days?.map((day) => ({
				isOpen: day.isOpen,
				is24h: day.is24h,
				periods: day.periods.map((p) => [timeToString(p.start), timeToString(p.end)])
			}))
		});
	}

	const dirty = $derived(started && days !== null && snapshot() !== savedSnapshot);

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

	function useWeeklySuggestion() {
		mode = 'weekly';
		days = suggestedWeek();
		started = true;
	}
	function useBlankWeekly() {
		mode = 'weekly';
		days = closedWeek();
		started = true;
	}
	function useAppointmentOnly() {
		mode = 'appointment_only';
		days = closedWeek();
		started = true;
	}

	function cancel() {
		if (!query.data) return;
		if (query.data.hours.mode === 'not_configured') {
			started = false;
			days = null;
			return;
		}
		mode = query.data.hours.mode as Mode;
		days =
			query.data.hours.mode === 'weekly' ? daysFromPeriods(query.data.hours.periods) : closedWeek();
		conflict = null;
		errorMessage = '';
	}

	async function save() {
		if (!query.data || !days) return;
		saving = true;
		errorMessage = '';
		conflict = null;

		const closedRow = (weekday: number): BusinessHourPeriod => ({
			weekday,
			period_index: 0,
			is_open: false,
			is_open_24h: false,
			opens_at: null,
			closes_at: null
		});

		const periods: BusinessHourPeriod[] =
			mode === 'appointment_only'
				? []
				: days.flatMap((day, weekday) => {
						if (!day.isOpen) return [closedRow(weekday)];
						if (day.is24h)
							return [
								{
									weekday,
									period_index: 0,
									is_open: true,
									is_open_24h: true,
									opens_at: null,
									closes_at: null
								}
							];
						const validPeriods = day.periods.filter((p) => p.start && p.end);
						if (validPeriods.length === 0) return [closedRow(weekday)];
						return validPeriods.map((p, index) => ({
							weekday,
							period_index: index,
							is_open: true,
							is_open_24h: false,
							opens_at: timeToString(p.start),
							closes_at: timeToString(p.end)
						}));
					});

		const result = await saveBusinessHours({
			expected_revision: query.data.hours.revision,
			mode,
			periods
		}).catch((error: Error) => {
			errorMessage = error.message;
			return null;
		});

		saving = false;
		if (!result) return;
		if (isSaveConflict(result)) {
			conflict = { editor_name: result.editor_name, edited_at: result.edited_at };
			return;
		}
		savedSnapshot = snapshot();
		toast.success('Business hours saved.');
		queryClient.setQueryData(settingsBusinessKey, (current: SettingsBusiness | undefined) =>
			current
				? { ...current, hours: { ...current.hours, revision: result.hours_revision } }
				: current
		);
		await queryClient.invalidateQueries({ queryKey: settingsBusinessKey });
		await queryClient.invalidateQueries({ queryKey: ['settings', 'home'] });
	}
</script>

<svelte:head><title>Business hours · Settings · Contractor CRM</title></svelte:head>

{#if query.isPending}
	<LoadingSkeleton variant="card" rows={4} />
{:else if query.isError}
	<ErrorState description="Business hours could not be loaded." retry={() => query.refetch()} />
{:else}
	{@const canEdit = query.data.permissions.edit}
	{@const editor = query.data.hours.last_editor}

	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Business hours' }]}
	/>

	<RecordFormLayout title="Business hours" icon={clockIcon} bind:this={layout} error={saveError}>
		{#snippet main()}
			{#if !canEdit}
				<p class="business-hours__readonly">
					Only owners and administrators can change this. {#if editor}Last changed by {editor.name ??
							'a teammate'}.{/if}
				</p>
			{/if}

			{#if !started}
				<SectionBlock
					title="Not set yet"
					hint="Used for scheduling, online booking, and reminders."
				>
					<p class="business-hours__intro">
						Choose a starting point — you can change any day before saving.
					</p>
					<div class="business-hours__starters">
						<Button variant="secondary" onclick={useWeeklySuggestion} disabled={!canEdit}
							>Use Monday–Friday, 8am–5pm</Button
						>
						<Button variant="secondary" onclick={useBlankWeekly} disabled={!canEdit}
							>Set custom weekly hours</Button
						>
						<Button variant="secondary" onclick={useAppointmentOnly} disabled={!canEdit}
							>By appointment only</Button
						>
					</div>
				</SectionBlock>
			{:else if mode === 'appointment_only'}
				<SectionBlock
					title="By appointment only"
					hint="No fixed weekly hours — every visit is scheduled individually."
				>
					<Button variant="tertiary" onclick={useWeeklySuggestion} disabled={!canEdit}
						>Switch to weekly hours instead</Button
					>
				</SectionBlock>
			{:else if days}
				<SectionBlock
					title="Weekly hours"
					hint="Up to three periods a day. Mark a day closed, open 24 hours, or by appointment separately for each day."
					form
				>
					<WeeklyHoursEditor bind:days disabled={!canEdit} />
				</SectionBlock>
			{/if}
		{/snippet}

		{#snippet actions()}
			{#if canEdit && started}
				<Button variant="secondary" onclick={cancel} disabled={saving}>Cancel</Button>
				<Button
					onclick={() => void save().finally(() => layout?.revealError())}
					disabled={!dirty || saving}
					loading={saving}>Save</Button
				>
			{/if}
		{/snippet}
	</RecordFormLayout>
{/if}

<style lang="scss">
	.business-hours {
		&__readonly {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
		}
		&__intro {
			color: var(--color-text--secondary);
		}
		&__starters {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}
	}
</style>
