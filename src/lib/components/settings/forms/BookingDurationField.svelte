<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';

	// A minutes value shown as "a number of days/hours/minutes" instead of raw minutes — nobody wants to
	// type "43200" for "30 days". The stored unit is display-only: the bound value is always minutes, which
	// is exactly what `form_booking_rules` and `update_form_booking_settings` speak.
	type Unit = 'minutes' | 'hours' | 'days';

	const UNIT_MINUTES: Record<Unit, number> = { minutes: 1, hours: 60, days: 1440 };
	const UNIT_LABELS: Record<Unit, string> = { minutes: 'minutes', hours: 'hours', days: 'days' };

	let {
		id,
		label,
		minutes = $bindable(0),
		minMinutes = 0,
		maxMinutes,
		units = ['minutes', 'hours'],
		disabled = false,
		hint
	}: {
		id: string;
		label: string;
		minutes?: number;
		minMinutes?: number;
		maxMinutes: number;
		units?: Unit[];
		disabled?: boolean;
		hint?: string;
	} = $props();

	// Largest offered unit that divides the starting value evenly reads best ("2 hours", not "120 minutes").
	// Only picked once at load — after that, the unit only changes when the person changes it.
	function initialUnit(): Unit {
		const descending = [...units].sort((a, b) => UNIT_MINUTES[b] - UNIT_MINUTES[a]);
		for (const unit of descending) {
			if (minutes > 0 && minutes % UNIT_MINUTES[unit] === 0) return unit;
		}
		return units[units.length - 1];
	}

	let unit = $state<Unit>(initialUnit());
	let amount = $derived(minutes / UNIT_MINUTES[unit]);

	function setAmount(next: number | null) {
		const raw = Math.max(0, next ?? 0) * UNIT_MINUTES[unit];
		minutes = Math.min(maxMinutes, Math.max(minMinutes, Math.round(raw)));
	}

	function setUnit(next: string) {
		unit = next as Unit;
	}

	const unitOptions = $derived(units.map((u) => ({ value: u, label: UNIT_LABELS[u] })));
</script>

<div class="booking-duration">
	<Input
		{id}
		{label}
		type="number"
		min="0"
		step="1"
		value={Math.round(amount * 100) / 100}
		oninput={(event: Event) => setAmount(Number((event.currentTarget as HTMLInputElement).value))}
		{disabled}
	/>
	{#if unitOptions.length > 1}
		<Select
			id={`${id}-unit`}
			ariaLabel={`${label} unit`}
			options={unitOptions}
			value={unit}
			onchange={setUnit}
			{disabled}
		/>
	{:else}
		<span class="booking-duration__unit">{UNIT_LABELS[unit]}</span>
	{/if}
	{#if hint}<p class="booking-duration__hint">{hint}</p>{/if}
</div>

<style lang="scss">
	.booking-duration {
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(96px, auto);
		align-items: end;
		gap: var(--space-small);

		&__unit {
			padding: 0 0 calc(var(--space-small) + 2px);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__hint {
			grid-column: 1 / -1;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
