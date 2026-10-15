<script lang="ts">
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import FilterChip from '$lib/components/ui/FilterChip.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import DataTable from '$lib/components/data-display/DataTable.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Popover from '$lib/components/ui/Popover.svelte';
	import Tabs from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import listIcon from '@tabler/icons/outline/list.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import { CalendarDate } from '@internationalized/date';

	let search = $state('');
	let status = $state('all');
	let date = $state<CalendarDate | undefined>(new CalendarDate(2026, 10, 20));
	let selected = $state(new Set<string>());
	let dialog = $state(false);
	let confirm = $state(false);
	let anchor = $state<HTMLElement | null>(null);
	let view = $state('list');
	let result = $state('No action taken');
	const records = [
		{
			id: 'priya',
			name: 'Priya Nair',
			status: 'active',
			work: 'Job #1042 · Exterior paint',
			total: '$3,250'
		},
		{
			id: 'henderson',
			name: 'Henderson Homes & Commercial Property Management',
			status: 'waiting',
			work: 'Quote #1043 · Interior paint',
			total: '$8,100'
		}
	];
	const filtered = $derived(
		records.filter(
			(r) =>
				(status === 'all' || r.status === status) &&
				r.name.toLowerCase().includes(search.toLowerCase())
		)
	);
</script>

<svelte:head><title>Shared parts preview</title></svelte:head>
<div class="shared-preview">
	<h1>Shared parts preview</h1>
	<div class="shared-preview__toolbar">
		<SearchInput id="preview-search" label="Find records" bind:value={search} />
		<FilterChip
			id="preview-filter"
			label="Status"
			value={status}
			restValue="all"
			options={[
				{ value: 'all', label: 'All' },
				{ value: 'active', label: 'In progress' },
				{ value: 'waiting', label: 'Waiting' }
			]}
			onchange={(v) => (status = v)}
		/>
		<Avatar id="priya" name="Priya Nair" size="medium" />
		<Avatar id="image-fallback" name="Image Fallback" src="/missing-preview-photo.png" />
	</div>
	<DataTable
		columns={[
			{ key: 'name', label: 'Client' },
			{ key: 'status', label: 'Status' },
			{ key: 'total', label: 'Total', align: 'end' }
		]}
		items={filtered}
		rowId={(r) => r.id}
		rowLabel={(r) => r.name}
		caption="Preview records"
		selectable
		bind:selectedIds={selected}
		onRowActivate={(r) => {
			result = `Opened ${r.name}`;
			dialog = true;
		}}
	>
		{#snippet row(record)}
			<th scope="row">{record.name}<small>{record.work}</small></th><td>{record.status}</td><td
				class="align-end">{record.total}</td
			>
		{/snippet}
	</DataTable>
	<p role="status">{filtered.length} records · {selected.size} selected · {result}</p>
	<div class="shared-preview__dates">
		<CalendarPicker id="preview-date" label="Visit date" bind:value={date} />
		<CalendarPicker id="disabled-date" label="Disabled date" disabled />
		<CalendarPicker
			id="restricted-date"
			label="Future date"
			minValue={new CalendarDate(2099, 1, 1)}
		/>
		<CalendarPicker
			id="invalid-date"
			label="Invalid date"
			invalid
			errorMessage="Choose a visit date."
		/>
	</div>
	<p>Chosen date: {date?.toString() ?? 'None'}</p>
	<div class="shared-preview__toolbar">
		<Button variant="secondary" onclick={() => (dialog = true)}>Open dialog</Button>
		<Button variant="secondary" onclick={() => (confirm = true)}>Open confirmation</Button>
		<Button variant="secondary" onclick={(e) => (anchor = e.currentTarget)}>Open information</Button
		>
		<DropdownMenu
			triggerLabel="Preview actions"
			groups={[
				{
					heading: 'Create record',
					items: [
						{
							label: 'Create job',
							icon: calendarIcon,
							iconTone: 'green',
							onSelect: () => (result = 'Create job selected')
						},
						{
							label: 'Create invoice',
							icon: listIcon,
							iconTone: 'blue',
							disabled: true,
							note: 'Needs a job first',
							onSelect: () => (result = 'ERROR disabled action')
						}
					]
				}
			]}
			footer={[{ label: 'Delete preview', destructive: true, onSelect: () => (confirm = true) }]}
		/>
	</div>
	<SegmentedControl
		ariaLabel="Preview view"
		bind:value={view}
		options={[
			{ value: 'list', label: 'List', icon: listIcon },
			{ value: 'calendar', label: 'Calendar', icon: calendarIcon }
		]}
	/>
	<Tabs
		label="Preview sections"
		tabs={[
			{ value: 'visits', label: 'Visits', count: 4 },
			{ value: 'files', label: 'Files', count: 2 }
		]}
	>
		<TabPanel value="visits">Four scheduled visits</TabPanel><TabPanel value="files"
			>Two attached files</TabPanel
		>
	</Tabs>
	<Dialog open={dialog} title="Visit details" onClose={() => (dialog = false)}
		><p>This preview does not save any records.</p>
		<Button onclick={() => (dialog = false)}>Done</Button></Dialog
	>
	<ConfirmDialog
		open={confirm}
		title="Remove this preview?"
		confirmLabel="Remove preview"
		destructive
		onClose={() => (confirm = false)}
		onConfirm={() => {
			result = 'Preview removed';
			confirm = false;
		}}><p>Only this example is affected. No saved records will be removed.</p></ConfirmDialog
	>
	<Popover open={anchor !== null} {anchor} title="Visit information" onClose={() => (anchor = null)}
		><p>The crew and customer can see the scheduled visit.</p></Popover
	>
</div>

<style lang="scss">
	.shared-preview {
		display: grid;
		gap: 20px;
		max-width: 960px;
		margin: 24px;
		min-width: 0;
	}
	.shared-preview__toolbar {
		display: flex;
		align-items: center;
		gap: 12px;
		flex-wrap: wrap;
	}
	.shared-preview__toolbar :global(.search-input) {
		flex: 1 1 240px;
	}
	.shared-preview__dates {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 16px;
	}
	small {
		display: block;
		font-size: 12px;
		font-weight: 400;
		white-space: normal;
	}
	@media (max-width: 767px) {
		.shared-preview__dates {
			grid-template-columns: 1fr;
		}
	}
</style>
