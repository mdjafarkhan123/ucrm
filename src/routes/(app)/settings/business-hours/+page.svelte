<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import TimePicker from '$lib/components/ui/TimePicker.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { timeFromString, timeToString, type TimeRangeValue } from '$lib/components/ui/date-time';
	import {
		fetchSettingsBusiness,
		settingsBusinessKey,
		saveBusinessHours,
		isSaveConflict,
		WEEKDAY_LABELS,
		type BusinessHourPeriod,
		type SettingsBusiness
	} from '$lib/settings/api';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsBusinessKey,
		queryFn: fetchSettingsBusiness
	}));

	type DayState = { isOpen: boolean; is24h: boolean; periods: TimeRangeValue[] };
	type Mode = 'weekly' | 'appointment_only';

	function blankDay(isOpen: boolean): DayState {
		return {
			isOpen,
			is24h: false,
			periods: isOpen ? [{ start: timeFromString('09:00'), end: timeFromString('17:00') }] : []
		};
	}

	function suggestedWeek(): DayState[] {
		return [0, 1, 2, 3, 4, 5, 6].map((weekday) => {
			const open = weekday >= 1 && weekday <= 5;
			return open
				? {
						isOpen: true,
						is24h: false,
						periods: [{ start: timeFromString('08:00'), end: timeFromString('17:00') }]
					}
				: blankDay(false);
		});
	}

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

	$effect(() => {
		const business = query.data;
		if (!business) return;
		untrack(() => {
			if (days !== null) return;
			if (business.hours.mode === 'not_configured') return;
			started = true;
			mode = business.hours.mode;
			days =
				business.hours.mode === 'weekly'
					? daysFromPeriods(business.hours.periods)
					: [0, 1, 2, 3, 4, 5, 6].map(() => blankDay(false));
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
		days = [0, 1, 2, 3, 4, 5, 6].map(() => blankDay(false));
		started = true;
	}
	function useAppointmentOnly() {
		mode = 'appointment_only';
		days = [0, 1, 2, 3, 4, 5, 6].map(() => blankDay(false));
		started = true;
	}

	function toggleDayOpen(weekday: number, isOpen: boolean) {
		if (!days) return;
		days[weekday] = isOpen ? blankDay(true) : blankDay(false);
	}
	function toggleDay24h(weekday: number, is24h: boolean) {
		if (!days) return;
		days[weekday].is24h = is24h;
		if (is24h) days[weekday].periods = [];
		else if (days[weekday].periods.length === 0)
			days[weekday].periods = [{ start: timeFromString('09:00'), end: timeFromString('17:00') }];
	}
	function addPeriod(weekday: number) {
		if (!days || days[weekday].periods.length >= 3) return;
		days[weekday].periods.push({ start: undefined, end: undefined });
	}
	function removePeriod(weekday: number, index: number) {
		if (!days) return;
		days[weekday].periods.splice(index, 1);
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
			query.data.hours.mode === 'weekly'
				? daysFromPeriods(query.data.hours.periods)
				: [0, 1, 2, 3, 4, 5, 6].map(() => blankDay(false));
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

	<RecordFormLayout title="Business hours" icon={clockIcon}>
		{#snippet main()}
			{#if !canEdit}
				<p class="business-hours__readonly">
					Only owners and administrators can change this. {#if editor}Last changed by {editor.name ??
							'a teammate'}.{/if}
				</p>
			{/if}
			{#if conflict}
				<p class="business-hours__conflict" role="alert">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span aria-hidden="true">{@html alertTriangleIcon}</span>
					{conflict.editor_name ?? 'Someone else'} just changed this. Refresh to see their version before
					saving yours.
				</p>
			{/if}
			{#if errorMessage}
				<p class="business-hours__error" role="alert">{errorMessage}</p>
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
					<div class="business-hours__week">
						{#each days as day, weekday (weekday)}
							<div class="business-hours__day">
								<div class="business-hours__day-header">
									<span class="business-hours__day-name">{WEEKDAY_LABELS[weekday]}</span>
									<Toggle
										id={`hours-open-${weekday}`}
										label={day.isOpen ? 'Open' : 'Closed'}
										checked={day.isOpen}
										disabled={!canEdit}
										onchange={(checked) => toggleDayOpen(weekday, checked)}
									/>
								</div>
								{#if day.isOpen}
									<div class="business-hours__day-body">
										<Toggle
											id={`hours-24h-${weekday}`}
											label="Open 24 hours"
											checked={day.is24h}
											disabled={!canEdit}
											onchange={(checked) => toggleDay24h(weekday, checked)}
										/>
										{#if !day.is24h}
											{#each day.periods as period, index (index)}
												<div class="business-hours__period">
													<TimePicker
														bind:value={days[weekday].periods[index]}
														range
														label={`${WEEKDAY_LABELS[weekday]} period ${index + 1}`}
														disabled={!canEdit}
													/>
													{#if canEdit}
														<button
															type="button"
															class="business-hours__remove-period"
															aria-label="Remove this period"
															onclick={() => removePeriod(weekday, index)}
															><!-- eslint-disable-next-line svelte/no-at-html-tags -->
															{@html xIcon}</button
														>
													{/if}
												</div>
											{/each}
											{#if canEdit && day.periods.length < 3}
												<button
													type="button"
													class="business-hours__add-period"
													onclick={() => addPeriod(weekday)}
													><!-- eslint-disable-next-line svelte/no-at-html-tags -->
													{@html plusIcon} Add another period</button
												>
											{/if}
										{/if}
									</div>
								{/if}
							</div>
						{/each}
					</div>
				</SectionBlock>
			{/if}
		{/snippet}

		{#snippet actions()}
			{#if canEdit && started}
				<Button variant="secondary" onclick={cancel} disabled={saving}>Cancel</Button>
				<Button onclick={save} disabled={!dirty || saving} loading={saving}>Save</Button>
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
		&__conflict {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-small);
		}
		&__conflict :global(svg) {
			width: 18px;
			height: 18px;
			flex: 0 0 auto;
		}
		&__error {
			padding: var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
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
		&__week {
			display: grid;
			grid-template-columns: 1fr 1fr;
			gap: var(--space-base);
		}
		&__day {
			min-width: 0;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}
		&__day-header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
		}
		&__day-name {
			color: var(--color-heading);
			font-weight: 700;
		}
		&__day-body {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin-top: var(--space-base);
		}
		&__period {
			display: flex;
			align-items: flex-end;
			gap: var(--space-small);
		}
		&__remove-period {
			display: grid;
			width: 32px;
			height: 32px;
			flex: 0 0 auto;
			place-items: center;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: var(--color-surface);
			margin-bottom: 2px;
		}
		&__remove-period:hover {
			background: var(--color-surface--hover);
		}
		&__remove-period :global(svg) {
			width: 16px;
			height: 16px;
		}
		&__add-period {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			width: fit-content;
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) dashed var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			background: transparent;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__add-period:hover {
			background: var(--color-surface--hover);
		}
		&__add-period :global(svg) {
			width: 14px;
			height: 14px;
		}
	}
	@media (max-width: 900px) {
		.business-hours__week {
			grid-template-columns: 1fr;
		}
	}
</style>
