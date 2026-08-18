<script lang="ts">
	// TEMPORARY QA harness for the Part 3 collaboration components (Notes, Tags, Attachments,
	// Activity). Not part of the approved app navigation -- delete once Part 6 wires these into the
	// real Client detail workspace, or once Jafar has finished eyeballing them here.
	import { page } from '$app/state';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import NotesPanel from '$lib/components/collaboration/NotesPanel.svelte';
	import TagPicker from '$lib/components/collaboration/TagPicker.svelte';
	import AttachmentsCard from '$lib/components/collaboration/AttachmentsCard.svelte';
	import ActivityFeed from '$lib/components/collaboration/ActivityFeed.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import type { NoteChange } from '$lib/collaboration/api';

	const CLIENT_ID = '8a30dee4-7c71-4752-abdd-1ea7c082081e';
	const PROPERTY_ID = '92609728-6957-402a-ae8b-94d4087a757c';

	const currentUserId = $derived(page.data.user?.id as string | undefined);
	let canManage = $state(true);
	// The panel stages its changes now; this harness just holds them so they can be eyeballed.
	let notePending = $state<NoteChange[]>([]);
	// Attachments stage too, and a real page saves them from its action bar. This harness has none, so it
	// gets its own button — without one, picked files would sit here forever.
	let attachmentsCard = $state<AttachmentsCard>();
	let pendingFileCount = $state(0);
	let savingFiles = $state(false);
</script>

<PageContainer variant="standard">
	<PageHeader
		eyebrow="QA harness"
		title="Collaboration components preview"
		description="Notes, tags, attachments, and activity wired to a real demo Client (Riverbend Family Diner) and its Property. Temporary -- not part of the app navigation."
	/>

	<label class="preview-toggle">
		<input type="checkbox" bind:checked={canManage} />
		canManage (view-only when unchecked)
	</label>

	<div class="preview-grid">
		<Card heading="Notes">
			<NotesPanel
				entityType="client"
				entityId={CLIENT_ID}
				{canManage}
				{currentUserId}
				pending={notePending}
				onChange={(next) => (notePending = next)}
			/>
		</Card>

		<Card heading="Tags">
			<TagPicker entityType="client" entityId={CLIENT_ID} {canManage} />
		</Card>

		<div class="preview-attachments">
			<AttachmentsCard
				bind:this={attachmentsCard}
				onPendingChange={(count) => (pendingFileCount = count)}
				entityType="property"
				entityId={PROPERTY_ID}
				{canManage}
				{currentUserId}
			/>
			{#if pendingFileCount > 0}
				<Button
					variant="primary"
					loading={savingFiles}
					onclick={async () => {
						savingFiles = true;
						await attachmentsCard?.saveAll(PROPERTY_ID);
						savingFiles = false;
					}}
				>
					Save {pendingFileCount} file {pendingFileCount === 1 ? 'change' : 'changes'}
				</Button>
			{/if}
		</div>

		<Card heading="Activity — Client">
			<ActivityFeed entityType="client" entityId={CLIENT_ID} {currentUserId} />
		</Card>
	</div>
</PageContainer>

<style lang="scss">
	.preview-toggle {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: var(--space-large) 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.preview-attachments {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-base);
	}

	.preview-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-large);
	}

	@media (max-width: 900px) {
		.preview-grid {
			grid-template-columns: 1fr;
		}
	}
</style>
