<script lang="ts">
	// TEMPORARY preview for Toggle, so Jafar can eyeball every state before it goes into real pages.
	// Delete once the component is settled.
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import toggleLeftIcon from '@tabler/icons/outline/toggle-left.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import layoutColumnsIcon from '@tabler/icons/outline/layout-columns.svg?raw';

	let plain = $state(true);
	let described = $state(false);
	let quoteFollowUps = $state(true);
	let invoiceReminders = $state(true);
	let marketing = $state(false);
	let compare = $state(true);

	let schedule = $state('one_off');
	let clientType = $state('person');
	let lifecycle = $state('customer');
	let range = $state('month');
	let view = $state('list');
</script>

<svelte:head><title>Toggle preview · Contractor CRM</title></svelte:head>

<PageContainer variant="standard">
	<PageHeader
		eyebrow="QA harness"
		title="Toggle preview"
		description="The segmented picker and the on/off switch, in every state."
	/>

	<Card>
		<div class="preview-stack">
			<SectionBlock title="Segmented picker" icon={layoutColumnsIcon} level={3} form>
				<div class="preview-stack">
					<SegmentedControl
						label="Schedule"
						bind:value={schedule}
						options={[
							{ value: 'one_off', label: 'One-off' },
							{ value: 'recurring', label: 'Recurring' }
						]}
					/>

					<SegmentedControl
						bind:value={clientType}
						options={[
							{ value: 'person', label: 'Person' },
							{ value: 'company', label: 'Company' }
						]}
					/>

					<SegmentedControl
						label="Lifecycle"
						bind:value={lifecycle}
						options={[
							{
								value: 'lead',
								label: 'Lead',
								disabled: true,
								title: 'A customer cannot be turned back into a lead.'
							},
							{ value: 'customer', label: 'Customer' }
						]}
					/>

					<SegmentedControl
						label="Date range"
						size="small"
						bind:value={range}
						options={[
							{ value: 'week', label: 'Week' },
							{ value: 'month', label: 'Month' },
							{ value: 'quarter', label: 'Quarter' },
							{ value: 'year', label: 'Year' }
						]}
					/>

					<SegmentedControl
						label="Whole group disabled"
						disabled
						bind:value={view}
						options={[
							{ value: 'list', label: 'List' },
							{ value: 'map', label: 'Map' }
						]}
					/>
				</div>

				<p class="preview-note preview-note--top">Full width, for a narrow column or mobile.</p>
				<div class="preview-narrow">
					<SegmentedControl
						fullWidth
						value="recurring"
						options={[
							{ value: 'one_off', label: 'One-off' },
							{ value: 'recurring', label: 'Recurring' }
						]}
					/>
				</div>
			</SectionBlock>
		</div>
	</Card>

	<Card>
		<div class="preview-stack">
			<SectionBlock title="Basics" icon={toggleLeftIcon} level={3} form>
				<div class="preview-stack">
					<Toggle id="preview-plain" label="On by default" bind:checked={plain} />
					<Toggle
						id="preview-described"
						label="With a line of helper text"
						description="The description sits under the label in secondary text."
						bind:checked={described}
					/>
				</div>
			</SectionBlock>

			<SectionBlock title="Fixed states" icon={toggleLeftIcon} level={3} form>
				<div class="preview-stack">
					<Toggle id="preview-off" label="Off" checked={false} />
					<Toggle id="preview-on" label="On" checked={true} />
					<Toggle id="preview-off-disabled" label="Off and disabled" checked={false} disabled />
					<Toggle id="preview-on-disabled" label="On and disabled" checked={true} disabled />
					<Toggle
						id="preview-disabled-described"
						label="Disabled with helper text"
						description="Nothing here reacts to hover or focus."
						checked={true}
						disabled
					/>
				</div>
			</SectionBlock>

			<SectionBlock title="Settings row" icon={bellIcon} level={3} form>
				<p class="preview-note">
					Label on the left, switch on the far right — how a list of settings would read.
				</p>
				<div class="preview-rows">
					<Toggle
						id="preview-row-quotes"
						labelSide="start"
						label="Outstanding quote follow-ups"
						description="A nudge when a quote has been sitting unanswered."
						bind:checked={quoteFollowUps}
					/>
					<Toggle
						id="preview-row-invoices"
						labelSide="start"
						label="Overdue invoice reminders"
						description="A reminder once an invoice passes its due date."
						bind:checked={invoiceReminders}
					/>
					<Toggle
						id="preview-row-marketing"
						labelSide="start"
						label="Marketing messages"
						description="Promotions and seasonal offers."
						bind:checked={marketing}
					/>
				</div>
			</SectionBlock>

			<SectionBlock title="Next to a checkbox" icon={toggleLeftIcon} level={3} form>
				<div class="preview-stack">
					<Toggle id="preview-compare-toggle" label="Toggle" bind:checked={compare} />
					<Checkbox id="preview-compare-checkbox" label="Checkbox" bind:checked={compare} />
				</div>
			</SectionBlock>
		</div>
	</Card>
</PageContainer>

<style lang="scss">
	.preview-stack {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		align-items: flex-start;
	}

	.preview-rows {
		display: flex;
		flex-direction: column;
		width: 100%;
		max-width: 520px;

		:global(.toggle) {
			padding: var(--space-slim) 0;
		}

		:global(.toggle + .toggle) {
			border-top: var(--border-base) solid var(--color-border);
		}
	}

	.preview-note {
		margin-bottom: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--top {
			margin-top: var(--space-large);
		}
	}

	.preview-narrow {
		max-width: 280px;
	}
</style>
