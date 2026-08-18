<script lang="ts">
	// TEMPORARY preview for the shared work-object components, so Jafar can look at the header and the
	// create-page card before any of them are wired to real data. Everything below is made up. Delete
	// once the request pages are built on these.
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import RecordDetailLayout from '$lib/components/layout/RecordDetailLayout.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import WorkRecordHeader from '$lib/components/work/WorkRecordHeader.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import RecordFactsList from '$lib/components/work/RecordFactsList.svelte';
	import PrimaryInfoCard from '$lib/components/work/PrimaryInfoCard.svelte';
	import clipboardIcon from '@tabler/icons/outline/clipboard-text.svg?raw';
	import fileIcon from '@tabler/icons/outline/file-text.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	const demoClient = {
		name: 'Mr Abbas Uddin',
		addresses: [{ value: 'Dendabor, Pallibidyut, Savar, Dhaka' }],
		phone: '+8801834979674',
		email: 'youremail@gmail.com'
	};

	const noop = () => {};

	const clientMenu = [
		{ label: 'View client profile', icon: userIcon, onSelect: noop },
		{ label: 'Edit client details', icon: userIcon, onSelect: noop },
		{ label: 'Change property', icon: mapPinIcon, onSelect: noop }
	];

	const requestMenu = [
		{ label: 'Convert to quote', icon: fileIcon, onSelect: noop },
		{ label: 'Convert to job', icon: clipboardIcon, onSelect: noop },
		{ label: 'Archive', icon: archiveIcon, onSelect: noop },
		{ label: 'Delete', icon: trashIcon, onSelect: noop, destructive: true }
	];

	// The three states a request's header goes through, so all three can be compared side by side.
	const states = [
		{
			caption: 'New — nothing booked yet',
			title: 'Kitchen socket not working',
			statusLabel: 'New',
			statusTone: 'informative' as const,
			action: 'Schedule assessment',
			facts: [
				{ label: 'Requested', value: '18 Aug 2026' },
				{ label: 'Assessment', value: null, empty: 'Not booked yet' }
			]
		},
		{
			caption: 'Scheduled — assessment booked',
			title: 'Fuse box replacement',
			statusLabel: 'Upcoming',
			statusTone: 'success' as const,
			action: 'Email booking confirmation',
			facts: [
				{ label: 'Requested', value: '16 Aug 2026' },
				{ label: 'Assessment', value: 'Aug 20, 2026 @ 9:00 AM' }
			]
		},
		{
			caption: 'Overdue — the visit date has passed',
			title: 'Door repair',
			statusLabel: 'Overdue',
			statusTone: 'critical' as const,
			action: 'Email booking confirmation',
			facts: [
				{ label: 'Requested', value: '14 Aug 2026' },
				{ label: 'Assessment', value: 'Aug 15, 2026 @ 9:00 PM' }
			]
		}
	];

	// One record type at a time is not enough to prove these are shared, so the quote below draws the
	// same components with a quote's words.
	const quoteFacts = [
		{ label: 'Quote #', value: '1042' },
		{ label: 'Created', value: '12 Aug 2026' },
		{ label: 'Approved', value: null, empty: 'Not approved yet' }
	];

	let newTitle = $state('');
	let newClient = $state('');
</script>

<svelte:head><title>Work record preview · Contractor CRM</title></svelte:head>

<PageContainer variant="standard">
	<PageHeader
		eyebrow="QA harness"
		title="Work record preview"
		description="The header, client card, facts list and create-page card that requests, quotes, jobs and invoices all share. Every value on this page is made up."
	/>

	<h2 class="preview-label">Detail header — the three request states</h2>
	<div class="preview-stack">
		{#each states as state (state.title)}
			<p class="preview-caption">{state.caption}</p>
			<WorkRecordHeader
				icon={clipboardIcon}
				recordType="Request"
				title={state.title}
				statusLabel={state.statusLabel}
				statusTone={state.statusTone}
				primaryAction={{ label: state.action, onclick: noop }}
				menuItems={requestMenu}
				onHistory={noop}
				onEditTitle={noop}
			>
				{#snippet summary()}
					<ClientSummaryCard
						name={demoClient.name}
						addresses={demoClient.addresses}
						phone={demoClient.phone}
						email={demoClient.email}
						menuItems={clientMenu}
					/>
				{/snippet}
				{#snippet facts()}
					<RecordFactsList facts={state.facts} />
				{/snippet}
			</WorkRecordHeader>
		{/each}
	</div>

	<h2 class="preview-label">The same header on a quote</h2>
	<div class="preview-stack">
		<WorkRecordHeader
			icon={fileIcon}
			recordType="Quote"
			title="Rewire the upstairs landing"
			statusLabel="Awaiting response"
			statusTone="warning"
			primaryAction={{ label: 'Convert to job', onclick: noop }}
			menuItems={requestMenu}
			onHistory={noop}
			onEditTitle={noop}
		>
			{#snippet summary()}
				<ClientSummaryCard
					name="Riverbend Diner"
					addresses={[
						{ label: 'Billing address', value: '12 Mill Lane, Bristol' },
						{ label: 'Property address', value: null, empty: 'No property on this quote' }
					]}
					phone={null}
					email="accounts@riverbend.example"
					menuItems={clientMenu}
				/>
			{/snippet}
			{#snippet facts()}
				<RecordFactsList facts={quoteFacts} />
			{/snippet}
		</WorkRecordHeader>
	</div>

	<h2 class="preview-label">Inside the detail page shell, with its rail</h2>
	<RecordDetailLayout>
		{#snippet main()}
			<WorkRecordHeader
				icon={clipboardIcon}
				recordType="Request"
				title="Door repair"
				statusLabel="Overdue"
				statusTone="critical"
				primaryAction={{ label: 'Email booking confirmation', onclick: noop }}
				menuItems={requestMenu}
				onHistory={noop}
				onEditTitle={noop}
			>
				{#snippet summary()}
					<ClientSummaryCard
						name={demoClient.name}
						addresses={demoClient.addresses}
						phone={demoClient.phone}
						email={demoClient.email}
						menuItems={clientMenu}
					/>
				{/snippet}
				{#snippet facts()}
					<RecordFactsList facts={states[2].facts} />
				{/snippet}
			</WorkRecordHeader>

			<SectionBlock title="Service overview" icon={clipboardIcon} level={2}>
				<p class="preview-body">
					A body block, here only to show what the header sits above. The real ones arrive with the
					request detail page.
				</p>
			</SectionBlock>
		{/snippet}

		{#snippet rail()}
			<RailCard title="Notes">
				<p class="preview-body">Notes and attachments already have their own cards.</p>
			</RailCard>
		{/snippet}
	</RecordDetailLayout>

	<h2 class="preview-label">Create page — the Primary Info card</h2>
	<div class="preview-stack preview-stack--on-background">
		<SectionBlock title="New Request" icon={clipboardIcon} level={2}>
			<PrimaryInfoCard bind:title={newTitle} id="preview-new-request" icon={clipboardIcon}>
				{#snippet client()}
					<Input id="preview-client" label="Select a client" bind:value={newClient} />
				{/snippet}
				{#snippet fields()}
					<RecordFactsList facts={[{ label: 'Requested on', value: '18 Aug 2026' }]} />
				{/snippet}
			</PrimaryInfoCard>
		</SectionBlock>
	</div>
</PageContainer>

<style lang="scss">
	.preview-label {
		margin: var(--space-larger) 0 var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
	}

	.preview-caption {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.preview-stack {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	// These blocks sit straight on the page background, so the title notch has to match it.
	.preview-stack--on-background {
		--section-block-notch: var(--color-surface--background);
	}

	.preview-body {
		color: var(--color-text--secondary);
	}
</style>
