<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import { assignmentLabel, scheduleLabel } from '$lib/schedule/labels';
	import type { MoveScope, ScheduleChange, ScheduleProposal } from '$lib/schedule/drag';
	import type { ScheduleWarning } from '$lib/schedule/conflicts';
	import type { ScheduleVisit } from '$lib/schedule/api';
	import type { TeamMember } from '$lib/team/api';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowIcon from '@tabler/icons/outline/arrow-narrow-right.svg?raw';

	// What a drag proposes, before anything is written.
	//
	// The gesture is the easy part; this is the part that makes it safe. It says what the visit is now and
	// what it would become, warns about a double-booking or an out-of-hours slot without refusing either,
	// and -- on a repeating job -- makes the person say out loud whether they mean this visit or every visit
	// after it too. Nothing is saved until the button here is pressed.

	let {
		visit,
		proposal,
		change,
		warnings,
		employeesById,
		recurring,
		loading = false,
		saving = false,
		error = '',
		onsave,
		oncancel
	}: {
		visit: ScheduleVisit;
		proposal: ScheduleProposal;
		change: ScheduleChange;
		warnings: ScheduleWarning[];
		employeesById: Map<string, TeamMember>;
		/** Whether the owning job repeats, so the scope question is worth asking. */
		recurring: boolean;
		/** The job is still being read, so we do not yet know whether it repeats. */
		loading?: boolean;
		saving?: boolean;
		error?: string;
		onsave: (scope: MoveScope) => void;
		oncancel: () => void;
	} = $props();

	let scope = $state<MoveScope>('single');

	// Only a change the Jobs command can actually carry forward is worth offering. A new date, or work that
	// became Anytime, is this visit's alone whatever anybody picks.
	const canChooseScope = $derived(
		recurring && (change.time || change.duration || change.assignment) && change.shape === null
	);

	// Whatever the radios were last left on, a change that cannot travel forward saves as this visit alone.
	const effectiveScope = $derived(canChooseScope ? scope : 'single');

	function warningText(warning: ScheduleWarning): string {
		if (warning.kind === 'closed_day') return 'Your business is closed that day.';
		if (warning.kind === 'outside_hours') return 'That time is outside your working hours.';
		const name = employeesById.get(warning.employee_id)?.full_name ?? 'This employee';
		const count = warning.visit_ids.length;
		return `${name} is already booked then${count > 1 ? ` on ${count} other visits` : ''}.`;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="move-confirm">
	{#if error}
		<p class="move-confirm__error" role="alert">{error}</p>
	{/if}

	<dl class="move-confirm__change">
		<dt>Now</dt>
		<dd>{scheduleLabel(visit)}</dd>
		<dt>Move to</dt>
		<dd class="move-confirm__new">{scheduleLabel(proposal)}</dd>

		{#if change.assignment}
			<dt>Team</dt>
			<dd>
				{assignmentLabel(visit.assignee_ids, employeesById)}
				<span class="move-confirm__arrow">{@html arrowIcon}</span>
				<strong>{assignmentLabel(proposal.assignee_ids, employeesById)}</strong>
			</dd>
		{/if}
	</dl>

	{#each warnings as warning, index (index)}
		<p class="move-confirm__warning" role="status">
			<span class="move-confirm__warning-icon" aria-hidden="true">{@html alertIcon}</span>
			{warningText(warning)}
		</p>
	{/each}

	{#if loading}
		<p class="move-confirm__note">Checking whether this job repeats…</p>
	{:else if canChooseScope}
		<fieldset class="move-confirm__scope">
			<legend>This job repeats. Apply to:</legend>
			<label class="move-confirm__option">
				<input type="radio" name="move-scope" value="single" bind:group={scope} />
				<span>This visit only</span>
			</label>
			<label class="move-confirm__option">
				<input type="radio" name="move-scope" value="future" bind:group={scope} />
				<span>
					This and later visits
					<span class="move-confirm__hint">
						{change.assignment && (change.time || change.duration)
							? 'Copies the new time and crew onto the later visits. Completed ones never change.'
							: change.assignment
								? 'Copies the new crew onto the later visits. Completed ones never change.'
								: 'Copies the new time onto the later visits. Completed ones never change.'}
					</span>
				</span>
			</label>
		</fieldset>
	{:else if recurring && !loading}
		<p class="move-confirm__note">
			This job repeats, and a change like this only ever applies to this one visit. Use Edit all
			visits on the job to change the whole series.
		</p>
	{/if}

	<div class="move-confirm__actions">
		<Button variant="tertiary" size="small" onclick={oncancel} disabled={saving}>Cancel</Button>
		<Button
			size="small"
			onclick={() => onsave(effectiveScope)}
			loading={saving}
			disabled={!change.changed || loading}
		>
			Save move
		</Button>
	</div>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.move-confirm {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}

	.move-confirm__error {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		background-color: var(--color-critical--surface);
		color: var(--color-critical--onSurface);
		font-size: var(--typography--fontSize-small);
	}

	.move-confirm__change {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr);
		gap: var(--space-smaller) var(--space-slim);
		margin: 0;

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-tighter);
		}

		dd {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-tighter);
			overflow-wrap: anywhere;
		}
	}

	.move-confirm__new {
		color: var(--color-heading);
		font-weight: 700;
	}

	.move-confirm__arrow {
		display: inline-flex;
		color: var(--color-icon--secondary);
		vertical-align: middle;

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.move-confirm__warning {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		background-color: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
		font-size: var(--typography--fontSize-small);
	}

	.move-confirm__warning-icon {
		display: inline-flex;
		flex-shrink: 0;

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.move-confirm__note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tight);
	}

	.move-confirm__scope {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		padding: 0;
		border: none;

		legend {
			padding: 0 0 var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.move-confirm__option {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tight);
		cursor: pointer;

		input {
			flex-shrink: 0;
			margin: 0;
			width: 16px;
			height: 16px;
			accent-color: var(--color-interactive);
			cursor: pointer;

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
	}

	.move-confirm__hint {
		display: block;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
	}

	.move-confirm__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-smaller);
	}
</style>
