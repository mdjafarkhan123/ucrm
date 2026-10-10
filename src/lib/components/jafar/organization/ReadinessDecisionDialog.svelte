<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import type { ReadinessAreaSummary } from '$lib/experience/types';

	// Multi-industry foundation B8 (plan "Access, readiness and launch"): Jafar answers each check of one
	// area, then opens it, leaves it waiting or puts it on hold. The business reads the remaining tasks and,
	// when waiting or on hold, the message below; the reason stays with Uplift.
	let {
		area,
		pending,
		error,
		onSubmit,
		onClose
	}: {
		area: ReadinessAreaSummary;
		pending: boolean;
		error: string;
		onSubmit: (input: {
			status: 'ready' | 'not_ready' | 'held';
			checks: { key: string; state: 'open' | 'done' | 'not_applicable' }[];
			reason: string;
			business_message: string | null;
		}) => void;
		onClose: () => void;
	} = $props();

	const uid = $props.id();
	const STATUS_OPTIONS = [
		{ value: 'ready', label: 'Open for real customers' },
		{ value: 'not_ready', label: 'Not ready yet' },
		{ value: 'held', label: 'On hold' }
	];
	const CHECK_STATES = [
		{ value: 'open', label: 'To do' },
		{ value: 'done', label: 'Done' },
		{ value: 'not_applicable', label: 'Not needed' }
	];

	// The dialog opens fresh each time, so the starting answers are read once.
	// svelte-ignore state_referenced_locally
	const startStates = new Map(
		(area.current?.checks ?? []).map((check) => [check.key, check.state])
	);
	// svelte-ignore state_referenced_locally
	let states = $state<Record<string, string>>(
		Object.fromEntries(
			area.checks.map((check) => [check.key, startStates.get(check.key) ?? 'open'])
		)
	);
	// svelte-ignore state_referenced_locally
	let status = $state(
		area.current && area.current.source === 'review' ? area.current.status : 'not_ready'
	);
	// svelte-ignore state_referenced_locally
	let businessMessage = $state(area.current?.business_message ?? '');
	let reason = $state('');
	let errors = $state<Record<string, string>>({});

	const openCount = $derived(area.checks.filter((check) => states[check.key] === 'open').length);

	function submit(event: SubmitEvent) {
		event.preventDefault();
		const next: Record<string, string> = {};
		if (status === 'ready' && openCount > 0)
			next.status = 'Finish every check before opening this area.';
		if (status === 'held' && !businessMessage.trim())
			next.business_message = 'Tell the business why this is on hold.';
		if (!reason.trim()) next.reason = 'Explain what you checked or why you are holding this.';
		errors = next;
		if (Object.keys(next).length > 0) return;
		onSubmit({
			status: status as 'ready' | 'not_ready' | 'held',
			checks: area.checks.map((check) => ({
				key: check.key,
				state: states[check.key] as 'open' | 'done' | 'not_applicable'
			})),
			reason: reason.trim(),
			business_message: status === 'ready' ? null : businessMessage.trim() || null
		});
	}
</script>

<Dialog open title={`Review: ${area.label}`} initialFocusId={`${uid}-status`} {onClose}>
	<form class="readiness-dialog" onsubmit={submit} novalidate>
		<p class="readiness-dialog__lead">
			Once this is open, {area.opens}. Each answer is recorded with your name and kept in the
			history; an earlier decision is never changed.
		</p>

		<ul class="readiness-dialog__checks">
			{#each area.checks as check (check.key)}
				<li class="readiness-dialog__check">
					<div class="readiness-dialog__task">
						<span>{check.task}</span>
						<span class="readiness-dialog__owner"
							>{check.owner === 'business' ? 'The business does this' : 'Uplift does this'}</span
						>
					</div>
					<SegmentedControl
						ariaLabel={check.task}
						size="small"
						options={CHECK_STATES}
						bind:value={states[check.key]}
					/>
				</li>
			{/each}
		</ul>

		<Select id={`${uid}-status`} label="Decision" options={STATUS_OPTIONS} bind:value={status} />
		{#if errors.status}
			<p class="readiness-dialog__error" role="alert">{errors.status}</p>
		{/if}

		{#if status !== 'ready'}
			<Textarea
				id={`${uid}-message`}
				label={status === 'held'
					? 'What the business reads'
					: 'Extra note for the business (optional)'}
				rows={2}
				maxlength={500}
				required={status === 'held'}
				bind:value={businessMessage}
				invalid={Boolean(errors.business_message) && !businessMessage.trim()}
				errorMessage={businessMessage.trim() ? '' : (errors.business_message ?? '')}
			/>
		{/if}

		<Textarea
			id={`${uid}-reason`}
			label="What you checked (private to Uplift)"
			rows={3}
			maxlength={1000}
			required
			bind:value={reason}
			invalid={Boolean(errors.reason) && !reason.trim()}
			errorMessage={reason.trim() ? '' : (errors.reason ?? '')}
		/>

		{#if error}
			<p class="readiness-dialog__error" role="alert">{error}</p>
		{/if}
		<div class="readiness-dialog__actions">
			<Button type="button" variant="secondary" variation="subtle" onclick={onClose}>Cancel</Button>
			<Button type="submit" loading={pending}>Record decision</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.readiness-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__lead {
			margin: 0;
			color: var(--color-text--secondary);
		}

		&__checks {
			display: grid;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__check {
			display: grid;
			gap: var(--space-small);
			padding-bottom: var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);

			&:last-child {
				padding-bottom: 0;
				border-bottom: 0;
			}
		}

		&__task {
			display: grid;
			gap: var(--space-smallest);
			color: var(--color-heading);
		}

		&__owner {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical--onSurface);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			padding-top: var(--space-small);
		}
	}
</style>
