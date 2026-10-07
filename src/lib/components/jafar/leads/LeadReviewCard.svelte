<script lang="ts">
	import { resolve } from '$app/paths';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { today, getLocalTimeZone, type CalendarDate } from '@internationalized/date';
	import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import arrowBackIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import toolIcon from '@tabler/icons/outline/tool.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';
	import externalIcon from '@tabler/icons/outline/external-link.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { CONTACT_METHOD_LABELS, LEAD_SOURCE_LABELS, countryName } from '$lib/jafar/leads';
	import {
		LEAD_EXCLUSION_TEXT,
		leadExclusion,
		missingInformation,
		needsPermission,
		previousContactLine,
		type ReviewLead
	} from '$lib/jafar/lead-review';
	import { refreshLead, sendLeadWrite } from '$lib/jafar/lead-page-api';

	// Jafar business management B3: one business in the review queue, with everything Jafar needs to decide who
	// may be contacted -- why it fits, where each detail was found, its country, earlier contact, what is missing,
	// and anything that rules it out. Approving sends nothing: it gives the Lead a first-contact task.
	let {
		lead,
		canApprove,
		canMarkUnsuitable,
		onDone
	}: {
		lead: ReviewLead;
		/** "Approve who to contact" -- approving and sending back. */
		canApprove: boolean;
		/** Changing the Lead's status, for a business that cannot be approved. */
		canMarkUnsuitable: boolean;
		/** The Lead has left the queue; the page moves to the next one. */
		onDone: (message: string) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const exclusion = $derived(leadExclusion(lead));
	const missing = $derived(missingInformation(lead));

	// Nothing is ticked to start: approval is a decision about each detail, not a default.
	let chosen = $state<string[]>([]);
	let permitted = $state<string[]>([]);
	const todayDate = today(getLocalTimeZone());
	let dueOn = $state<CalendarDate | undefined>(todayDate);
	let saving = $state(false);
	let formError = $state('');

	function toggleChosen(id: string, on: boolean) {
		chosen = on ? [...chosen, id] : chosen.filter((value) => value !== id);
		if (!on) permitted = permitted.filter((value) => value !== id);
	}

	function togglePermitted(id: string, on: boolean) {
		permitted = on ? [...permitted, id] : permitted.filter((value) => value !== id);
		if (!on) chosen = chosen.filter((value) => value !== id);
	}

	function blocked(method: ReviewLead['contact_methods'][number]) {
		return needsPermission(method.kind) && !permitted.includes(method.id);
	}

	const approveLabel = $derived(
		chosen.length === 0
			? 'Approve'
			: chosen.length === 1
				? 'Approve 1 detail'
				: `Approve ${chosen.length} details`
	);

	async function approve() {
		if (saving) return;
		formError = '';
		if (chosen.length === 0) {
			formError = 'Tick at least one contact detail to approve.';
			return;
		}
		if (!dueOn) {
			formError = 'Choose when the first contact is due.';
			return;
		}
		saving = true;
		const result = await sendLeadWrite(
			`/api/jafar/leads/${encodeURIComponent(lead.id)}/approval`,
			'POST',
			{ method_ids: chosen, whatsapp_permission_ids: permitted, due_on: dueOn.toString() }
		);
		if (!result.ok) {
			saving = false;
			formError = result.error;
			return;
		}
		decided(`${lead.business_name} approved — first contact is on their next action`);
	}

	// Tell the page before the queue reloads: once it does, this Lead has left the list, and the page could no
	// longer tell which card comes next (the next one would be skipped) -- and `lead` would already be that card.
	function decided(message: string) {
		const id = lead.id;
		onDone(message);
		void refreshLead(queryClient, id);
	}

	async function markUnsuitable() {
		if (saving) return;
		saving = true;
		const result = await sendLeadWrite(`/api/jafar/leads/${encodeURIComponent(lead.id)}`, 'PATCH', {
			lead_status: 'unsuitable'
		});
		if (!result.ok) {
			saving = false;
			toast.error('The Lead could not be marked unsuitable.', result.error);
			return;
		}
		decided(`${lead.business_name} marked unsuitable`);
	}

	// --- Sending back --------------------------------------------------------------------------------

	let sendBackOpen = $state(false);
	let sendBackReason = $state('');
	let sendBackError = $state('');

	async function sendBack(event: SubmitEvent) {
		event.preventDefault();
		if (saving) return;
		sendBackError = '';
		if (!sendBackReason.trim()) {
			sendBackError = 'Say what needs fixing.';
			return;
		}
		saving = true;
		const result = await sendLeadWrite(
			`/api/jafar/leads/${encodeURIComponent(lead.id)}/approval/send-back`,
			'POST',
			{ reason: sendBackReason.trim() }
		);
		if (!result.ok) {
			saving = false;
			sendBackError = result.fieldErrors.reason ?? result.error;
			return;
		}
		sendBackOpen = false;
		decided(`${lead.business_name} sent back to Researching`);
	}

	const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' });
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<article class="review-card" aria-labelledby={`review-${lead.id}`}>
	<header class="review-card__header">
		<div class="review-card__identity">
			<h2 id={`review-${lead.id}`}>{lead.business_name}</h2>
			<ul class="review-card__facts">
				<li><span aria-hidden="true">{@html toolIcon}</span>{lead.trade}</li>
				<li><span aria-hidden="true">{@html mapPinIcon}</span>{countryName(lead.country_code)}</li>
				{#if lead.website}
					<li>
						<span aria-hidden="true">{@html worldIcon}</span>
						<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- the business's own website. -->
						<a href={lead.website} target="_blank" rel="noopener noreferrer"
							>{lead.website_host ?? lead.website}</a
						>
					</li>
				{/if}
				{#if lead.contact_name}
					<li><span aria-hidden="true">{@html userIcon}</span>{lead.contact_name}</li>
				{/if}
			</ul>
		</div>
		<a
			class="review-card__open"
			href={resolve('/jafar/(protected)/leads/[id]', { id: lead.id })}
			target="_blank"
			rel="noopener">Open Lead <span aria-hidden="true">{@html externalIcon}</span></a
		>
	</header>

	{#if exclusion}
		<div class="review-card__excluded" role="note">
			<span class="review-card__excluded-icon" aria-hidden="true">{@html banIcon}</span>
			<div>
				<p class="review-card__excluded-title">
					Excluded: {LEAD_EXCLUSION_TEXT[exclusion].title}
				</p>
				<p>{LEAD_EXCLUSION_TEXT[exclusion].detail}</p>
				{#if exclusion === 'do_not_contact' && lead.do_not_contact}
					<p class="review-card__excluded-meta">
						Recorded {dateFormat.format(new Date(lead.do_not_contact.at))}{lead.do_not_contact
							.reason
							? ` · “${lead.do_not_contact.reason}”`
							: ''}
					</p>
				{/if}
			</div>
		</div>
	{/if}

	<dl class="review-card__why">
		<div class="review-card__why-wide">
			<dt>Why they may fit</dt>
			<dd>
				{#if lead.fit_notes}
					<p class="review-card__notes">{lead.fit_notes}</p>
				{:else}
					<span class="review-card__missing-text">No notes yet</span>
				{/if}
			</dd>
		</div>
		<div>
			<dt><span aria-hidden="true">{@html searchIcon}</span>Found through</dt>
			<dd>
				{LEAD_SOURCE_LABELS[lead.source]}{lead.source_detail ? ` · ${lead.source_detail}` : ''}
			</dd>
		</div>
		<div>
			<dt><span aria-hidden="true">{@html historyIcon}</span>Earlier contact</dt>
			<dd>{previousContactLine(lead.contact)}</dd>
		</div>
		<div>
			<dt><span aria-hidden="true">{@html userIcon}</span>Prepared by</dt>
			<dd>{lead.prepared_by} · {dateFormat.format(new Date(lead.created_at))}</dd>
		</div>
	</dl>

	{#if missing.length || lead.last_sent_back}
		<div class="review-card__warnings">
			{#if missing.length}
				<p>
					<span aria-hidden="true">{@html alertIcon}</span>
					<span>Missing: {missing.join(', ')}</span>
				</p>
			{/if}
			{#if lead.last_sent_back}
				<p>
					<span aria-hidden="true">{@html arrowBackIcon}</span>
					<span>Sent back before: “{lead.last_sent_back}”</span>
				</p>
			{/if}
		</div>
	{/if}

	<SectionBlock
		title="Contact details"
		hint={exclusion
			? undefined
			: 'Tick each detail you approve for a first contact. Nothing is sent: you get a task to contact them yourself.'}
		form={!exclusion && canApprove}
		level={3}
	>
		{#if lead.contact_methods.length === 0}
			<p class="review-card__empty">No contact details on this Lead.</p>
		{:else}
			<ul class="review-card__methods">
				{#each lead.contact_methods as method (method.id)}
					{@const isChosen = chosen.includes(method.id)}
					<li class={['review-card__method', isChosen && 'review-card__method--chosen']}>
						<div class="review-card__method-main">
							{#if !exclusion && canApprove}
								<Checkbox
									id={`approve-${method.id}`}
									label={`${CONTACT_METHOD_LABELS[method.kind]}: ${method.value}`}
									hideLabel
									checked={isChosen}
									disabled={saving || blocked(method)}
									onchange={(on) => toggleChosen(method.id, on)}
								/>
							{/if}
							<div class="review-card__method-text">
								<span class="review-card__method-kind">{CONTACT_METHOD_LABELS[method.kind]}</span>
								<span class="review-card__method-value">{method.value}</span>
								<span class="review-card__method-source">Found: {method.found_at}</span>
							</div>
							{#if needsPermission(method.kind) && !permitted.includes(method.id)}
								<Badge size="small" status="warning">Needs their permission first</Badge>
							{:else if isChosen}
								<Badge size="small" status="success">Approve</Badge>
							{/if}
						</div>
						{#if needsPermission(method.kind) && !exclusion && canApprove}
							<div class="review-card__permission">
								<Checkbox
									id={`permission-${method.id}`}
									label="They asked to talk on WhatsApp"
									description="WhatsApp only allows messages to people who gave their permission. It is kept in the history."
									checked={permitted.includes(method.id)}
									disabled={saving}
									onchange={(on) => togglePermitted(method.id, on)}
								/>
							</div>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	</SectionBlock>

	{#if canApprove || (exclusion && canMarkUnsuitable)}
		<footer class="review-card__actions">
			{#if exclusion}
				<p class="review-card__actions-note">This business cannot be approved.</p>
				<div class="review-card__buttons">
					{#if canApprove}
						<Button variant="secondary" disabled={saving} onclick={() => (sendBackOpen = true)}>
							<span class="review-card__button-icon" aria-hidden="true">{@html arrowBackIcon}</span
							>Send back
						</Button>
					{/if}
					{#if canMarkUnsuitable}
						<Button variant="primary" loading={saving} onclick={markUnsuitable}
							>Mark unsuitable</Button
						>
					{/if}
				</div>
			{:else}
				<div class="review-card__due">
					<CalendarPicker
						id={`review-due-${lead.id}`}
						label="First contact due"
						required
						minValue={todayDate}
						disabled={saving}
						bind:value={dueOn}
					/>
				</div>
				<div class="review-card__buttons">
					<Button variant="secondary" disabled={saving} onclick={() => (sendBackOpen = true)}>
						<span class="review-card__button-icon" aria-hidden="true">{@html arrowBackIcon}</span
						>Send back
					</Button>
					<Button
						variant="primary"
						loading={saving}
						disabled={chosen.length === 0}
						onclick={approve}
					>
						<span class="review-card__button-icon" aria-hidden="true">{@html shieldCheckIcon}</span
						>{approveLabel}
					</Button>
				</div>
			{/if}
			{#if formError}
				<p class="review-card__error" role="alert">{formError}</p>
			{/if}
		</footer>
	{:else}
		<p class="review-card__view-only">
			Only someone allowed to approve who to contact can decide on this Lead.
		</p>
	{/if}
</article>

{#if sendBackOpen}
	<Dialog
		open={true}
		title="Send back for more research"
		size="small"
		initialFocusId="send-back-reason"
		onClose={() => (sendBackOpen = false)}
	>
		<form class="send-back" onsubmit={sendBack} novalidate>
			<p class="send-back__lead">
				{lead.business_name} goes back to Researching, and your note goes into its history so whoever
				prepared it knows what to fix.
			</p>
			<Textarea
				id="send-back-reason"
				label="What needs fixing"
				rows={3}
				maxlength={500}
				showCount
				required
				invalid={Boolean(sendBackError)}
				errorMessage={sendBackError}
				bind:value={sendBackReason}
			/>
			<div class="send-back__actions">
				<Button variant="tertiary" disabled={saving} onclick={() => (sendBackOpen = false)}
					>Cancel</Button
				>
				<Button variant="primary" type="submit" loading={saving}>Send back</Button>
			</div>
		</form>
	</Dialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.review-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);

		p,
		h2,
		dl,
		dd {
			margin: 0;
		}
	}

	.review-card__header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.review-card__identity {
		min-width: 0;

		h2 {
			color: var(--color-heading);
			font-family: var(--typography--fontFamily-display);
			font-size: var(--typography--fontSize-largest);
			font-weight: 800;
			line-height: var(--typography--lineHeight-tight);
			overflow-wrap: anywhere;
		}
	}

	.review-card__facts {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-smaller) var(--space-base);
		margin: var(--space-small) 0 0;
		padding: 0;
		list-style: none;
		color: var(--color-text--secondary);

		li {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			min-width: 0;
			overflow-wrap: anywhere;
		}

		a {
			color: var(--color-interactive);
		}

		span :global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.review-card__open {
		display: inline-flex;
		flex: none;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}

		&:focus-visible {
			border-radius: var(--radius-small);
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		span :global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.review-card__excluded {
		display: flex;
		gap: var(--space-slim);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-critical);
		border-radius: var(--radius-base);
		background: var(--color-critical--surface);
		color: var(--color-critical--onSurface);
	}

	.review-card__excluded-icon :global(svg) {
		width: 22px;
		height: 22px;
	}

	.review-card__excluded-title {
		font-weight: 700;
	}

	.review-card__excluded-meta {
		margin-top: var(--space-smaller) !important;
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}

	.review-card__why {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);

		dt {
			display: flex;
			align-items: center;
			gap: var(--space-smaller);
			margin-bottom: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			span :global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		dd {
			color: var(--color-heading);
			overflow-wrap: anywhere;
		}
	}

	.review-card__why-wide {
		grid-column: 1 / -1;
	}

	.review-card__notes {
		padding: var(--space-slim) var(--space-base);
		border-left: 3px solid var(--color-interactive);
		border-radius: var(--radius-small);
		background: var(--color-surface--background--subtle);
		line-height: var(--typography--lineHeight-large);
		white-space: pre-line;
	}

	.review-card__missing-text {
		color: var(--color-warning--onSurface);
		font-weight: 600;
	}

	.review-card__warnings {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		p {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
			overflow-wrap: anywhere;
		}

		span :global(svg) {
			width: 18px;
			height: 18px;
			margin-top: 1px;
		}
	}

	.review-card__methods {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.review-card__method {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		padding: var(--space-slim) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		transition:
			border-color var(--timing-quick),
			background-color var(--timing-quick);
	}

	.review-card__method--chosen {
		border-color: var(--color-success);
		background: var(--color-success--surface);
	}

	.review-card__method-main {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	.review-card__method-text {
		display: flex;
		flex: 1;
		flex-direction: column;
		min-width: 0;
	}

	.review-card__method-kind,
	.review-card__method-source {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.review-card__method-value {
		color: var(--color-heading);
		font-weight: 600;
		overflow-wrap: anywhere;
	}

	.review-card__permission {
		padding-left: var(--space-large);
	}

	.review-card__empty,
	.review-card__view-only {
		color: var(--color-text--secondary);
	}

	.review-card__actions {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-end;
		justify-content: space-between;
		gap: var(--space-base);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}

	.review-card__actions-note {
		color: var(--color-text--secondary);
	}

	.review-card__due {
		min-width: 220px;
	}

	.review-card__buttons {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
		margin-left: auto;
	}

	.review-card__button-icon {
		display: inline-flex;
		margin-right: var(--space-smaller);

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.review-card__error {
		flex-basis: 100%;
		color: var(--color-critical);
		font-weight: 600;
	}

	.send-back {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		p {
			margin: 0;
		}
	}

	.send-back__lead {
		color: var(--color-text--secondary);
	}

	.send-back__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}

	@media (max-width: 767px) {
		.review-card {
			padding: var(--space-base);
		}

		.review-card__header {
			flex-direction: column;
		}

		.review-card__why {
			grid-template-columns: minmax(0, 1fr);
		}

		.review-card__actions,
		.review-card__buttons {
			flex-direction: column;
			align-items: stretch;
		}

		.review-card__buttons {
			flex-direction: column-reverse;
			margin-left: 0;
		}

		.review-card__due {
			min-width: 0;
		}
	}
</style>
